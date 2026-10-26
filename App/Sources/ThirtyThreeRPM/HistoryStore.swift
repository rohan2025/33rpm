import AppKit
import Combine
import ImageIO
import UniformTypeIdentifiers

struct HistoryEntry: Codable, Identifiable, Equatable {
    var id: UUID
    var title: String
    var artist: String
    var album: String
    var playedAt: Date
    var hasArtwork: Bool
    var videoId: String?

    func isSameSong(as track: Track) -> Bool {
        if let videoId, let other = track.videoId { return videoId == other }
        return title == track.title && artist == track.artist
    }
}

/// The last 20 tracks that left the deck, newest first. Saved to
/// ~/Library/Application Support/33rpm/history.json with artwork in History/<id>.png.
@MainActor
final class HistoryStore: ObservableObject {
    static let limit = 20
    /// A track has to be on the deck this long to count, so a quick double-skip doesn't file the song in between.
    static let minimumSeconds: TimeInterval = 3

    @Published private(set) var entries: [HistoryEntry] = []
    private(set) var images: [UUID: CGImage] = [:]

    private let directory = PairingToken.directory.appendingPathComponent("History", isDirectory: true)
    private var file: URL { PairingToken.directory.appendingPathComponent("history.json") }
    private let ioQueue = DispatchQueue(label: "33rpm.history", qos: .utility)

    private var current: Track?
    private var currentArtwork: CGImage?
    private var currentSince = Date()
    private var cancellables: Set<AnyCancellable> = []

    init() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        load()
    }

    /// Watches the now-playing store and files each track into history when it leaves the deck.
    func record(from store: NowPlayingStore) {
        // @Published emits before the property changes, so these see the incoming values.
        store.$track
            .sink { [weak self] track in self?.trackChanged(to: track) }
            .store(in: &cancellables)
        store.$artwork
            .sink { [weak self] image in self?.currentArtwork = image?.squareCGImage }
            .store(in: &cancellables)
    }

    private func trackChanged(to track: Track?) {
        guard track != current else { return }
        if let leaving = current, Date().timeIntervalSince(currentSince) >= Self.minimumSeconds {
            add(leaving, artwork: currentArtwork)
        }
        current = track
        currentArtwork = nil   // the store keeps showing the old art until the new one loads
        currentSince = Date()
    }

    func add(_ track: Track, artwork: CGImage?) {
        // A connection blip re-sends the same song; don't file it twice in a row.
        if let top = entries.first, top.isSameSong(as: track) { return }

        let entry = HistoryEntry(id: UUID(), title: track.title, artist: track.artist, album: track.album,
                                 playedAt: Date(), hasArtwork: artwork != nil, videoId: track.videoId)
        if let artwork {
            let small = Self.downscaled(artwork, maxSide: 600)
            images[entry.id] = small
            let url = imageURL(entry.id)
            ioQueue.async { Self.writePNG(small, to: url) }
        }
        // A song played again from the crate goes back in at the front rather than appearing twice.
        var list = [entry]
        for old in entries {
            if old.isSameSong(as: track) { forget(old) } else { list.append(old) }
        }
        while list.count > Self.limit {
            forget(list.removeLast())
        }
        entries = list
        save()
    }

    private func forget(_ entry: HistoryEntry) {
        images[entry.id] = nil
        let url = imageURL(entry.id)
        ioQueue.async { try? FileManager.default.removeItem(at: url) }
    }

    // MARK: - Persistence

    private func imageURL(_ id: UUID) -> URL { directory.appendingPathComponent("\(id.uuidString).png") }

    private func load() {
        guard let data = try? Data(contentsOf: file),
              let saved = try? JSONDecoder().decode([HistoryEntry].self, from: data) else { return }
        entries = Array(saved.prefix(Self.limit))
        for entry in entries where entry.hasArtwork {
            if let source = CGImageSourceCreateWithURL(imageURL(entry.id) as CFURL, nil),
               let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
                images[entry.id] = image
            }
        }
    }

    private func save() {
        let snapshot = entries
        let url = file
        ioQueue.async {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            try? encoder.encode(snapshot).write(to: url, options: .atomic)
        }
    }

    private nonisolated static func writePNG(_ image: CGImage, to url: URL) {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { return }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
    }

    private static func downscaled(_ image: CGImage, maxSide: Int) -> CGImage {
        let side = max(image.width, image.height)
        guard side > maxSide else { return image }
        let s = CGFloat(maxSide) / CGFloat(side)
        let w = Int(CGFloat(image.width) * s), h = Int(CGFloat(image.height) * s)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage() ?? image
    }
}
