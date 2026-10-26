import AppKit

/// Simple drawn stand-ins for each asset slot, used until a PNG with the slot's name exists.
/// All drawing uses top-left-origin coordinates in the slot's frame size.
enum Placeholders {
    /// `variant` is the scene folder name, so each scene gets its own stand-in room.
    static func image(for slot: String, size: CGSize, variant: String = "Evening") -> CGImage? {
        guard size.width > 0, size.height > 0 else { return nil }
        let draw: ((CGContext, CGRect) -> Void)?
        switch (slot, variant) {
        case ("background", "RainyWindow"): draw = rainyBackground
        case ("background", "Minimal"): draw = minimalBackground
        case ("lamp_glow", "RainyWindow"):
            draw = { ctx, r in lampGlow(ctx, r, NSColor(red: 1, green: 0.72, blue: 0.42, alpha: 0.5)) }
        case ("lamp_glow", _):
            draw = { ctx, r in lampGlow(ctx, r, NSColor(red: 1, green: 0.68, blue: 0.32, alpha: 0.6)) }
        default:
            draw = nil
        }
        if let draw { return render(size: size, scale: slot == "lamp_glow" ? 0.5 : 2, draw: draw) }
        return image(for: slot, size: size)
    }

    private static func image(for slot: String, size: CGSize) -> CGImage? {
        let draw: ((CGContext, CGRect) -> Void)?
        switch slot {
        case "background": draw = background
        case "plant": draw = plant
        case "console": draw = console
        case "sleeve_shadow": draw = sleeveShadow
        case "crate": draw = crate
        case "deck_base": draw = deckBase
        case "platter": draw = platter
        case "record": draw = record
        case "tonearm": draw = tonearm
        case "lid": draw = lid
        default: draw = nil
        }
        guard let draw else { return nil }
        return render(size: size, draw: draw)
    }

    static func defaultLabel() -> CGImage {
        render(size: CGSize(width: 300, height: 300)) { ctx, r in
            fillEllipse(ctx, r, hex(0xEFE4CC))
            ctx.setStrokeColor(hex(0xB8412F))
            ctx.setLineWidth(r.width * 0.035)
            ctx.strokeEllipse(in: r.insetBy(dx: r.width * 0.08, dy: r.width * 0.08))
            drawText("33⅓", in: CGRect(x: 0, y: r.height * 0.18, width: r.width, height: r.height * 0.3),
                     size: r.width * 0.2, color: hex(0x3A2418), weight: .bold)
            drawText("rpm", in: CGRect(x: 0, y: r.height * 0.62, width: r.width, height: r.height * 0.2),
                     size: r.width * 0.1, color: hex(0x3A2418), weight: .medium)
        }!
    }

    /// Soft round particle for dust.
    static func softDot() -> CGImage {
        render(size: CGSize(width: 32, height: 32), scale: 1) { ctx, r in
            radialGlow(ctx, center: CGPoint(x: r.midX, y: r.midY), radius: r.width / 2, color: NSColor.white.cgColor)
        }!
    }

    /// Thin vertical streak for rain, brightest at the leading (bottom) end.
    static func rainStreak() -> CGImage {
        render(size: CGSize(width: 3, height: 40), scale: 1) { ctx, r in
            linearGradient(ctx, r, [NSColor.white.withAlphaComponent(0).cgColor, NSColor.white.cgColor])
        }!
    }

    /// Plain card sleeve shown on the wall when nothing is playing.
    static func defaultSleeve() -> CGImage {
        render(size: CGSize(width: 300, height: 300)) { ctx, r in
            linearGradient(ctx, r, [hex(0x2B2622), hex(0x1C1916)])
            ctx.setStrokeColor(hex(0xB08D57, alpha: 0.6))
            ctx.setLineWidth(2)
            ctx.strokeEllipse(in: r.insetBy(dx: r.width * 0.2, dy: r.height * 0.2))
            drawText("33⅓", in: CGRect(x: 0, y: r.height * 0.36, width: r.width, height: r.height * 0.2),
                     size: r.width * 0.14, color: hex(0xD9C7A3), weight: .semibold)
            drawText("rpm", in: CGRect(x: 0, y: r.height * 0.54, width: r.width, height: r.height * 0.12),
                     size: r.width * 0.06, color: hex(0xB08D57), weight: .medium)
        }!
    }

