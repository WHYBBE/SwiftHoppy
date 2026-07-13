import Foundation

enum SSHConnectionStoreError: LocalizedError {
    case invalidImportData
    case loadFailed(String)
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidImportData:
            return "无法导入该文件，JSON 格式无效或内容不匹配。 / Unable to import: invalid or mismatched JSON."
        case .loadFailed(let detail):
            return "连接数据读取失败 / Failed to load connections: \(detail)"
        case .saveFailed(let detail):
            return "连接数据保存失败 / Failed to save connections: \(detail)"
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

    @Published private(set) var persistenceErrorMessage: String?

    private var isApplyingLoadedState = false
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folderURL = appSupport.appendingPathComponent("SwiftHoppy", isDirectory: true)
        try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        self.fileURL = folderURL.appendingPathComponent("connections.json")

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
        case .failed(let message):
            persistenceErrorMessage = message
        }
    }

    func dismissPersistenceError() {
        persistenceErrorMessage = nil
    }

    var firstSelectableID: SSHConnection.ID? {
        connections.first(where: { !$0.isSeparator })?.id
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

    func importData(from data: Data) throws {
        do {
            let imported = try decoder.decode([SSHConnection].self, from: data)
            connections = imported
            normalizeManualOrder()
        } catch {
            throw SSHConnectionStoreError.invalidImportData
        }
    }

    func clearAll() {
        connections = []
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
                NoteEntry(content: "示例记录，可直接修改或删除。")
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
            return .failed(SSHConnectionStoreError.loadFailed(detail).errorDescription ?? detail)
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
            if persistenceErrorMessage?.contains("保存失败") == true
                || persistenceErrorMessage?.contains("Failed to save") == true {
                persistenceErrorMessage = nil
            }
        } catch {
            persistenceErrorMessage = SSHConnectionStoreError.saveFailed(error.localizedDescription).errorDescription
        }
    }
}
