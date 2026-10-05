import AppKit
import Observation

/// Owns the menu bar: one item per tracked app, plus Chime's own bell menu.
@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let model: AppModel
    private let showSettings: (_ pickingApps: Bool) -> Void

    private var bellItem: NSStatusItem?
    private var appItems: [String: NSStatusItem] = [:]

    /// App icons by bundle id, as drawn for `iconsConfig`.
    private var icons: [String: NSImage] = [:]
    private var iconsConfig: Config?

    init(model: AppModel, showSettings: @escaping (_ pickingApps: Bool) -> Void) {
        self.model = model
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
        if iconsConfig != config {
            icons.removeAll()
            iconsConfig = config
        }

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
                show(app, badge: badge, style: config.settings.badgeStyle, in: button)
            }
        }
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

    private func show(_ app: TrackedApp, badge: Badge?, style: BadgeStyle, in button: NSStatusBarButton) {
        let content = StatusItemArt.content(icon: icon(for: app), badge: badge, style: style)
        let summary = badge?.summary ?? "No notifications"
        button.image = content.image
        button.title = content.title
        button.imagePosition = content.title.isEmpty ? .imageOnly : .imageLeading
        button.toolTip = "\(app.name) – \(summary)"
        button.setAccessibilityLabel("\(app.name), \(summary)")
    }

    private func icon(for app: TrackedApp) -> NSImage {
        if let icon = icons[app.bundleId] {
            return icon
        }
        var icon = NSWorkspace.shared.icon(forFile: model.location(of: app).path)
        if model.config.settings.monochrome {
            icon = StatusItemArt.monochrome(icon)
        }
        icons[app.bundleId] = icon
        return icon
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
        item.menu = menu(for: app)
        button.performClick(nil)
        item.menu = nil
    }

    private func menu(for app: TrackedApp) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(ActionMenuItem("Open \(app.name)") { [model] in model.open(app) })
        menu.addItem(.separator())
        let alwaysShow = ActionMenuItem("Always Show in Menu Bar") { [model] in
            model.setAlwaysShow(!app.alwaysShow, for: app.bundleId)
        }
        alwaysShow.state = app.alwaysShow ? .on : .off
        menu.addItem(alwaysShow)
        menu.addItem(ActionMenuItem("Remove from Chime") { [model] in model.remove(app.bundleId) })
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem("Chime Settings…") { [showSettings] in showSettings(false) })
        menu.addItem(ActionMenuItem("Quit Chime") { NSApp.terminate(nil) })
        return menu
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

/// A menu item that runs a closure.
private final class ActionMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, keyEquivalent: String = "", handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: keyEquivalent)
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @objc private func run() {
        handler()
    }
}
