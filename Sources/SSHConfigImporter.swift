import Foundation

enum SSHConfigImporterError: LocalizedError {
    case fileNotFound(String)
    case unreadable(String)
    case noHosts

    func message(language: AppLanguage) -> String {
        switch self {
        case .fileNotFound(let path):
            return language.text("找不到配置文件：\(path)", "Config file not found: \(path)")
        case .unreadable(let detail):
            return language.text("无法读取 SSH 配置：\(detail)", "Unable to read SSH config: \(detail)")
        case .noHosts:
            return language.text(
                "未找到可导入的 Host（通配符 * / ? 会跳过）。",
                "No importable Host entries found (wildcard * / ? patterns are skipped)."
            )
        }
    }

    var errorDescription: String? {
        message(language: .chinese)
    }
}

/// One concrete Host block from OpenSSH config (no wildcards).
struct SSHConfigHostEntry: Identifiable, Hashable {
    var id: String { alias }
    var alias: String
    var hostName: String
    var user: String
    var port: Int
    var identityFile: String
    var proxyJump: String
    var extraOptions: [String]

    func makeConnection(manualOrder: Int) -> SSHConnection {
        SSHConnection(
            name: alias,
            host: hostName.isEmpty ? alias : hostName,
            port: port,
            username: user,
            isLocal: false,
            identityFile: identityFile,
            proxyJump: proxyJump,
            extraSSHOptions: extraOptions.joined(separator: "\n"),
            manualOrder: manualOrder
        )
    }
}

enum SSHConfigImporter {
    static var defaultConfigURL: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".ssh/config")
    }

    static func loadEntries(from url: URL = defaultConfigURL) throws -> [SSHConfigHostEntry] {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw SSHConfigImporterError.fileNotFound(url.path)
        }
        let text: String
        do {
            text = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw SSHConfigImporterError.unreadable(error.localizedDescription)
        }
        let entries = parse(text)
        if entries.isEmpty {
            throw SSHConfigImporterError.noHosts
        }
        return entries
    }

    static func parse(_ text: String) -> [SSHConfigHostEntry] {
        var results: [SSHConfigHostEntry] = []
        var currentAliases: [String] = []
        var hostName = ""
        var user = ""
        var port = 22
        var identityFile = ""
        var proxyJump = ""
        var extras: [String] = []

        func flush() {
            guard !currentAliases.isEmpty else { return }
            for alias in currentAliases {
                let concrete = !alias.contains("*") && !alias.contains("?")
                guard concrete else { continue }
                results.append(
                    SSHConfigHostEntry(
                        alias: alias,
                        hostName: hostName.isEmpty ? alias : hostName,
                        user: user,
                        port: port,
                        identityFile: identityFile,
                        proxyJump: proxyJump,
                        extraOptions: extras
                    )
                )
            }
            currentAliases = []
            hostName = ""
            user = ""
            port = 22
            identityFile = ""
            proxyJump = ""
            extras = []
        }

        for rawLine in text.components(separatedBy: .newlines) {
            var line = rawLine
            if let hash = line.firstIndex(of: "#") {
                line = String(line[..<hash])
            }
            line = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            let parts = line.split(whereSeparator: { $0.isWhitespace })
            guard let first = parts.first else { continue }
            let keyword = first.lowercased()
            let value = parts.dropFirst().joined(separator: " ")

            if keyword == "host" {
                flush()
                currentAliases = parts.dropFirst().map(String.init).filter { !$0.isEmpty }
                continue
            }

            guard !currentAliases.isEmpty else { continue }

            switch keyword {
            case "hostname":
                hostName = value
            case "user":
                user = value
            case "port":
                if let p = Int(value), (1...65_535).contains(p) {
                    port = p
                }
            case "identityfile":
                // Keep the last IdentityFile (common pattern).
                identityFile = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            case "proxyjump":
                proxyJump = value
            case "include":
                break
            default:
                // Capture other options (ForwardAgent, LocalForward, etc.) as Key=value lines.
                let key = String(first)
                let body = value.isEmpty ? key : "\(key)=\(value)"
                if !extras.contains(body) {
                    extras.append(body)
                }
            }
        }
        flush()

        // Prefer first occurrence of each alias (like ssh, first match wins for Host order —
        // but we emit one entry per concrete alias from each block).
        var seen = Set<String>()
        return results.filter { entry in
            if seen.contains(entry.alias) { return false }
            seen.insert(entry.alias)
            return true
        }
    }
}
