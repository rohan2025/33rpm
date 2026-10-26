import AppKit
import QuartzCore

/// The album sleeve leaning on the wall, and the crate of recently played sleeves.
/// Lives inside TurntableView's canvas (top-left origin, canvas points).
@MainActor
final class SleeveCrate {
    struct Item: Equatable {
        let id: UUID
        let image: CGImage?
        let title: String
        let artist: String
        var videoId: String? = nil
        static func == (a: Item, b: Item) -> Bool { a.id == b.id }
    }

    /// Sleeve on the wall. Added to the scene where the `sleeve` slot sits in scene.json.
    let wall = CALayer()
    /// Full-canvas container for crate sleeves, inserted just behind the crate's front panel.
    let stack = CALayer()
    /// Title/artist pill shown while browsing; added on top of everything.
    let caption = CALayer()
    private let captionText = CATextLayer()
    /// Room lighting over the wall sleeve.
    private let wallShade = CAGradientLayer()

    /// The `sleeve_shadow` layer; it leaves and returns with the wall sleeve.
    private weak var wallShadow: CALayer?
    private var wallShadowOpacity: Float = 1
    private var wallFrame = CGRect.zero
    private var wallRotation: CGFloat = 0
    private var crateFrame = CGRect.zero
    private var settings = SceneConfig.Crate()
    private var defaultSleeve: CGImage?

    private var items: [Item] = []
    private var layers: [UUID: CALayer] = [:]
    private(set) var browsing: Int?
    private var scrollAccumulator: CGFloat = 0

    private var shownWall: CGImage?
    private var desiredWall: CGImage?
    /// After a sleeve leaves the wall, keep the wall empty until new art arrives (or briefly, if it's the same art).
    private var wallHoldImage: CGImage?
    private var wallHoldUntil = Date.distantPast

    var hasCrate: Bool { crateFrame != .zero }
    private var sleeveSide: CGFloat { crateFrame.width * settings.sleeveSize }

    init() {
        for layer in [wall, caption] { layer.actions = ["position": NSNull(), "bounds": NSNull()] }
        wall.contentsGravity = .resizeAspectFill
        wall.masksToBounds = true
        wall.borderWidth = 1
        wall.borderColor = NSColor(white: 1, alpha: 0.12).cgColor
        wall.cornerRadius = 2
        wall.name = "sleeve"
        wall.addSublayer(wallShade)

        caption.backgroundColor = NSColor(white: 0.05, alpha: 0.72).cgColor
        caption.cornerRadius = 10
        caption.opacity = 0
        caption.addSublayer(captionText)
        captionText.isWrapped = false
        captionText.truncationMode = .end
        captionText.alignmentMode = .center
    }

    // MARK: - Setup (called on every scene load)

    func reset(defaultSleeve: CGImage, settings: SceneConfig.Crate?) {
        self.defaultSleeve = defaultSleeve
        self.settings = settings ?? SceneConfig.Crate()
        wallFrame = .zero
        crateFrame = .zero
        wallShadow = nil
        wallHoldImage = nil
        layers.values.forEach { $0.removeFromSuperlayer() }
        layers = [:]
        browsing = nil
        caption.opacity = 0
    }

    func configureWall(_ spec: SceneConfig.Layer) {
        wallFrame = spec.rect
        wallRotation = (spec.rotation ?? 0) * .pi / 180
        withoutAnimation {
            wall.bounds = CGRect(origin: .zero, size: wallFrame.size)
            wall.position = CGPoint(x: wallFrame.midX, y: wallFrame.midY)
            wall.setAffineTransform(CGAffineTransform(rotationAngle: wallRotation))
            wall.opacity = spec.opacity ?? 1
            wall.contents = shownWall ?? defaultSleeve
            wallShade.frame = wall.bounds
            applyLighting(to: wallShade, darkness: settings.sleeveShade)
        }
    }

    /// A black gradient: darkest on the side away from the light.
    private func applyLighting(to shade: CAGradientLayer, darkness: CGFloat) {
        let far = NSColor.black.withAlphaComponent(min(0.9, darkness * 1.25)).cgColor
        let near = NSColor.black.withAlphaComponent(min(0.9, darkness * 0.55)).cgColor
        switch settings.lightFrom {
        case "left": shade.colors = [near, far]
        case "none": shade.colors = [far, far]
        default: shade.colors = [far, near]
        }
        shade.startPoint = CGPoint(x: 0, y: 0.5)
        shade.endPoint = CGPoint(x: 1, y: 0.5)
    }

