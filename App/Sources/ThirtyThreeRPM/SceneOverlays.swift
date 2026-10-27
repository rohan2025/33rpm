import AppKit
import QuartzCore

/// Previous / play-pause / next as softly lit symbols on the turntable's front edge, like a modern deck's
/// touch controls. They fade in only while the pointer is over the turntable.
/// Lives in TurntableView's canvas (top-left origin, canvas points).
@MainActor
final class PlaybackControls {
    let layer = CALayer()
    private let buttons: [(command: PlayerCommand, layer: CALayer)]
    private var isPlaying = false
    private(set) var isShown = false

    private static let glyphSize: CGFloat = 13
    private static let spacing: CGFloat = 34

    init() {
        buttons = [PlayerCommand.previous, .playPause, .next].map { ($0, CALayer()) }
        layer.name = "controls"
        layer.opacity = 0
        for (_, button) in buttons {
            button.contentsGravity = .resizeAspect
            // Warm backlight bleeding around the symbol.
            button.shadowColor = NSColor(red: 1, green: 0.7, blue: 0.35, alpha: 1).cgColor
            button.shadowOpacity = 0.9
            button.shadowRadius = 3
            button.shadowOffset = .zero
            button.opacity = 0.75
            layer.addSublayer(button)
        }
        updateGlyphs()
    }

    func configure(center: CGPoint, scale: CGFloat, rotation: CGFloat = 0) {
        let width = Self.spacing * 2 + Self.glyphSize * 2
        let height = Self.glyphSize * 2
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.bounds = CGRect(x: 0, y: 0, width: width, height: height)
        layer.position = center
        layer.setAffineTransform(CGAffineTransform(rotationAngle: rotation * .pi / 180).scaledBy(x: scale, y: scale))
        for (i, (_, button)) in buttons.enumerated() {
            button.bounds = CGRect(x: 0, y: 0, width: Self.glyphSize, height: Self.glyphSize)
            button.position = CGPoint(x: width / 2 + CGFloat(i - 1) * Self.spacing, y: height / 2)
        }
        CATransaction.commit()
    }

    var frame: CGRect { layer.frame }

    func setPlaying(_ playing: Bool) {
        guard playing != isPlaying else { return }
        isPlaying = playing
        updateGlyphs()
    }

    func setShown(_ shown: Bool) {
        guard shown != isShown else { return }
        isShown = shown
        CATransaction.begin()
        CATransaction.setAnimationDuration(shown ? 0.35 : 0.6)
        layer.opacity = shown ? 1 : 0
        CATransaction.commit()
        if !shown { highlight(nil) }
    }

    func command(at point: CGPoint) -> PlayerCommand? {
        guard isShown else { return nil }
        let local = layer.convert(point, from: layer.superlayer)
        let r = Self.spacing / 2
        for (command, button) in buttons {
            let dx = local.x - button.position.x, dy = local.y - button.position.y
            if dx * dx + dy * dy <= r * r { return command }
        }
        return nil
    }

    /// The symbol under the pointer glows brighter.
    func highlight(_ command: PlayerCommand?) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.15)
        for (c, button) in buttons {
            button.opacity = c == command ? 1 : 0.75
            button.shadowRadius = c == command ? 6 : 3
        }
        CATransaction.commit()
    }

    func pulse(_ command: PlayerCommand) {
        guard let button = buttons.first(where: { $0.command == command })?.layer else { return }
        let flash = CAKeyframeAnimation(keyPath: "shadowRadius")
        flash.values = [3, 12, 4]
        flash.duration = 0.4
        button.add(flash, forKey: "press")
    }

    private func updateGlyphs() {
        let names: [PlayerCommand: String] = [
            .previous: "backward.end.fill", .next: "forward.end.fill",
            .playPause: isPlaying ? "pause.fill" : "play.fill",
        ]
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (command, button) in buttons { button.contents = Self.lit(names[command] ?? "circle") }
        CATransaction.commit()
    }

    private static func lit(_ name: String) -> CGImage? {
        let config = NSImage.SymbolConfiguration(pointSize: 40, weight: .medium)
            .applying(NSImage.SymbolConfiguration(paletteColors: [NSColor(red: 1, green: 0.88, blue: 0.68, alpha: 1)]))
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return nil }
        return Placeholders.render(size: image.size, scale: 2) { _, rect in image.draw(in: rect) }
    }
}

/// A paper tracklist taped to the wall showing what YouTube Music plays next. Click a line to play it.
@MainActor
final class UpNextCard {
    let layer = CALayer()
    private let highlightLayer = CALayer()
    private var items: [QueueItem] = []
    private var shade: CGFloat = 0
    private var lightFrom = "right"
    private var hovered: Int?

