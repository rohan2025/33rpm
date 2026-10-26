import AppKit
import AVFoundation
import QuartzCore

/// What the turntable should be doing right now.
struct PlaybackInput {
    var isPlaying: Bool
    /// 0...1 through the song.
    var progress: Double
    /// Seconds left in the song; 0 when unknown.
    var remaining: Double
    var label: CGImage?
}

/// Layer-hosting view that draws a scene and animates the record and tonearm with Core Animation.
/// Animations run in the render server, so the app itself stays idle while music plays.
@MainActor
final class TurntableView: NSView {
    /// Root layers use flipped geometry so scene.json can use top-left coordinates, which makes
    /// positive z rotation clockwise on screen.
    private static let clockwise: CGFloat = 1

    private let host = CALayer()
    private let root = CALayer()
    private var record: CALayer?
    private var tonearm: CALayer?
    private let label = CALayer()
    private let spindle = CALayer()
    private let crate = SleeveCrate()
    private var crateItems: [SleeveCrate.Item] = []
    private let controls = PlaybackControls()
    private let upNext = UpNextCard()
    private var queue: [QueueItem] = []
    /// The turntable's footprint on screen (canvas points): hovering shows the controls, clicking plays/pauses.
    private var turntableRect = CGRect.zero

    /// Record speed override; nil uses the scene's rpm.
    var rpmOverride: Double? {
        didSet { if rpmOverride != oldValue, spinning { restartSpinLoop() } }
    }
    var showsControls = true {
        didSet { if !showsControls { controls.setShown(false) } }
    }
    var showsUpNext = true {
        didSet { if showsUpNext != oldValue { upNext.setItems(queue, visible: showsUpNext) } }
    }
    var ambientEnabled = true {
        didSet { if ambientEnabled != oldValue { setAmbient(active: ambientActive && ambientEnabled) } }
    }
    private var rootScale: CGFloat = 1
    private var emitters: [CAEmitterLayer] = []
    private var flickering: [(layer: CALayer, amount: CGFloat)] = []
    private var ambientActive = false
    /// Frozen while the screen sleeps or the scene is covered; nothing renders or animates.
    private(set) var isSuspended = false

    private var scene: LoadedScene?
    private let edgeMask = CALayer()

    /// Fade the scene's edges into the wallpaper. Off for full-screen, where the scene is the wallpaper.
    var fadesEdges = true {
        didSet { if fadesEdges != oldValue { updateEdgeMask() } }
    }
    private var input = PlaybackInput(isPlaying: false, progress: 0, remaining: 0, label: nil)
    private var spinning = false
    private var armOnRecord = false
    private var armMoving = false
    private var spinGeneration = 0
    private var armGeneration = 0
    private var shownLabel: CGImage?

    override init(frame: NSRect) {
        super.init(frame: frame)
        layer = host
        wantsLayer = true
        host.addSublayer(root)
        host.isGeometryFlipped = false
        root.isGeometryFlipped = true
        root.masksToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        layoutRoot()
    }

    /// Scales the canvas to cover the view (aspect fill). When the view's shape differs from the canvas,
    /// the crop keeps the scene's `focus` point as central as the edges allow.
    func layoutRoot() {
        guard let scene else { return }
        let canvas = scene.config.canvasSize
        let scale = max(host.bounds.width / canvas.width, host.bounds.height / canvas.height)
        let focus = scene.config.focus.flatMap { $0.count == 2 ? CGPoint(x: $0[0], y: $0[1]) : nil }
            ?? CGPoint(x: canvas.width / 2, y: canvas.height / 2)
        let slackX = max(0, (canvas.width * scale - host.bounds.width) / 2)
        let slackY = max(0, (canvas.height * scale - host.bounds.height) / 2)
        // Canvas y runs down, the host's runs up.
        let shiftX = min(slackX, max(-slackX, (canvas.width / 2 - focus.x) * scale))
        let shiftY = min(slackY, max(-slackY, (focus.y - canvas.height / 2) * scale))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        root.bounds = CGRect(origin: .zero, size: canvas)
        root.position = CGPoint(x: host.bounds.midX + shiftX, y: host.bounds.midY + shiftY)
        root.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
        CATransaction.commit()
        rootScale = scale
        crate.setTextScale(scale * (window?.backingScaleFactor ?? 2))
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        layoutRoot()
    }

