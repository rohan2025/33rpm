import AppKit

/// A vacuum-fluorescent character display, the kind on 70s/80s hi-fi: 5×7 dot characters in fixed cells,
/// with every unlit dot faintly visible behind the glass.
enum DotMatrix {
    static let columns = 5, rows = 7
    /// Cell width in dots: five for the character plus one gap.
    static let cellDots = 6

    /// Bit rows for each character, top to bottom, five bits wide (16 = leftmost).
    private static let font: [Character: [UInt8]] = {
        var f: [Character: [UInt8]] = [:]
        func add(_ c: Character, _ rows: [String]) { f[c] = rows.map { UInt8($0, radix: 2)! } }
        add("A", ["01110", "10001", "10001", "11111", "10001", "10001", "10001"])
        add("B", ["11110", "10001", "10001", "11110", "10001", "10001", "11110"])
        add("C", ["01110", "10001", "10000", "10000", "10000", "10001", "01110"])
        add("D", ["11100", "10010", "10001", "10001", "10001", "10010", "11100"])
        add("E", ["11111", "10000", "10000", "11110", "10000", "10000", "11111"])
        add("F", ["11111", "10000", "10000", "11110", "10000", "10000", "10000"])
        add("G", ["01110", "10001", "10000", "10111", "10001", "10001", "01111"])
        add("H", ["10001", "10001", "10001", "11111", "10001", "10001", "10001"])
        add("I", ["01110", "00100", "00100", "00100", "00100", "00100", "01110"])
        add("J", ["00111", "00010", "00010", "00010", "00010", "10010", "01100"])
        add("K", ["10001", "10010", "10100", "11000", "10100", "10010", "10001"])
        add("L", ["10000", "10000", "10000", "10000", "10000", "10000", "11111"])
        add("M", ["10001", "11011", "10101", "10101", "10001", "10001", "10001"])
        add("N", ["10001", "10001", "11001", "10101", "10011", "10001", "10001"])
        add("O", ["01110", "10001", "10001", "10001", "10001", "10001", "01110"])
        add("P", ["11110", "10001", "10001", "11110", "10000", "10000", "10000"])
        add("Q", ["01110", "10001", "10001", "10001", "10101", "10010", "01101"])
        add("R", ["11110", "10001", "10001", "11110", "10100", "10010", "10001"])
        add("S", ["01111", "10000", "10000", "01110", "00001", "00001", "11110"])
        add("T", ["11111", "00100", "00100", "00100", "00100", "00100", "00100"])
        add("U", ["10001", "10001", "10001", "10001", "10001", "10001", "01110"])
        add("V", ["10001", "10001", "10001", "10001", "10001", "01010", "00100"])
        add("W", ["10001", "10001", "10001", "10101", "10101", "10101", "01010"])
        add("X", ["10001", "10001", "01010", "00100", "01010", "10001", "10001"])
        add("Y", ["10001", "10001", "10001", "01010", "00100", "00100", "00100"])
        add("Z", ["11111", "00001", "00010", "00100", "01000", "10000", "11111"])
        add("0", ["01110", "10001", "10011", "10101", "11001", "10001", "01110"])
        add("1", ["00100", "01100", "00100", "00100", "00100", "00100", "01110"])
        add("2", ["01110", "10001", "00001", "00010", "00100", "01000", "11111"])
        add("3", ["11111", "00010", "00100", "00010", "00001", "10001", "01110"])
        add("4", ["00010", "00110", "01010", "10010", "11111", "00010", "00010"])
        add("5", ["11111", "10000", "11110", "00001", "00001", "10001", "01110"])
        add("6", ["00110", "01000", "10000", "11110", "10001", "10001", "01110"])
        add("7", ["11111", "00001", "00010", "00100", "01000", "01000", "01000"])
        add("8", ["01110", "10001", "10001", "01110", "10001", "10001", "01110"])
        add("9", ["01110", "10001", "10001", "01111", "00001", "00010", "01100"])
        add(" ", ["00000", "00000", "00000", "00000", "00000", "00000", "00000"])
        add(".", ["00000", "00000", "00000", "00000", "00000", "01100", "01100"])
        add(",", ["00000", "00000", "00000", "00000", "01100", "00100", "01000"])
        add("&", ["01100", "10010", "10100", "01000", "10101", "10010", "01101"])
        add("'", ["01100", "00100", "01000", "00000", "00000", "00000", "00000"])
        add("\"", ["01010", "01010", "01010", "00000", "00000", "00000", "00000"])
        add("-", ["00000", "00000", "00000", "11111", "00000", "00000", "00000"])
        add("_", ["00000", "00000", "00000", "00000", "00000", "00000", "11111"])
        add("(", ["00010", "00100", "01000", "01000", "01000", "00100", "00010"])
        add(")", ["01000", "00100", "00010", "00010", "00010", "00100", "01000"])
        add("[", ["01110", "01000", "01000", "01000", "01000", "01000", "01110"])
        add("]", ["01110", "00010", "00010", "00010", "00010", "00010", "01110"])
        add("!", ["00100", "00100", "00100", "00100", "00100", "00000", "00100"])
        add("?", ["01110", "10001", "00001", "00010", "00100", "00000", "00100"])
        add(":", ["00000", "01100", "01100", "00000", "01100", "01100", "00000"])
        add(";", ["00000", "01100", "01100", "00000", "01100", "00100", "01000"])
        add("/", ["00000", "00001", "00010", "00100", "01000", "10000", "00000"])
        add("+", ["00000", "00100", "00100", "11111", "00100", "00100", "00000"])
        add("#", ["01010", "01010", "11111", "01010", "11111", "01010", "01010"])
        add("*", ["00000", "00100", "10101", "01110", "10101", "00100", "00000"])
        add("|", ["00100", "00100", "00100", "00100", "00100", "00100", "00100"])
        add("<", ["00010", "00100", "01000", "10000", "01000", "00100", "00010"])
        add(">", ["01000", "00100", "00010", "00001", "00010", "00100", "01000"])
        add("⅓", ["10000", "10000", "10010", "00100", "01011", "10001", "00011"])
        add("▶", ["01000", "01100", "01110", "01111", "01110", "01100", "01000"])
        add("❚", ["11011", "11011", "11011", "11011", "11011", "11011", "11011"])
        return f
    }()

