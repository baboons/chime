import AppKit
import Observation
import ServiceManagement

/// The app's state: the saved config, the live badges reported by the core, and
/// what the apps have to say for themselves.
@MainActor
@Observable
final class AppModel {
    /// Changes are saved and applied as they are made.
    var config = Config() {
        didSet {
            if isStarted, config != oldValue {
                Core.setConfig(config)
                watchOwnItems()
            }
        }
    }

    private(set) var state = CoreState()
    /// The tracked apps that have an item of their own in the menu bar, while Chime is to use those.
    private(set) var appsWithOwnItem: Set<String> = []
    /// Those items, by bundle id.
    private(set) var ownItems: [String: MenuBarItem] = [:]
    /// What apps have sent Chime to show with them, by bundle id.
    private(set) var sentLabels: [String: ItemLabel] = [:]
    private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled
    private(set) var launchAtLoginError: String?

    /// Whether the settings window is showing the app picker.
    var isPickingApps = false

    @ObservationIgnored private var isStarted = false
    @ObservationIgnored private let itemReader = MenuBarItemReader()
    @ObservationIgnored private var itemWatch: Task<Void, Never>?
    @ObservationIgnored private var inbox: ItemInbox?
    @ObservationIgnored private let sound = NSSound(named: "Glass")

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
            self?.receive(state)
        }
        config = Core.config
        isStarted = true
        watchOwnItems()

        let inbox = ItemInbox { [weak self] bundleId, label in
            // Whoever observes this is told of every assignment, so only assign what changed.
            if let self, sentLabels[bundleId] != label {
                sentLabels[bundleId] = label
            }
        }
        inbox.start()
        self.inbox = inbox
    }

    private func receive(_ newState: CoreState) {
        let hasArrivals = newState.hasArrivals(since: state)
        state = newState
        if hasArrivals, config.settings.playSound {
            playSound()
        }
        watchOwnItems()
    }

    /// Plays the sound that announces a notification.
    func playSound() {
        sound?.play()
    }

    // MARK: Apps

    func status(of app: TrackedApp) -> AppStatus? {
        state.apps.first { $0.bundleId == app.bundleId }
    }

    /// Whether `app` has something to be shown for: a badge on its Dock icon,
    /// or an item it sent, which says there is something even without one.
    func isNotified(_ app: TrackedApp) -> Bool {
        status(of: app)?.badge != nil || sentLabels[app.bundleId] != nil
    }

    /// Whether any tracked app has something to be shown for.
    var hasNotifications: Bool {
        config.apps.contains { isNotified($0) }
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

    // MARK: What apps say

    /// What `app` has to say next to its icon: what it sent Chime or, failing
    /// that, the title of its own menu bar item.
    func label(of app: TrackedApp) -> ItemLabel? {
        sentLabels[app.bundleId] ?? itemTitle(of: app).map { ItemLabel(title: $0) }
    }

    /// Whether `app` is in the menu bar by itself, so that Chime need not put it there.
    func hasOwnItem(_ app: TrackedApp) -> Bool {
        appsWithOwnItem.contains(app.bundleId)
    }

    /// What `app`'s own menu bar item says, if Chime is to use the item and it says anything.
    private func itemTitle(of app: TrackedApp) -> String? {
        guard let title = ownItems[app.bundleId]?.title, !title.isEmpty,
              // An item that shows no text is often titled after its app, which the icon says already.
              title.caseInsensitiveCompare(app.name) != .orderedSame
        else { return nil }
        return title
    }

    /// Reads the tracked apps' own menu bar items now, and from then on for as
    /// long as Chime is to use them. Called whenever what to read may have changed.
    private func watchOwnItems() {
        itemWatch?.cancel()
        itemWatch = Task { [weak self] in
            while !Task.isCancelled, let wait = await self?.readOwnItems() {
                try? await Task.sleep(for: wait)
            }
        }
    }

    /// Reads the items once. Returns how long to wait before reading them
    /// again, or nil if Chime is not to use them.
    private func readOwnItems() async -> Duration? {
        let settings = config.settings
        guard settings.useOwnItems, state.trusted else {
            setOwnItems([:])
            return nil
        }
        var running: [String: [pid_t]] = [:]
        for app in config.apps {
            running[app.bundleId] = NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleId)
                .map(\.processIdentifier)
        }
        let items = await itemReader.read(running)
        guard !Task.isCancelled else { return nil }

        setOwnItems(items)
        // A title on show in the indicator may be counting down the seconds.
        // Twice a second misses none of them. An app that sends its own needs no watching.
        let isShowingTitle = settings.showIndicator && config.apps.contains { app in
            status(of: app)?.badge != nil && sentLabels[app.bundleId] == nil && itemTitle(of: app) != nil
        }
        return .milliseconds(isShowingTitle ? 500 : settings.pollIntervalMs)
    }

    private func setOwnItems(_ items: [String: MenuBarItem]) {
        // Whoever observes these is told of every assignment, so only assign what changed.
        if ownItems != items {
            ownItems = items
        }
        let apps = Set(items.keys)
        if appsWithOwnItem != apps {
            appsWithOwnItem = apps
        }
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
