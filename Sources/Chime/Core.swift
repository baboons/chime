import CChimeCore
import Foundation

/// The Rust core, which watches the Dock and owns the saved configuration.
@MainActor
enum Core {
    typealias StateHandler = @MainActor @Sendable (CoreState) -> Void

    /// Loads the config at `configURL` and starts watching the Dock. `onState`
    /// gets the first reading right away, then one whenever it changes.
    static func start(configURL: URL, onState: @escaping StateHandler) {
        // The core calls back for as long as the app runs, so the box is never released.
        let box = Unmanaged.passRetained(HandlerBox(handler: onState))
        let started = chime_start(configURL.path, stateDidChange, box.toOpaque())
        if !started {
            box.release()
        }
    }

    static var config: Config {
        take(chime_config_get()).flatMap { decode(Config.self, from: $0) } ?? Config()
    }

    /// Saves the config and applies it to the running monitor.
    static func setConfig(_ config: Config) {
        guard let json = try? JSONEncoder().encode(config) else { return }
        _ = chime_config_set(String(decoding: json, as: UTF8.self))
    }

    /// Every app in the Dock, or nothing if the Dock cannot be read.
    static func dockApps() -> [DockApp] {
        take(chime_dock_snapshot()).flatMap { decode([DockApp].self, from: $0) } ?? []
    }

    /// Whether Accessibility access is granted, optionally asking macOS to prompt for it.
    static func isTrusted(prompt: Bool = false) -> Bool {
        chime_accessibility_trusted(prompt)
    }

    /// Reads the Dock right away instead of waiting for the next check.
    static func refresh() {
        chime_refresh()
    }
}

private final class HandlerBox: Sendable {
    let handler: Core.StateHandler

    init(handler: @escaping Core.StateHandler) {
        self.handler = handler
    }
}

/// The core's state callback. It runs on the core's monitor thread, so it is
/// a global function: a closure written inside `Core` would be main-actor isolated.
private func stateDidChange(json: UnsafePointer<CChar>, context: UnsafeMutableRawPointer?) {
    guard let context, let state = decode(CoreState.self, from: Data(cString: json)) else { return }
    let handler = Unmanaged<HandlerBox>.fromOpaque(context).takeUnretainedValue().handler
    DispatchQueue.main.async {
        MainActor.assumeIsolated { handler(state) }
    }
}

private func decode<Value: Decodable>(_ type: Value.Type, from json: Data) -> Value? {
    try? JSONDecoder().decode(type, from: json)
}

/// Copies a string returned by the core and releases the original.
private func take(_ string: UnsafeMutablePointer<CChar>?) -> Data? {
    guard let string else { return nil }
    defer { chime_string_free(string) }
    return Data(cString: string)
}

private extension Data {
    init(cString: UnsafePointer<CChar>) {
        self.init(bytes: cString, count: strlen(cString))
    }
}