    /// Upper-cases, romanises and strips accents so as much as possible lands in the font; anything left becomes "?".
    static func cells(_ text: String) -> [[UInt8]] {
        displayable(text).uppercased().folding(options: [.diacriticInsensitive, .widthInsensitive], locale: nil)
            .map { font[$0] ?? font["?"]! }
    }

    /// Text in other scripts (Hindi, Japanese, …) is romanised first so it can be shown on a Latin display.
    private static func displayable(_ text: String) -> String {
        guard text.unicodeScalars.contains(where: { $0.value > 0x24F && !"⅓▶❚".unicodeScalars.contains($0) }) else { return text }
        return text.applyingTransform(.toLatin, reverse: false)?.applyingTransform(.stripDiacritics, reverse: false) ?? text
    }

    /// Lit dots for a run of characters: a phosphor dot with a soft edge, `pitch` points apart.
    static func render(_ cells: [[UInt8]], pitch: CGFloat, color: NSColor) -> (image: CGImage?, size: CGSize) {
        let size = CGSize(width: CGFloat(max(cells.count, 1) * cellDots) * pitch, height: CGFloat(rows) * pitch)
        let image = Placeholders.render(size: size, scale: 6) { ctx, _ in
            for (i, glyph) in cells.enumerated() {
                for (r, bits) in glyph.enumerated() {
                    for c in 0..<columns where bits & (1 << UInt8(columns - 1 - c)) != 0 {
                        dot(ctx, at: CGPoint(x: (CGFloat(i * cellDots + c) + 0.5) * pitch, y: (CGFloat(r) + 0.5) * pitch),
                            pitch: pitch, color: color)
                    }
                }
            }
        }
        return (image, size)
    }

    /// The whole glass: every dot of every cell, unlit, the way a VFD looks when you can see its grid.
    static func ghost(cellsWide: Int, lines: Int, lineGap: CGFloat, pitch: CGFloat, color: NSColor) -> CGImage? {
        let lineHeight = CGFloat(rows) * pitch
        let size = CGSize(width: CGFloat(cellsWide * cellDots - 1) * pitch,
                          height: lineHeight * CGFloat(lines) + lineGap * CGFloat(lines - 1))
        return Placeholders.render(size: size, scale: 6) { ctx, _ in
            for line in 0..<lines {
                let top = CGFloat(line) * (lineHeight + lineGap)
                for cell in 0..<cellsWide {
                    for r in 0..<rows {
                        for c in 0..<columns {
                            dot(ctx, at: CGPoint(x: (CGFloat(cell * cellDots + c) + 0.5) * pitch,
                                                 y: top + (CGFloat(r) + 0.5) * pitch), pitch: pitch, color: color)
                        }
                    }
                }
            }
        }
    }

    private static func dot(_ ctx: CGContext, at p: CGPoint, pitch: CGFloat, color: NSColor) {
        let r = pitch * 0.42
        let space = CGColorSpaceCreateDeviceRGB()
        guard let g = CGGradient(colorsSpace: space, colors: [color.cgColor, color.withAlphaComponent(color.alphaComponent * 0.75).cgColor,
                                                              color.withAlphaComponent(0).cgColor] as CFArray,
                                 locations: [0, 0.6, 1]) else { return }
        ctx.drawRadialGradient(g, startCenter: p, startRadius: 0, endCenter: p, endRadius: r, options: [])
    }
}
