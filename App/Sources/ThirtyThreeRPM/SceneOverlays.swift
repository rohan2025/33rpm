import AppKit
import QuartzCore

/// Previous / play-pause / next as a small brushed-brass faceplate on the console, with engraved symbols.
/// Lives in TurntableView's canvas (top-left origin, canvas points).
@MainActor
final class PlaybackControls {
    let layer = CALayer()
    private let plate = CALayer()
    /// Room light over the plate (the engravings sit on top and keep their own highlights).
    private let dimmer = CAGradientLayer()
    private let buttons: [(command: PlayerCommand, layer: CALayer)]
    private var isPlaying = false
    private(set) var isShown = false

    static let plateSize = CGSize(width: 196, height: 52)
    private static let buttonDiameter: CGFloat = 36
    private static let spacing: CGFloat = 56

    init() {
        buttons = [PlayerCommand.previous, .playPause, .next].map { ($0, CALayer()) }
        layer.name = "controls"
        layer.opacity = 0
        layer.shadowColor = NSColor.black.cgColor
        layer.shadowOpacity = 0.55
        layer.shadowRadius = 4
        layer.shadowOffset = CGSize(width: 0, height: 3)
        plate.contentsGravity = .resize
        layer.addSublayer(plate)
        dimmer.cornerRadius = 9
        dimmer.startPoint = CGPoint(x: 0, y: 0.5)
        dimmer.endPoint = CGPoint(x: 1, y: 0.5)
        layer.addSublayer(dimmer)
        for (_, button) in buttons {
            button.contentsGravity = .resizeAspect
            layer.addSublayer(button)
        }
        setPlate(nil)
        updateGlyphs()
    }

    /// Uses a photographed plate if the scene has one (control_plate.png), otherwise a drawn brass plate.
    func setPlate(_ image: CGImage?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        plate.contents = image ?? Self.drawnPlate
        CATransaction.commit()
    }