    // MARK: - Building

    func load(_ scene: LoadedScene) {
        self.scene = scene
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        root.sublayers?.forEach { $0.removeFromSuperlayer() }
        record = nil
        tonearm = nil
        emitters = []
        flickering = []
        crate.reset(defaultSleeve: scene.defaultSleeve, settings: scene.config.crate)

        for spec in scene.config.layers {
            if spec.slot == "sleeve", spec.frame != nil, spec.hidden != true {
                crate.configureWall(spec)
                root.addSublayer(crate.wall)
                continue
            }
            if spec.slot == "crate", spec.frame != nil, spec.hidden != true {
                // Sleeves stand behind the crate's front panel.
                crate.configureCrate(spec, canvas: scene.config.canvasSize)
                root.addSublayer(crate.stack)
            }
            if spec.slot == "up_next", spec.frame != nil, spec.hidden != true {
                upNext.configure(spec, crate: scene.config.crate)
                root.addSublayer(upNext.layer)
                continue
            }
            if spec.frame != nil, spec.hidden != true, let ambient = makeAmbient(spec, scene: scene) {
                root.addSublayer(ambient)
                continue
            }
            if spec.slot == "deck" {
                // A flat container keeps the tilted deck from being depth-sorted against (and sliced by)
                // its flat neighbours.
                let container = CALayer()
                container.frame = CGRect(origin: .zero, size: scene.config.canvasSize)
                container.addSublayer(makeDeck(scene))
                root.addSublayer(container)
            } else if let layer = makeLayer(spec, image: scene.images[spec.slot]) {
                root.addSublayer(layer)
                if spec.slot == "sleeve_shadow" { crate.attachShadow(layer) }
                if let amount = spec.flicker, amount > 0 { flickering.append((layer, amount)) }
            }
        }
        configureControls(scene.config)
        root.addSublayer(controls.layer)
        root.addSublayer(crate.caption)
        CATransaction.commit()
        upNext.setItems(queue, visible: showsUpNext)
        layoutRoot()
        updateEdgeMask()
        crate.setItems(crateItems, animated: false)

        // Rebuilt layers have no animations; put everything back where it should be.
        spinning = false
        armOnRecord = false
        armMoving = false
        shownLabel = nil
        ambientActive = false
        setAmbient(active: false)
        apply(input, animated: false)
    }

    /// Works out the turntable's on-screen footprint and puts the controls just in front of it.
    private func configureControls(_ config: SceneConfig) {
        let d = config.deck
        let squash = cos(d.tilt * .pi / 180)
        let w = d.size[0], h = d.size[1] * squash
        turntableRect = CGRect(x: d.center[0] - w / 2, y: d.center[1] - h / 2 - 40, width: w, height: h + 70)
        let center = config.controls?.center.flatMap { $0.count == 2 ? CGPoint(x: $0[0], y: $0[1]) : nil }
            ?? CGPoint(x: d.center[0], y: d.center[1] + h / 2 + 60)
        controls.configure(center: center, scale: config.controls?.scale ?? 1)
        controls.setShown(false)
    }

    func setQueue(_ items: [QueueItem]) {
        queue = items
        upNext.setItems(items, visible: showsUpNext)
    }

