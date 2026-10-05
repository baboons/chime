import Foundation

/// The system's "Automatically hide and show the menu bar" setting, which Chime
/// can turn off for as long as there are notifications to show.
@MainActor
enum SystemMenuBar {
    /// The global preference behind the setting.
    private static let autoHideKey = "_HIHideMenuBar" as CFString
    /// What System Settings posts when the preference changes. The menu bar follows it right away.
    private static let autoHideChanged = Notification.Name("AppleInterfaceMenuBarHidingChangedNotification")
    /// Set while the menu bar is in view because of Chime. It is saved, so that
    /// a Chime that was killed in that state still hides the menu bar next time.
    private static let revealedKey = "menuBarRevealed"

    /// Brings a menu bar that hides automatically into view, or lets it hide
    /// again. A menu bar that is always in view is left alone.
    static func setRevealed(_ revealed: Bool) {
        let defaults = UserDefaults.standard
        if revealed {
            guard autoHides else { return }
            defaults.set(true, forKey: revealedKey)
            autoHides = false
        } else if defaults.bool(forKey: revealedKey) {
            defaults.removeObject(forKey: revealedKey)
            autoHides = true
        }
    }

    private static var autoHides: Bool {
        get {
            let value = CFPreferencesCopyValue(
                autoHideKey, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
            return value as? Bool ?? false
        }
        set {
            CFPreferencesSetValue(
                autoHideKey, newValue as CFBoolean,
                kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
            CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
            DistributedNotificationCenter.default().postNotificationName(
                autoHideChanged, object: nil, userInfo: nil, deliverImmediately: true)
        }
    }
}
