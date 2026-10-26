import Foundation
import Network

/// WebSocket server on 127.0.0.1 that the Chrome extension connects to.
///
/// Protocol (JSON text frames):
///   ext → app  {type:"hello", token}            must be the first message, within 5s
///   app → ext  {type:"welcome"} | {type:"error", reason:"bad_token"}
///   ext → app  {type:"state", track:{title,artist,album,artwork,artworkFallback}|null,
///               state:"playing"|"paused", position, duration}
///   ext → app  {type:"idle"} | {type:"ping"} | {type:"queue", items:[{title,artist,videoId,thumb}]}
///   app → ext  {type:"command", action:"playPause"|"play"|"pause"|"next"|"previous"} | {type:"pong"}
///   app → ext  {type:"command", action:"playVideo", videoId} | {type:"command", action:"search", query}
///   app → ext  {type:"command", action:"playQueue", videoId}
final class NowPlayingServer {
    enum Event {
        case listening
        case failed(String)
        case connected
        case disconnected
        case state(StateUpdate)
        case queue([QueueItem])
        case idle
    }

    static let defaultPort: UInt16 = 33333

    private let port: UInt16
    private let token: String
    private let queue = DispatchQueue(label: "33rpm.server")
    private var listener: NWListener?
    private var clients: [ObjectIdentifier: Client] = [:]
    private var active: Client?
    private var watchdog: DispatchSourceTimer?

    /// Called on the main queue.
    var onEvent: ((Event) -> Void)?

    private final class Client {
        let connection: NWConnection
        var authenticated = false
        var lastActivity = Date()
        init(_ connection: NWConnection) { self.connection = connection }
        var id: ObjectIdentifier { ObjectIdentifier(self) }
    }

    init(port: UInt16 = NowPlayingServer.defaultPort, token: String) {
        self.port = port
        self.token = token
    }

    func start() {
        let ws = NWProtocolWebSocket.Options()
        ws.autoReplyPing = true
        ws.maximumMessageSize = 1 << 20
        // Only Chrome extensions may connect; this blocks web pages from talking to us.
        ws.setClientRequestHandler(queue) { _, headers in
            let origin = headers.first { $0.name.lowercased() == "origin" }?.value ?? ""
            let allowed = origin.hasPrefix("chrome-extension://")
            return NWProtocolWebSocket.Response(status: allowed ? .accept : .reject,
                                                subprotocol: nil, additionalHeaders: nil)
        }

        let params = NWParameters.tcp
        params.defaultProtocolStack.applicationProtocols.insert(ws, at: 0)
        params.allowLocalEndpointReuse = true
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)

