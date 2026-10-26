import AppKit
import Combine
import CoreServices
import ImageIO

/// Layout for one scene, read from `Scenes/<Folder>/scene.json`.
/// Coordinates are in canvas points with the origin at the top-left.
struct SceneConfig: Decodable {
    struct Layer: Decodable {
        var slot: String
        /// [x, y, width, height]. Omitted only for the `deck` group marker.
        var frame: [CGFloat]?
        /// Rotation/pivot point as a fraction of the layer's size, top-left origin. Default [0.5, 0.5].
        var anchor: [CGFloat]?
        var opacity: Float?
        var hidden: Bool?
        /// Degrees, clockwise. Used for the leaning sleeve.
        var rotation: CGFloat?
        /// "screen", "add", "softLight", "overlay" or "multiply". Good for glows and light videos.
        var blend: String?
        /// lamp_glow: how deep the flicker dips (0 = steady, 0.15 = gentle).
        var flicker: CGFloat?
        /// dust / rain: density multiplier (1 = default).
        var amount: CGFloat?
        /// video: file name in the scene folder (default "ambient.mp4").
        var file: String?
    }

    /// The turntable top, laid out top-down in its own coordinates and then tilted away from the viewer.
    struct Deck: Decodable {
        var center: [CGFloat]
        var size: [CGFloat]
        /// Degrees the deck top leans back. 0 = seen from directly above.
        var tilt: CGFloat
        /// Viewer distance for perspective, in canvas points. Larger = flatter.
        var perspective: CGFloat
        var layers: [Layer]
    }

    struct Record: Decodable {
        var rpm: Double = 33.333
        /// Label size as a fraction of the record's diameter.
        var labelDiameter: CGFloat = 0.36
        var sheenOpacity: Float = 0.5
        var spinUpSeconds: Double = 1.0
        var spinDownSeconds: Double = 1.8
    }

    /// Angles in degrees, clockwise from the tonearm image's own orientation.
    struct Tonearm: Decodable {
        var restAngle: CGFloat = 0
        var startAngle: CGFloat = 27
        var endAngle: CGFloat = 44
        var moveSeconds: Double = 1.4
    }

    /// How sleeves sit in the crate and lift out when browsing. All sizes relative to the sleeve.
    struct Crate: Decodable {
        /// Sleeve width as a fraction of the crate's width.
        var sleeveSize: CGFloat = 0.8
        /// How much of each sleeve shows above the crate's top edge.
        var peek: CGFloat = 0.3
        /// How far the hovered sleeve rises out of the crate.
        var browseLift: CGFloat = 0.62
        /// Darkens sleeves to sit in a dim room (0 = as is, 0.5 = quite dark). Lighter on the `lightFrom` side.
        var sleeveShade: CGFloat = 0
        /// Where the room's light comes from: "left", "right" or "none".
        var lightFrom: String = "right"

        init() {}
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            sleeveSize = try c.decodeIfPresent(CGFloat.self, forKey: .sleeveSize) ?? sleeveSize
            peek = try c.decodeIfPresent(CGFloat.self, forKey: .peek) ?? peek
            browseLift = try c.decodeIfPresent(CGFloat.self, forKey: .browseLift) ?? browseLift
            sleeveShade = try c.decodeIfPresent(CGFloat.self, forKey: .sleeveShade) ?? sleeveShade
            lightFrom = try c.decodeIfPresent(String.self, forKey: .lightFrom) ?? lightFrom
        }
        private enum CodingKeys: String, CodingKey { case sleeveSize, peek, browseLift, sleeveShade, lightFrom }
    }

    /// Where the hover playback controls sit (canvas point). Default: just in front of the deck.
    struct Controls: Decodable {
        var center: [CGFloat]?
        var scale: CGFloat?
        /// Degrees, to follow the turntable's edge.
        var rotation: CGFloat?
    }

    /// The receiver in the room photo: its display window [x, y, w, h] and three knobs [x, y, radius]
    /// (previous, play/pause, next), in canvas points.
    struct Receiver: Decodable {
        var display: [CGFloat]
        var knobs: [[CGFloat]]
    }

    var canvas: [CGFloat]
    var controls: Controls?
    var receiver: Receiver?
    /// Canvas point kept in view when the scene is cropped to fill a screen of a different shape.
    var focus: [CGFloat]?
    var crate: Crate?
    /// Width in canvas points of the soft fade into the wallpaper at the scene's edges (windowed sizes only).
    var edgeFade: CGFloat?
    var layers: [Layer]
    var deck: Deck
    var record: Record
    var tonearm: Tonearm

    var canvasSize: CGSize { CGSize(width: canvas[0], height: canvas[1]) }
}

extension SceneConfig.Layer {
    var rect: CGRect {
        guard let f = frame, f.count == 4 else { return .zero }
        return CGRect(x: f[0], y: f[1], width: f[2], height: f[3])
    }
    var anchorPoint: CGPoint {
        guard let a = anchor, a.count == 2 else { return CGPoint(x: 0.5, y: 0.5) }
        return CGPoint(x: a[0], y: a[1])
    }
}

