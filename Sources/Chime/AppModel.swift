import AppKit
import Observation
import ServiceManagement

/// The app's state: the saved config, and the live badges reported by the core.
@MainActor
@Observable
final class AppModel {
    /// Changes are saved and applied as they are made.
    var config = Config() {
        didSet {
            if isStarted, config != oldValue {
                Core.setConfig(config)
            }
        }
    }

    private(set) var state = CoreState()
    private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled
    private(set) var launchAtLoginError: String?

    /// Whether the settings window is showing the app picker.
    var isPickingApps = false

    @ObservationIgnored private var isStarted = false

    init() {}

    /// A model that shows fixed sample data instead of the live Dock, for `DemoSnapshot`.
    init(sampleConfig: Config, state: CoreState) {
        self.config = sampleConfig
        self.state = state
    }

    private static var configURL: URL {
        // Lets a development build run against a scratch config.
        if let path = ProcessInfo.processInfo.environment["CHIME_CONFIG"] {
            return URL(fileURLWithPath: path)
        }
        return URL.applicationSupportDirectory.appending(path: "Chime/config.json")
    }

    func start() {
        state.trusted = Core.isTrusted()
        Core.start(configURL: Self.configURL) { [weak self] state in
            self?.state = state
        }
        config = Core.config
        isStarted = true
    }

    // MARK: Apps

    func status(of app: TrackedApp) -> AppStatus? {
        state.apps.first { $0.bundleId == app.bundleId }
    }

    /// Whether any tracked app has a badge.
    var hasNotifications: Bool {
        config.apps.contains { status(of: $0)?.badge != nil }
    }

    func isTracked(_ bundleId: String) -> Bool {
        config.apps.contains { $0.bundleId == bundleId }
    }

    func add(_ app: InstalledApp) {
        guard !isTracked(app.bundleId) else { return }
        config.apps.append(TrackedApp(bundleId: app.bundleId, name: app.name, path: app.path))
    }

    /// Adds the app bundles among `urls`. Returns whether there were any.
    @discardableResult
    func add(_ urls: [URL]) -> Bool {
        let apps = urls.compactMap(InstalledApp.init(url:))
        apps.forEach(add)
        return !apps.isEmpty
    }

    func remove(_ bundleId: String) {
        config.apps.removeAll { $0.bundleId == bundleId }
    }

    func toggle(_ app: InstalledApp) {
        if isTracked(app.bundleId) {
            remove(app.bundleId)
        } else {
            add(app)
        }
    }

    func setAlwaysShow(_ alwaysShow: Bool, for bundleId: String) {
        guard let index = config.apps.firstIndex(where: { $0.bundleId == bundleId }) else { return }
        config.apps[index].alwaysShow = alwaysShow
    }

    /// Where the app is installed now, which may differ from where it was added.
    func location(of app: TrackedApp) -> URL {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleId)
            ?? URL(fileURLWithPath: app.path)
    }

    func open(_ app: TrackedApp) {
        NSWorkspace.shared.openApplication(at: location(of: app), configuration: NSWorkspace.OpenConfiguration())
    }

    // MARK: System

    /// Asks macOS for Accessibility access and takes the user to the setting.
    func requestAccessibilityAccess() {
        if Core.isTrusted(prompt: true) {
            Core.refresh()
            return
        }
        let settings = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        NSWorkspace.shared.open(URL(string: settings)!)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = error.localizedDescription
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
