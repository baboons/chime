import AppKit

/// Receives what apps send Chime to show with them. docs/api.md describes it
/// from the sending side.
@MainActor
final class ItemInbox: NSObject {
    /// What an app posts, with the item as JSON in the notification's object.
    private static let item = Notification.Name("com.baboons.chime.item")
    /// What Chime posts when it starts to listen, for apps that posted before then.
    private static let ready = Notification.Name("com.baboons.chime.ready")

    /// An item as an app sends it.
    private struct Sent: Decodable {
        var app: String
        var title: String?
        var color: String?
        var icon: String?
    }

    /// The longest icon taken, in bytes: an image for the indicator is small.
    private static let iconLimit = 64 * 1024

    private let receive: (_ bundleId: String, _ label: ItemLabel?) -> Void

    /// `receive` gets what an app wants shown with it, or nil when that is nothing.
    init(receive: @escaping (_ bundleId: String, _ label: ItemLabel?) -> Void) {
        self.receive = receive
    }

    func start() {
        let center = DistributedNotificationCenter.default()
        // An app that is not the active one, as Chime hardly ever is, gets its
        // notifications late unless it asks for them at once.
        center.addObserver(
            self, selector: #selector(itemSent), name: Self.item, object: nil, suspensionBehavior: .deliverImmediately)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(appQuit), name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        center.postNotificationName(Self.ready, object: nil, userInfo: nil, deliverImmediately: true)
    }

    @objc private func itemSent(_ notification: Notification) {
        guard let json = notification.object as? String,
              let sent = try? JSONDecoder().decode(Sent.self, from: Data(json.utf8)),
              // An app that is not running has nothing to show, and would never quit to be forgotten.
              !NSRunningApplication.runningApplications(withBundleIdentifier: sent.app).isEmpty
        else { return }

        let title = sent.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let color = sent.color.flatMap(NSColor.init(hex:))
        let icon = sent.icon.flatMap { $0.utf8.count <= Self.iconLimit ? $0 : nil }
        receive(sent.app, title.isEmpty ? nil : ItemLabel(title: title, color: color, icon: icon))
    }

    @objc private func appQuit(_ notification: Notification) {
        let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        if let bundleId = app?.bundleIdentifier {
            receive(bundleId, nil)
        }
    }
}

private extension NSColor {
    /// A color written as `#RRGGBB`.
    convenience init?(hex: String) {
        let digits = hex.hasPrefix("#") ? hex.dropFirst() : Substring(hex)
        guard digits.count == 6, digits.allSatisfy(\.isHexDigit), let value = UInt32(digits, radix: 16) else {
            return nil
        }
        self.init(
            srgbRed: CGFloat(value >> 16 & 0xFF) / 255,
            green: CGFloat(value >> 8 & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}
