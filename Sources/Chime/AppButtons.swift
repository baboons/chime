import AppKit

/// How a tracked app looks and what its menu offers, wherever Chime shows it:
/// in the menu bar and in the floating indicator.
@MainActor
final class AppButtons {
    private let model: AppModel
    private let showSettings: (_ pickingApps: Bool) -> Void

    /// App icons by bundle id, as drawn for `iconsConfig`.
    private var icons: [String: NSImage] = [:]
    private var iconsConfig: Config?

    init(model: AppModel, showSettings: @escaping (_ pickingApps: Bool) -> Void) {
        self.model = model
        self.showSettings = showSettings
    }

    /// Draws the app and its badge into `button`, followed by `label` if there is one.
    func show(_ app: TrackedApp, badge: Badge?, label: ItemLabel? = nil, in button: NSButton) {
        let content = StatusItemArt.content(
            icon: icon(for: app), badge: badge, style: model.config.settings.badgeStyle, label: label)
        // An app shown for what it sent, without a badge, is about that.
        let summary = badge?.summary ?? model.sentLabels[app.bundleId]?.title ?? "No notifications"
        button.image = content.image
        button.title = content.title
        button.imagePosition = content.title.isEmpty ? .imageOnly : .imageLeading
        button.toolTip = "\(app.name) – \(summary)"
        button.setAccessibilityLabel("\(app.name), \(summary)")
    }

    private func icon(for app: TrackedApp) -> NSImage {
        // The icons depend on the settings and on where the apps are installed.
        if iconsConfig != model.config {
            icons.removeAll()
            iconsConfig = model.config
        }
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

    /// The menu that right-clicking the app opens.
    func menu(for app: TrackedApp) -> NSMenu {
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
}

/// A menu item that runs a closure.
final class ActionMenuItem: NSMenuItem {
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
