import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private lazy var settings = SettingsWindowController(model: model)
    private lazy var statusBar = StatusBarController(model: model) { [unowned self] pickingApps in
        settings.show(pickingApps: pickingApps)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = makeMainMenu()
        model.start()
        statusBar.start()

        // Nothing to show in the menu bar yet, so start with setup.
        if model.config.apps.isEmpty || !model.state.trusted {
            settings.show()
        }
    }

    /// Nothing would hide the menu bar again once Chime is gone.
    func applicationWillTerminate(_ notification: Notification) {
        SystemMenuBar.setRevealed(false)
    }

    /// Opening Chime while it runs is the way back to settings when the bell is hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        settings.show()
        return true
    }

    /// Chime has no menu bar of its own, but the main menu is still what makes
    /// ⌘Q, ⌘W and the editing shortcuts work in its windows.
    private func makeMainMenu() -> NSMenu {
        let app = NSMenu()
        app.addItem(withTitle: "About Chime", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: "Quit Chime", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")

        let main = NSMenu()
        for submenu in [app, edit, window] {
            let item = NSMenuItem()
            item.submenu = submenu
            main.addItem(item)
        }
        return main
    }
}
