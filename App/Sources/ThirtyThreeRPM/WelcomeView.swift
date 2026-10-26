import AppKit
import SwiftUI

/// First-run setup: install the Chrome extension, pair it, play something.
struct WelcomeView: View {
    @ObservedObject var store: NowPlayingStore
    let token: String
    let done: () -> Void
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Welcome to 33rpm").font(.title2.weight(.semibold))
                    Text("A record player on your desktop for whatever's playing in YouTube Music.")
                        .foregroundStyle(.secondary)
                }
            }

            step(1, "Add the Chrome extension",
                 "In Chrome's Extensions page, turn on Developer mode, click Load unpacked and choose the 33rpm Bridge folder.") {
                Button("Show Extension Folder") { WelcomeView.revealExtension() }
                Button("Open Chrome Extensions") { WelcomeView.openChromeExtensions() }
            }

            step(2, "Pair it with this Mac",
                 "Click the 33rpm Bridge icon in Chrome's toolbar, paste this token and press Save.") {
                Button(copied ? "Copied" : "Copy Pairing Token") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(token, forType: .string)
                    copied = true
                }
            }

            step(3, "Play something on music.youtube.com",
                 "The turntable on your desktop picks it up within a second. Click the turntable to pause, the Up Next card or the crate to change songs.") {
                Label(statusText, systemImage: store.connection == .connected ? "checkmark.circle.fill" : "circle.dotted")
                    .foregroundStyle(store.connection == .connected ? .green : .secondary)
            }

            HStack {
                Text("Everything stays on this Mac (127.0.0.1). No accounts, no analytics.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Done", action: done).keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520)
    }

    private var statusText: String {
        switch store.connection {
        case .connected: store.track.map { "Connected · \($0.title)" } ?? "Connected"
        case .failed(let reason): "Problem: \(reason)"
        default: "Waiting for the extension…"
        }
    }

    private func step<Actions: View>(_ n: Int, _ title: String, _ detail: String,
                                     @ViewBuilder actions: () -> Actions) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(n)")
                .font(.headline.monospacedDigit())
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.accentColor.opacity(0.18)))
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack { actions() }.controlSize(.small)
            }
        }
    }

    /// The extension ships inside the app; copy it somewhere stable (Chrome keeps loading it from there) and show it.
    static func revealExtension() {
        let fm = FileManager.default
        guard let bundled = Bundle.main.resourceURL?.appendingPathComponent("33rpm Bridge"),
              fm.fileExists(atPath: bundled.path) else {
            if let repo = SceneLibrary.repoRoot?.deletingLastPathComponent().appendingPathComponent("extension") {
                NSWorkspace.shared.activateFileViewerSelecting([repo])
            }
            return
        }
        let target = PairingToken.directory.appendingPathComponent("33rpm Bridge")
        try? fm.removeItem(at: target)
        try? fm.copyItem(at: bundled, to: target)
        NSWorkspace.shared.activateFileViewerSelecting([target])
    }

    static func openChromeExtensions() {
        guard let chrome = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome"),
              let url = URL(string: "chrome://extensions") else { return }
        NSWorkspace.shared.open([url], withApplicationAt: chrome, configuration: NSWorkspace.OpenConfiguration())
    }
}
