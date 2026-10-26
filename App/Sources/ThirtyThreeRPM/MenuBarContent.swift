import AppKit
import SwiftUI

struct MenuBarContent: View {
    @ObservedObject var store: NowPlayingStore
    @ObservedObject var settings: AppSettings
    @ObservedObject var displays: DisplayCatalog
    @ObservedObject var loginItem: LoginItem
    let copyToken: () -> Void
    let showDebugWindow: () -> Void
    let openScenesFolder: () -> Void
    let showSettings: () -> Void
    let showWelcome: () -> Void

    var body: some View {
        if let track = store.track {
            Text(track.title)
            Text(track.artist)
        } else {
            Text("Nothing playing")
        }

        Group {
            Button(store.state == .playing ? "Pause" : "Play") { store.send(.playPause) }
            Button("Next Track") { store.send(.next) }
            Button("Previous Track") { store.send(.previous) }
        }
        .disabled(store.connection != .connected || store.track == nil)

        Divider()

        Toggle("Show Turntable", isOn: $settings.isVisible)
            .keyboardShortcut("t")

        Picker("Scene", selection: $settings.scene) {
            ForEach(SceneID.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.menu)

        Picker("Size", selection: $settings.size) {
            ForEach(SceneSize.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.menu)

        Picker("Display", selection: $settings.displayID) {
            Text("All Displays").tag(CGDirectDisplayID?.none)
            ForEach(displays.displays) { Text($0.name).tag(CGDirectDisplayID?.some($0.id)) }
        }
        .pickerStyle(.menu)

        Divider()

        Toggle("Launch at Login", isOn: Binding(get: { loginItem.isEnabled },
                                                set: { loginItem.setEnabled($0) }))
        Button("Settings…", action: showSettings)
            .keyboardShortcut(",")
        Button("Open Scenes Folder", action: openScenesFolder)
        Button("Copy Pairing Token", action: copyToken)
        Button("Setup Guide…", action: showWelcome)
        Button("Show Debug Window", action: showDebugWindow)

        Divider()

        Text(connectionText)
        Button("Quit 33rpm") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private var connectionText: String {
        switch store.connection {
        case .starting: "Starting…"
        case .waiting: "Waiting for Chrome extension"
        case .connected: "Chrome extension connected"
        case .failed(let reason): "Server error: \(reason)"
        }
    }
}