    static let maxRows = 4
    private static let header: CGFloat = 62
    private static let rowHeight: CGFloat = 46
    private static let padding: CGFloat = 22

    init() {
        layer.name = "up_next"
        layer.contentsGravity = .resize
        layer.shadowColor = NSColor.black.cgColor
        layer.shadowOpacity = 0.55
        layer.shadowRadius = 9
        layer.shadowOffset = CGSize(width: 4, height: 7)
        layer.opacity = 0
        highlightLayer.backgroundColor = NSColor(red: 0.55, green: 0.32, blue: 0.12, alpha: 0.16).cgColor
        highlightLayer.cornerRadius = 6
        highlightLayer.opacity = 0
        layer.addSublayer(highlightLayer)
    }

    private var targetOpacity: Float = 1

    func configure(_ spec: SceneConfig.Layer, crate: SceneConfig.Crate?) {
        let rect = spec.rect
        shade = crate?.sleeveShade ?? 0
        lightFrom = crate?.lightFrom ?? "right"
        targetOpacity = spec.opacity ?? 1
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.bounds = CGRect(origin: .zero, size: rect.size)
        layer.position = CGPoint(x: rect.midX, y: rect.midY)
        layer.setAffineTransform(CGAffineTransform(rotationAngle: (spec.rotation ?? 0) * .pi / 180))
        CATransaction.commit()
        render()
    }

    var isShown: Bool { layer.opacity > 0 && !items.isEmpty }