    func configure(center: CGPoint, scale: CGFloat, shade: CGFloat = 0, lightFrom: String = "right") {
        let size = Self.plateSize
        let far = NSColor.black.withAlphaComponent(min(0.8, shade * 1.3)).cgColor
        let near = NSColor.black.withAlphaComponent(min(0.8, shade * 0.7)).cgColor
        dimmer.colors = lightFrom == "left" ? [near, far] : [far, near]
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.bounds = CGRect(origin: .zero, size: size)
        layer.position = center
        layer.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
        plate.frame = layer.bounds
        dimmer.frame = layer.bounds
        for (i, (_, button)) in buttons.enumerated() {
            let d = Self.buttonDiameter * 0.5
            button.bounds = CGRect(x: 0, y: 0, width: d, height: d)
            button.position = CGPoint(x: size.width / 2 + CGFloat(i - 1) * Self.spacing, y: size.height / 2)
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
        CATransaction.setAnimationDuration(0.4)
        layer.opacity = shown ? 1 : 0
        CATransaction.commit()
        if !shown { highlight(nil) }
    }

    func command(at point: CGPoint) -> PlayerCommand? {
        guard isShown else { return nil }
        let local = layer.convert(point, from: layer.superlayer)
        let r = Self.buttonDiameter / 2 + 6
        for (command, button) in buttons {
            let dx = local.x - button.position.x, dy = local.y - button.position.y
            if dx * dx + dy * dy <= r * r { return command }
        }
        return nil
    }

    /// Hovered button: its engraving catches a little more light.
    func highlight(_ command: PlayerCommand?) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.15)
        for (c, button) in buttons { button.opacity = c == command ? 1 : 0.82 }
        CATransaction.commit()
    }

    /// The button sinks into the plate for a moment.
    func pulse(_ command: PlayerCommand) {
        guard let button = buttons.first(where: { $0.command == command })?.layer else { return }
        let press = CAKeyframeAnimation(keyPath: "transform.scale")
        press.values = [1, 0.86, 1]
        press.keyTimes = [0, 0.35, 1]
        press.duration = 0.22
        button.add(press, forKey: "press")
    }

    private func updateGlyphs() {
        let names: [PlayerCommand: String] = [
            .previous: "backward.end.fill", .next: "forward.end.fill",
            .playPause: isPlaying ? "pause.fill" : "play.fill",
        ]
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (command, button) in buttons { button.contents = Self.engraved(names[command] ?? "circle") }
        CATransaction.commit()
    }

    /// A symbol cut into brass: dark recess with a thin light edge below it.
    private static func engraved(_ name: String) -> CGImage? {
        let config = NSImage.SymbolConfiguration(pointSize: 40, weight: .bold)
        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return nil }
        func tinted(_ color: NSColor) -> NSImage {
            let img = NSImage(size: base.size)
            img.lockFocus()
            base.draw(in: NSRect(origin: .zero, size: base.size))
            color.set()
            NSRect(origin: .zero, size: base.size).fill(using: .sourceAtop)
            img.unlockFocus()
            return img
        }
        let highlight = tinted(NSColor(red: 1, green: 0.93, blue: 0.75, alpha: 0.55))
        let recess = tinted(NSColor(red: 0.18, green: 0.11, blue: 0.04, alpha: 0.9))
        let pad: CGFloat = 4
        let size = CGSize(width: base.size.width + pad * 2, height: base.size.height + pad * 2)
        return Placeholders.render(size: size, scale: 2) { _, r in
            highlight.draw(in: CGRect(x: pad, y: pad + 1.6, width: base.size.width, height: base.size.height))
            recess.draw(in: CGRect(x: pad, y: pad, width: base.size.width, height: base.size.height))
        }
    }

    /// Brushed brass plate with a bevel and three slightly domed buttons.
    private static let drawnPlate: CGImage? = {
        let size = plateSize
        return Placeholders.render(size: size, scale: 4) { ctx, r in
            let srgb = CGColorSpace(name: CGColorSpace.sRGB)
            let body = CGPath(roundedRect: r.insetBy(dx: 1, dy: 1), cornerWidth: 9, cornerHeight: 9, transform: nil)
            ctx.addPath(body)
            ctx.clip()
            // Brass: warm vertical gradient...
            let brass = [Placeholders.hex(0xD9B77A), Placeholders.hex(0xB48A4C), Placeholders.hex(0x8A6532)] as CFArray
            if let g = CGGradient(colorsSpace: srgb, colors: brass, locations: [0, 0.45, 1]) {
                ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: r.minY), end: CGPoint(x: 0, y: r.maxY), options: [])
            }
            // ...with fine horizontal brushing.
            var seed: UInt32 = 7
            for y in stride(from: r.minY, to: r.maxY, by: 0.5) {
                seed = seed &* 1_103_515_245 &+ 12_345
                let a = CGFloat((seed >> 16) & 0xFF) / 255 * 0.09
                ctx.setFillColor(NSColor(white: (seed & 1) == 0 ? 1 : 0, alpha: a).cgColor)
                ctx.fill(CGRect(x: r.minX, y: y, width: r.width, height: 0.5))
            }
            // Lamp light from the right.
            if let g = CGGradient(colorsSpace: srgb, colors: [NSColor(white: 0, alpha: 0.28).cgColor,
                                                               NSColor(white: 1, alpha: 0.10).cgColor] as CFArray,
                                  locations: [0, 1]) {
                ctx.drawLinearGradient(g, start: CGPoint(x: r.minX, y: 0), end: CGPoint(x: r.maxX, y: 0), options: [])
            }
            // Buttons: a dark seat ring, then a domed brass cap.
            for i in -1...1 {
                let c = CGPoint(x: r.midX + CGFloat(i) * spacing, y: r.midY)
                let rad = buttonDiameter / 2
                ctx.setFillColor(Placeholders.hex(0x3A2810, alpha: 0.85))
                ctx.fillEllipse(in: CGRect(x: c.x - rad - 1.5, y: c.y - rad - 1.5, width: (rad + 1.5) * 2, height: (rad + 1.5) * 2))
                let cap = [Placeholders.hex(0xF0D9A6), Placeholders.hex(0xC29A5C), Placeholders.hex(0x8C6633)] as CFArray
                if let g = CGGradient(colorsSpace: srgb, colors: cap, locations: [0, 0.5, 1]) {
                    ctx.saveGState()
                    ctx.addEllipse(in: CGRect(x: c.x - rad, y: c.y - rad, width: rad * 2, height: rad * 2))
                    ctx.clip()
                    ctx.drawRadialGradient(g, startCenter: CGPoint(x: c.x + rad * 0.3, y: c.y - rad * 0.35), startRadius: 0,
                                           endCenter: c, endRadius: rad * 1.15, options: [.drawsAfterEndLocation])
                    ctx.restoreGState()
                }
            }
            ctx.resetClip()
            // Bevel: light top edge, dark bottom edge.
            ctx.addPath(body)
            ctx.setStrokeColor(NSColor(red: 1, green: 0.92, blue: 0.75, alpha: 0.5).cgColor)
            ctx.setLineWidth(1)
            ctx.strokePath()
            ctx.setStrokeColor(NSColor(red: 0.25, green: 0.16, blue: 0.06, alpha: 0.6).cgColor)
            ctx.move(to: CGPoint(x: r.minX + 9, y: r.maxY - 1.5))
            ctx.addLine(to: CGPoint(x: r.maxX - 9, y: r.maxY - 1.5))
            ctx.strokePath()
        }
    }()
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

    static let maxRows = 5
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

    func configure(_ spec: SceneConfig.Layer, crate: SceneConfig.Crate?) {
        let rect = spec.rect
        shade = crate?.sleeveShade ?? 0
        lightFrom = crate?.lightFrom ?? "right"
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
        layer.opacity = visible && !items.isEmpty ? 1 : 0
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

/// The current song set in type on the wall, blended into the plaster so it reads as painted lettering.
@MainActor
final class WallTitle {
    let layer = CALayer()
    private var title = ""
    private var artist = ""
    private var visible = false
    private var shade: CGFloat = 0

    init() {
        layer.name = "now_playing"
        layer.contentsGravity = .resize
        layer.opacity = 0
    }

    func configure(_ spec: SceneConfig.Layer, crate: SceneConfig.Crate?) {
        let rect = spec.rect
        shade = crate?.sleeveShade ?? 0
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.bounds = CGRect(origin: .zero, size: rect.size)
        layer.position = CGPoint(x: rect.midX, y: rect.midY)
        layer.compositingFilter = Ambient.compositingFilter(spec.blend ?? "overlay")
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
        if changed {
            CATransaction.begin()
            if animated {
                let fade = CATransition()
                fade.type = .fade
                fade.duration = 1.0
                layer.add(fade, forKey: "contents")
            } else {
                CATransaction.setDisableActions(true)
            }
            render()
            CATransaction.commit()
        }
        guard shouldShow != visible || changed else { return }
        visible = shouldShow
        CATransaction.begin()
        CATransaction.setAnimationDuration(animated ? 0.8 : 0)
        CATransaction.setDisableActions(!animated)
        layer.opacity = shouldShow ? target : 0
        CATransaction.commit()
    }

    private func render() {
        let size = layer.bounds.size
        guard size.width > 0 else { return }
        let title = self.title, artist = self.artist.uppercased()
        guard !title.isEmpty else { layer.contents = nil; return }
        layer.contents = Placeholders.render(size: size, scale: 3) { _, r in
            let ink = NSColor(red: 0.98, green: 0.90, blue: 0.74, alpha: 1)
            let center = NSMutableParagraphStyle()
            center.alignment = .center
            center.lineBreakMode = .byWordWrapping
            center.lineHeightMultiple = 0.92

            // Largest size at which the title fits in two lines.
            var fontSize: CGFloat = 64
            var titleFont = NSFont(name: "Didot-Italic", size: fontSize) ?? .systemFont(ofSize: fontSize)
            var titleRect = CGRect.zero
            while fontSize > 22 {
                titleFont = NSFont(name: "Didot-Italic", size: fontSize) ?? .systemFont(ofSize: fontSize)
                titleRect = (title as NSString).boundingRect(
                    with: CGSize(width: r.width, height: 1000), options: [.usesLineFragmentOrigin],
                    attributes: [.font: titleFont, .paragraphStyle: center])
                if titleRect.height <= fontSize * 2.05 && titleRect.height <= r.height - 46 { break }
                fontSize -= 2
            }
            let artistFont = NSFont(name: "AvenirNext-Medium", size: 13) ?? .systemFont(ofSize: 13, weight: .medium)
            let blockHeight = titleRect.height + 14 + 18
            var y = (r.height - blockHeight) / 2
            (title as NSString).draw(
                with: CGRect(x: 0, y: y, width: r.width, height: titleRect.height + 4),
                options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                attributes: [.font: titleFont, .foregroundColor: ink, .paragraphStyle: center])
            y += titleRect.height + 8
            // A short rule, then the artist in spaced capitals.
            ink.withAlphaComponent(0.7).setFill()
            NSRect(x: r.midX - 18, y: y, width: 36, height: 1).fill()
            y += 8
            if !artist.isEmpty {
                let style = NSMutableParagraphStyle()
                style.alignment = .center
                style.lineBreakMode = .byTruncatingTail
                (artist as NSString).draw(
                    with: CGRect(x: 0, y: y, width: r.width, height: 18),
                    options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                    attributes: [.font: artistFont, .foregroundColor: ink.withAlphaComponent(0.85),
                                 .paragraphStyle: style, .kern: 3.2])
            }
        }
    }
}
