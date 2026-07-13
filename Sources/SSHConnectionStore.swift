import Foundation

enum SSHConnectionStoreError: LocalizedError {
    case invalidImportData
    case loadFailed(String)
    case saveFailed(String)
    case backupFailed(String)

    func message(language: AppLanguage) -> String {
        switch self {
        case .invalidImportData:
            return language.text(
                "无法导入该文件，JSON 格式无效或内容不匹配。",
                "Unable to import: invalid or mismatched JSON."
            )
        case .loadFailed(let detail):
            return language.text(
                "连接数据读取失败：\(detail)",
                "Failed to load connections: \(detail)"
            )
        case .saveFailed(let detail):
            return language.text(
                "连接数据保存失败：\(detail)",
                "Failed to save connections: \(detail)"
            )
        case .backupFailed(let detail):
            return language.text(
                "创建备份失败：\(detail)",
                "Failed to create backup: \(detail)"
            )
        }
    }

    var errorDescription: String? {
        message(language: .chinese)
    }
}

enum ImportMode: String, CaseIterable, Identifiable {
    case merge
    case replace

    var id: String { rawValue }
}

struct ImportPreview: Identifiable {
    let id = UUID()
    let items: [SSHConnection]
    let sourceFileName: String

    var importedCount: Int { items.count }
    var connectionCount: Int { items.filter { !$0.isSeparator }.count }
    var separatorCount: Int { items.filter(\.isSeparator).count }

    func newCount(against existing: [SSHConnection]) -> Int {
        let existingIDs = Set(existing.map(\.id))
        return items.filter { !existingIDs.contains($0.id) }.count
    }

    func duplicateCount(against existing: [SSHConnection]) -> Int {
        let existingIDs = Set(existing.map(\.id))
        return items.filter { existingIDs.contains($0.id) }.count
    }
}

enum ConnectionPersistenceIssue: Equatable {
    case loadFailed(detail: String)
    case saveFailed(detail: String)

    func message(language: AppLanguage) -> String {
        switch self {
        case .loadFailed(let detail):
            return SSHConnectionStoreError.loadFailed(detail).message(language: language)
        case .saveFailed(let detail):
            return SSHConnectionStoreError.saveFailed(detail).message(language: language)
        }
    }
}

@MainActor
final class SSHConnectionStore: ObservableObject {
    @Published var connections: [SSHConnection] = [] {
        didSet {
            guard !isApplyingLoadedState else { return }
            save()
        }
    }

    @Published private(set) var persistenceIssue: ConnectionPersistenceIssue?

    private var isApplyingLoadedState = false
    private let folderURL: URL
    private let fileURL: URL
    private let backupsFolderURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folderURL = appSupport.appendingPathComponent("SwiftHoppy", isDirectory: true)
        try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let backupsFolderURL = folderURL.appendingPathComponent("Backups", isDirectory: true)
        try? FileManager.default.createDirectory(at: backupsFolderURL, withIntermediateDirectories: true)
        self.folderURL = folderURL
        self.fileURL = folderURL.appendingPathComponent("connections.json")
        self.backupsFolderURL = backupsFolderURL

        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601

        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601