    func attachShadow(_ layer: CALayer) {
        wallShadow = layer
        wallShadowOpacity = layer.opacity
    }

    func configureCrate(_ spec: SceneConfig.Layer, canvas: CGSize) {
        crateFrame = spec.rect
        stack.frame = CGRect(origin: .zero, size: canvas)
        stack.name = "crate_stack"
        rebuildStack()
    }

    /// Text scale so the caption stays sharp after the canvas is scaled down.
    func setTextScale(_ scale: CGFloat) {
        captionText.contentsScale = scale
    }

    // MARK: - Wall sleeve

    func setWall(_ image: CGImage?, animated: Bool) {
        let desired = image ?? defaultSleeve
        desiredWall = desired
        guard wallFrame != .zero, let desired else { return }

        if wallHoldImage != nil {
            if desired === wallHoldImage && Date() < wallHoldUntil { return }
            wallHoldImage = nil
            reveal(desired, animated: animated)
            return
        }
        guard desired !== shownWall else { return }
        shownWall = desired
        CATransaction.begin()
        if animated {
            let fade = CATransition()
            fade.type = .fade
            fade.duration = 0.7
            wall.add(fade, forKey: "contents")
        } else {
            CATransaction.setDisableActions(true)
        }
        wall.contents = desired
        CATransaction.commit()
    }

    private func reveal(_ image: CGImage, animated: Bool) {
        shownWall = image
        withoutAnimation {
            wall.contents = image
            wall.opacity = 1
            wallShadow?.opacity = wallShadowOpacity
        }
        guard animated else { return }
        let shadowFade = CABasicAnimation(keyPath: "opacity")
        shadowFade.fromValue = 0
        shadowFade.toValue = wallShadowOpacity
        shadowFade.duration = 0.6
        wallShadow?.add(shadowFade, forKey: "reveal")
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        let drop = CABasicAnimation(keyPath: "position.y")
        drop.fromValue = wall.position.y - 24
        drop.toValue = wall.position.y
        let group = CAAnimationGroup()
        group.animations = [fade, drop]
        group.duration = 0.6
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        wall.add(group, forKey: "reveal")
    }

    // MARK: - Crate

    /// Newest first. When `animated` and a new item arrives at the front, it slides off the wall into the crate.
    func setItems(_ newItems: [Item], animated: Bool) {
        let incoming = newItems.first.flatMap { first in items.contains(first) ? nil : first }
        items = newItems
        guard hasCrate else { return }

        if animated, let incoming {
            launchFromWall(incoming)
        }
        rebuildStack(animated: animated, skipping: animated ? incoming?.id : nil)
        if let i = browsing { browsing = nil; setBrowse(min(i, items.count - 1), animated: animated) }
    }

    private func rebuildStack(animated: Bool = false, skipping: UUID? = nil) {
        guard hasCrate else { return }
        let ids = Set(items.map(\.id))
        for (id, layer) in layers where !ids.contains(id) {
            layers[id] = nil
            if animated {
                CATransaction.begin()
                CATransaction.setAnimationDuration(0.4)
                CATransaction.setCompletionBlock { layer.removeFromSuperlayer() }
                layer.opacity = 0
                CATransaction.commit()
            } else {
                layer.removeFromSuperlayer()
            }
        }

        CATransaction.begin()
        CATransaction.setAnimationDuration(animated ? 0.6 : 0)
        CATransaction.setDisableActions(!animated)
        for (index, item) in items.enumerated() {
            let layer = layers[item.id] ?? makeSleeveLayer(item)
            if layers[item.id] == nil {
                layers[item.id] = layer
                stack.addSublayer(layer)
            }
            if item.id != skipping { place(layer, at: index, lift: 0) }
        }
        CATransaction.commit()
    }

    private func makeSleeveLayer(_ item: Item) -> CALayer {
        let layer = CALayer()
        layer.contents = item.image ?? defaultSleeve
        layer.contentsGravity = .resizeAspectFill
        layer.masksToBounds = true
        layer.borderWidth = 1
        layer.borderColor = NSColor(white: 1, alpha: 0.1).cgColor
        layer.cornerRadius = 2
        layer.bounds = CGRect(x: 0, y: 0, width: sleeveSide, height: sleeveSide)
        let lighting = CAGradientLayer()
        lighting.name = "lighting"
        lighting.frame = layer.bounds
        applyLighting(to: lighting, darkness: settings.sleeveShade)
        layer.addSublayer(lighting)
        let shade = CALayer()
        shade.name = "shade"
        shade.backgroundColor = NSColor.black.cgColor
        shade.frame = layer.bounds
        layer.addSublayer(shade)
        return layer
    }