/// A scene with every slot's image resolved (user PNG or placeholder).
struct LoadedScene {
    var id: SceneID
    var config: SceneConfig
    var images: [String: CGImage]
    var defaultLabel: CGImage
    var defaultSleeve: CGImage
}

extension SceneID {
    var folderName: String {
        switch self {
        case .evening: "Evening"
        case .rainyWindow: "RainyWindow"
        case .minimal: "Minimal"
        }
    }
}

/// Finds scene files. Each file is looked up in order:
///   1. ~/Library/Application Support/33rpm/Scenes/<Folder>/   (personal overrides)
///   2. <repo>/Scenes/<Folder>/                                  (when built from this checkout)
///   3. 33rpm.app/Contents/Resources/Scenes/<Folder>/            (bundled copy)
/// Missing PNGs get a drawn placeholder; a missing scene falls back to Evening.
enum SceneLibrary {
    static var userRoot: URL { PairingToken.directory.appendingPathComponent("Scenes", isDirectory: true) }

    static var repoRoot: URL? {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Scenes", isDirectory: true)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static var bundleRoot: URL? {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("Scenes", isDirectory: true),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    static var searchRoots: [URL] { [userRoot] + [repoRoot, bundleRoot].compactMap { $0 } }

    static func file(_ name: String, in folder: String) -> URL? {
        for root in searchRoots {
            let url = root.appendingPathComponent(folder).appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }

    /// The folder to open for editing: the repo copy if present, else the personal override folder.
    static func editableFolder(for id: SceneID) -> URL {
        if let repo = repoRoot?.appendingPathComponent(id.folderName),
           FileManager.default.fileExists(atPath: repo.path) { return repo }
        let url = userRoot.appendingPathComponent(id.folderName)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func load(_ id: SceneID) -> LoadedScene? {
        guard let configURL = file("scene.json", in: id.folderName) else {
            if id != .evening {
                return load(.evening).map { var s = $0; s.id = id; return s }
            }
            NSLog("33rpm: no scene.json found for \(id.folderName)")
            return nil
        }
        let config: SceneConfig
        do {
            config = try JSONDecoder().decode(SceneConfig.self, from: Data(contentsOf: configURL))
        } catch {
            NSLog("33rpm: can't read \(configURL.path): \(error)")
            return nil
        }

        var images: [String: CGImage] = [:]
        for layer in config.layers + config.deck.layers where layer.frame != nil {
            images[layer.slot] = image(named: layer.slot, in: id.folderName)
                ?? Placeholders.image(for: layer.slot, size: layer.rect.size, variant: id.folderName)
        }
        let label = image(named: "default_label", in: id.folderName) ?? Placeholders.defaultLabel()
        let sleeve = image(named: "default_sleeve", in: id.folderName) ?? Placeholders.defaultSleeve()
        return LoadedScene(id: id, config: config, images: images, defaultLabel: label, defaultSleeve: sleeve)
    }

    static func image(named slot: String, in folder: String) -> CGImage? {
        guard let url = file("\(slot).png", in: folder),
              let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    }
}

/// Loads the selected scene and reloads it when its files change on disk.
@MainActor
final class SceneRuntime: ObservableObject {
    @Published private(set) var scene: LoadedScene?

    private let settings: AppSettings
    private var watcher: FolderWatcher?
    private var cancellables: Set<AnyCancellable> = []
    private var reloadWork: DispatchWorkItem?

    init(settings: AppSettings) {
        self.settings = settings
        try? FileManager.default.createDirectory(at: SceneLibrary.userRoot, withIntermediateDirectories: true)
        scene = SceneLibrary.load(settings.scene)

        settings.$scene.dropFirst().removeDuplicates()
            .sink { [weak self] id in self?.scene = SceneLibrary.load(id) ?? self?.scene }
            .store(in: &cancellables)

        let paths = [SceneLibrary.userRoot, SceneLibrary.repoRoot].compactMap { $0?.path }
        watcher = FolderWatcher(paths: paths) { [weak self] in
            MainActor.assumeIsolated { self?.scheduleReload() }
        }
    }

    private func scheduleReload() {
        reloadWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            // Keep the old scene if the new JSON is broken mid-edit.
            if let fresh = SceneLibrary.load(self.settings.scene) { self.scene = fresh }
        }
        reloadWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }
}

/// Recursive FSEvents watch; calls `handler` on the main queue.
final class FolderWatcher {
    private let handler: () -> Void
    private var stream: FSEventStreamRef?

    init(paths: [String], handler: @escaping () -> Void) {
        self.handler = handler
        guard !paths.isEmpty else { return }
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue().handler()
        }
        guard let stream = FSEventStreamCreate(nil, callback, &context, paths as CFArray,
                                               FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.25,
                                               FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents))
        else { return }
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
        self.stream = stream
    }

    deinit {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }
}