    func setItems(_ newItems: [QueueItem], visible: Bool) {
        let rows = Array(newItems.prefix(Self.maxRows))
        if rows != items {
            items = rows
            hovered = nil
            render()
        }
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.4)
        layer.opacity = visible && !items.isEmpty ? targetOpacity : 0
        CATransaction.commit()
    }

    /// Which queued song is under a canvas point.
    func item(at point: CGPoint) -> QueueItem? {
        guard isShown, let row = row(at: point) else { return nil }
        return items[row]
    }

    func hover(at point: CGPoint?) {
        let row = point.flatMap { isShown ? self.row(at: $0) : nil }
        guard row != hovered else { return }
        hovered = row
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.12)
        if let row {
            CATransaction.setDisableActions(highlightLayer.opacity == 0)
            highlightLayer.frame = rowRect(row).insetBy(dx: -8, dy: 2)
            CATransaction.setDisableActions(false)
            highlightLayer.opacity = 1
        } else {
            highlightLayer.opacity = 0
        }
        CATransaction.commit()
    }

    /// Canvas-space area that takes the mouse.
    var hitRect: CGRect { isShown ? layer.frame : .zero }

    private func row(at point: CGPoint) -> Int? {
        let local = layer.convert(point, from: layer.superlayer)
        for i in items.indices where rowRect(i).insetBy(dx: -8, dy: 0).contains(local) { return i }
        return nil
    }

    private func rowRect(_ i: Int) -> CGRect {
        CGRect(x: Self.padding, y: Self.header + CGFloat(i) * Self.rowHeight,
               width: layer.bounds.width - Self.padding * 2, height: Self.rowHeight)
    }

    private func render() {
        let size = layer.bounds.size
        guard size.width > 0 else { return }
        let rows = items
        let shade = self.shade
        let lightFrom = self.lightFrom
        let image = Placeholders.render(size: size, scale: 3) { ctx, r in
            // Paper with a little warmth toward the edges.
            let paper = CGPath(roundedRect: r.insetBy(dx: 1, dy: 1), cornerWidth: 3, cornerHeight: 3, transform: nil)
            ctx.addPath(paper)
            ctx.clip()
            ctx.setFillColor(Placeholders.hex(0xEADFC8))
            ctx.fill(r)
            if let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                  colors: [Placeholders.hex(0x8A6A40, alpha: 0), Placeholders.hex(0x8A6A40, alpha: 0.22)] as CFArray,
                                  locations: [0.55, 1]) {
                ctx.drawRadialGradient(g, startCenter: CGPoint(x: r.midX, y: r.midY), startRadius: 0,
                                       endCenter: CGPoint(x: r.midX, y: r.midY), endRadius: max(r.width, r.height) * 0.75,
                                       options: [.drawsAfterEndLocation])
            }

            let ink = NSColor(red: 0.16, green: 0.12, blue: 0.09, alpha: 1)
            let faded = NSColor(red: 0.42, green: 0.35, blue: 0.28, alpha: 1)
            let typewriter = NSFont(name: "AmericanTypewriter", size: 15) ?? .monospacedSystemFont(ofSize: 15, weight: .regular)
            let serifBold = NSFont(name: "IowanOldStyle-Bold", size: 19) ?? NSFont(name: "Georgia-Bold", size: 19) ?? .boldSystemFont(ofSize: 19)
            let serif = NSFont(name: "IowanOldStyle-Italic", size: 14) ?? NSFont(name: "Georgia-Italic", size: 14) ?? .systemFont(ofSize: 14)

            func draw(_ text: String, _ font: NSFont, _ color: NSColor, _ rect: CGRect, kern: CGFloat = 0) {
                let style = NSMutableParagraphStyle()
                style.lineBreakMode = .byTruncatingTail
                (text as NSString).draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                                        attributes: [.font: font, .foregroundColor: color, .paragraphStyle: style, .kern: kern])
            }

            let pad = UpNextCard.padding
            draw("UP NEXT", typewriter, faded, CGRect(x: pad, y: 20, width: r.width - pad * 2, height: 22), kern: 3)
            ctx.setStrokeColor(faded.withAlphaComponent(0.5).cgColor)
            ctx.setLineWidth(1)
            ctx.move(to: CGPoint(x: pad, y: 48))
            ctx.addLine(to: CGPoint(x: r.width - pad, y: 48))
            ctx.strokePath()

            for (i, item) in rows.enumerated() {
                let y = UpNextCard.header + CGFloat(i) * UpNextCard.rowHeight
                draw(String(format: "%02d", i + 1), typewriter, faded, CGRect(x: pad, y: y + 4, width: 30, height: 20))
                draw(item.title, serifBold, ink, CGRect(x: pad + 34, y: y + 1, width: r.width - pad * 2 - 34, height: 24))
                draw(item.artist, serif, faded, CGRect(x: pad + 34, y: y + 24, width: r.width - pad * 2 - 34, height: 19))
            }

            // Room lighting, like the sleeves.
            if shade > 0, let g = CGGradient(
                colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                colors: [NSColor.black.withAlphaComponent(min(0.9, shade * 1.5)).cgColor,
                         NSColor.black.withAlphaComponent(min(0.9, shade * 0.75)).cgColor] as CFArray,
                locations: [0, 1]) {
                let fromLeft = lightFrom == "left"
                ctx.drawLinearGradient(g, start: CGPoint(x: fromLeft ? r.maxX : r.minX, y: r.midY),
                                       end: CGPoint(x: fromLeft ? r.minX : r.maxX, y: r.midY), options: [])
            }
            ctx.resetClip()

            // A strip of masking tape across the top.
            ctx.saveGState()
            ctx.translateBy(x: r.midX, y: 4)
            ctx.rotate(by: -0.04)
            ctx.setFillColor(NSColor(red: 0.93, green: 0.88, blue: 0.74, alpha: 0.72).cgColor)
            ctx.fill(CGRect(x: -36, y: -10, width: 72, height: 22))
            ctx.restoreGState()
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.contents = image
        CATransaction.commit()
    }
}

/// The current song on a small museum-style wall label beside the leaning sleeve, as if the cover were framed art.
@MainActor
final class WallTitle {
    let layer = CALayer()
    private var title = ""
    private var artist = ""
    private var visible = false
    private var shade: CGFloat = 0
    private var lightFrom = "right"

    init() {
        layer.name = "now_playing"
        layer.contentsGravity = .resize
        layer.opacity = 0
        layer.shadowColor = NSColor.black.cgColor
        layer.shadowOpacity = 0.55
        layer.shadowRadius = 3
        layer.shadowOffset = CGSize(width: 2, height: 3)
    }

    func configure(_ spec: SceneConfig.Layer, crate: SceneConfig.Crate?) {
        let rect = spec.rect
        shade = crate?.sleeveShade ?? 0
        lightFrom = crate?.lightFrom ?? "right"
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.bounds = CGRect(origin: .zero, size: rect.size)
        layer.position = CGPoint(x: rect.midX, y: rect.midY)
        layer.setAffineTransform(CGAffineTransform(rotationAngle: (spec.rotation ?? 0) * .pi / 180))
        layer.compositingFilter = Ambient.compositingFilter(spec.blend)
        layer.setValue(spec.opacity ?? 1, forKey: "targetOpacity")
        CATransaction.commit()
        title = ""
        render()
    }