    /// Resting spot for the sleeve `index` places back from the front. Back sleeves sit a touch higher and darker,
    /// and each keeps its own slight tilt.
    private func place(_ layer: CALayer, at index: Int, lift: CGFloat) {
        guard let id = layers.first(where: { $0.value === layer })?.key else { return }
        let s = sleeveSide
        let (jx, jr) = jitter(id)
        let top = crateFrame.minY - s * settings.peek - CGFloat(index) * 2.2 - lift
        layer.bounds = CGRect(x: 0, y: 0, width: s, height: s)
        layer.position = CGPoint(x: crateFrame.midX + jx * crateFrame.width * 0.035, y: top + s / 2)
        layer.setAffineTransform(CGAffineTransform(rotationAngle: lift > 0 ? 0 : jr * .pi / 180 * 2))
        layer.zPosition = CGFloat(items.count - index)
        layer.opacity = 1
        let shade = layer.sublayers?.first { $0.name == "shade" }
        shade?.frame = layer.bounds
        shade?.opacity = lift > 0 ? 0 : Float(min(0.55, Double(index) * 0.07))
        layer.sublayers?.first { $0.name == "lighting" }?.frame = layer.bounds
    }

    private func jitter(_ id: UUID) -> (CGFloat, CGFloat) {
        let b = id.uuid
        return (CGFloat(b.0) / 127.5 - 1, CGFloat(b.1) / 127.5 - 1)
    }

    /// Copies the wall sleeve and arcs it over into the front of the crate.
    private func launchFromWall(_ item: Item) {
        let layer = makeSleeveLayer(item)
        layers[item.id] = layer
        stack.addSublayer(layer)

        let start = wallFrame != .zero ? wallFrame : CGRect(x: crateFrame.midX - 50, y: crateFrame.minY - 300,
                                                           width: 100, height: 100)
        // The flying copy takes over from the wall, which stays empty until the next sleeve arrives.
        if wallFrame != .zero {
            layer.contents = shownWall ?? item.image ?? defaultSleeve
            wallHoldImage = shownWall
            wallHoldUntil = Date().addingTimeInterval(1.6)
            withoutAnimation {
                wall.opacity = 0
                wallShadow?.opacity = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.65) { [weak self] in
                guard let self, self.wallHoldImage != nil else { return }
                self.setWall(self.desiredWall, animated: true)
            }
        }

        withoutAnimation { place(layer, at: 0, lift: 0) }
        let end = layer.position
        let endBounds = layer.bounds
        let endTransform = layer.transform

        let duration = 1.15
        let path = CGMutablePath()
        let from = CGPoint(x: start.midX, y: start.midY)
        path.move(to: from)
        path.addQuadCurve(to: end, control: CGPoint(x: (from.x + end.x) / 2,
                                                    y: min(start.minY, end.y - endBounds.height / 2) - 140))
        let move = CAKeyframeAnimation(keyPath: "position")
        move.path = path
        move.calculationMode = .paced
        let size = CABasicAnimation(keyPath: "bounds")
        size.fromValue = NSValue(rect: CGRect(origin: .zero, size: start.size))
        size.toValue = NSValue(rect: endBounds)
        let spin = CABasicAnimation(keyPath: "transform")
        spin.fromValue = NSValue(caTransform3D: CATransform3DMakeRotation(wallRotation, 0, 0, 1))
        spin.toValue = NSValue(caTransform3D: endTransform)

        let group = CAAnimationGroup()
        group.animations = [move, size, spin]
        group.duration = duration
        group.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(group, forKey: "fly")
        // The shade sublayer follows the bounds change.
        let shade = layer.sublayers?.first { $0.name == "shade" }
        let shadeSize = CABasicAnimation(keyPath: "bounds")
        shadeSize.fromValue = size.fromValue
        shadeSize.toValue = size.toValue
        shadeSize.duration = duration
        shadeSize.timingFunction = group.timingFunction
        shade?.add(shadeSize, forKey: "fly")
        layer.sublayers?.first { $0.name == "lighting" }?.add(shadeSize, forKey: "fly")
    }

    // MARK: - Browsing

