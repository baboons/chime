import Foundation

// These mirror the JSON the Rust core reads and writes (core/src/config.rs,
// core/src/monitor.rs, core/src/dock.rs).

struct Config: Codable, Equatable, Sendable {
    var version = 1
    var apps: [TrackedApp] = []
    var settings = AppSettings()
}

/// An app whose Dock badge is mirrored into the menu bar.
struct TrackedApp: Codable, Equatable, Identifiable, Sendable {
    var bundleId: String
    var name: String
    var path: String
    /// Keep the app in the menu bar even when it has no badge.
    var alwaysShow = false

    var id: String { bundleId }
}

struct AppSettings: Codable, Equatable, Sendable {
    var badgeStyle = BadgeStyle.pill
    var monochrome = false
    var showMenuIcon = true
    /// Bring a menu bar that hides automatically into view while there are notifications.
    var revealMenuBar = false
    var pollIntervalMs = 1000
}

enum BadgeStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    /// A red pill with the count, overlapping the icon like in the Dock.
    case pill
    /// The count as plain menu bar text next to the icon.
    case number
    /// A red dot with no count.
    case dot

    var id: Self { self }

    var title: String {
        switch self {
        case .pill: "Badge"
        case .number: "Number"
        case .dot: "Dot"
        }
    }
}

struct CoreState: Codable, Equatable, Sendable {
    /// Whether Accessibility access has been granted.
    var trusted = false
    var apps: [AppStatus] = []
}

struct AppStatus: Codable, Equatable, Sendable {
    var bundleId: String
    var running: Bool
    var badge: Badge?
}

struct Badge: Codable, Equatable, Sendable {
    /// The badge text exactly as the app set it.
    var label: String
    /// A compact form that fits in the menu bar, e.g. "1.2K".
    var short: String
    /// The numeric value, when the badge is a plain count.
    var count: UInt64?

    /// "3 notifications", or the badge text when it is not a count.
    var summary: String {
        switch count {
        case 1: "1 notification"
        case let count?: "\(count.formatted()) notifications"
        case nil: "Badge: \(label)"
        }
    }
}

/// An app icon in the Dock.
struct DockApp: Codable, Sendable {
    var path: String?
    var bundleId: String?
    var badge: Badge?
}