    /// Dust, rain and video layers. Returns nil for ordinary image slots.
    private func makeAmbient(_ spec: SceneConfig.Layer, scene: LoadedScene) -> CALayer? {
        let layer: CALayer
        switch spec.slot {
        case "dust":
            let e = Ambient.dust(frame: spec.rect, amount: spec.amount ?? 1)
            emitters.append(e)
            layer = e
        case "rain":
            let e = Ambient.rain(frame: spec.rect, amount: spec.amount ?? 1)
            emitters.append(e)
            layer = e
        case "video":
            guard let url = SceneLibrary.file(spec.file ?? "ambient.mp4", in: scene.id.folderName) else {
                return CALayer()   // no video in this scene: an empty placeholder keeps the order intact
            }
            let video = AVPlayerLayer(player: AmbientVideo.shared.player(for: url))
            video.frame = spec.rect
            video.videoGravity = .resizeAspectFill
            layer = video
        default:
            return nil
        }
        layer.opacity = spec.opacity ?? 1
        layer.compositingFilter = Ambient.compositingFilter(spec.blend)
        return layer
    }

    /// Ambient motion runs only while music plays.
    private func setAmbient(active requested: Bool) {
        let active = requested && ambientEnabled
        for emitter in emitters { emitter.birthRate = active ? 1 : 0 }
        for (layer, amount) in flickering {
            if active { layer.add(Ambient.flicker(amount: amount), forKey: "flicker") }
            else { layer.removeAnimation(forKey: "flicker") }
        }
    }

    /// Freezes (or resumes) every animation in the scene. Used when nobody can see it.
    func setSuspended(_ suspended: Bool) {
        guard suspended != isSuspended else { return }
        isSuspended = suspended
        if suspended {
            let now = root.convertTime(CACurrentMediaTime(), from: nil)
            root.speed = 0
            root.timeOffset = now
        } else {
            let pausedAt = root.timeOffset
            root.speed = 1
            root.timeOffset = 0
            root.beginTime = 0
            root.beginTime = root.convertTime(CACurrentMediaTime(), from: nil) - pausedAt
        }
    }

    private func updateEdgeMask() {
        let fade = scene?.config.edgeFade ?? 0
        guard fadesEdges, fade > 0, let canvas = scene?.config.canvasSize else {
            root.mask = nil
            return
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        edgeMask.frame = CGRect(origin: .zero, size: canvas)
        edgeMask.contents = Self.edgeMaskImage(canvas: canvas, fade: fade)
        edgeMask.contentsGravity = .resize
        root.mask = edgeMask
        CATransaction.commit()
    }

    /// Alpha mask, opaque in the middle and easing to clear over `fade` points at each edge.
    private static func edgeMaskImage(canvas: CGSize, fade: CGFloat) -> CGImage? {
        let scale: CGFloat = 0.25
        let w = Int(canvas.width * scale), h = Int(canvas.height * scale)
        let f = max(1, fade * scale)
        var pixels = [UInt8](repeating: 0, count: w * h)
        for y in 0..<h {
            let dy = CGFloat(min(y, h - 1 - y))
            for x in 0..<w {
                let d = min(CGFloat(min(x, w - 1 - x)), dy)
                let t = min(1, d / f)
                pixels[y * w + x] = UInt8(t * t * (3 - 2 * t) * 255)   // smoothstep
            }
        }
        return pixels.withUnsafeMutableBytes { buf in
            CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue)?
                .makeImage()
        }
    }

    private func makeLayer(_ spec: SceneConfig.Layer, image: CGImage?) -> CALayer? {
        guard spec.frame != nil, spec.hidden != true else { return nil }
        let layer = CALayer()
        let rect = spec.rect
        layer.bounds = CGRect(origin: .zero, size: rect.size)
        layer.anchorPoint = spec.anchorPoint
        layer.position = CGPoint(x: rect.minX + rect.width * layer.anchorPoint.x,
                                 y: rect.minY + rect.height * layer.anchorPoint.y)
        layer.contents = image
        layer.contentsGravity = .resize
        layer.minificationFilter = .trilinear
        layer.opacity = spec.opacity ?? 1
        layer.compositingFilter = Ambient.compositingFilter(spec.blend)
        layer.name = spec.slot
        return layer
    }

