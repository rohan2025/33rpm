import AppKit
import Combine
import ServiceManagement

enum SceneID: String, CaseIterable, Identifiable {
    case evening, rainyWindow, minimal
    var id: String { rawValue }
    var title: String {
        switch self {
        case .evening: "Evening"
        case .rainyWindow: "Rainy Window"
        case .minimal: "Minimal"
        }
    }
}

enum SceneSize: String, CaseIterable, Identifiable {
    case small, medium, full
    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    /// Scene width in points for the windowed sizes; `full` fills the display.
    var width: CGFloat? {
        switch self {
        case .small: 480
        case .medium: 800
        case .full: nil
        }
    }
}

/// User preferences, persisted in UserDefaults.
@MainActor
final class AppSettings: ObservableObject {
    private let defaults = UserDefaults.standard

    @Published var isVisible: Bool { didSet { defaults.set(isVisible, forKey: "isVisible") } }
    @Published var scene: SceneID { didSet { defaults.set(scene.rawValue, forKey: "scene") } }
    @Published var size: SceneSize { didSet { defaults.set(size.rawValue, forKey: "size") } }
    /// Record speed. nil = the scene's own (33⅓ for all bundled scenes).
    @Published var rpm: Double? {
        didSet {
            if let rpm { defaults.set(rpm, forKey: "rpm") } else { defaults.removeObject(forKey: "rpm") }
        }
    }
    /// Play/pause, previous, next under the turntable when the pointer is over it.
    @Published var showControls: Bool { didSet { defaults.set(showControls, forKey: "showControls") } }
    /// Up Next card on the wall.
    @Published var showUpNext: Bool { didSet { defaults.set(showUpNext, forKey: "showUpNext") } }
    /// Dust, lamp flicker, rain and ambient video.
    @Published var ambientEffects: Bool { didSet { defaults.set(ambientEffects, forKey: "ambientEffects") } }

    /// nil means "every display".
    @Published var displayID: CGDirectDisplayID? {
        didSet {
            if let displayID { defaults.set(Int(displayID), forKey: "displayID") }
            else { defaults.removeObject(forKey: "displayID") }
        }
    }

    init() {
        rpm = defaults.object(forKey: "rpm") as? Double
        showControls = defaults.object(forKey: "showControls") as? Bool ?? true
        showUpNext = defaults.object(forKey: "showUpNext") as? Bool ?? true
        ambientEffects = defaults.object(forKey: "ambientEffects") as? Bool ?? true
        isVisible = defaults.object(forKey: "isVisible") as? Bool ?? true
        scene = SceneID(rawValue: defaults.string(forKey: "scene") ?? "") ?? .evening
        size = SceneSize(rawValue: defaults.string(forKey: "size") ?? "") ?? .medium
        displayID = (defaults.object(forKey: "displayID") as? Int).map { CGDirectDisplayID($0) }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}

/// The connected displays, kept current as monitors are plugged in or removed.
@MainActor
final class DisplayCatalog: ObservableObject {
    struct Display: Identifiable, Hashable {
        let id: CGDirectDisplayID
        let name: String
    }

    @Published private(set) var displays: [Display] = []
    private var observer: NSObjectProtocol?

    init() {
        refresh()
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func refresh() {
        displays = NSScreen.screens.compactMap { screen in
            screen.displayID.map { Display(id: $0, name: screen.localizedName) }
        }
    }

    /// The screens to show the scene on: every screen when `id` is nil, otherwise the chosen one
    /// (falling back to every screen if it's disconnected).
    static func screens(for id: CGDirectDisplayID?) -> [NSScreen] {
        if let id, let match = NSScreen.screens.first(where: { $0.displayID == id }) { return [match] }
        return NSScreen.screens
    }
}

/// Launch at login via SMAppService. Only works when running from the .app bundle.
@MainActor
final class LoginItem: ObservableObject {
    @Published private(set) var isEnabled = false

    init() { refresh() }

    func refresh() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("33rpm: launch at login change failed: \(error.localizedDescription)")
        }
        if SMAppService.mainApp.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
        refresh()
    }
}
