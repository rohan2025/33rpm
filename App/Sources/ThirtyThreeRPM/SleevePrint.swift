import AppKit
import CoreImage

/// Turns flat, screen-bright album art into a printed cardboard sleeve that belongs in the room:
/// matte ink in the room's light, paper grain, a faint ring where the record inside presses through,
/// worn edges and corners, and a sliver of light along the edge facing the lamp.
@MainActor
enum SleevePrint {
    struct Look: Equatable {
        /// Colour of the room's light, multiplied into the print. [1, 1, 1] leaves colours as they are.
        var tint: [CGFloat] = [1, 0.9, 0.8]
        var lightFrom = "right"
    }

    private static var cache: [(art: CGImage, look: Look, print: CGImage)] = []
    private static let context = CIContext(options: [.cacheIntermediates: false])
    private static let side = 600

    static func make(_ art: CGImage, look: Look) -> CGImage {
        if let hit = cache.first(where: { $0.art === art && $0.look == look }) { return hit.print }
        let print = render(art, look: look) ?? art
        cache.insert((art, look, print), at: 0)
        if cache.count > 48 { cache.removeLast() }
        return print
    }

    private static func render(_ art: CGImage, look: Look) -> CGImage? {
        let s = CGFloat(side)
        // Aspect-fill into a square.
        var image = CIImage(cgImage: art)
        let scale = s / min(image.extent.width, image.extent.height)
        image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        image = image.transformed(by: CGAffineTransform(translationX: -(image.extent.width - s) / 2 - image.extent.minX,
                                                        y: -(image.extent.height - s) / 2 - image.extent.minY))
            .cropped(to: CGRect(x: 0, y: 0, width: s, height: s))

        // Ink on card is a little less saturated than a screen.
        let t = look.tint.count == 3 ? look.tint : [1, 1, 1]
        image = image.applyingFilter("CIColorControls", parameters: [
            kCIInputSaturationKey: 0.85,
        ])
        // The room photo is soft; a perfectly crisp sleeve looks pasted on. Match its focus.
        image = image.clampedToExtent().applyingGaussianBlur(sigma: 1.5).cropped(to: CGRect(x: 0, y: 0, width: s, height: s))
        guard let inked = context.createCGImage(image, from: CGRect(x: 0, y: 0, width: s, height: s)) else { return nil }

        return Placeholders.render(size: CGSize(width: s, height: s), scale: 1) { ctx, r in
            // The context is flipped (y = 0 at the top); CGImages draw bottom-up, so flip them back.
            ctx.saveGState()
            ctx.translateBy(x: 0, y: s)
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(inked, in: r)
            ctx.restoreGState()
            // Lit by the room: multiply in display space so the tint reads the way it looks.
            ctx.saveGState()
            ctx.setBlendMode(.multiply)
            ctx.setFillColor(NSColor(srgbRed: t[0] * 0.95, green: t[1] * 0.95, blue: t[2] * 0.95, alpha: 1).cgColor)
            ctx.fill(r)
            ctx.restoreGState()
            let space = CGColorSpaceCreateDeviceRGB()
            func white(_ a: CGFloat) -> CGColor { NSColor(white: 1, alpha: a).cgColor }
            func black(_ a: CGFloat) -> CGColor { NSColor(white: 0, alpha: a).cgColor }

            // Paper grain.
            if let grain = grain {
                ctx.saveGState()
                ctx.setBlendMode(.overlay)
                ctx.setAlpha(0.16)
                ctx.draw(grain, in: r)
                ctx.restoreGState()
            }

            // Ring wear: the record's edge rubbing through the card over the years.
            let c = CGPoint(x: r.midX + s * 0.01, y: r.midY - s * 0.005)
            if let ring = CGGradient(colorsSpace: space, colors: [white(0), white(0.03), white(0.01), white(0)] as CFArray,
                                     locations: [0, 0.5, 0.7, 1]) {
                ctx.saveGState()
                ctx.setBlendMode(.screen)
                ctx.drawRadialGradient(ring, startCenter: c, startRadius: s * 0.405, endCenter: c, endRadius: s * 0.455,
                                       options: [])
                ctx.restoreGState()
            }

            // Worn edges and softened corners.
            ctx.saveGState()
            ctx.setBlendMode(.screen)
            ctx.setStrokeColor(white(0.07))
            ctx.setLineWidth(s * 0.014)
            ctx.stroke(r.insetBy(dx: s * 0.007, dy: s * 0.007))
            if let corner = CGGradient(colorsSpace: space, colors: [white(0.14), white(0)] as CFArray, locations: [0, 1]) {
                for p in [CGPoint(x: 0, y: 0), CGPoint(x: s, y: 0), CGPoint(x: 0, y: s), CGPoint(x: s, y: s)] {
                    ctx.drawRadialGradient(corner, startCenter: p, startRadius: 0, endCenter: p, endRadius: s * 0.06,
                                           options: [])
                }
            }
            ctx.restoreGState()

            // Card thickness: light catches the top edge and the side facing the lamp; the others fall dark.
            // (The context is flipped: y = 0 is the top.)
            let fromLeft = look.lightFrom == "left"
            ctx.setFillColor(white(0.16))
            ctx.fill(CGRect(x: 0, y: 0, width: s, height: 2.5))
            ctx.fill(CGRect(x: fromLeft ? 0 : s - 2.5, y: 0, width: 2.5, height: s))
            ctx.setFillColor(black(0.35))
            ctx.fill(CGRect(x: 0, y: s - 3, width: s, height: 3))
            ctx.fill(CGRect(x: fromLeft ? s - 3 : 0, y: 0, width: 3, height: s))

            // A soft matte sheen from the lamp's side.
            if let sheen = CGGradient(colorsSpace: space, colors: [white(0.06), white(0)] as CFArray, locations: [0, 1]) {
                ctx.saveGState()
                ctx.setBlendMode(.screen)
                ctx.drawLinearGradient(sheen, start: CGPoint(x: fromLeft ? 0 : s, y: 0),
                                       end: CGPoint(x: fromLeft ? s * 0.7 : s * 0.3, y: s * 0.7), options: [])
                ctx.restoreGState()
            }
        }
    }