    private func makeDeck(_ scene: LoadedScene) -> CALayer {
        let d = scene.config.deck
        let deck = CALayer()
        deck.name = "deck"
        deck.bounds = CGRect(x: 0, y: 0, width: d.size[0], height: d.size[1])
        deck.position = CGPoint(x: d.center[0], y: d.center[1])
        var t = CATransform3DIdentity
        t.m34 = -1 / max(d.perspective, 1)
        deck.transform = CATransform3DRotate(t, d.tilt * .pi / 180, 1, 0, 0)

        for spec in d.layers {
            guard let layer = makeLayer(spec, image: scene.images[spec.slot]) else { continue }
            deck.addSublayer(layer)
            switch spec.slot {
            case "record":
                record = layer
                setUpLabel(on: layer, config: scene.config.record)
                // The sheen doesn't rotate with the record, like a real reflection.
                deck.addSublayer(makeSheen(over: layer, opacity: scene.config.record.sheenOpacity))
            case "tonearm":
                tonearm = layer
                layer.shadowColor = NSColor.black.cgColor
                layer.shadowOpacity = 0.5
                layer.shadowRadius = 2
                layer.shadowOffset = CGSize(width: 2, height: 3)
            default:
                break
            }
        }
        return deck
    }

    private func setUpLabel(on record: CALayer, config: SceneConfig.Record) {
        let d = record.bounds.width * config.labelDiameter
        label.bounds = CGRect(x: 0, y: 0, width: d, height: d)
        label.position = CGPoint(x: record.bounds.midX, y: record.bounds.midY)
        label.cornerRadius = d / 2
        label.masksToBounds = true
        label.contentsGravity = .resizeAspectFill
        label.minificationFilter = .trilinear
        record.addSublayer(label)

        let s = max(4, record.bounds.width * 0.025)
        spindle.bounds = CGRect(x: 0, y: 0, width: s, height: s)
        spindle.position = label.position
        spindle.cornerRadius = s / 2
        spindle.backgroundColor = NSColor(white: 0.78, alpha: 1).cgColor
        record.addSublayer(spindle)
    }

    private func makeSheen(over record: CALayer, opacity: Float) -> CALayer {
        let sheen = CAGradientLayer()
        sheen.type = .conic
        sheen.startPoint = CGPoint(x: 0.5, y: 0.5)
        sheen.endPoint = CGPoint(x: 0.5, y: 0)
        let clear = NSColor.white.withAlphaComponent(0).cgColor
        let glint = NSColor.white.withAlphaComponent(0.22).cgColor
        sheen.colors = [clear, glint, clear, clear, glint, clear, clear]
        sheen.locations = [0, 0.1, 0.22, 0.5, 0.6, 0.72, 1]
        sheen.frame = record.frame
        sheen.cornerRadius = record.bounds.width / 2
        sheen.masksToBounds = true
        sheen.opacity = opacity
        sheen.name = "sheen"
        return sheen
    }

    // MARK: - Playback

    func apply(_ input: PlaybackInput, animated: Bool) {
        self.input = input
        guard let scene else { return }

        crate.setWall(input.label, animated: animated)
        controls.setPlaying(input.isPlaying)

        let wantedLabel = input.label ?? scene.defaultLabel
        if wantedLabel !== shownLabel {
            setLabel(wantedLabel, animated: animated && shownLabel != nil)
        }

        if input.isPlaying != ambientActive {
            ambientActive = input.isPlaying
            setAmbient(active: input.isPlaying)
        }

        if input.isPlaying != spinning {
            spinning = input.isPlaying
            input.isPlaying ? startSpin(animated: animated) : stopSpin(animated: animated)
        }

        if input.isPlaying {
            if !armOnRecord {
                armOnRecord = true
                moveArmOntoRecord(duration: animated ? scene.config.tonearm.moveSeconds : 0)
            } else if !armMoving {
                resyncArm()
            }
        } else if armOnRecord {
            armOnRecord = false
            moveArmToRest(animated: animated)
        }
    }

