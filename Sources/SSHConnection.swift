import Foundation

enum SSHSidebarItemKind: String, Codable {
    case connection
    case separator
}

struct SystemInfoSnapshot: Identifiable, Codable, Hashable {
    var id: UUID
    var kernelVersion: String
    var updateInfo: String
    var recordedAt: Date

    init(
        id: UUID = UUID(),
        kernelVersion: String = "",
        updateInfo: String = "",
        recordedAt: Date = .now
    ) {
        self.id = id
        self.kernelVersion = kernelVersion
        self.updateInfo = updateInfo
        self.recordedAt = recordedAt
    }
}

struct SSHConnection: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var host: String
    var port: Int
    var username: String
    var notes: String
    var systemInfoHistory: [SystemInfoSnapshot]
    var preferredAppPath: String
    var itemKind: SSHSidebarItemKind
    var manualOrder: Int
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case host
        case port
        case username
        case notes
        case systemInfoHistory
        case preferredAppPath
        case itemKind
        case manualOrder
        case createdAt
        case updatedAt
        case kernelVersion
        case lastUpdateInfo
    }

    init(
        id: UUID = UUID(),
        name: String = "",
        host: String = "",
        port: Int = 22,
        username: String = "",
        notes: String = "",
        systemInfoHistory: [SystemInfoSnapshot] = [],
        preferredAppPath: String = "",
        itemKind: SSHSidebarItemKind = .connection,
        manualOrder: Int = 0,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.username = username
        self.notes = notes
        self.systemInfoHistory = systemInfoHistory
        self.preferredAppPath = preferredAppPath
        self.itemKind = itemKind
        self.manualOrder = manualOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        host = try container.decode(String.self, forKey: .host)
        port = try container.decode(Int.self, forKey: .port)
        username = try container.decode(String.self, forKey: .username)
        notes = try container.decode(String.self, forKey: .notes)
        preferredAppPath = try container.decode(String.self, forKey: .preferredAppPath)
        itemKind = try container.decodeIfPresent(SSHSidebarItemKind.self, forKey: .itemKind) ?? .connection
        manualOrder = try container.decodeIfPresent(Int.self, forKey: .manualOrder) ?? 0
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)

        if let history = try container.decodeIfPresent([SystemInfoSnapshot].self, forKey: .systemInfoHistory) {
            systemInfoHistory = history
        } else {
            let legacyKernelVersion = try container.decodeIfPresent(String.self, forKey: .kernelVersion) ?? ""
            let legacyLastUpdateInfo = try container.decodeIfPresent(String.self, forKey: .lastUpdateInfo) ?? ""
            if legacyKernelVersion.isEmpty && legacyLastUpdateInfo.isEmpty {
                systemInfoHistory = []
            } else {
                systemInfoHistory = [
                    SystemInfoSnapshot(
                        kernelVersion: legacyKernelVersion,
                        updateInfo: legacyLastUpdateInfo,
                        recordedAt: updatedAt
                    )
                ]
            }
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(host, forKey: .host)
        try container.encode(port, forKey: .port)
        try container.encode(username, forKey: .username)
        try container.encode(notes, forKey: .notes)
        try container.encode(systemInfoHistory, forKey: .systemInfoHistory)
        try container.encode(preferredAppPath, forKey: .preferredAppPath)
        try container.encode(itemKind, forKey: .itemKind)
        try container.encode(manualOrder, forKey: .manualOrder)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }

    var latestSystemInfo: SystemInfoSnapshot? {
        systemInfoHistory.sorted { $0.recordedAt > $1.recordedAt }.first
    }

    var displayName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? host : name
    }

    var isSeparator: Bool {
        itemKind == .separator
    }

    var sshURL: URL? {
        var components = URLComponents()
        components.scheme = "ssh"
        components.host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        if !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            components.user = username.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if port != 22 {
            components.port = port
        }
        return components.url
    }

    var destination: String {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedUsername.isEmpty ? trimmedHost : "\(trimmedUsername)@\(trimmedHost)"
    }
}
