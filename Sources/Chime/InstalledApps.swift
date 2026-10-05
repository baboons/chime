import AppKit

/// An app on this Mac that could be tracked.
struct InstalledApp: Identifiable, Hashable, Sendable {
    let bundleId: String
    let name: String
    let path: String

    var id: String { bundleId }

    /// Nil unless `url` is an app bundle with a bundle identifier.
    init?(url: URL) {
        guard url.pathExtension == "app", let bundleId = Bundle(url: url)?.bundleIdentifier else {
            return nil
        }
        // Finder's name for the app, minus the extension it adds when extensions are shown.
        let displayName = FileManager.default.displayName(atPath: url.path)
        self.bundleId = bundleId
        self.name = displayName.hasSuffix(".app") ? String(displayName.dropLast(4)) : displayName
        self.path = url.path
    }
}

enum AppCatalog {
    /// How far below an applications folder to look, for apps kept in subfolders.
    private static let maxDepth = 2

    private static var folders: [URL] {
        [
            URL(fileURLWithPath: "/Applications"),
            URL.homeDirectory.appending(path: "Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            // Where Safari really lives on current macOS.
            URL(fileURLWithPath: "/System/Cryptexes/App/System/Applications"),
        ]
    }

    /// The apps in the standard applications folders plus `extra`, sorted by name.
    static func installedApps(including extra: [URL]) async -> [InstalledApp] {
        let ownBundleId = Bundle.main.bundleIdentifier
        return await Task.detached {
            var seen = Set<String>()
            return (folders.flatMap { apps(in: $0, depth: maxDepth) } + extra)
                .compactMap(InstalledApp.init(url:))
                .filter { $0.bundleId != ownBundleId && seen.insert($0.bundleId).inserted }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }.value
    }

    private static func apps(in folder: URL, depth: Int) -> [URL] {
        let contents = try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        )
        return (contents ?? []).flatMap { url -> [URL] in
            if url.pathExtension == "app" {
                return [url]
            }
            let isFolder = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            return isFolder && depth > 0 ? apps(in: url, depth: depth - 1) : []
        }
    }
}
