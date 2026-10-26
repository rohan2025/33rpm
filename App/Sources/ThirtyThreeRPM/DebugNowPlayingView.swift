import AppKit
import SwiftUI

/// Step 1 window: shows the live now-playing info and the pairing token.
struct DebugNowPlayingView: View {
    @ObservedObject var store: NowPlayingStore
    let token: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                artwork
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.track?.title ?? "Nothing playing")
                        .font(.title2.weight(.semibold))
                        .lineLimit(2)
                    Text(store.track?.artist ?? "—").foregroundStyle(.secondary)
                    Text(store.track?.album ?? "").foregroundStyle(.tertiary)
                    Spacer(minLength: 8)
                    Label(store.state.rawValue.capitalized, systemImage: stateIcon)
                        .font(.caption)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                let pos = store.position(at: context.date)
                VStack(spacing: 4) {
                    ProgressView(value: store.progress(at: context.date))
                    HStack {
                        Text(format(pos))
                        Spacer()
                        Text(format(store.duration))
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 20) {
                Spacer()
                Button { store.send(.previous) } label: { Image(systemName: "backward.fill") }
                Button { store.send(.playPause) } label: {
                    Image(systemName: store.state == .playing ? "pause.fill" : "play.fill")
                }
                Button { store.send(.next) } label: { Image(systemName: "forward.fill") }
                Spacer()
            }
            .buttonStyle(.borderless)
            .font(.title2)
            .disabled(store.connection != .connected || store.track == nil)

            Divider()

            HStack {
                Circle().fill(statusColor).frame(width: 8, height: 8)
                Text(statusText).font(.caption)
                Spacer()
                Button(copied ? "Copied" : "Copy pairing token") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(token, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                }
                .controlSize(.small)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    @ViewBuilder private var artwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.2))
            if let image = store.artwork {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "opticaldisc").font(.system(size: 48)).foregroundStyle(.secondary)
            }
        }
        .frame(width: 160, height: 160)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .animation(.easeInOut(duration: 0.4), value: store.artwork)
    }

    private var stateIcon: String {
        switch store.state {
        case .playing: "play.circle.fill"
        case .paused: "pause.circle.fill"
        case .idle: "moon.zzz.fill"
        }
    }

    private var statusText: String {
        switch store.connection {
        case .starting: "Starting server…"
        case .waiting: "Listening on 127.0.0.1:\(NowPlayingServer.defaultPort) — waiting for Chrome"
        case .connected: "Extension connected"
        case .failed(let reason): "Server failed: \(reason)"
        }
    }

    private var statusColor: Color {
        switch store.connection {
        case .connected: .green
        case .failed: .red
        default: .orange
        }
    }

    private func format(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let s = Int(seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