    // MARK: - Slots

    private static func background(_ ctx: CGContext, _ r: CGRect) {
        let floorY = r.height * 0.78
        linearGradient(ctx, CGRect(x: 0, y: 0, width: r.width, height: floorY), [hex(0x26170F), hex(0x3A2316)])
        linearGradient(ctx, CGRect(x: 0, y: floorY, width: r.width, height: r.height - floorY), [hex(0x1E120B), hex(0x120B07)])
        ctx.setFillColor(hex(0x2E1C12))
        ctx.fill(CGRect(x: 0, y: floorY - r.height * 0.015, width: r.width, height: r.height * 0.015))

        // Floor lamp with amber glow.
        let lampX = r.width * 0.86, shadeTop = r.height * 0.14, shadeBottom = r.height * 0.26
        radialGlow(ctx, center: CGPoint(x: lampX, y: shadeBottom), radius: r.width * 0.5,
                   color: NSColor(red: 1, green: 0.66, blue: 0.3, alpha: 0.42).cgColor)
        ctx.setFillColor(hex(0x1A110C))
        ctx.fill(CGRect(x: lampX - 3, y: shadeBottom, width: 6, height: floorY + r.height * 0.06 - shadeBottom))
        let shade = CGMutablePath()
        shade.move(to: CGPoint(x: lampX - r.width * 0.035, y: shadeTop))
        shade.addLine(to: CGPoint(x: lampX + r.width * 0.035, y: shadeTop))
        shade.addLine(to: CGPoint(x: lampX + r.width * 0.06, y: shadeBottom))
        shade.addLine(to: CGPoint(x: lampX - r.width * 0.06, y: shadeBottom))
        shade.closeSubpath()
        ctx.addPath(shade)
        ctx.setFillColor(hex(0xE9B26A))
        ctx.fillPath()
    }

    private static func plant(_ ctx: CGContext, _ r: CGRect) {
        let potTop = r.height * 0.72
        ctx.setFillColor(hex(0x1F3A24))
        for i in 0..<9 {
            let t = CGFloat(i) / 8
            ctx.saveGState()
            ctx.translateBy(x: r.midX, y: potTop)
            ctx.rotate(by: (t - 0.5) * 1.9)
            ctx.fillEllipse(in: CGRect(x: -r.width * 0.09, y: -r.height * (0.55 + 0.12 * sin(t * 9)),
                                       width: r.width * 0.18, height: r.height * 0.5))
            ctx.restoreGState()
        }
        let pot = CGMutablePath()
        pot.move(to: CGPoint(x: r.width * 0.2, y: potTop))
        pot.addLine(to: CGPoint(x: r.width * 0.8, y: potTop))
        pot.addLine(to: CGPoint(x: r.width * 0.7, y: r.height))
        pot.addLine(to: CGPoint(x: r.width * 0.3, y: r.height))
        pot.closeSubpath()
        ctx.addPath(pot)
        ctx.setFillColor(hex(0x8A4B2C))
        ctx.fillPath()
    }

    private static func console(_ ctx: CGContext, _ r: CGRect) {
        let topH = r.height * 0.15, bodyBottom = r.height * 0.86
        // Legs
        ctx.setFillColor(hex(0x2A170C))
        for x in [r.width * 0.07, r.width * 0.9] {
            ctx.fill(CGRect(x: x, y: bodyBottom, width: r.width * 0.03, height: r.height - bodyBottom))
        }
        // Top surface and front face
        linearGradient(ctx, CGRect(x: 0, y: 0, width: r.width, height: topH), [hex(0x6B3E22), hex(0x8A5430)])
        linearGradient(ctx, CGRect(x: 0, y: topH, width: r.width, height: bodyBottom - topH), [hex(0x5C331B), hex(0x3E2112)])
        // Doors and brass pulls
        ctx.setStrokeColor(hex(0x2B160A))
        ctx.setLineWidth(3)
        let doorW = r.width / 3
        for i in 0..<3 {
            let door = CGRect(x: CGFloat(i) * doorW + 14, y: topH + 14, width: doorW - 28, height: bodyBottom - topH - 28)
            ctx.stroke(door)
            fillEllipse(ctx, CGRect(x: door.midX - 7, y: door.minY + 22, width: 14, height: 14), hex(0xB08D57))
        }
    }

