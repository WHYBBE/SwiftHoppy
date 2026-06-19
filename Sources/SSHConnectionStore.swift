import Foundation

enum SSHConnectionStoreError: LocalizedError {
    case invalidImportData

    var errorDescription: String? {
        switch self {
        case .invalidImportData:
            return "无法导入该文件，JSON 格式无效或内容不匹配。"
        }
    }
}

@MainActor
final class SSHConnectionStore: ObservableObject {
    @Published var connections: [SSHConnection] = [] {
        didSet {
            save()
        }
    }

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folderURL = appSupport.appendingPathComponent("SwiftGNUInfo", isDirectory: true)
        try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        self.fileURL = folderURL.appendingPathComponent("connections.json")

        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601

        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601

        load()
        if connections.isEmpty {
            connections = [
                SSHConnection(
                    name: "Production",
                    host: "192.168.1.10",
                    username: "root",
                    notes: "示例记录，可直接修改或删除。",
                    systemInfoHistory: [
                        SystemInfoSnapshot(
                            kernelVersion: "Linux 6.8.0-31-generic",
                            updateInfo: "2026-06-10 apt upgrade"
                        )
                    ]
                )
            ]
        }
    }

    func addConnection() -> SSHConnection.ID {
        let connection = SSHConnection(name: "New Connection")
        connections.insert(connection, at: 0)
        return connection.id
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
            connections = try decoder.decode([SSHConnection].self, from: data)
        } catch {
            throw SSHConnectionStoreError.invalidImportData
        }
    }

    func clearAll() {
        connections = []
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            connections = try decoder.decode([SSHConnection].self, from: data)
        } catch {
            connections = []
        }
    }

    private func save() {
        do {
            let data = try encoder.encode(connections)
            try data.write(to: fileURL, options: .atomic)
        } catch {
        }
    }
}