    /// Canvas area that should take the mouse: the crate plus the sleeves sticking out of it.
    var hitRect: CGRect {
        guard hasCrate, !items.isEmpty else { return .zero }
        let s = sleeveSide
        let rise = s * (settings.peek + (browsing != nil ? settings.browseLift + 0.25 : 0.05))
        return CGRect(x: crateFrame.minX, y: crateFrame.minY - rise,
                      width: crateFrame.width, height: crateFrame.height + rise)
    }

    func hover(at point: CGPoint) {
        guard hitRect.contains(point), !items.isEmpty else {
            endBrowse()
            return
        }
        // Left edge = most recent, right edge = oldest.
        let f = max(0, min(0.999, (point.x - crateFrame.minX) / crateFrame.width))
        setBrowse(Int(f * CGFloat(items.count)), animated: true)
    }

    func scroll(by delta: CGFloat) {
        guard let current = browsing else { return }
        scrollAccumulator += delta
        guard abs(scrollAccumulator) > 10 else { return }
        let step = scrollAccumulator > 0 ? -1 : 1
        scrollAccumulator = 0
        setBrowse(max(0, min(items.count - 1, current + step)), animated: true)
    }

    func setBrowse(_ index: Int, animated: Bool) {
        guard index >= 0, index < items.count, index != browsing else { return }
        browsing = index
        CATransaction.begin()
        CATransaction.setAnimationDuration(animated ? 0.3 : 0)
        CATransaction.setDisableActions(!animated)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        for (i, item) in items.enumerated() {
            guard let layer = layers[item.id] else { continue }
            if i == index {
                place(layer, at: i, lift: sleeveSide * settings.browseLift)
                layer.zPosition = CGFloat(items.count + 1)
            } else {
                // Sleeves in front of the pulled one lean forward a little.
                place(layer, at: i, lift: i < index ? -sleeveSide * 0.05 : 0)
            }
        }
        CATransaction.commit()
        showCaption(for: items[index], animated: animated)
    }

    /// The sleeve currently pulled up, after a little bounce to acknowledge the click.
    func activateBrowsed() -> Item? {
        guard let index = browsing, index < items.count else { return nil }
        let item = items[index]
        if let layer = layers[item.id] {
            let bounce = CAKeyframeAnimation(keyPath: "transform.scale")
            bounce.values = [1, 1.08, 0.97, 1]
            bounce.keyTimes = [0, 0.35, 0.7, 1]
            bounce.duration = 0.35
            layer.add(bounce, forKey: "bounce")
        }
        return item
    }

    func endBrowse() {
        guard browsing != nil else { return }
        browsing = nil
        scrollAccumulator = 0
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.35)
        for (i, item) in items.enumerated() {
            if let layer = layers[item.id] { place(layer, at: i, lift: 0) }
        }
        caption.opacity = 0
        CATransaction.commit()
    }

    private func showCaption(for item: Item, animated: Bool) {
        let title = NSAttributedString(string: item.title, attributes: [
            .font: NSFont.systemFont(ofSize: 17, weight: .semibold),
            .foregroundColor: NSColor(white: 0.96, alpha: 1),
        ])
        let text = NSMutableAttributedString(attributedString: title)
        if !item.artist.isEmpty {
            text.append(NSAttributedString(string: "\n" + item.artist, attributes: [
                .font: NSFont.systemFont(ofSize: 14, weight: .regular),
                .foregroundColor: NSColor(white: 0.8, alpha: 1),
            ]))
        }
        let maxWidth: CGFloat = 340
        let measured = text.boundingRect(with: CGSize(width: 10_000, height: 200), options: [.usesLineFragmentOrigin])
        let size = CGSize(width: min(maxWidth, ceil(measured.width)) + 28, height: ceil(measured.height) + 16)
        let sleeveTop = crateFrame.minY - sleeveSide * (settings.peek + settings.browseLift)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        captionText.string = text
        caption.bounds = CGRect(origin: .zero, size: size)
        caption.position = CGPoint(x: crateFrame.midX, y: sleeveTop - 14 - size.height / 2)
        captionText.frame = caption.bounds.insetBy(dx: 14, dy: 8)
        CATransaction.commit()

        CATransaction.begin()
        CATransaction.setAnimationDuration(animated ? 0.2 : 0)
        caption.opacity = 1
        CATransaction.commit()
    }

    private func withoutAnimation(_ body: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        body()
        CATransaction.commit()
    }
}