    private static func sleeveShadow(_ ctx: CGContext, _ r: CGRect) {
        ctx.setShadow(offset: .zero, blur: r.width * 0.06, color: NSColor.black.withAlphaComponent(0.8).cgColor)
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.55).cgColor)
        ctx.fill(r.insetBy(dx: r.width * 0.07, dy: r.height * 0.07))
    }

    /// Front panel only: sleeves stand behind it and poke out of the top.
    private static func crate(_ ctx: CGContext, _ r: CGRect) {
        let planks = 3
        let gap = r.height * 0.04
        let plankH = (r.height - gap * CGFloat(planks - 1)) / CGFloat(planks)
        for i in 0..<planks {
            let y = CGFloat(i) * (plankH + gap)
            linearGradient(ctx, CGRect(x: 0, y: y, width: r.width, height: plankH), [hex(0xA9784A), hex(0x82552F)])
        }
        ctx.setFillColor(hex(0x6E4728))
        ctx.fill(CGRect(x: 0, y: 0, width: r.width * 0.05, height: r.height))
        ctx.fill(CGRect(x: r.width * 0.95, y: 0, width: r.width * 0.05, height: r.height))
    }

    private static func deckBase(_ ctx: CGContext, _ r: CGRect) {
        let body = CGPath(roundedRect: r.insetBy(dx: 2, dy: 2), cornerWidth: 14, cornerHeight: 14, transform: nil)
        ctx.addPath(body)
        ctx.clip()
        linearGradient(ctx, r, [hex(0x1C1C1C), hex(0x101010)])
        ctx.resetClip()
        ctx.addPath(body)
        ctx.setStrokeColor(hex(0xB08D57))
        ctx.setLineWidth(3)
        ctx.strokePath()
        // Speed knob and start button, brass
        fillEllipse(ctx, CGRect(x: r.width * 0.05, y: r.height * 0.84, width: r.width * 0.07, height: r.width * 0.07), hex(0xB08D57))
        ctx.setFillColor(hex(0x8C6F44))
        ctx.fill(CGRect(x: r.width * 0.15, y: r.height * 0.86, width: r.width * 0.08, height: r.height * 0.04))
    }

    private static func platter(_ ctx: CGContext, _ r: CGRect) {
        fillEllipse(ctx, r.insetBy(dx: 1, dy: 1), hex(0x2A2A2A))
        ctx.setStrokeColor(hex(0xB08D57))
        ctx.setLineWidth(r.width * 0.012)
        ctx.strokeEllipse(in: r.insetBy(dx: r.width * 0.01, dy: r.width * 0.01))
        // Strobe dots
        ctx.setFillColor(hex(0x5A5A5A))
        let c = CGPoint(x: r.midX, y: r.midY), rad = r.width * 0.475
        for i in 0..<90 {
            let a = CGFloat(i) / 90 * .pi * 2
            ctx.fill(CGRect(x: c.x + cos(a) * rad - 1.5, y: c.y + sin(a) * rad - 1.5, width: 3, height: 3))
        }
    }

    private static func record(_ ctx: CGContext, _ r: CGRect) {
        fillEllipse(ctx, r.insetBy(dx: 1, dy: 1), hex(0x0C0C0C))
        let c = CGPoint(x: r.midX, y: r.midY)
        ctx.setLineWidth(1)
        var rad = r.width * 0.19
        var i = 0
        while rad < r.width * 0.49 {
            let alpha: CGFloat = (i % 9 == 0) ? 0.02 : 0.07   // occasional gaps between tracks
            ctx.setStrokeColor(NSColor.white.withAlphaComponent(alpha).cgColor)
            ctx.strokeEllipse(in: CGRect(x: c.x - rad, y: c.y - rad, width: rad * 2, height: rad * 2))
            rad += 2.2
            i += 1
        }
    }

    private static func tonearm(_ ctx: CGContext, _ r: CGRect) {
        // Pivot at (0.5, 0.08) of the frame, matching the default anchor in scene.json.
        let pivot = CGPoint(x: r.width * 0.5, y: r.height * 0.08)
        let tip = CGPoint(x: pivot.x, y: r.height * 0.88)
        ctx.setShadow(offset: CGSize(width: 2, height: 3), blur: 4, color: NSColor.black.withAlphaComponent(0.6).cgColor)
        ctx.setStrokeColor(hex(0xC9A86A))
        ctx.setLineWidth(r.width * 0.1)
        ctx.setLineCap(.round)
        ctx.move(to: pivot)
        ctx.addLine(to: tip)
        ctx.strokePath()
        // Headshell
        ctx.setFillColor(hex(0x1A1A1A))
        ctx.fill(CGRect(x: tip.x - r.width * 0.22, y: tip.y - 4, width: r.width * 0.44, height: r.height * 0.12))
        // Pivot base with counterweight
        let baseR = r.width * 0.34
        fillEllipse(ctx, CGRect(x: pivot.x - baseR, y: pivot.y - baseR, width: baseR * 2, height: baseR * 2), hex(0xB08D57))
        fillEllipse(ctx, CGRect(x: pivot.x - baseR * 0.55, y: pivot.y - baseR * 0.55, width: baseR * 1.1, height: baseR * 1.1), hex(0x2A2A2A))
    }

    private static func lid(_ ctx: CGContext, _ r: CGRect) {
        let path = CGPath(roundedRect: r.insetBy(dx: 2, dy: 2), cornerWidth: 16, cornerHeight: 16, transform: nil)
        ctx.addPath(path)
        ctx.clip()
        ctx.setFillColor(NSColor(white: 0.05, alpha: 0.35).cgColor)
        ctx.fill(r)
        // Diagonal reflection
        let glare = CGMutablePath()
        glare.move(to: CGPoint(x: r.width * 0.55, y: 0))
        glare.addLine(to: CGPoint(x: r.width * 0.75, y: 0))
        glare.addLine(to: CGPoint(x: r.width * 0.35, y: r.height))
        glare.addLine(to: CGPoint(x: r.width * 0.15, y: r.height))
        glare.closeSubpath()
        ctx.addPath(glare)
        ctx.setFillColor(NSColor.white.withAlphaComponent(0.07).cgColor)
        ctx.fillPath()
        ctx.resetClip()
        ctx.addPath(path)
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.25).cgColor)
        ctx.setLineWidth(2)
        ctx.strokePath()
    }

    // MARK: - Scene variants

    private static func lampGlow(_ ctx: CGContext, _ r: CGRect, _ color: NSColor) {
        radialGlow(ctx, center: CGPoint(x: r.midX, y: r.midY), radius: r.width / 2, color: color.cgColor)
    }

    /// Cool night room with a big window onto blurred city lights.
    private static func rainyBackground(_ ctx: CGContext, _ r: CGRect) {
        let floorY = r.height * 0.78
        linearGradient(ctx, CGRect(x: 0, y: 0, width: r.width, height: floorY), [hex(0x1A2027), hex(0x262C33)])
        linearGradient(ctx, CGRect(x: 0, y: floorY, width: r.width, height: r.height - floorY), [hex(0x15181C), hex(0x0C0E10)])

        // Window (matches the rain emitter frame in RainyWindow/scene.json: 160,110 560x400 on a 1500x1000 canvas).
        let win = CGRect(x: r.width * 0.1067, y: r.height * 0.11, width: r.width * 0.3733, height: r.height * 0.4)
        linearGradient(ctx, win, [hex(0x0E1A2B), hex(0x1D2B3E)])
        let lights: [(CGFloat, CGFloat, CGFloat, UInt32)] = [
            (0.15, 0.7, 0.07, 0xF2B45A), (0.3, 0.8, 0.05, 0xE07A4F), (0.48, 0.66, 0.08, 0xF4D18A),
            (0.62, 0.84, 0.06, 0x8FB3E0), (0.78, 0.72, 0.07, 0xF2B45A), (0.9, 0.86, 0.05, 0xE07A4F),
            (0.4, 0.9, 0.04, 0xF4D18A), (0.7, 0.6, 0.04, 0x8FB3E0),
        ]
        ctx.saveGState()
        ctx.clip(to: win)
        for (x, y, rad, color) in lights {
            radialGlow(ctx, center: CGPoint(x: win.minX + win.width * x, y: win.minY + win.height * y),
                       radius: win.width * rad, color: hex(color, alpha: 0.55))
        }
        ctx.restoreGState()
        ctx.setStrokeColor(hex(0x2E3A44))
        ctx.setLineWidth(r.width * 0.008)
        ctx.stroke(win)
        ctx.move(to: CGPoint(x: win.midX, y: win.minY))
        ctx.addLine(to: CGPoint(x: win.midX, y: win.maxY))
        ctx.move(to: CGPoint(x: win.minX, y: win.midY))
        ctx.addLine(to: CGPoint(x: win.maxX, y: win.midY))
        ctx.strokePath()

        // Dim floor lamp on the right.
        let lampX = r.width * 0.86, shadeTop = r.height * 0.14, shadeBottom = r.height * 0.26
        ctx.setFillColor(hex(0x101214))
        ctx.fill(CGRect(x: lampX - 3, y: shadeBottom, width: 6, height: floorY + r.height * 0.06 - shadeBottom))
        let shade = CGMutablePath()
        shade.move(to: CGPoint(x: lampX - r.width * 0.035, y: shadeTop))
        shade.addLine(to: CGPoint(x: lampX + r.width * 0.035, y: shadeTop))
        shade.addLine(to: CGPoint(x: lampX + r.width * 0.06, y: shadeBottom))
        shade.addLine(to: CGPoint(x: lampX - r.width * 0.06, y: shadeBottom))
        shade.closeSubpath()
        ctx.addPath(shade)
        ctx.setFillColor(hex(0xD9A25E))
        ctx.fillPath()
    }

    /// Clean warm-grey backdrop with a low oak plinth.
    private static func minimalBackground(_ ctx: CGContext, _ r: CGRect) {
        linearGradient(ctx, r, [hex(0x2A2724), hex(0x1A1817)])
        radialGlow(ctx, center: CGPoint(x: r.width * 0.47, y: r.height * 0.45), radius: r.width * 0.45,
                   color: hex(0x5A4C3E, alpha: 0.5))
        let top = CGRect(x: r.width * 0.13, y: r.height * 0.6, width: r.width * 0.74, height: r.height * 0.05)
        let front = CGRect(x: top.minX, y: top.maxY, width: top.width, height: r.height * 0.07)
        linearGradient(ctx, top, [hex(0x9C7A55), hex(0xB48D63)])
        linearGradient(ctx, front, [hex(0x7A5C3E), hex(0x5E4530)])
        ctx.setShadow(offset: .zero, blur: r.width * 0.03, color: NSColor.black.withAlphaComponent(0.6).cgColor)
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.35).cgColor)
        ctx.fill(CGRect(x: front.minX + 10, y: front.maxY, width: front.width - 20, height: 6))
    }

    // MARK: - Helpers

    /// Renders at 2x into a top-left-origin context.
    static func render(size: CGSize, scale: CGFloat = 2, draw: (CGContext, CGRect) -> Void) -> CGImage? {
        let w = Int((size.width * scale).rounded()), h = Int((size.height * scale).rounded())
        guard w > 0, h > 0,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: scale, y: -scale)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        draw(ctx, CGRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()
    }

    static func hex(_ value: UInt32, alpha: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255, alpha: alpha)
    }

    private static func fillEllipse(_ ctx: CGContext, _ r: CGRect, _ color: CGColor) {
        ctx.setFillColor(color)
        ctx.fillEllipse(in: r)
    }

    private static func linearGradient(_ ctx: CGContext, _ r: CGRect, _ colors: [CGColor]) {
        guard let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: nil)
        else { return }
        ctx.saveGState()
        ctx.clip(to: r)
        ctx.drawLinearGradient(g, start: CGPoint(x: r.midX, y: r.minY), end: CGPoint(x: r.midX, y: r.maxY), options: [])
        ctx.restoreGState()
    }

    private static func radialGlow(_ ctx: CGContext, center: CGPoint, radius: CGFloat, color: CGColor) {
        guard let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                 colors: [color, color.copy(alpha: 0)!] as CFArray, locations: [0, 1])
        else { return }
        ctx.drawRadialGradient(g, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
    }

    private static func drawText(_ text: String, in rect: CGRect, size: CGFloat, color: CGColor, weight: NSFont.Weight) {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: NSColor(cgColor: color) ?? .black,
            .paragraphStyle: style,
        ]
        (text as NSString).draw(in: rect, withAttributes: attrs)
    }
}
