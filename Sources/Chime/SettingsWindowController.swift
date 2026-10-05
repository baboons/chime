import AppKit
import SwiftUI

/// Chime's one window: the tracked apps and the settings.
@MainActor
final class SettingsWindowController {
    private let model: AppModel
    private var window: NSWindow?

    init(model: AppModel) {
        self.model = model
    }

    /// Brings the window forward, optionally straight into the app picker.
    func show(pickingApps: Bool = false) {
        let window = window ?? makeWindow()
        self.window = window
        if pickingApps {
            model.isPickingApps = true
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let content = NSHostingController(rootView: SettingsView().environment(model))
        // The view fixes the width and a minimum height; the height is the user's to resize.
        content.sizingOptions = [.minSize, .maxSize]

        let window = NSWindow(contentViewController: content)
        window.title = "Chime"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 480, height: 640))
        window.center()
        window.setFrameAutosaveName("Settings")
        return window
    }
}
