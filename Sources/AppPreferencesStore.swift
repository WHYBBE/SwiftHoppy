import Foundation

enum AppPreferencesStoreError: LocalizedError {
    case loadFailed(String)
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .loadFailed(let detail):
            return "偏好设置读取失败 / Failed to load preferences: \(detail)"
        case .saveFailed(let detail):
            return "偏好设置保存失败 / Failed to save preferences: \(detail)"
        }
    }
}

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

enum ConnectionSortMode: String, Codable, CaseIterable, Identifiable {
    case manual
    case name
    case ip

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
    var connectionSortMode: ConnectionSortMode
    var hidesSensitiveInfo: Bool

    enum CodingKeys: String, CodingKey {
        case apps
        case lastScannedAt
        case language
        case theme
        case connectionSortMode
        case hidesSensitiveInfo
    }

    init(
        apps: [InstalledTerminalApp] = [],
        lastScannedAt: Date? = nil,
        language: AppLanguage = .chinese,
        theme: AppTheme = .system,
        connectionSortMode: ConnectionSortMode = .manual,
        hidesSensitiveInfo: Bool = false
    ) {
        self.apps = apps
        self.lastScannedAt = lastScannedAt
        self.language = language
        self.theme = theme
        self.connectionSortMode = connectionSortMode
        self.hidesSensitiveInfo = hidesSensitiveInfo
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        apps = try container.decodeIfPresent([InstalledTerminalApp].self, forKey: .apps) ?? []
        lastScannedAt = try container.decodeIfPresent(Date.self, forKey: .lastScannedAt)
        language = try container.decodeIfPresent(AppLanguage.self, forKey: .language) ?? .chinese
        theme = try container.decodeIfPresent(AppTheme.self, forKey: .theme) ?? .system
        connectionSortMode = try container.decodeIfPresent(ConnectionSortMode.self, forKey: .connectionSortMode) ?? .manual
        hidesSensitiveInfo = try container.decodeIfPresent(Bool.self, forKey: .hidesSensitiveInfo) ?? false
    }
}

@MainActor
final class AppPreferencesStore: ObservableObject {
    @Published private(set) var installedApps: [InstalledTerminalApp] = []
    @Published private(set) var lastScannedAt: Date?
    @Published var language: AppLanguage = .chinese {
        didSet {
            guard !isApplyingLoadedState else { return }
            save()
        }
    }
    @Published var theme: AppTheme = .system {
        didSet {
            guard !isApplyingLoadedState else { return }
            save()
        }
    }
    @Published var connectionSortMode: ConnectionSortMode = .manual {
        didSet {
            guard !isApplyingLoadedState else { return }
            save()
        }
    }
    @Published var hidesSensitiveInfo = false {
        didSet {
            guard !isApplyingLoadedState else { return }
            save()
        }
    }
    @Published private(set) var persistenceErrorMessage: String?

    private var isApplyingLoadedState = false
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folderURL = appSupport.appendingPathComponent("SwiftHoppy", isDirectory: true)
        try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        self.fileURL = folderURL.appendingPathComponent("terminal-apps.json")
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder.dateDecodingStrategy = .iso8601
        load()
    }

    func dismissPersistenceError() {
        persistenceErrorMessage = nil
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

    func setConnectionSortMode(_ mode: ConnectionSortMode) {
        connectionSortMode = mode
    }

    func setHidesSensitiveInfo(_ hidesSensitiveInfo: Bool) {
        self.hidesSensitiveInfo = hidesSensitiveInfo
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }

        do {
            let data = try Data(contentsOf: fileURL)
            let cache = try decoder.decode(TerminalAppCache.self, from: data)
            isApplyingLoadedState = true
            installedApps = cache.apps
            lastScannedAt = cache.lastScannedAt
            language = cache.language
            theme = cache.theme
            connectionSortMode = cache.connectionSortMode
            hidesSensitiveInfo = cache.hidesSensitiveInfo
            isApplyingLoadedState = false
        } catch {
            // Keep in-memory defaults; do not overwrite the on-disk file.
            let backupPath = preserveCorruptFile()
            var detail = error.localizedDescription
            if let backupPath {
                detail += " | backup: \(backupPath)"
            }
            persistenceErrorMessage = AppPreferencesStoreError.loadFailed(detail).errorDescription
        }
    }

    private func preserveCorruptFile() -> String? {
        let stamp = Int(Date().timeIntervalSince1970)
        let backupURL = fileURL
            .deletingLastPathComponent()
            .appendingPathComponent("terminal-apps.corrupt.\(stamp).json")
        do {
            if FileManager.default.fileExists(atPath: backupURL.path) {
                try FileManager.default.removeItem(at: backupURL)
            }
            try FileManager.default.copyItem(at: fileURL, to: backupURL)
            return backupURL.path
        } catch {
            return nil
        }
    }

    private func save() {
        do {
            let cache = TerminalAppCache(
                apps: installedApps,
                lastScannedAt: lastScannedAt,
                language: language,
                theme: theme,
                connectionSortMode: connectionSortMode,
                hidesSensitiveInfo: hidesSensitiveInfo
            )
            let data = try encoder.encode(cache)
            try data.write(to: fileURL, options: .atomic)
            if persistenceErrorMessage?.contains("保存失败") == true
                || persistenceErrorMessage?.contains("Failed to save") == true {
                persistenceErrorMessage = nil
            }
        } catch {
            persistenceErrorMessage = AppPreferencesStoreError.saveFailed(error.localizedDescription).errorDescription
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
