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
    /// Show the apps that have notifications in a floating panel.
    var showIndicator = false
    /// What the floating panel's background is made of.
    var indicatorEffect = IndicatorEffect.blur
    /// How opaque that background is, from 0 (clear) to 1.
    var indicatorOpacity = 1.0
    /// Play a sound when a notification arrives.
    var playSound = false
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

enum IndicatorEffect: String, Codable, CaseIterable, Identifiable, Sendable {
    /// The system's blurred HUD material.
    case blur
    /// Liquid Glass. Needs macOS 26; older systems show the blur.
    case glass

    var id: Self { self }

    var title: String {
        switch self {
        case .blur: "Blur"
        case .glass: "Liquid Glass"
        }
    }

    /// Whether this version of macOS can draw the effect.
    var isAvailable: Bool {
        guard self == .glass else { return true }
        if #available(macOS 26, *) {
            return true
        }
        return false
    }
}

struct CoreState: Codable, Equatable, Sendable {
    /// Whether Accessibility access has been granted.
    var trusted = false
    var apps: [AppStatus] = []

    /// Whether a notification arrived since `previous`: an app got a badge, or
    /// its count went up. A badge that was already there when Chime started
    /// watching the app is not an arrival.
    func hasArrivals(since previous: CoreState) -> Bool {
        guard trusted, previous.trusted else { return false }
        return apps.contains { app in
            guard let badge = app.badge,
                  let before = previous.apps.first(where: { $0.bundleId == app.bundleId })
            else { return false }
            guard let oldBadge = before.badge else { return true }
            guard let count = badge.count, let oldCount = oldBadge.count else { return false }
            return count > oldCount
        }
    }
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
