import Foundation

struct InstalledTerminalApp: Identifiable, Hashable, Codable {
    let path: String
    let name: String

    var id: String { path }
}

struct TerminalAppCache: Codable {
    var apps: [InstalledTerminalApp]
    var lastScannedAt: Date?
}

@MainActor
final class AppPreferencesStore: ObservableObject {
    @Published private(set) var installedApps: [InstalledTerminalApp] = []
    @Published private(set) var lastScannedAt: Date?

    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folderURL = appSupport.appendingPathComponent("SwiftGNUInfo", isDirectory: true)
        try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        self.fileURL = folderURL.appendingPathComponent("terminal-apps.json")
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder.dateDecodingStrategy = .iso8601
        load()
    }

    func refreshInstalledApps() {
        installedApps = Self.discoverInstalledApps()
        lastScannedAt = .now
        save()
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let cache = try decoder.decode(TerminalAppCache.self, from: data)
            installedApps = cache.apps
            lastScannedAt = cache.lastScannedAt
        } catch {
            installedApps = []
            lastScannedAt = nil
        }
    }

    private func save() {
        do {
            let cache = TerminalAppCache(apps: installedApps, lastScannedAt: lastScannedAt)
            let data = try encoder.encode(cache)
            try data.write(to: fileURL, options: .atomic)
        } catch {
        }
    }

    private static func discoverInstalledApps() -> [InstalledTerminalApp] {
        let knownNames = [
            "Terminal", "iTerm", "iTerm2", "Warp", "Termius", "Kitty",
            "Alacritty", "Hyper", "SecureCRT", "Ghostty", "Tabby", "WezTerm"
        ]
        let searchDirectories = [
            "/Applications",
            "/System/Applications",
            NSHomeDirectory() + "/Applications"
        ]
        let fileManager = FileManager.default
        var appsByPath: [String: InstalledTerminalApp] = [:]

        for directory in searchDirectories {
            guard let enumerator = fileManager.enumerator(at: URL(fileURLWithPath: directory), includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
                continue
            }

            for case let url as URL in enumerator {
                guard url.pathExtension == "app" else { continue }
                let appName = url.deletingPathExtension().lastPathComponent
                let lowercasedName = appName.lowercased()
                let isMatch = knownNames.contains(where: { lowercasedName.contains($0.lowercased()) }) || lowercasedName.contains("terminal")
                guard isMatch else { continue }
                appsByPath[url.path] = InstalledTerminalApp(path: url.path, name: appName)
                enumerator.skipDescendants()
            }
        }

        return appsByPath.values.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
}
