import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var loginItem: LoginItem

    private static let realRPM = 100.0 / 3

    var body: some View {
        Form {
            Section("Record") {
                LabeledContent("Speed") {
                    HStack {
                        Slider(value: speed, in: 12...45)
                        Text(speedLabel)
                            .monospacedDigit()
                            .frame(width: 64, alignment: .trailing)
                    }
                }
                HStack {
                    Spacer()
                    Button("Real 33⅓") { settings.rpm = nil }
                        .disabled(settings.rpm == nil)
                    Button("Relaxed 22") { settings.rpm = 22 }
                }
                .controlSize(.small)
            }

            Section("On the desktop") {
                Toggle("Play/pause controls when pointing at the turntable", isOn: $settings.showControls)
                Toggle("Up Next card on the wall", isOn: $settings.showUpNext)
                Toggle("Ambient effects (dust, lamp flicker, rain, video)", isOn: $settings.ambientEffects)
                Text("Click the turntable to play or pause, a song on the Up Next card to play it, or a sleeve in the crate to play it again.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Scene") {
                Picker("Scene", selection: $settings.scene) {
                    ForEach(SceneID.allCases) { Text($0.title).tag($0) }
                }
                Picker("Size", selection: $settings.size) {
                    ForEach(SceneSize.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Launch at login", isOn: Binding(get: { loginItem.isEnabled },
                                                        set: { loginItem.setEnabled($0) }))
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var speed: Binding<Double> {
        Binding(get: { settings.rpm ?? Self.realRPM },
                set: { settings.rpm = abs($0 - Self.realRPM) < 0.4 ? nil : ($0 * 2).rounded() / 2 })
    }

    private var speedLabel: String {
        guard let rpm = settings.rpm else { return "33⅓ rpm" }
        return rpm == rpm.rounded() ? "\(Int(rpm)) rpm" : String(format: "%.1f rpm", rpm)
    }
}
