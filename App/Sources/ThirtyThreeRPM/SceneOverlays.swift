import AppKit
import QuartzCore

/// Previous / play-pause / next, shown just in front of the deck while the pointer is over the turntable.
/// Lives in TurntableView's canvas (top-left origin, canvas points).
@MainActor
final class PlaybackControls {
    let layer = CALayer()
    private let buttons: [(command: PlayerCommand, layer: CALayer)]
    private var isPlaying = false
    private(set) var isShown = false

    private static let buttonSize: CGFloat = 40
    private static let spacing: CGFloat = 54

    init() {
        buttons = [PlayerCommand.previous, .playPause, .next].map { ($0, CALayer()) }
        layer.backgroundColor = NSColor(white: 0.04, alpha: 0.62).cgColor
        layer.borderColor = NSColor(white: 1, alpha: 0.12).cgColor
        layer.borderWidth = 1
        layer.shadowColor = NSColor.black.cgColor
        layer.shadowOpacity = 0.5
        layer.shadowRadius = 10
        layer.shadowOffset = CGSize(width: 0, height: 4)
        layer.opacity = 0
        layer.name = "controls"
        for (_, button) in buttons {
            button.contentsGravity = .resizeAspect
            button.opacity = 0.85
            layer.addSublayer(button)
        }
        updateGlyphs()
    }

    func configure(center: CGPoint, scale: CGFloat) {
        let width = Self.spacing * 2 + Self.buttonSize + 36
        let height = Self.buttonSize + 16
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.bounds = CGRect(x: 0, y: 0, width: width, height: height)
        layer.cornerRadius = height / 2
        layer.position = center
        layer.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
        for (i, (_, button)) in buttons.enumerated() {
            button.bounds = CGRect(x: 0, y: 0, width: Self.buttonSize * 0.6, height: Self.buttonSize * 0.6)
            button.position = CGPoint(x: width / 2 + CGFloat(i - 1) * Self.spacing, y: height / 2)
        }
        CATransaction.commit()
    }

    /// Area covered by the pill, in canvas coordinates.
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
        CATransaction.setAnimationDuration(shown ? 0.2 : 0.35)
        layer.opacity = shown ? 1 : 0
        CATransaction.commit()
        if !shown { highlight(nil) }
    }

    /// The button under a canvas point, if the controls are showing.
    func command(at point: CGPoint) -> PlayerCommand? {
        guard isShown else { return nil }
        let local = layer.convert(point, from: layer.superlayer)
        for (command, button) in buttons where button.frame.insetBy(dx: -10, dy: -8).contains(local) {
            return command
        }
        return nil
    }

    func highlight(_ command: PlayerCommand?) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.12)
        for (c, button) in buttons { button.opacity = c == command ? 1 : 0.8 }
        CATransaction.commit()
    }

    /// Small press feedback.
    func pulse(_ command: PlayerCommand) {
        guard let button = buttons.first(where: { $0.command == command })?.layer else { return }
        let press = CAKeyframeAnimation(keyPath: "transform.scale")
        press.values = [1, 0.82, 1.06, 1]
        press.duration = 0.25
        button.add(press, forKey: "press")
    }

    private func updateGlyphs() {
        let names: [PlayerCommand: String] = [
            .previous: "backward.fill", .next: "forward.fill",
            .playPause: isPlaying ? "pause.fill" : "play.fill",
        ]
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (command, button) in buttons {
            button.contents = Self.symbol(names[command] ?? "circle")
        }
        CATransaction.commit()
    }

    private static func symbol(_ name: String) -> CGImage? {
        let config = NSImage.SymbolConfiguration(pointSize: 44, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [NSColor(white: 0.96, alpha: 1)]))
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return nil }
        let size = image.size
        return Placeholders.render(size: size, scale: 2) { _, rect in
            image.draw(in: rect)
        }
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
