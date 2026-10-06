import AppKit

/// An item that an app has put in the menu bar itself.
struct MenuBarItem: Equatable, Sendable {
    /// Its accessibility title, which is the text it shows if it shows any. Empty for none.
    var title = ""
}

/// Reads the items that other apps have in the menu bar, through the Accessibility API.
actor MenuBarItemReader {
    private struct NoAnswer: Error {}

    /// Each app's item when the app last answered.
    private var items: [String: MenuBarItem] = [:]

    /// The items of the apps that have one, by bundle id. `apps` has the
    /// processes that each app is running as.
    func read(_ apps: [String: [pid_t]]) -> [String: MenuBarItem] {
        var items: [String: MenuBarItem] = [:]
        for (bundleId, pids) in apps {
            // Whoever asked may have asked again since, and no longer waits for this answer.
            guard !Task.isCancelled else { return [:] }
            // An app can run more than once; the first copy with an item speaks for it.
            for pid in pids where items[bundleId] == nil {
                do {
                    items[bundleId] = try Self.item(of: pid)
                } catch {
                    // An app too busy to answer still has the item it had.
                    items[bundleId] = self.items[bundleId]
                }
            }
        }
        self.items = items
        return items
    }

    /// The first menu bar item of the app with `pid`, or nil if it has none in
    /// view. Throws if the app does not answer.
    private static func item(of pid: pid_t) throws -> MenuBarItem? {
        let app = AXUIElementCreateApplication(pid)
        guard let bar = try value("AXExtrasMenuBar", of: app), CFGetTypeID(bar) == AXUIElementGetTypeID(),
              let items = try value(kAXChildrenAttribute, of: bar as! AXUIElement) as? [AXUIElement]
        else { return nil }

        for item in items {
            var size = CGSize.zero
            guard let value = try value(kAXSizeAttribute, of: item), CFGetTypeID(value) == AXValueGetTypeID(),
                  AXValueGetValue(value as! AXValue, .cgSize, &size), size.width > 0, size.height > 0
            else { continue }
            let title = try self.value(kAXTitleAttribute, of: item) as? String ?? ""
            return MenuBarItem(title: title.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    /// An attribute of an accessibility element, or nil if it has none. Throws
    /// if the element's app does not answer.
    private static func value(_ attribute: String, of element: AXUIElement) throws -> CFTypeRef? {
        // Every element has a timeout of its own. A short one keeps a busy app from holding up the rest.
        AXUIElementSetMessagingTimeout(element, 0.5)
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        if error == .cannotComplete {
            throw NoAnswer()
        }
        return error == .success ? value : nil
    }
}
