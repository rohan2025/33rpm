import AppKit
import Foundation

struct Track: Equatable, Codable {
    var title: String
    var artist: String
    var album: String
    var artworkURL: URL?
    var artworkFallbackURL: URL?
    /// YouTube video ID, so the song can be played again from the crate.
    var videoId: String?
}

/// A song coming up next in YouTube Music's queue.
struct QueueItem: Equatable {
    var title: String
    var artist: String
    var videoId: String?
    var thumbnailURL: URL?
}

enum PlaybackState: String {
    case playing, paused, idle
}

enum ConnectionStatus: Equatable {
    case starting
    case waiting            // listening, no extension connected
    case connected
    case failed(String)     // e.g. port already in use
}

enum PlayerCommand: String {
    case playPause, play, pause, next, previous
    /// Load a song by video ID (extra: "videoId"), or search for one (extra: "query").
    case playVideo, search
    /// Jump to a song already in the queue (extra: "videoId").
    case playQueue
}

/// A state snapshot sent by the extension.
struct StateUpdate {
    var track: Track?
    var isPlaying: Bool
    var position: Double
    var duration: Double
}

@MainActor
final class NowPlayingStore: ObservableObject {
    @Published private(set) var track: Track?
    @Published private(set) var state: PlaybackState = .idle
    @Published private(set) var duration: Double = 0
    @Published private(set) var artwork: NSImage?
    @Published var connection: ConnectionStatus = .starting
    /// Up next, in order.
    @Published private(set) var queue: [QueueItem] = []

    /// Where the song was at `anchorDate`; position is extrapolated from here while playing.
    private var anchorPosition: Double = 0
    private var anchorDate = Date()

    private var artworkTask: Task<Void, Never>?
    private let artworkCache = NSCache<NSURL, NSImage>()

    var commandSink: ((PlayerCommand, [String: String]) -> Void)?

    func position(at date: Date = Date()) -> Double {
        guard state == .playing else { return anchorPosition }
        let p = anchorPosition + date.timeIntervalSince(anchorDate)
        return duration > 0 ? min(duration, p) : p
    }

    /// 0...1 progress through the current song.
    func progress(at date: Date = Date()) -> Double {
        guard duration > 0 else { return 0 }
        return max(0, min(1, position(at: date) / duration))
    }

    func apply(_ update: StateUpdate) {
        guard let newTrack = update.track else {
            setIdle()
            return
        }
        if newTrack != track {
            track = newTrack
            loadArtwork(for: newTrack)
        }
        state = update.isPlaying ? .playing : .paused
        duration = update.duration
        anchorPosition = update.position
        anchorDate = Date()
    }

    func setIdle() {
        artworkTask?.cancel()
        track = nil
        artwork = nil
        queue = []
        state = .idle
        duration = 0
        anchorPosition = 0
    }

    func send(_ command: PlayerCommand) {
        commandSink?(command, [:])
    }

    func setQueue(_ items: [QueueItem]) {
        if items != queue { queue = items }
    }

    /// Skips ahead to a queued song (or plays it by ID if it's no longer in the queue).
    func play(_ item: QueueItem) {
        if let id = item.videoId {
            commandSink?(.playQueue, ["videoId": id])
        } else {
            play(videoId: nil, title: item.title, artist: item.artist)
        }
    }

    /// Plays a song in the YouTube Music tab: by video ID when known, otherwise via search.
    func play(videoId: String?, title: String, artist: String) {
        if let videoId {
            commandSink?(.playVideo, ["videoId": videoId])
        } else {
            commandSink?(.search, ["query": "\(title) \(artist)"])
        }
    }

    private func loadArtwork(for track: Track) {
        artworkTask?.cancel()
        let urls = [track.artworkURL, track.artworkFallbackURL].compactMap { $0 }
        if let first = urls.first, let cached = artworkCache.object(forKey: first as NSURL) {
            artwork = cached
            return
        }
        artworkTask = Task { [weak self] in
            for url in urls {
                guard !Task.isCancelled else { return }
                guard let (data, response) = try? await URLSession.shared.data(from: url),
                      (response as? HTTPURLResponse)?.statusCode == 200,
                      let image = NSImage(data: data) else { continue }
                guard !Task.isCancelled, let self, self.track == track else { return }
                self.artworkCache.setObject(image, forKey: (urls.first ?? url) as NSURL)
                self.artwork = image
                return
            }
            guard let self, self.track == track else { return }
            self.artwork = nil
        }
    }
}
