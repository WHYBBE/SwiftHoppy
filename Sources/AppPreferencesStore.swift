import Foundation

enum AppLanguage: String, Codable, CaseIterable, Identifiable {
    case english
    case chinese

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english:
            return "English"
        case .chinese:
            return "中文"
        }
    }
}

enum AppTheme: String, Codable, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }
}

struct InstalledTerminalApp: Identifiable, Hashable, Codable {
    let path: String
    let name: String

    var id: String { path }
}

struct TerminalAppCache: Codable {
    var apps: [InstalledTerminalApp]
    var lastScannedAt: Date?
    var language: AppLanguage
    var theme: AppTheme
}

@MainActor
final class AppPreferencesStore: ObservableObject {
    @Published private(set) var installedApps: [InstalledTerminalApp] = []
    @Published private(set) var lastScannedAt: Date?
    @Published var language: AppLanguage = .chinese {
        didSet { save() }
    }
    @Published var theme: AppTheme = .system {
        didSet { save() }
    }

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

    func setLanguage(_ language: AppLanguage) {
        self.language = language
    }

    func setTheme(_ theme: AppTheme) {
        self.theme = theme
    }

    func text(_ chinese: String, _ english: String) -> String {
        switch language {
        case .english:
            return english
        case .chinese:
            return chinese
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let cache = try decoder.decode(TerminalAppCache.self, from: data)
            installedApps = cache.apps
            lastScannedAt = cache.lastScannedAt
            language = cache.language
            theme = cache.theme
        } catch {
            installedApps = []
            lastScannedAt = nil
            language = .chinese
            theme = .system
        }
    }

    private func save() {
        do {
            let cache = TerminalAppCache(
                apps: installedApps,
                lastScannedAt: lastScannedAt,
                language: language,
                theme: theme
            )
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