    func set(title newTitle: String?, artist newArtist: String?, visible show: Bool, animated: Bool) {
        let t = newTitle ?? "", a = newArtist ?? ""
        let changed = t != title || a != artist
        title = t
        artist = a
        let target = (layer.value(forKey: "targetOpacity") as? Float) ?? 1
        let shouldShow = show && !t.isEmpty
        if changed && !t.isEmpty {
            CATransaction.begin()
            if animated && visible {
                let fade = CATransition()
                fade.type = .fade
                fade.duration = 0.8
                layer.add(fade, forKey: "contents")
            } else {
                CATransaction.setDisableActions(true)
            }
            render()
            CATransaction.commit()
        }
        guard shouldShow != visible else { return }
        visible = shouldShow
        CATransaction.begin()
        CATransaction.setAnimationDuration(animated ? 0.8 : 0)
        CATransaction.setDisableActions(!animated)
        layer.opacity = shouldShow ? target : 0
        CATransaction.commit()
    }

    private func render() {
        let size = layer.bounds.size
        guard size.width > 0, !title.isEmpty else { return }
        let title = self.title, artist = self.artist
        let shade = self.shade, lightFrom = self.lightFrom
        layer.contents = Placeholders.render(size: size, scale: 4) { ctx, r in
            // Matte card stock.
            ctx.setFillColor(Placeholders.hex(0xEDE7DB))
            ctx.fill(r)
            let pad: CGFloat = 11
            let ink = NSColor(red: 0.13, green: 0.11, blue: 0.09, alpha: 1)
            let grey = NSColor(red: 0.42, green: 0.38, blue: 0.33, alpha: 1)
            let kickerFont = NSFont(name: "AvenirNext-DemiBold", size: 6.5) ?? .systemFont(ofSize: 6.5, weight: .semibold)
            let artistFont = NSFont(name: "AvenirNext-Regular", size: 9.5) ?? .systemFont(ofSize: 9.5)
            let left = NSMutableParagraphStyle()
            left.lineBreakMode = .byTruncatingTail

            // Title: the largest size that fits in two lines.
            let width = r.width - pad * 2
            var size: CGFloat = 14
            var titleFont = NSFont(name: "AvenirNext-DemiBold", size: size) ?? .boldSystemFont(ofSize: size)
            var titleHeight: CGFloat = 0
            let wrap = NSMutableParagraphStyle()
            wrap.lineBreakMode = .byWordWrapping
            while size > 9 {
                titleFont = NSFont(name: "AvenirNext-DemiBold", size: size) ?? .boldSystemFont(ofSize: size)
                titleHeight = (title as NSString).boundingRect(
                    with: CGSize(width: width, height: 200), options: [.usesLineFragmentOrigin],
                    attributes: [.font: titleFont, .paragraphStyle: wrap]).height
                if titleHeight <= size * 2.6 { break }
                size -= 1
            }
            titleHeight = min(titleHeight, size * 2.6)

            let block = 9 + titleHeight + 2 + 13
            var y = max(pad - 2, (r.height - block) / 2)
            ("NOW PLAYING" as NSString).draw(
                with: CGRect(x: pad, y: y, width: width, height: 9), options: [.usesLineFragmentOrigin],
                attributes: [.font: kickerFont, .foregroundColor: grey, .kern: 1.6])
            y += 10
            (title as NSString).draw(
                with: CGRect(x: pad, y: y, width: width, height: titleHeight + 2),
                options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                attributes: [.font: titleFont, .foregroundColor: ink, .paragraphStyle: wrap])
            y += titleHeight + 2
            if !artist.isEmpty {
                (artist as NSString).draw(
                    with: CGRect(x: pad, y: y, width: width, height: 13),
                    options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                    attributes: [.font: artistFont, .foregroundColor: grey, .paragraphStyle: left])
            }

            // Room light, darker away from the lamp.
            if shade > 0, let g = CGGradient(
                colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                colors: [NSColor.black.withAlphaComponent(min(0.85, shade * 1.25)).cgColor,
                         NSColor.black.withAlphaComponent(min(0.85, shade * 0.6)).cgColor] as CFArray,
                locations: [0, 1]) {
                let fromLeft = lightFrom == "left"
                ctx.drawLinearGradient(g, start: CGPoint(x: fromLeft ? r.maxX : r.minX, y: r.midY),
                                       end: CGPoint(x: fromLeft ? r.minX : r.maxX, y: r.midY), options: [])
            }
        }
    }
}

