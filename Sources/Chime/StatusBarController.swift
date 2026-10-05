import AppKit
import Observation

/// Owns the menu bar: one item per tracked app, plus Chime's own bell menu.
@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let model: AppModel
    private let appButtons: AppButtons
    private let showSettings: (_ pickingApps: Bool) -> Void

    private var bellItem: NSStatusItem?
    private var appItems: [String: NSStatusItem] = [:]

    init(model: AppModel, appButtons: AppButtons, showSettings: @escaping (_ pickingApps: Bool) -> Void) {
        self.model = model
        self.appButtons = appButtons
        self.showSettings = showSettings
    }

    /// Shows the menu bar items and keeps them in step with the model.
    func start() {
        withObservationTracking {
            render()
        } onChange: { [weak self] in
            // Fires before the change lands, so render on the next main-queue turn.
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.start() }
            }
        }
    }

    private func render() {
        let config = model.config
        renderBell(visible: config.settings.showMenuIcon)

        for (bundleId, item) in appItems where !model.isTracked(bundleId) {
            NSStatusBar.system.removeStatusItem(item)
            appItems[bundleId] = nil
        }
        for app in config.apps {
            let badge = model.status(of: app)?.badge
            let item = appItems[app.bundleId] ?? makeItem(for: app)
            appItems[app.bundleId] = item
            item.isVisible = app.alwaysShow || badge != nil
            if item.isVisible, let button = item.button {
                appButtons.show(app, badge: badge, in: button)
            }
        }

        SystemMenuBar.setRevealed(config.settings.revealMenuBar && model.hasNotifications)
    }

    // MARK: App items

    private func makeItem(for app: TrackedApp) -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // Remembers where the user ⌘-dragged the item.
        item.autosaveName = "chime.app.\(app.bundleId)"
        if let button = item.button {
            button.identifier = NSUserInterfaceItemIdentifier(app.bundleId)
            button.target = self
            button.action = #selector(appItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.font = StatusItemArt.titleFont
        }
        return item
    }

    @objc private func appItemClicked(_ button: NSStatusBarButton) {
        guard let bundleId = button.identifier?.rawValue,
              let app = model.config.apps.first(where: { $0.bundleId == bundleId }),
              let item = appItems[bundleId]
        else { return }

        let event = NSApp.currentEvent
        let wantsMenu = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
        guard wantsMenu else {
            model.open(app)
            return
        }
        // A status item with a menu always opens it, so attach it for this click only.
        item.menu = appButtons.menu(for: app)
        button.performClick(nil)
        item.menu = nil
    }

    // MARK: Bell menu

    private func renderBell(visible: Bool) {
        guard visible else {
            if let bellItem {
                NSStatusBar.system.removeStatusItem(bellItem)
            }
            bellItem = nil
            return
        }
        guard bellItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.autosaveName = "chime.bell"
        item.button?.image = NSImage(systemSymbolName: "bell.fill", accessibilityDescription: "Chime")
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        bellItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if !model.state.trusted {
            menu.addItem(ActionMenuItem("Allow Accessibility Access…") { [showSettings] in showSettings(false) })
            menu.addItem(.separator())
        }
        for app in model.config.apps {
            let item = ActionMenuItem(app.name) { [model] in model.open(app) }
            let icon = NSWorkspace.shared.icon(forFile: model.location(of: app).path)
            icon.size = NSSize(width: 18, height: 18)
            item.image = icon
            if let badge = model.status(of: app)?.badge {
                item.badge = NSMenuItemBadge(string: badge.short)
            }
            menu.addItem(item)
        }
        if model.config.apps.isEmpty {
            menu.addItem(withTitle: "No Apps Added", action: nil, keyEquivalent: "")
        }
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem("Add Apps…") { [showSettings] in showSettings(true) })
        menu.addItem(ActionMenuItem("Settings…", keyEquivalent: ",") { [showSettings] in showSettings(false) })
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem("Quit Chime", keyEquivalent: "q") { NSApp.terminate(nil) })
    }
}