    /// Recently played sleeves, newest first. A new front item slides off the wall into the crate.
    func setHistory(_ items: [SleeveCrate.Item], animated: Bool) {
        crateItems = items
        crate.setItems(items, animated: animated && scene != nil)
    }

    /// For snapshots: pull sleeve `index` out of the crate as if hovered.
    func browse(index: Int) {
        crate.setBrowse(index, animated: false)
    }

    // MARK: - Mouse (only delivered while DesktopWindowController lets this window take the mouse)

    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    /// Whether this point (view coordinates) is over something interactive: the turntable, its controls,
    /// the Up Next card or the crate. Everywhere else, clicks go through to the desktop.
    func isInteractive(at point: CGPoint) -> Bool {
        let p = canvasPoint(point)
        return turntableRect.contains(p) || (controls.isShown && controls.frame.insetBy(dx: -12, dy: -12).contains(p))
            || upNext.hitRect.contains(p) || crate.hitRect.contains(p)
    }

    /// For snapshots: show the controls as if hovered.
    func previewControls() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        controls.setShown(true)
        controls.layer.opacity = 1
        CATransaction.commit()
    }

    /// Pointer left everything interactive.
    func endBrowse() {
        crate.endBrowse()
        controls.setShown(false)
        upNext.hover(at: nil)
    }

    /// Called when a sleeve in the crate is clicked.
    var onPlayItem: ((SleeveCrate.Item) -> Void)?
    /// Called for play/pause, previous and next from the scene.
    var onCommand: ((PlayerCommand) -> Void)?
    /// Called when a song on the Up Next card is clicked.
    var onPlayQueued: ((QueueItem) -> Void)?

    // The window is never key, so take the very first click.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        click(at: convert(event.locationInWindow, from: nil))
    }

    /// Handles a click at a point in view coordinates.
    func click(at point: CGPoint) {
        hover(at: point)
        let p = canvasPoint(point)
        if let command = controls.command(at: p) {
            controls.pulse(command)
            onCommand?(command)
        } else if let item = upNext.item(at: p) {
            onPlayQueued?(item)
        } else if turntableRect.contains(p) {
            onCommand?(.playPause)
        } else if let item = crate.activateBrowsed() {
            onPlayItem?(item)
        }
    }

    /// Updates hover state for a pointer at a point in view coordinates.
    func hover(at point: CGPoint) {
        let p = canvasPoint(point)
        crate.hover(at: p)
        upNext.hover(at: p)
        let overDeck = turntableRect.contains(p) || (controls.isShown && controls.frame.insetBy(dx: -12, dy: -12).contains(p))
        controls.setShown(showsControls && overDeck)
        controls.highlight(controls.command(at: p))
    }

    override func mouseMoved(with event: NSEvent) {
        hover(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) { endBrowse() }

    override func scrollWheel(with event: NSEvent) { crate.scroll(by: event.scrollingDeltaY) }

    private func canvasPoint(_ viewPoint: CGPoint) -> CGPoint {
        root.convert(viewPoint, from: host)
    }

    private func setLabel(_ image: CGImage, animated: Bool) {
        shownLabel = image
        CATransaction.begin()
        if animated {
            let fade = CATransition()
            fade.type = .fade
            fade.duration = 0.8
            label.add(fade, forKey: "contents")
        } else {
            CATransaction.setDisableActions(true)
        }
        label.contents = image
        CATransaction.commit()
    }

    // MARK: Record

    private func restartSpinLoop() {
        guard let record else { return }
        spinGeneration += 1
        let angle = currentAngle(of: record)
        record.removeAnimation(forKey: "spin")
        addSpinLoop(from: angle)
    }

    private var omega: CGFloat {
        guard let rpm = rpmOverride ?? scene?.config.record.rpm, rpm > 0 else { return 0 }
        return CGFloat(rpm / 60) * 2 * .pi * Self.clockwise
    }

    private func currentAngle(of layer: CALayer) -> CGFloat {
        let source = layer.presentation() ?? layer
        return (source.value(forKeyPath: "transform.rotation.z") as? CGFloat) ?? 0
    }

    private func startSpin(animated: Bool) {
        guard let record, let cfg = scene?.config.record else { return }
        spinGeneration += 1
        let generation = spinGeneration
        let a0 = currentAngle(of: record)
        record.removeAnimation(forKey: "spin")

        guard animated, cfg.spinUpSeconds > 0 else {
            addSpinLoop(from: a0)
            return
        }
        // Constant acceleration up to full speed: covers half the distance full speed would.
        let a1 = a0 + omega * CGFloat(cfg.spinUpSeconds) / 2
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            guard let self, self.spinGeneration == generation else { return }
            self.addSpinLoop(from: a1)
        }
        let up = rotation(from: a0, to: a1, duration: cfg.spinUpSeconds,
                          timing: CAMediaTimingFunction(controlPoints: 1 / 3, 0, 2 / 3, 1 / 3))
        record.add(up, forKey: "spin")
        setModelAngle(record, a1)
        CATransaction.commit()
    }

    private func addSpinLoop(from angle: CGFloat) {
        guard let record, omega != 0 else { return }
        let loop = rotation(from: angle, to: angle + 2 * .pi * Self.clockwise,
                            duration: Double(2 * .pi / abs(omega)), timing: CAMediaTimingFunction(name: .linear))
        loop.repeatCount = .infinity
        setModelAngle(record, angle)
        record.add(loop, forKey: "spin")
    }

    private func stopSpin(animated: Bool) {
        guard let record, let cfg = scene?.config.record else { return }
        spinGeneration += 1
        let a0 = currentAngle(of: record)
        record.removeAnimation(forKey: "spin")
        guard animated, cfg.spinDownSeconds > 0 else {
            setModelAngle(record, a0)
            return
        }
        // Constant deceleration to rest; the ease-out curve starts at full speed so there's no jolt.
        let a1 = a0 + omega * CGFloat(cfg.spinDownSeconds) / 2
        let down = rotation(from: a0, to: a1, duration: cfg.spinDownSeconds,
                            timing: CAMediaTimingFunction(controlPoints: 1 / 3, 2 / 3, 2 / 3, 1))
        setModelAngle(record, a1)
        record.add(down, forKey: "spin")
    }

    // MARK: Tonearm

    private func armAngle(at progress: Double) -> CGFloat {
        guard let t = scene?.config.tonearm else { return 0 }
        let p = CGFloat(max(0, min(1, progress)))
        return radians(t.startAngle + (t.endAngle - t.startAngle) * p)
    }

    private var restAngle: CGFloat { radians(scene?.config.tonearm.restAngle ?? 0) }

    private func moveArmOntoRecord(duration: Double) {
        guard let tonearm else { return }
        armGeneration += 1
        let generation = armGeneration
        let a0 = currentAngle(of: tonearm)
        tonearm.removeAnimation(forKey: "arm")

        // Aim for where the stylus should be when the arm lands, then follow the song from there.
        let landingProgress = input.remaining > 0
            ? input.progress + duration / (input.remaining / max(1 - input.progress, 0.0001))
            : input.progress
        let landing = armAngle(at: landingProgress)

        guard duration > 0 else {
            setModelAngle(tonearm, armAngle(at: input.progress))
            startArmDrift(from: armAngle(at: input.progress), remaining: input.remaining)
            return
        }

        armMoving = true
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            guard let self, self.armGeneration == generation else { return }
            self.armMoving = false
            self.startArmDrift(from: landing, remaining: max(0, self.input.remaining))
        }
        tonearm.add(rotation(from: a0, to: landing, duration: duration,
                             timing: CAMediaTimingFunction(name: .easeInEaseOut)), forKey: "arm")
        tonearm.add(liftAnimation(duration: duration), forKey: "lift")
        setModelAngle(tonearm, landing)
        CATransaction.commit()
    }

    /// Linear sweep from here to the end angle over the rest of the song. Runs entirely in Core Animation.
    private func startArmDrift(from angle: CGFloat, remaining: Double) {
        guard let tonearm else { return }
        tonearm.removeAnimation(forKey: "arm")
        let end = armAngle(at: 1)
        guard remaining > 0.5 else {
            setModelAngle(tonearm, angle)
            return
        }
        setModelAngle(tonearm, end)
        tonearm.add(rotation(from: angle, to: end, duration: remaining,
                             timing: CAMediaTimingFunction(name: .linear)), forKey: "arm")
    }

    /// Called on each update while playing: corrects drift, and re-cues the arm after a seek or new track.
    private func resyncArm() {
        guard let tonearm else { return }
        let expected = armAngle(at: input.progress)
        let actual = currentAngle(of: tonearm)
        let diff = abs(expected - actual)
        if diff > radians(2) {
            moveArmOntoRecord(duration: 0.8)
        } else if diff > radians(0.2) {
            startArmDrift(from: actual, remaining: input.remaining)
        }
    }

    private func moveArmToRest(animated: Bool) {
        guard let tonearm, let cfg = scene?.config.tonearm else { return }
        armGeneration += 1
        armMoving = false
        let a0 = currentAngle(of: tonearm)
        tonearm.removeAnimation(forKey: "arm")
        setModelAngle(tonearm, restAngle)
        guard animated else { return }
        tonearm.add(rotation(from: a0, to: restAngle, duration: cfg.moveSeconds,
                             timing: CAMediaTimingFunction(name: .easeInEaseOut)), forKey: "arm")
        tonearm.add(liftAnimation(duration: cfg.moveSeconds), forKey: "lift")
    }

    /// The arm's shadow spreads while it's raised, so it reads as lifting off the record.
    private func liftAnimation(duration: Double) -> CAAnimation {
        let offset = CAKeyframeAnimation(keyPath: "shadowOffset")
        offset.values = [CGSize(width: 2, height: 3), CGSize(width: 7, height: 10),
                         CGSize(width: 7, height: 10), CGSize(width: 2, height: 3)].map { NSValue(size: $0) }
        let radius = CAKeyframeAnimation(keyPath: "shadowRadius")
        radius.values = [2, 6, 6, 2]
        let group = CAAnimationGroup()
        group.animations = [offset, radius]
        group.duration = duration
        offset.keyTimes = [0, 0.2, 0.8, 1]
        radius.keyTimes = [0, 0.2, 0.8, 1]
        return group
    }

    // MARK: Helpers

    private func rotation(from: CGFloat, to: CGFloat, duration: Double, timing: CAMediaTimingFunction) -> CABasicAnimation {
        let anim = CABasicAnimation(keyPath: "transform.rotation.z")
        anim.fromValue = from
        anim.toValue = to
        anim.duration = duration
        anim.timingFunction = timing
        return anim
    }

    private func setModelAngle(_ layer: CALayer, _ angle: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.setValue(angle, forKeyPath: "transform.rotation.z")
        CATransaction.commit()
    }

    private func radians(_ degrees: CGFloat) -> CGFloat { degrees * .pi / 180 * Self.clockwise }
}

extension NSImage {
    /// Centre square crop, for video thumbnails that aren't square.
    var squareCGImage: CGImage? {
        guard let cg = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let side = min(cg.width, cg.height)
        let rect = CGRect(x: (cg.width - side) / 2, y: (cg.height - side) / 2, width: side, height: side)
        return cg.cropping(to: rect) ?? cg
    }
}
