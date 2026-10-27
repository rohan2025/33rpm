import AppKit
import Metal
import QuartzCore

/// `33rpm --snapshot out.png [--scene evening] [--playing] [--title T] [--artist A] [--progress 0.4] [--width 1500] [--height 844]`
/// Renders the scene offscreen with CARenderer (which, unlike `render(in:)`, handles the 3D deck tilt)
/// and exits. Handy for checking scene.json edits without looking at the desktop.
@MainActor
enum Snapshot {
    static func runIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count else { return }
        let out = URL(fileURLWithPath: args[i + 1])
        func value(_ flag: String) -> String? {
            args.firstIndex(of: flag).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }
        }
        let sceneID = value("--scene").flatMap(SceneID.init(rawValue:)) ?? .evening
        let progress = value("--progress").flatMap(Double.init) ?? 0.3
        let width = value("--width").flatMap(Double.init) ?? 1500
        let playing = args.contains("--playing")
        let demoHistory = value("--demo-history").flatMap(Int.init) ?? 0
        let browse = value("--browse").flatMap(Int.init)
        let flyAt = value("--fly-at").flatMap(Double.init)
        let demoQueue = value("--demo-queue").flatMap(Int.init) ?? 0
        let showControls = args.contains("--show-controls")
        coversDir = value("--covers").map { URL(fileURLWithPath: $0) }

        do {
            try render(sceneID: sceneID, playing: playing, progress: progress, width: width,
                       demoHistory: demoHistory, browse: browse, flyAt: flyAt,
                       demoQueue: demoQueue, showControls: showControls, to: out)
            print("Wrote \(out.path)")
            exit(0)
        } catch {
            FileHandle.standardError.write("snapshot failed: \(error)\n".data(using: .utf8)!)
            exit(1)
        }
    }

    /// Optional folder of PNG covers to use instead of the coloured stand-ins (for launch screenshots).
    private static var coversDir: URL?

    private static var covers: [(title: String, image: CGImage)] {
        guard let dir = coversDir,
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        else { return [] }
        let titles = ["candle": "Wick", "lamp": "Low Lamp", "leaves": "Greenhouse", "rain": "Window Seat",
                      "rug": "Persian Blue", "woodgrain": "Grain"]
        return files.filter { $0.pathExtension == "png" }.sorted { $0.path < $1.path }.compactMap { url in
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
            let key = url.deletingPathExtension().lastPathComponent
            return (titles[key] ?? key.capitalized, img)
        }
    }

    /// Stand-in album art: a coloured square with a few shapes.
    static func demoArt(hue: CGFloat) -> CGImage? {
        Placeholders.render(size: CGSize(width: 300, height: 300)) { ctx, r in
            ctx.setFillColor(NSColor(hue: hue, saturation: 0.55, brightness: 0.75, alpha: 1).cgColor)
            ctx.fill(r)
            ctx.setFillColor(NSColor(hue: (hue + 0.5).truncatingRemainder(dividingBy: 1), saturation: 0.6,
                                     brightness: 0.9, alpha: 1).cgColor)
            ctx.fillEllipse(in: r.insetBy(dx: 70, dy: 70))
            ctx.setFillColor(NSColor(white: 0.1, alpha: 0.8).cgColor)
            ctx.fill(CGRect(x: 30, y: 230, width: 160, height: 22))
        }
    }

    struct Failure: Error, CustomStringConvertible { let description: String }

    static func render(sceneID: SceneID, playing: Bool, progress: Double, width: Double,
                       demoHistory: Int, browse: Int?, flyAt: Double? = nil,
                       demoQueue: Int = 0, showControls: Bool = false, to url: URL) throws {
        guard let scene = SceneLibrary.load(sceneID) else { throw Failure(description: "scene didn't load") }
        let canvas = scene.config.canvasSize
        let heightArg = CommandLine.arguments.firstIndex(of: "--height").flatMap {
            $0 + 1 < CommandLine.arguments.count ? Double(CommandLine.arguments[$0 + 1]) : nil
        }
        let size = CGSize(width: width, height: heightArg ?? (width * canvas.height / canvas.width).rounded())

        let view = TurntableView(frame: CGRect(origin: .zero, size: size))
        let layer = view.layer!
        layer.frame = CGRect(origin: .zero, size: size)
        view.load(scene)
        if CommandLine.arguments.contains("--no-fade") { view.fadesEdges = false }
        let art = covers
        let demo = (0..<max(demoHistory, 0)).map { i in
            art.isEmpty
                ? SleeveCrate.Item(id: UUID(), image: demoArt(hue: CGFloat(i) / CGFloat(max(demoHistory, 1))),
                                   title: "Demo Track \(i + 1)", artist: "Some Artist")
                : SleeveCrate.Item(id: UUID(), image: art[(i + 1) % art.count].image,
                                   title: art[(i + 1) % art.count].title, artist: "The Late Hours")
        }
        // remaining 0: static arm, no sweep animation
        let label = playing && demoHistory > 0 ? (art.first?.image ?? demoArt(hue: 0.55)) : nil
        let args = CommandLine.arguments
        func value(_ flag: String) -> String? {
            args.firstIndex(of: flag).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }
        }
        let nowTitle = value("--title") ?? (playing && demoHistory > 0 ? (art.first?.title ?? "Demo Track") : nil)
        let nowArtist = value("--artist").map { $0.isEmpty ? nil : $0 } ?? (nowTitle == nil ? nil : "Mira Sol")
        view.apply(PlaybackInput(isPlaying: playing, progress: progress, remaining: 0, label: label,
                                 title: nowTitle, artist: nowArtist), animated: false)
        if flyAt != nil, let newest = demo.first {
            // Show the newest sleeve mid-flight from the wall into the crate.
            view.setHistory(Array(demo.dropFirst()), animated: false)
            CATransaction.flush()
            view.setHistory([newest] + demo.dropFirst(), animated: true)
        } else {
            view.setHistory(demo, animated: false)
        }
        if let browse { view.browse(index: browse) }
        // Fictional tracks, so screenshots don't feature real artists.
        let titles = ["Window Seat", "Greenhouse", "Persian Blue", "After the Rain", "Grain", "Low Lamp"]
        let artists = ["Nadia Rowe", "Kiln", "Ostra", "The Late Hours", "Halden", "Mira Sol"]
        view.setQueue((0..<max(0, demoQueue)).map {
            QueueItem(title: titles[$0 % titles.count], artist: artists[$0 % artists.count], videoId: nil, thumbnailURL: nil)
        })
        if showControls { view.previewControls() }
        CATransaction.flush()

        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue()
        else { throw Failure(description: "no Metal device") }
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: Int(size.width),
                                                            height: Int(size.height), mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: desc) else { throw Failure(description: "no texture") }

        let renderer = CARenderer(mtlTexture: texture, options: [kCARendererMetalCommandQueue as String: queue])
        renderer.layer = layer
        renderer.bounds = layer.bounds
        CATransaction.flush()   // the renderer only sees changes committed after it's attached
        renderer.beginFrame(atTime: CACurrentMediaTime() + (flyAt ?? 0), timeStamp: nil)
        renderer.addUpdate(renderer.bounds)
        renderer.render()
        renderer.endFrame()
        // Commands on one queue finish in order, so waiting on an empty buffer waits for the render.
        let fence = queue.makeCommandBuffer()!
        fence.commit()
        fence.waitUntilCompleted()

        let w = texture.width, h = texture.height, rowBytes = w * 4
        var pixels = [UInt8](repeating: 0, count: rowBytes * h)
        texture.getBytes(&pixels, bytesPerRow: rowBytes, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        // CARenderer's output has its origin at the bottom-left; flip rows for the PNG.
        var flipped = [UInt8](repeating: 0, count: pixels.count)
        for row in 0..<h {
            let src = row * rowBytes, dst = (h - 1 - row) * rowBytes
            flipped[dst..<dst + rowBytes] = pixels[src..<src + rowBytes]
        }
        pixels = flipped
        guard let ctx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: rowBytes,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
              let image = ctx.makeImage(),
              let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)
        else { throw Failure(description: "couldn't encode PNG") }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw Failure(description: "couldn't write \(url.path)") }
    }
}