/// The vintage receiver sitting in the console: its amber display shows the song, and three of its knobs are
/// previous / play-pause / next. The receiver itself is part of the room photo; this draws only the live parts.
@MainActor
final class ReceiverOverlay {
    let layer = CALayer()
    private let screen = CALayer()            // the display window, in the photo's perspective
    private let panel = CALayer()             // our own dark VFD glass, filling the window
    private let display = CALayer()           // clips the text, right of the play/pause mark
    private let ghost = CALayer()             // every unlit dot, faintly visible behind the glass
    private let glass = CALayer()             // bezel shadow and a faint reflection over the text
    private let titleLine = CALayer()         // each line scrolls on its own when it's too long
    private let artistLine = CALayer()
    private let stateGlyph = CALayer()
    private var knobs: [(command: PlayerCommand, center: CGPoint, radius: CGFloat, ring: CAShapeLayer, press: CALayer)] = []
    private var labels: [CALayer] = []
    private var displayRect = CGRect.zero
    /// The dot-matrix grid: two lines of `cellsWide` characters, `pitch` points between dots.
    private var grid = (origin: CGPoint.zero, pitch: CGFloat(1), cellsWide: 13, lineGap: CGFloat(3))
    private var title = ""
    private var artist = ""
    private var isPlaying = false
    private var flashing = false
    private(set) var isConfigured = false
    var controlsEnabled = true {
        didSet { labels.forEach { $0.opacity = controlsEnabled ? 1 : 0 }; if !controlsEnabled { highlight(nil) } }
    }
    var showsTitle = true {
        didSet { if showsTitle != oldValue { renderText() } }
    }

    private static let amber = NSColor(red: 1.0, green: 0.71, blue: 0.32, alpha: 1)

    init() {
        layer.name = "receiver"
        display.masksToBounds = true
        layer.addSublayer(screen)
        panel.contentsGravity = .resize
        screen.addSublayer(panel)
        ghost.contentsGravity = .resize
        screen.addSublayer(ghost)
        screen.addSublayer(display)
        display.addSublayer(titleLine)
        display.addSublayer(artistLine)
        for l in [titleLine, artistLine, stateGlyph] {
            l.contentsGravity = .resize
            l.anchorPoint = .zero
            // Lit from behind the smoked glass: adds light to it instead of painting over it.
            l.compositingFilter = "screenBlendMode"
            l.shadowColor = Self.amber.cgColor
            l.shadowOpacity = 0.75
            l.shadowRadius = 1.4
            l.shadowOffset = .zero
        }
        screen.addSublayer(stateGlyph)
        screen.addSublayer(glass)
    }

