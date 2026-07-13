import Foundation

enum PreferencesPersistenceIssue: Equatable {
    case loadFailed(detail: String)
    case saveFailed(detail: String)

    func message(language: AppLanguage) -> String {
        switch self {
        case .loadFailed(let detail):
            return language.text(
                "偏好设置读取失败：\(detail)",
                "Failed to load preferences: \(detail)"
            )
        case .saveFailed(let detail):
            return language.text(
                "偏好设置保存失败：\(detail)",
                "Failed to save preferences: \(detail)"
            )
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

    func text(_ chinese: String, _ english: String) -> String {
        switch self {
        case .english:
            return english
        case .chinese:
            return chinese
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

/// Maps to OpenSSH `StrictHostKeyChecking`.
enum SSHHostKeyPolicy: String, Codable, CaseIterable, Identifiable {
    /// Reject unknown hosts (must already be in known_hosts).
    case strict
    /// Trust unknown hosts once and record them (previous app default).
    case acceptNew
    /// Do not verify host keys (lab only).
    case off

    var id: String { rawValue }

    var sshOptionValue: String {
        switch self {
        case .strict:
            return "yes"
        case .acceptNew:
            return "accept-new"
        case .off:
            return "no"
        }
    }

    func title(language: AppLanguage) -> String {
        switch self {
        case .strict:
            return language.text("严格（仅 known_hosts）", "Strict (known_hosts only)")
        case .acceptNew:
            return language.text("接受新主机", "Accept new hosts")
        case .off:
            return language.text("关闭校验（不安全）", "Off (insecure)")
        }
    }

    func detail(language: AppLanguage) -> String {
        switch self {
        case .strict:
            return language.text(
                "未知主机拒绝连接；指纹变化时拒绝。最安全。",
                "Reject unknown hosts; reject changed fingerprints. Most secure."
            )
        case .acceptNew:
            return language.text(
                "首次连接自动信任并写入 known_hosts；指纹变化时仍会拒绝。",
                "Auto-trust first connection into known_hosts; still rejects changed fingerprints."
            )
        case .off:
            return language.text(
                "不校验主机密钥，仅建议在隔离实验环境使用。",
                "Skip host-key checks. Use only in isolated lab environments."
            )
        }
    }
}

/// How password / interactive auth is handled for in-app SSH fetches.
enum SSHPasswordAuthPolicy: String, Codable, CaseIterable, Identifiable {
    /// Prefer keys; fall back to graphical askpass password prompt.
    case allowPasswordPrompt
    /// Public key / agent only; never run askpass.
    case publicKeyOnly

    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        switch self {
        case .allowPasswordPrompt:
            return language.text("允许密码提示", "Allow password prompt")
        case .publicKeyOnly:
            return language.text("仅公钥 / Agent", "Public key / agent only")
        }
    }

    func detail(language: AppLanguage) -> String {
        switch self {
        case .allowPasswordPrompt:
            return language.text(
                "无密钥时用图形对话框询问密码（经临时 askpass）。",
                "If no key works, show a graphical password dialog via temporary askpass."
            )
        case .publicKeyOnly:
            return language.text(
                "只用密钥与 ssh-agent，不弹出密码框，也不使用 askpass。",
                "Use keys and ssh-agent only; no password dialog or askpass."
            )
        }
    }
}

struct ResolvedSSHSecurity: Equatable {
    var hostKeyPolicy: SSHHostKeyPolicy
    var passwordAuthPolicy: SSHPasswordAuthPolicy
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
    var defaultHostKeyPolicy: SSHHostKeyPolicy
    var defaultPasswordAuthPolicy: SSHPasswordAuthPolicy

    enum CodingKeys: String, CodingKey {
        case apps
        case lastScannedAt
        case language
        case theme
        case connectionSortMode
        case hidesSensitiveInfo
        case defaultHostKeyPolicy
        case defaultPasswordAuthPolicy
    }

    init(
        apps: [InstalledTerminalApp] = [],
        lastScannedAt: Date? = nil,
        language: AppLanguage = .chinese,
        theme: AppTheme = .system,
        connectionSortMode: ConnectionSortMode = .manual,
        hidesSensitiveInfo: Bool = false,
        defaultHostKeyPolicy: SSHHostKeyPolicy = .acceptNew,
        defaultPasswordAuthPolicy: SSHPasswordAuthPolicy = .allowPasswordPrompt
    ) {
        self.apps = apps
        self.lastScannedAt = lastScannedAt
        self.language = language
        self.theme = theme
        self.connectionSortMode = connectionSortMode
        self.hidesSensitiveInfo = hidesSensitiveInfo
        self.defaultHostKeyPolicy = defaultHostKeyPolicy
        self.defaultPasswordAuthPolicy = defaultPasswordAuthPolicy
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        apps = try container.decodeIfPresent([InstalledTerminalApp].self, forKey: .apps) ?? []
        lastScannedAt = try container.decodeIfPresent(Date.self, forKey: .lastScannedAt)
        language = try container.decodeIfPresent(AppLanguage.self, forKey: .language) ?? .chinese
        theme = try container.decodeIfPresent(AppTheme.self, forKey: .theme) ?? .system
        connectionSortMode = try container.decodeIfPresent(ConnectionSortMode.self, forKey: .connectionSortMode) ?? .manual
        hidesSensitiveInfo = try container.decodeIfPresent(Bool.self, forKey: .hidesSensitiveInfo) ?? false
        defaultHostKeyPolicy = try container.decodeIfPresent(SSHHostKeyPolicy.self, forKey: .defaultHostKeyPolicy) ?? .acceptNew
        defaultPasswordAuthPolicy = try container.decodeIfPresent(SSHPasswordAuthPolicy.self, forKey: .defaultPasswordAuthPolicy) ?? .allowPasswordPrompt
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
    @Published var defaultHostKeyPolicy: SSHHostKeyPolicy = .acceptNew {
        didSet {
            guard !isApplyingLoadedState else { return }
            save()
        }
    }
    @Published var defaultPasswordAuthPolicy: SSHPasswordAuthPolicy = .allowPasswordPrompt {
        didSet {
            guard !isApplyingLoadedState else { return }
            save()
        }
    }
    @Published private(set) var persistenceIssue: PreferencesPersistenceIssue?

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
        persistenceIssue = nil
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
        language.text(chinese, english)
    }

    func setConnectionSortMode(_ mode: ConnectionSortMode) {
        connectionSortMode = mode
    }

    func setHidesSensitiveInfo(_ hidesSensitiveInfo: Bool) {
        self.hidesSensitiveInfo = hidesSensitiveInfo
    }

    func setDefaultHostKeyPolicy(_ policy: SSHHostKeyPolicy) {
        defaultHostKeyPolicy = policy
    }

    func setDefaultPasswordAuthPolicy(_ policy: SSHPasswordAuthPolicy) {
        defaultPasswordAuthPolicy = policy
    }

    func resolvedSecurity(for connection: SSHConnection) -> ResolvedSSHSecurity {
        ResolvedSSHSecurity(
            hostKeyPolicy: connection.hostKeyPolicy ?? defaultHostKeyPolicy,
            passwordAuthPolicy: connection.passwordAuthPolicy ?? defaultPasswordAuthPolicy
        )
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
            defaultHostKeyPolicy = cache.defaultHostKeyPolicy
            defaultPasswordAuthPolicy = cache.defaultPasswordAuthPolicy
            isApplyingLoadedState = false
        } catch {
            // Keep in-memory defaults; do not overwrite the on-disk file.
            let backupPath = preserveCorruptFile()
            var detail = error.localizedDescription
            if let backupPath {
                detail += " | backup: \(backupPath)"
            }
            persistenceIssue = .loadFailed(detail: detail)
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
                hidesSensitiveInfo: hidesSensitiveInfo,
                defaultHostKeyPolicy: defaultHostKeyPolicy,
                defaultPasswordAuthPolicy: defaultPasswordAuthPolicy
            )
            let data = try encoder.encode(cache)
            try data.write(to: fileURL, options: .atomic)
            if case .saveFailed = persistenceIssue {
                persistenceIssue = nil
            }
        } catch {
            persistenceIssue = .saveFailed(detail: error.localizedDescription)
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