    /// Grounds a cut-out prop (the crate) in the photo: muted, slightly soft like the rest of the picture, in the
    /// room's light, darker on the side away from the lamp and towards the bottom where little light reaches.
    static func settle(_ art: CGImage, look: Look) -> CGImage {
        let extent = CGRect(x: 0, y: 0, width: art.width, height: art.height)
        let source = CIImage(cgImage: art)
        let image = source.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0.8])
            .clampedToExtent().applyingGaussianBlur(sigma: Double(art.width) / 600).cropped(to: extent)
        guard let soft = context.createCGImage(image, from: extent) else { return art }
        let t = look.tint.count == 3 ? look.tint : [1, 1, 1]
        let fromLeft = look.lightFrom == "left"
        return Placeholders.render(size: extent.size, scale: 1) { ctx, r in
            func drawSoft() {
                ctx.saveGState()
                ctx.translateBy(x: 0, y: r.height)
                ctx.scaleBy(x: 1, y: -1)
                ctx.draw(soft, in: r)
                ctx.restoreGState()
            }
            drawSoft()
            let space = CGColorSpaceCreateDeviceRGB()
            ctx.saveGState()
            ctx.setBlendMode(.multiply)
            ctx.setFillColor(NSColor(srgbRed: t[0] * 0.85, green: t[1] * 0.85, blue: t[2] * 0.85, alpha: 1).cgColor)
            ctx.fill(r)
            ctx.restoreGState()
            func black(_ a: CGFloat) -> CGColor { NSColor(white: 0, alpha: a).cgColor }
            // Away from the lamp. (Flipped context: y = 0 is the top.)
            if let side = CGGradient(colorsSpace: space, colors: [black(0.5), black(0.05)] as CFArray, locations: [0, 1]) {
                ctx.drawLinearGradient(side, start: CGPoint(x: fromLeft ? r.maxX : 0, y: 0),
                                       end: CGPoint(x: fromLeft ? 0 : r.maxX, y: 0), options: [])
            }
            // Little light reaches the bottom of the box.
            if let low = CGGradient(colorsSpace: space, colors: [black(0), black(0.4)] as CFArray, locations: [0, 1]) {
                ctx.drawLinearGradient(low, start: CGPoint(x: 0, y: r.height * 0.45), end: CGPoint(x: 0, y: r.height),
                                       options: [])
            }
            // Keep the crate's own outline.
            ctx.setBlendMode(.destinationIn)
            drawSoft()
        } ?? art
    }

    /// The same picture in shadow, keeping its outline.
    static func darken(_ art: CGImage, by amount: CGFloat) -> CGImage {
        let r = CGRect(x: 0, y: 0, width: art.width, height: art.height)
        guard let ctx = CGContext(data: nil, width: art.width, height: art.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return art }
        ctx.draw(art, in: r)
        ctx.setBlendMode(.sourceAtop)
        ctx.setFillColor(NSColor(white: 0, alpha: amount).cgColor)
        ctx.fill(r)
        return ctx.makeImage() ?? art
    }

    /// A leaning sleeve's shadow: a soft one thrown on the wall, and a tight dark line where it stands on the console.
    /// `contactOffset` is how far the soft shadow sits from the sleeve, so the contact line stays under the sleeve itself.
    static func shadow(size: CGSize, blur: CGFloat, pad: CGFloat, contactOffset: CGFloat) -> CGImage? {
        let scale: CGFloat = 2
        let full = CGRect(x: 0, y: 0, width: (size.width + pad * 2) * scale, height: (size.height + pad * 2) * scale)
        // Core Image's origin is bottom-left: the sleeve's bottom edge sits at y = pad.
        let soft = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0.6))
            .cropped(to: CGRect(x: pad * scale, y: pad * scale, width: size.width * scale, height: size.height * 0.96 * scale))
            .applyingGaussianBlur(sigma: blur * scale / 2)
        let contact = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0.85))
            .cropped(to: CGRect(x: (pad - contactOffset + size.width * 0.02) * scale, y: (pad - 1.2) * scale,
                                width: size.width * 0.96 * scale, height: 2.4 * scale))
            .applyingGaussianBlur(sigma: 1.6 * scale)
        return context.createCGImage(contact.composited(over: soft).cropped(to: full), from: full)
    }

    /// Fine mottled noise, made once.
    private static let grain: CGImage? = {
        let n = side
        var bytes = [UInt8](repeating: 0, count: n * n)
        var seed: UInt32 = 0x33_1333
        for i in 0..<bytes.count {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            bytes[i] = UInt8(96 + Int(seed >> 24) % 64)
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: n, height: n, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: n,
                       space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }()
}