        switch load() {
        case .missing:
            // First launch only — never seed after a corrupt/failed load.
            applyLoadedConnections([Self.sampleConnection])
            save()
        case .success(let loaded):
            applyLoadedConnections(loaded)
            normalizeManualOrder()
        case .failed(let detail):
            persistenceIssue = .loadFailed(detail: detail)
        }
    }

    var firstSelectableID: SSHConnection.ID? {
        connections.first(where: { !$0.isSeparator })?.id
    }

    func dismissPersistenceError() {
        persistenceIssue = nil
    }

    func addConnection() -> SSHConnection.ID {
        // Smaller manualOrder sorts first; place new items at the top of the list.
        let nextOrder = (connections.map(\.manualOrder).min() ?? 0) - 1
        let connection = SSHConnection(name: "New Connection", isLocal: false, manualOrder: nextOrder)
        connections.insert(connection, at: 0)
        return connection.id
    }

    func addSeparator() -> SSHConnection.ID {
        let nextOrder = (connections.map(\.manualOrder).min() ?? 0) - 1
        let separator = SSHConnection(
            name: "Divider",
            itemKind: .separator,
            manualOrder: nextOrder
        )
        connections.insert(separator, at: 0)
        return separator.id
    }

    /// Inserts imported SSH hosts at the top. Skips aliases that already exist (by name or host).
    @discardableResult
    func importSSHConfigEntries(_ entries: [SSHConfigHostEntry]) -> (added: Int, skipped: Int) {
        let existingKeys = Set(
            connections.flatMap { connection -> [String] in
                guard !connection.isSeparator else { return [] }
                let name = connection.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let host = connection.host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                return [name, host].filter { !$0.isEmpty }
            }
        )

        var added = 0
        var skipped = 0
        var nextOrder = (connections.map(\.manualOrder).min() ?? 0) - 1
        var batch: [SSHConnection] = []

        for entry in entries {
            let key = entry.alias.lowercased()
            let hostKey = entry.hostName.lowercased()
            if existingKeys.contains(key) || existingKeys.contains(hostKey) {
                skipped += 1
                continue
            }
            batch.append(entry.makeConnection(manualOrder: nextOrder))
            nextOrder -= 1
            added += 1
        }

        if !batch.isEmpty {
            connections = batch + connections
        }
        return (added, skipped)
    }

    func update(_ connection: SSHConnection) {
        guard let index = connections.firstIndex(where: { $0.id == connection.id }) else { return }
        var updated = connection
        updated.updatedAt = .now
        connections[index] = updated
    }

    func delete(at offsets: IndexSet) {
        connections.remove(atOffsets: offsets)
    }

    func delete(id: SSHConnection.ID) {
        connections.removeAll { $0.id == id }
    }

    func exportData() throws -> Data {
        try encoder.encode(connections)
    }

    func previewImport(from data: Data, sourceFileName: String) throws -> ImportPreview {
        do {
            let imported = try decoder.decode([SSHConnection].self, from: data)
            return ImportPreview(items: imported, sourceFileName: sourceFileName)
        } catch {
            throw SSHConnectionStoreError.invalidImportData
        }
    }

    @discardableResult
    func applyImport(_ preview: ImportPreview, mode: ImportMode) throws -> URL? {
        let backupURL = try createBackup(reason: mode == .replace ? "pre-replace" : "pre-merge")
        switch mode {
        case .replace:
            connections = preview.items
        case .merge:
            connections = merge(imported: preview.items, into: connections)
        }
        normalizeManualOrder()
        return backupURL
    }

    /// Replaces all data after writing a backup. Returns the backup URL when created.
    @discardableResult
    func clearAllPreservingBackup() throws -> URL? {
        let backupURL = try createBackup(reason: "pre-clear")
        connections = []
        return backupURL
    }

    func clearAll() {
        connections = []
    }

    /// Writes current connections to Backups/. Returns nil if there is nothing to back up.
    @discardableResult
    func createBackup(reason: String) throws -> URL? {
        guard !connections.isEmpty || FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        try FileManager.default.createDirectory(at: backupsFolderURL, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: .now)
        let safeReason = reason
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: " ", with: "-")
        let backupURL = backupsFolderURL.appendingPathComponent("connections.\(safeReason).\(stamp).json")

        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.copyItem(at: fileURL, to: backupURL)
            } else {
                let data = try encoder.encode(connections)
                try data.write(to: backupURL, options: .atomic)
            }
            pruneOldBackups(keeping: 20)
            return backupURL
        } catch {
            throw SSHConnectionStoreError.backupFailed(error.localizedDescription)
        }
    }

    private func merge(imported: [SSHConnection], into existing: [SSHConnection]) -> [SSHConnection] {
        var result = existing
        let existingIDs = Set(existing.map(\.id))
        var nextOrder = (existing.map(\.manualOrder).max() ?? -1) + 1

        for item in imported where !existingIDs.contains(item.id) {
            var copy = item
            copy.manualOrder = nextOrder
            nextOrder += 1
            result.append(copy)
        }
        return result
    }

    private func pruneOldBackups(keeping limit: Int) {
        let fileManager = FileManager.default
        guard let urls = try? fileManager.contentsOfDirectory(
            at: backupsFolderURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        let backups = urls
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> (URL, Date)? in
                let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                return (url, values?.contentModificationDate ?? .distantPast)
            }
            .sorted { $0.1 > $1.1 }

        for item in backups.dropFirst(limit) {
            try? fileManager.removeItem(at: item.0)
        }
    }

    func moveManually(from source: IndexSet, to destination: Int) {
        var manuallySorted = connections.sorted {
            if $0.manualOrder == $1.manualOrder {
                return $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
            }
            return $0.manualOrder < $1.manualOrder
        }
        manuallySorted.move(fromOffsets: source, toOffset: destination)
        for index in manuallySorted.indices {
            manuallySorted[index].manualOrder = index
        }
        connections = manuallySorted
    }

    private static var sampleConnection: SSHConnection {
        SSHConnection(
            name: "Production",
            host: "192.168.1.10",
            username: "root",
            isLocal: false,
            notesEntries: [
                NoteEntry(content: "示例记录，可直接修改或删除。 / Sample entry — edit or delete.")
            ],
            systemInfoHistory: [
                SystemInfoSnapshot(
                    kernelVersion: "Linux 6.8.0-31-generic",
                    updateInfo: "2026-06-10 apt upgrade"
                )
            ],
            manualOrder: 0
        )
    }

    private func applyLoadedConnections(_ loaded: [SSHConnection]) {
        isApplyingLoadedState = true
        connections = loaded
        isApplyingLoadedState = false
    }

    private func normalizeManualOrder() {
        let normalized = connections
            .sorted {
                if $0.manualOrder == $1.manualOrder {
                    return $0.createdAt < $1.createdAt
                }
                return $0.manualOrder < $1.manualOrder
            }
            .enumerated()
            .map { index, connection in
                var updated = connection
                updated.manualOrder = index
                return updated
            }
        if normalized != connections {
            connections = normalized
        }
    }

    private enum LoadResult {
        case missing
        case success([SSHConnection])
        case failed(String)
    }

    private func load() -> LoadResult {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .missing
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let loaded = try decoder.decode([SSHConnection].self, from: data)
            return .success(loaded)
        } catch {
            let backupPath = preserveCorruptFile()
            var detail = error.localizedDescription
            if let backupPath {
                detail += " | backup: \(backupPath)"
            }
            return .failed(detail)
        }
    }

    private func preserveCorruptFile() -> String? {
        let stamp = Int(Date().timeIntervalSince1970)
        let backupURL = fileURL
            .deletingLastPathComponent()
            .appendingPathComponent("connections.corrupt.\(stamp).json")
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
            let data = try encoder.encode(connections)
            try data.write(to: fileURL, options: .atomic)
            if case .saveFailed = persistenceIssue {
                persistenceIssue = nil
            }
        } catch {
            persistenceIssue = .saveFailed(detail: error.localizedDescription)
        }
    }
}