    func configure(_ spec: SceneConfig.Receiver, canvas: CGSize) {
        let d = spec.display
        displayRect = CGRect(x: d[0], y: d[1], width: d[2], height: d[3])
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.frame = CGRect(origin: .zero, size: canvas)
        // Everything on the display is laid out flat in `inner`, then projected onto the window's corners.
        let corners = (spec.window ?? []).filter { $0.count >= 2 }.map { CGPoint(x: $0[0], y: $0[1]) }
        let inner: CGRect
        screen.anchorPoint = .zero
        if corners.count == 4 {
            inner = CGRect(x: 0, y: 0,
                           width: ((corners[1].x - corners[0].x) + (corners[2].x - corners[3].x)) / 2,
                           height: ((corners[3].y - corners[0].y) + (corners[2].y - corners[1].y)) / 2)
            screen.bounds = inner
            screen.position = .zero
            screen.transform = Self.projection(of: inner.size, onto: corners)
            panel.frame = inner
            panel.contents = Self.panelImage(size: inner.size)
            panel.isHidden = false
        } else {
            inner = CGRect(origin: .zero, size: displayRect.size)
            screen.transform = CATransform3DIdentity
            screen.bounds = inner
            screen.position = displayRect.origin
            panel.isHidden = true
        }
        // Two lines of 5×7 characters with a little dark glass around them, like a real 2-line VFD.
        let cellsWide = 13
        let lineGap: CGFloat = 2.5   // in dots
        let pitch = min((inner.width - 14) / CGFloat(cellsWide * DotMatrix.cellDots - 1),
                        (inner.height - 12) / (CGFloat(DotMatrix.rows * 2) + lineGap + 2))
        let gridSize = CGSize(width: CGFloat(cellsWide * DotMatrix.cellDots - 1) * pitch,
                              height: (CGFloat(DotMatrix.rows * 2) + lineGap) * pitch)
        grid = (CGPoint(x: (inner.width - gridSize.width) / 2, y: (inner.height - gridSize.height) / 2),
                pitch, cellsWide, lineGap * pitch)
        ghost.frame = CGRect(origin: grid.origin, size: gridSize)
        ghost.contents = DotMatrix.ghost(cellsWide: cellsWide, lines: 2, lineGap: grid.lineGap, pitch: pitch,
                                         color: Self.amber.withAlphaComponent(0.075))
        glass.frame = inner
        glass.contents = Self.glassImage(size: inner.size)
        glass.contentsGravity = .resize
        // The legends lean with the row of knobs, which the photo shows slightly from below-left.
        let row = spec.knobs.count >= 2 ? atan2(spec.knobs.last![1] - spec.knobs[0][1], spec.knobs.last![0] - spec.knobs[0][0]) : 0
        knobs.forEach { $0.ring.removeFromSuperlayer(); $0.press.removeFromSuperlayer() }
        labels.forEach { $0.removeFromSuperlayer() }
        knobs = []
        labels = []
        let commands: [PlayerCommand] = [.previous, .playPause, .next]
        let marks = ["backward.fill", "playpause.fill", "forward.fill"]
        for (i, k) in spec.knobs.prefix(3).enumerated() where k.count >= 3 {
            let center = CGPoint(x: k[0], y: k[1]), r = k[2]
            let ring = CAShapeLayer()
            ring.path = CGPath(ellipseIn: CGRect(x: center.x - r - 2, y: center.y - r - 2, width: (r + 2) * 2, height: (r + 2) * 2), transform: nil)
            ring.fillColor = nil
            ring.strokeColor = Self.amber.withAlphaComponent(0.85).cgColor
            ring.lineWidth = 1.2
            ring.shadowColor = Self.amber.cgColor
            ring.shadowOpacity = 1
            ring.shadowRadius = 4
            ring.shadowOffset = .zero
            ring.opacity = 0
            let press = CALayer()
            press.frame = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
            press.cornerRadius = r
            press.backgroundColor = NSColor.black.cgColor
            press.opacity = 0
            layer.addSublayer(press)
            layer.addSublayer(ring)
            // A tiny printed legend above the knob, like the labels on real hi-fi gear.
            let label = CALayer()
            let lw: CGFloat = 9, lh: CGFloat = 5
            label.frame = CGRect(x: center.x - lw / 2, y: center.y - r - lh - 2.5, width: lw, height: lh)
            label.contents = Self.legend(marks[i])
            label.contentsGravity = .resizeAspect
            label.setAffineTransform(CGAffineTransform(rotationAngle: row * 0.6))
            label.opacity = controlsEnabled ? 1 : 0
            layer.addSublayer(label)
            labels.append(label)
            knobs.append((commands[i], center, r, ring, press))
        }
        CATransaction.commit()
        isConfigured = true
        renderText()
    }

    var hitRect: CGRect {
        guard isConfigured, controlsEnabled else { return .zero }
        return knobs.reduce(CGRect.null) { $0.union(CGRect(x: $1.center.x - $1.radius - 6, y: $1.center.y - $1.radius - 10,
                                                          width: ($1.radius + 6) * 2, height: ($1.radius + 8) * 2)) }
    }

    func command(at point: CGPoint) -> PlayerCommand? {
        guard controlsEnabled else { return nil }
        for k in knobs {
            let dx = point.x - k.center.x, dy = point.y - k.center.y
            if dx * dx + dy * dy <= (k.radius + 5) * (k.radius + 5) { return k.command }
        }
        return nil
    }