        do {
            let listener = try NWListener(using: params)
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready: self?.emit(.listening)
                case .failed(let error): self?.emit(.failed("Port \(self?.port ?? 0): \(error.localizedDescription)"))
                default: break
                }
            }
            listener.newConnectionHandler = { [weak self] conn in self?.accept(conn) }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            emit(.failed(error.localizedDescription))
        }

        startWatchdog()
    }

    func send(command: PlayerCommand, extra: [String: String] = [:]) {
        queue.async { [weak self] in
            guard let self, let client = self.active else { return }
            var message: [String: Any] = ["type": "command", "action": command.rawValue]
            extra.forEach { message[$0.key] = $0.value }
            self.send(message, to: client)
        }
    }

    // MARK: - Connections

    private func accept(_ conn: NWConnection) {
        let client = Client(conn)
        clients[client.id] = client
        conn.stateUpdateHandler = { [weak self, weak client] state in
            guard let self, let client else { return }
            switch state {
            case .failed, .cancelled: self.drop(client)
            default: break
            }
        }
        conn.start(queue: queue)
        receive(client)

        queue.asyncAfter(deadline: .now() + 5) { [weak self, weak client] in
            guard let self, let client, !client.authenticated else { return }
            self.drop(client)
        }
    }

    private func drop(_ client: Client) {
        guard clients.removeValue(forKey: client.id) != nil else { return }
        client.connection.cancel()
        if active === client {
            active = nil
            emit(.disconnected)
        }
    }

    private func receive(_ client: Client) {
        client.connection.receiveMessage { [weak self, weak client] data, context, _, error in
            guard let self, let client else { return }
            if error != nil {
                self.drop(client)
                return
            }
            let meta = context?.protocolMetadata(definition: NWProtocolWebSocket.definition)
                as? NWProtocolWebSocket.Metadata
            if meta?.opcode == .close {
                self.drop(client)
                return
            }
            if let data, meta?.opcode == .text {
                client.lastActivity = Date()
                self.handle(data, from: client)
            }
            if self.clients[client.id] != nil { self.receive(client) }
        }
    }

    private func send(_ object: [String: Any], to client: Client) {
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return }
        let meta = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "msg", metadata: [meta])
        client.connection.send(content: data, contentContext: context, isComplete: true, completion: .idempotent)
    }

    // MARK: - Messages

    private struct Inbound: Decodable {
        struct TrackPayload: Decodable {
            var title: String?
            var artist: String?
            var album: String?
            var artwork: String?
            var artworkFallback: String?
            var videoId: String?
        }
        var type: String
        var token: String?
        var track: TrackPayload?
        var state: String?
        var position: Double?
        var duration: Double?
        var items: [QueuePayload]?
    }

    private struct QueuePayload: Decodable {
        var title: String?
        var artist: String?
        var videoId: String?
        var thumb: String?
    }

    private func handle(_ data: Data, from client: Client) {
        guard let msg = try? JSONDecoder().decode(Inbound.self, from: data) else { return }

        guard client.authenticated else {
            if msg.type == "hello", let t = msg.token, PairingToken.matches(t, token) {
                client.authenticated = true
                // Newest extension connection wins (e.g. after Chrome restarts its worker).
                if let previous = active, previous !== client {
                    active = nil
                    drop(previous)
                }
                active = client
                send(["type": "welcome"], to: client)
                emit(.connected)
            } else {
                send(["type": "error", "reason": "bad_token"], to: client)
                queue.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.drop(client) }
            }
            return
        }

        switch msg.type {
        case "ping":
            send(["type": "pong"], to: client)
        case "idle":
            emit(.idle)
        case "queue":
            let items = (msg.items ?? []).prefix(12).compactMap { q -> QueueItem? in
                guard let title = q.title, !title.isEmpty else { return nil }
                let thumb = q.thumb.flatMap(URL.init(string:)).flatMap { $0.scheme == "https" ? $0 : nil }
                return QueueItem(title: title, artist: q.artist ?? "", videoId: q.videoId, thumbnailURL: thumb)
            }
            emit(.queue(Array(items)))
        case "state":
            guard let t = msg.track, let title = t.title, !title.isEmpty else {
                emit(.idle)
                return
            }
            let track = Track(title: title,
                              artist: t.artist ?? "",
                              album: t.album ?? "",
                              artworkURL: t.artwork.flatMap(URL.init(string:)),
                              artworkFallbackURL: t.artworkFallback.flatMap(URL.init(string:)),
                              videoId: t.videoId)
            emit(.state(StateUpdate(track: track,
                                    isPlaying: msg.state == "playing",
                                    position: msg.position ?? 0,
                                    duration: msg.duration ?? 0)))
        default:
            break
        }
    }

    /// The extension pings every 20s; a minute of silence means it's gone without closing the socket.
    private func startWatchdog() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 15, repeating: 15)
        timer.setEventHandler { [weak self] in
            guard let self, let client = self.active else { return }
            if Date().timeIntervalSince(client.lastActivity) > 60 { self.drop(client) }
        }
        timer.resume()
        watchdog = timer
    }

    private func emit(_ event: Event) {
        DispatchQueue.main.async { [weak self] in self?.onEvent?(event) }
    }
}
