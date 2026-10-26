import AppKit
import Combine

/// Borderless, click-through windows pinned at desktop level: above the wallpaper, below every app window
/// (and below desktop icons), on all Spaces. One window per display the scene is shown on.
@MainActor
final class DesktopWindowController {
    /// Gap between a windowed scene and the bottom of the usable screen area.
    static let bottomMargin: CGFloat = 48

    /// Normally just above the wallpaper, below desktop icons.
    static let restingLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
    /// While the pointer is over the crate: just above Finder's desktop layer (still below every app window),
    /// so clicks reach us instead of Finder, which would trigger "click wallpaper to reveal desktop".
    static let interactiveLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)

    private let store: NowPlayingStore
    private let settings: AppSettings
    private let runtime: SceneRuntime
    private let history: HistoryStore
    private var windows: [CGDirectDisplayID: NSWindow] = [:]
    private var cancellables: Set<AnyCancellable> = []

    private var labelSource: NSImage?
    private var labelImage: CGImage?
    private var mouseMonitors: [Any] = []
    private var screensAsleep = false
    private var sessionInactive = false

    init(store: NowPlayingStore, settings: AppSettings, runtime: SceneRuntime, history: HistoryStore) {
        self.store = store
        self.settings = settings
        self.runtime = runtime
        self.history = history

        // Re-layout whenever size, display or visibility change. `receive(on:)` lets the @Published
        // values settle before we read them.
        settings.$size.combineLatest(settings.$displayID, settings.$isVisible)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.update() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.update() }
            .store(in: &cancellables)

        runtime.$scene
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.reloadScene() }
            .store(in: &cancellables)

        // The store changes several properties per update; coalesce them into one push.
        store.objectWillChange
            .debounce(for: .milliseconds(30), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.pushPlayback(animated: true) }
            .store(in: &cancellables)

        // Freeze everything nobody can see: display sleep, screen lock / user switch, or a fully covered window.
        let workspace = NSWorkspace.shared.notificationCenter
        let power: [(NSNotification.Name, NotificationCenter, (DesktopWindowController) -> Void)] = [
            (NSWorkspace.screensDidSleepNotification, workspace, { $0.screensAsleep = true }),
            (NSWorkspace.screensDidWakeNotification, workspace, { $0.screensAsleep = false }),
            (NSWorkspace.sessionDidResignActiveNotification, workspace, { $0.sessionInactive = true }),
            (NSWorkspace.sessionDidBecomeActiveNotification, workspace, { $0.sessionInactive = false }),
            (Notification.Name("com.apple.screenIsLocked"), DistributedNotificationCenter.default(), { $0.sessionInactive = true }),
            (Notification.Name("com.apple.screenIsUnlocked"), DistributedNotificationCenter.default(), { $0.sessionInactive = false }),
        ]
        for (name, center, change) in power {
            center.publisher(for: name)
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in
                    guard let self else { return }
                    change(self)
                    self.updateActivity()
                }
                .store(in: &cancellables)
        }
        NotificationCenter.default.publisher(for: NSWindow.didChangeOcclusionStateNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateActivity() }
            .store(in: &cancellables)
        store.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateActivity() }
            .store(in: &cancellables)

        store.$queue
            .receive(on: RunLoop.main)
            .sink { [weak self] queue in self?.views.forEach { $0.setQueue(queue) } }
            .store(in: &cancellables)

        // Settings window changes apply live.
        settings.$rpm.combineLatest(settings.$showControls, settings.$showUpNext, settings.$ambientEffects)
            .combineLatest(settings.$showTitle)
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.views.forEach { self.applySettings(to: $0) }
                self.updateActivity()
            }
            .store(in: &cancellables)

        history.$entries
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.pushHistory(animated: true) }
            .store(in: &cancellables)

        // Windows ignore the mouse (clicks reach the desktop) except while the pointer is over the crate.
        // Mouse-moved monitors need no special permission.
        let track: (NSEvent) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.updateMouseCapture() }
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved, handler: track) {
            mouseMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved, handler: { track($0); return $0 }) {
            mouseMonitors.append(local)
        }
        // Fallback for clicks that still land on Finder's desktop layer (e.g. before the window was lifted).
        if let clicks = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.handleGlobalClick() }
        }) {
            mouseMonitors.append(clicks)
        }
    }

    private func handleGlobalClick() {
        let mouse = NSEvent.mouseLocation
        for window in windows.values {
            guard window.frame.contains(mouse), let view = window.contentView as? TurntableView else { continue }
            let point = view.convert(window.convertPoint(fromScreen: mouse), from: nil)
            guard view.isInteractive(at: point), !Self.isCovered(mouse, above: window) else { continue }
            view.click(at: point)
        }
    }

    /// Whether a regular window (any app's) is over this screen point above our desktop-level window.
    /// Desktop elements like Finder's icon layer don't count.
    private static func isCovered(_ point: NSPoint, above window: NSWindow) -> Bool {
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenAboveWindow, .excludeDesktopElements],
                                                    CGWindowID(window.windowNumber)) as? [[String: Any]],
              let mainHeight = NSScreen.screens.first?.frame.height else { return false }
        // CG window bounds use a top-left origin on the main display.
        let cgPoint = CGPoint(x: point.x, y: mainHeight - point.y)
        let ownPID = Int(ProcessInfo.processInfo.processIdentifier)
        for w in info {
            guard (w[kCGWindowLayer as String] as? Int ?? 0) >= 0,
                  (w[kCGWindowOwnerPID as String] as? Int) != ownPID,
                  (w[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let boundsDict = w[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict) else { continue }
            if bounds.contains(cgPoint) { return true }
        }
        return false
    }

    private func applySettings(to view: TurntableView) {
        view.rpmOverride = settings.rpm
        view.showsControls = settings.showControls
        view.showsUpNext = settings.showUpNext
        view.showsTitle = settings.showTitle
        view.ambientEnabled = settings.ambientEffects
    }

    /// Suspends windows nobody can see and runs the ambient video only when it's worth decoding.
    private func updateActivity() {
        var anyVisible = false
        for window in windows.values {
            guard let view = window.contentView as? TurntableView else { continue }
            let hidden = screensAsleep || sessionInactive || !window.occlusionState.contains(.visible)
            view.setSuspended(hidden)
            anyVisible = anyVisible || !hidden
        }
        AmbientVideo.shared.setPlaying(anyVisible && store.state == .playing && settings.ambientEffects)
    }

    private func updateMouseCapture() {
        let mouse = NSEvent.mouseLocation
        for window in windows.values {
            guard let view = window.contentView as? TurntableView else { continue }
            let point = view.convert(window.convertPoint(fromScreen: mouse), from: nil)
            let inside = window.frame.contains(mouse) && view.isInteractive(at: point)
            if window.ignoresMouseEvents == inside {
                window.ignoresMouseEvents = !inside
                window.level = inside ? Self.interactiveLevel : Self.restingLevel
            }
            // Drive browsing from here too, so it doesn't depend on a background window getting hover events.
            if inside { view.hover(at: point) } else { view.endBrowse() }
        }
    }

    func update() {
        let screens = settings.isVisible ? DisplayCatalog.screens(for: settings.displayID) : []
        let wanted = Set(screens.compactMap(\.displayID))

        for (id, window) in windows where !wanted.contains(id) {
            window.orderOut(nil)
            windows[id] = nil
        }
        for screen in screens {
            guard let id = screen.displayID else { continue }
            let window = windows[id] ?? makeWindow()
            windows[id] = window
            window.setFrame(Self.frame(for: settings.size, on: screen, canvas: canvasSize), display: true)
            DispatchQueue.main.async { [weak self] in self?.updateActivity() }
            (window.contentView as? TurntableView)?.fadesEdges = settings.size != .full
            window.orderFront(nil)
        }
    }

    private var canvasSize: CGSize { runtime.scene?.config.canvasSize ?? CGSize(width: 1500, height: 1000) }

    private var views: [TurntableView] { windows.values.compactMap { $0.contentView as? TurntableView } }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 533),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.level = Self.restingLevel
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.acceptsMouseMovedEvents = true

        let view = TurntableView(frame: window.contentLayoutRect)
        view.onPlayItem = { [weak self] item in self?.play(item) }
        view.onCommand = { [weak self] command in self?.store.send(command) }
        view.onPlayQueued = { [weak self] item in self?.store.play(item) }
        applySettings(to: view)
        view.setQueue(store.queue)
        window.contentView = view
        if let scene = runtime.scene { view.load(scene) }
        view.apply(currentInput(), animated: false)
        view.setHistory(historyItems(), animated: false)
        return window
    }

    private func reloadScene() {
        guard let scene = runtime.scene else { return }
        views.forEach { $0.load(scene) }
        update()   // canvas aspect may have changed
    }

    private func pushPlayback(animated: Bool) {
        let input = currentInput()
        views.forEach { $0.apply(input, animated: animated) }
    }

    private func pushHistory(animated: Bool) {
        let items = historyItems()
        views.forEach { $0.setHistory(items, animated: animated) }
    }

    private func historyItems() -> [SleeveCrate.Item] {
        history.entries.map {
            SleeveCrate.Item(id: $0.id, image: history.images[$0.id], title: $0.title, artist: $0.artist,
                             videoId: $0.videoId)
        }
    }

    /// Plays a crate sleeve: through the extension when connected, otherwise by opening it in Chrome.
    private func play(_ item: SleeveCrate.Item) {
        if store.connection == .connected {
            store.play(videoId: item.videoId, title: item.title, artist: item.artist)
            return
        }
        var components = URLComponents(string: "https://music.youtube.com")!
        if let id = item.videoId {
            components.path = "/watch"
            components.queryItems = [URLQueryItem(name: "v", value: id)]
        } else {
            components.path = "/search"
            components.queryItems = [URLQueryItem(name: "q", value: "\(item.title) \(item.artist)")]
        }
        guard let url = components.url else { return }
        if let chrome = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome") {
            NSWorkspace.shared.open([url], withApplicationAt: chrome, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    private func currentInput() -> PlaybackInput {
        if store.artwork !== labelSource {
            labelSource = store.artwork
            labelImage = store.artwork?.squareCGImage
        }
        let remaining = store.duration > 0 ? max(0, store.duration - store.position()) : 0
        return PlaybackInput(isPlaying: store.state == .playing, progress: store.progress(),
                             remaining: remaining, label: labelImage,
                             title: store.track?.title, artist: store.track?.artist)
    }

    static func frame(for size: SceneSize, on screen: NSScreen, canvas: CGSize) -> NSRect {
        guard let width = size.width else { return screen.frame }
        let area = screen.visibleFrame
        let w = min(width, area.width - 32)
        let h = (w * canvas.height / canvas.width).rounded()
        return NSRect(x: (area.midX - w / 2).rounded(), y: area.minY + bottomMargin, width: w, height: h)
    }
}
