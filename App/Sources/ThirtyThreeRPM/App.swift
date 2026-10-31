import AppKit
import SwiftUI

@main
struct ThirtyThreeRPMApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        Snapshot.runIfRequested()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(store: appDelegate.store,
                           settings: appDelegate.settings,
                           displays: appDelegate.displays,
                           loginItem: appDelegate.loginItem,
                           copyToken: appDelegate.copyToken,
                           showDebugWindow: appDelegate.showDebugWindow,
                           showSettings: appDelegate.showSettings,
                           showWelcome: appDelegate.showWelcome)
        } label: {
            Image(systemName: "opticaldisc")
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = NowPlayingStore()
    let settings = AppSettings()
    let displays = DisplayCatalog()
    let loginItem = LoginItem()
    lazy var sceneRuntime = SceneRuntime(settings: settings)
    let history = HistoryStore()
    let token = PairingToken.loadOrCreate()

    private var server: NowPlayingServer?
    private var desktopWindow: DesktopWindowController?
    private var debugWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var welcomeWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar only, no Dock icon. The bundle sets LSUIElement; this covers `swift run`.
        NSApp.setActivationPolicy(.accessory)

        let server = NowPlayingServer(token: token)
        server.onEvent = { [weak self] event in self?.handle(event) }
        store.commandSink = { [weak server] command, extra in server?.send(command: command, extra: extra) }
        server.start()
        self.server = server
        history.record(from: store)

        if !UserDefaults.standard.bool(forKey: "didShowWelcome") {
            UserDefaults.standard.set(true, forKey: "didShowWelcome")
            showWelcome()
        }

        let desktop = DesktopWindowController(store: store, settings: settings, runtime: sceneRuntime, history: history)
        desktop.update()
        desktopWindow = desktop
    }

    func copyToken() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(token, forType: .string)
    }

    func showWelcome() {
        if welcomeWindow == nil {
            let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable],
                                  backing: .buffered, defer: false)
            window.title = "Set up 33rpm"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: WelcomeView(store: store, token: token) { [weak window] in
                window?.close()
            })
            window.center()
            welcomeWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        welcomeWindow?.makeKeyAndOrderFront(nil)
    }

    func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable],
                                  backing: .buffered, defer: false)
            window.title = "33rpm Settings"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView(settings: settings, loginItem: loginItem))
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func showDebugWindow() {
        if debugWindow == nil {
            let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .miniaturizable],
                                  backing: .buffered, defer: false)
            window.title = "33rpm"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: DebugNowPlayingView(store: store, token: token))
            window.center()
            debugWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        debugWindow?.makeKeyAndOrderFront(nil)
    }

    private func handle(_ event: NowPlayingServer.Event) {
        switch event {
        case .listening:
            if store.connection != .connected { store.connection = .waiting }
        case .failed(let reason):
            store.connection = .failed(reason)
        case .connected:
            store.connection = .connected
        case .disconnected:
            store.connection = .waiting
            store.setIdle()
        case .state(let update):
            store.apply(update)
        case .queue(let items):
            store.setQueue(items)
        case .idle:
            store.setIdle()
        }
    }
}