    func highlight(_ command: PlayerCommand?) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.18)
        for k in knobs { k.ring.opacity = k.command == command ? 1 : 0 }
        CATransaction.commit()
    }

    /// The knob sinks for a moment and the display confirms the action.
    func press(_ command: PlayerCommand) {
        guard let k = knobs.first(where: { $0.command == command }) else { return }
        let sink = CAKeyframeAnimation(keyPath: "opacity")
        sink.values = [0, 0.45, 0]
        sink.duration = 0.3
        k.press.add(sink, forKey: "press")
        let word: String
        switch command {
        case .previous: word = "<< PREV"
        case .next: word = "NEXT >>"
        default: word = isPlaying ? "❚ PAUSE" : "▶ PLAY"
        }
        flashing = true
        stateGlyph.opacity = 0
        show(word, nil, leading: false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { [weak self] in
            self?.flashing = false
            self?.renderText()
        }
    }

    func set(title newTitle: String?, artist newArtist: String?, playing: Bool) {
        let t = newTitle ?? "", a = newArtist ?? ""
        let changed = t != title || a != artist || playing != isPlaying
        title = t
        artist = a
        isPlaying = playing
        if changed { renderText() }
    }

    private func renderText() {
        guard isConfigured, !flashing else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        stateGlyph.contents = title.isEmpty || !showsTitle ? nil
            : DotMatrix.render(DotMatrix.cells(isPlaying ? "▶" : "❚"), pitch: grid.pitch, color: Self.amber).image
        stateGlyph.opacity = 1
        CATransaction.commit()
        if title.isEmpty || !showsTitle {
            show("33⅓ RPM", nil, dim: true, leading: false)
        } else {
            show(title.uppercased(), artist.isEmpty ? nil : artist.uppercased(), leading: true)
        }
    }

    /// Title on the first line, artist on the second, in the display's fixed character cells. `leading` keeps the
    /// first two cells for the play/pause mark; otherwise a single line is centred.
    private func show(_ line1: String, _ line2: String?, dim: Bool = false, leading: Bool) {
        let p = grid.pitch
        let cell = CGFloat(DotMatrix.cellDots) * p
        let lineHeight = CGFloat(DotMatrix.rows) * p
        let firstCell = leading ? 2 : 0
        let visible = grid.cellsWide - firstCell
        let color = Self.amber.withAlphaComponent(dim ? 0.45 : 0.95)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        display.frame = CGRect(x: grid.origin.x + CGFloat(firstCell) * cell, y: grid.origin.y,
                               width: CGFloat(visible) * cell - p, height: lineHeight * 2 + grid.lineGap)
        place(titleLine, DotMatrix.cells(line1), y: 0, visible: visible, centred: !leading, color: color)
        if let line2 {
            artistLine.isHidden = false
            place(artistLine, DotMatrix.cells(line2), y: lineHeight + grid.lineGap, visible: visible, centred: !leading,
                  color: color.withAlphaComponent(dim ? 0.35 : 0.6))
        } else {
            artistLine.isHidden = true
            artistLine.removeAnimation(forKey: "marquee")
        }
        stateGlyph.frame = CGRect(x: grid.origin.x, y: grid.origin.y, width: CGFloat(DotMatrix.columns) * p, height: lineHeight)
        CATransaction.commit()
    }

    /// Lays out one line in its cells. Too long: it steps along a character at a time, the way these displays
    /// scroll, pauses at the end and jumps back.
    private func place(_ line: CALayer, _ cells: [[UInt8]], y: CGFloat, visible: Int, centred: Bool, color: NSColor) {
        let cell = CGFloat(DotMatrix.cellDots) * grid.pitch
        let rendered = DotMatrix.render(cells, pitch: grid.pitch, color: color)
        line.removeAnimation(forKey: "marquee")
        let fadeIn = CATransition()
        fadeIn.type = .fade
        fadeIn.duration = 0.2
        line.add(fadeIn, forKey: "contents")
        line.contents = rendered.image
        let x = cells.count < visible && centred ? CGFloat((visible - cells.count) / 2) * cell : 0
        line.frame = CGRect(origin: CGPoint(x: x, y: y), size: rendered.size)
        let steps = cells.count - visible
        guard steps > 0 else { return }
        let hold = 2.5, step = 0.32, end = 1.8
        let total = hold + Double(steps) * step + end
        let anim = CAKeyframeAnimation(keyPath: "position.x")
        anim.calculationMode = .discrete
        var values: [CGFloat] = [0], times: [NSNumber] = [0]
        for k in 1...steps {
            values.append(-CGFloat(k) * cell)
            times.append(NSNumber(value: (hold + Double(k - 1) * step) / total))
        }
        values.append(-CGFloat(steps) * cell)
        times.append(1)
        anim.values = values
        anim.keyTimes = times
        anim.duration = total
        anim.repeatCount = .infinity
        line.add(anim, forKey: "marquee")
    }

    /// The perspective transform that maps a flat `size` rectangle (anchored at its top-left) onto four corners:
    /// top-left, top-right, bottom-right, bottom-left. A standard square-to-quad homography.
    static func projection(of size: CGSize, onto q: [CGPoint]) -> CATransform3D {
        let (p0, p1, p2, p3) = (q[0], q[1], q[2], q[3])
        let dx1 = p1.x - p2.x, dx2 = p3.x - p2.x, dx3 = p0.x - p1.x + p2.x - p3.x
        let dy1 = p1.y - p2.y, dy2 = p3.y - p2.y, dy3 = p0.y - p1.y + p2.y - p3.y
        let den = dx1 * dy2 - dx2 * dy1
        let g = den == 0 ? 0 : (dx3 * dy2 - dx2 * dy3) / den
        let h = den == 0 ? 0 : (dx1 * dy3 - dx3 * dy1) / den
        let a = p1.x - p0.x + g * p1.x, b = p3.x - p0.x + h * p3.x
        let d = p1.y - p0.y + g * p1.y, e = p3.y - p0.y + h * p3.y
        var t = CATransform3DIdentity
        t.m11 = a / size.width; t.m12 = d / size.width; t.m14 = g / size.width
        t.m21 = b / size.height; t.m22 = e / size.height; t.m24 = h / size.height
        t.m41 = p0.x; t.m42 = p0.y
        return t
    }

    /// Smoked VFD glass sitting in the window: near-black with a warm cast, deeper at the edges where the bezel
    /// shades it, so it reads as a recessed screen rather than a flat panel.
    private static func panelImage(size: CGSize) -> CGImage? {
        Placeholders.render(size: size, scale: 4) { ctx, r in
            let space = CGColorSpaceCreateDeviceRGB()
            ctx.setFillColor(NSColor(srgbRed: 0.075, green: 0.05, blue: 0.035, alpha: 1).cgColor)
            ctx.fill(r)
            // Recess: the bezel's shadow along the top and left, falling off inward.
            let edge = min(r.width, r.height) * 0.22
            for (start, end) in [(CGPoint(x: 0, y: 0), CGPoint(x: 0, y: edge)),
                                 (CGPoint(x: 0, y: 0), CGPoint(x: edge * 0.7, y: 0)),
                                 (CGPoint(x: r.width, y: 0), CGPoint(x: r.width - edge * 0.5, y: 0)),
                                 (CGPoint(x: 0, y: r.height), CGPoint(x: 0, y: r.height - edge * 0.5))] {
                if let g = CGGradient(colorsSpace: space, colors: [NSColor(white: 0, alpha: 0.75).cgColor,
                                                                   NSColor(white: 0, alpha: 0).cgColor] as CFArray,
                                      locations: [0, 1]) {
                    ctx.drawLinearGradient(g, start: start, end: end, options: [])
                }
            }
            // A hairline where the glass meets the frame.
            ctx.setStrokeColor(NSColor(white: 0, alpha: 0.85).cgColor)
            ctx.setLineWidth(1.2)
            ctx.stroke(r.insetBy(dx: 0.6, dy: 0.6))
        }
    }

    /// Dark silkscreen printing on the brushed faceplate, with a hairline of light catching its lower edge.
    private static func legend(_ name: String) -> CGImage? {
        func symbol(_ color: NSColor) -> NSImage? {
            let config = NSImage.SymbolConfiguration(pointSize: 30, weight: .semibold)
                .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
            return NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config)
        }
        guard let ink = symbol(NSColor(white: 0.06, alpha: 0.78)),
              let catchLight = symbol(NSColor(white: 1, alpha: 0.16)) else { return nil }
        let size = CGSize(width: ink.size.width, height: ink.size.height + 2.5)
        return Placeholders.render(size: size, scale: 2) { _, _ in   // flipped: y grows downward
            catchLight.draw(in: CGRect(x: 0, y: 2.5, width: ink.size.width, height: ink.size.height))
            ink.draw(in: CGRect(x: 0, y: 0, width: ink.size.width, height: ink.size.height))
        }
    }

    /// Smoked glass: the bezel's shadow along the top, a soft falloff at the bottom and one diagonal reflection.
    private static func glassImage(size: CGSize) -> CGImage? {
        Placeholders.render(size: size, scale: 4) { ctx, r in
            let space = CGColorSpaceCreateDeviceRGB()
            if let shade = CGGradient(colorsSpace: space, colors: [
                NSColor(white: 0, alpha: 0.4).cgColor, NSColor(white: 0, alpha: 0).cgColor,
                NSColor(white: 0, alpha: 0).cgColor, NSColor(white: 0, alpha: 0.2).cgColor] as CFArray,
                                      locations: [0, 0.3, 0.75, 1]) {
                ctx.drawLinearGradient(shade, start: CGPoint(x: 0, y: r.minY), end: CGPoint(x: 0, y: r.maxY), options: [])
            }
            if let sheen = CGGradient(colorsSpace: space, colors: [
                NSColor(white: 1, alpha: 0).cgColor, NSColor(white: 1, alpha: 0.035).cgColor,
                NSColor(white: 1, alpha: 0).cgColor] as CFArray, locations: [0.3, 0.42, 0.58]) {
                ctx.drawLinearGradient(sheen, start: CGPoint(x: r.minX, y: r.minY), end: CGPoint(x: r.maxX, y: r.maxY), options: [])
            }
        }
    }
}
