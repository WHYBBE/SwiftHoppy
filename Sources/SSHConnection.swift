import Foundation

enum SSHSidebarItemKind: String, Codable {
    case connection
    case separator
}

enum NoteSortMode: String, Codable {
    case manual
    case time
}

struct NoteEntry: Identifiable, Codable, Hashable {
    var id: UUID
    var content: String
    var createdAt: Date
    var manualOrder: Int

    init(id: UUID = UUID(), content: String = "", createdAt: Date = .now, manualOrder: Int = 0) {
        self.id = id
        self.content = content
        self.createdAt = createdAt
        self.manualOrder = manualOrder
    }

    enum CodingKeys: String, CodingKey {
        case id
        case content
        case createdAt
        case manualOrder
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        content = try container.decodeIfPresent(String.self, forKey: .content) ?? ""
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        manualOrder = try container.decodeIfPresent(Int.self, forKey: .manualOrder) ?? 0
    }
}

struct SystemInfoSnapshot: Identifiable, Codable, Hashable {
    var id: UUID
    var kernelVersion: String
    var updateInfo: String
    var uptimeInfo: String
    var updateRecordedAt: Date?
    var isManualEntry: Bool
    var isEdited: Bool
    var recordedAt: Date

    init(
        id: UUID = UUID(),
        kernelVersion: String = "",
        updateInfo: String = "",
        uptimeInfo: String = "",
        updateRecordedAt: Date? = nil,
        isManualEntry: Bool = false,
        isEdited: Bool = false,
        recordedAt: Date = .now
    ) {
        self.id = id
        self.kernelVersion = kernelVersion
        self.updateInfo = updateInfo
        self.uptimeInfo = uptimeInfo
        self.updateRecordedAt = updateRecordedAt
        self.isManualEntry = isManualEntry
        self.isEdited = isEdited
        self.recordedAt = recordedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case kernelVersion
        case updateInfo
        case uptimeInfo
        case updateRecordedAt
        case isManualEntry
        case isEdited
        case recordedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kernelVersion = try container.decodeIfPresent(String.self, forKey: .kernelVersion) ?? ""
        updateInfo = try container.decodeIfPresent(String.self, forKey: .updateInfo) ?? ""
        uptimeInfo = try container.decodeIfPresent(String.self, forKey: .uptimeInfo) ?? ""
        updateRecordedAt = try container.decodeIfPresent(Date.self, forKey: .updateRecordedAt)
        isManualEntry = try container.decodeIfPresent(Bool.self, forKey: .isManualEntry) ?? false
        isEdited = try container.decodeIfPresent(Bool.self, forKey: .isEdited) ?? false
        recordedAt = try container.decodeIfPresent(Date.self, forKey: .recordedAt) ?? .now
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kernelVersion, forKey: .kernelVersion)
        try container.encode(updateInfo, forKey: .updateInfo)
        try container.encode(uptimeInfo, forKey: .uptimeInfo)
        try container.encodeIfPresent(updateRecordedAt, forKey: .updateRecordedAt)
        try container.encode(isManualEntry, forKey: .isManualEntry)
        try container.encode(isEdited, forKey: .isEdited)
        try container.encode(recordedAt, forKey: .recordedAt)
    }
}

struct HardwareInfo: Identifiable, Codable, Hashable {
    var id: UUID
    var osName: String
    var architecture: String
    var cpuModel: String
    var cpuCores: String
    var memoryTotal: String
    var recordedAt: Date

    init(
        id: UUID = UUID(),
        osName: String = "",
        architecture: String = "",
        cpuModel: String = "",
        cpuCores: String = "",
        memoryTotal: String = "",
        recordedAt: Date = .now
    ) {
        self.id = id
        self.osName = osName
        self.architecture = architecture
        self.cpuModel = cpuModel
        self.cpuCores = cpuCores
        self.memoryTotal = memoryTotal
        self.recordedAt = recordedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case osName
        case architecture
        case cpuModel
        case cpuCores
        case memoryTotal
        case recordedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        osName = try container.decodeIfPresent(String.self, forKey: .osName) ?? ""
        architecture = try container.decodeIfPresent(String.self, forKey: .architecture) ?? ""
        cpuModel = try container.decodeIfPresent(String.self, forKey: .cpuModel) ?? ""
        cpuCores = try container.decodeIfPresent(String.self, forKey: .cpuCores) ?? ""
        memoryTotal = try container.decodeIfPresent(String.self, forKey: .memoryTotal) ?? ""
        recordedAt = try container.decodeIfPresent(Date.self, forKey: .recordedAt) ?? .now
    }

    var hasVisibleContent: Bool {
        [osName, architecture, cpuModel, cpuCores, memoryTotal].contains {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}

struct SSHConnection: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var host: String
    var port: Int
    var username: String
    var isLocal: Bool
    var noteSortMode: NoteSortMode
    var notesEntries: [NoteEntry]
    var systemInfoHistory: [SystemInfoSnapshot]
    var hardwareInfo: HardwareInfo?
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
        case isLocal
        case noteSortMode
        case notesEntries
        case systemInfoHistory
        case hardwareInfo
        case preferredAppPath
        case itemKind
        case manualOrder
        case createdAt
        case updatedAt
    }

    init(
        id: UUID = UUID(),
        name: String = "",
        host: String = "",
        port: Int = 22,
        username: String = "",
        isLocal: Bool = false,
        noteSortMode: NoteSortMode = .time,
        notesEntries: [NoteEntry] = [],
        systemInfoHistory: [SystemInfoSnapshot] = [],
        hardwareInfo: HardwareInfo? = nil,
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
        self.isLocal = isLocal
        self.noteSortMode = noteSortMode
        self.notesEntries = notesEntries
        self.systemInfoHistory = systemInfoHistory
        self.hardwareInfo = hardwareInfo
        self.preferredAppPath = preferredAppPath
        self.itemKind = itemKind
        self.manualOrder = manualOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        host = try container.decodeIfPresent(String.self, forKey: .host) ?? ""
        port = try container.decodeIfPresent(Int.self, forKey: .port) ?? 22
        username = try container.decodeIfPresent(String.self, forKey: .username) ?? ""
        isLocal = try container.decodeIfPresent(Bool.self, forKey: .isLocal) ?? false
        noteSortMode = try container.decodeIfPresent(NoteSortMode.self, forKey: .noteSortMode) ?? .time
        notesEntries = try container.decodeIfPresent([NoteEntry].self, forKey: .notesEntries) ?? []
        preferredAppPath = try container.decodeIfPresent(String.self, forKey: .preferredAppPath) ?? ""
        itemKind = try container.decodeIfPresent(SSHSidebarItemKind.self, forKey: .itemKind) ?? .connection
        manualOrder = try container.decodeIfPresent(Int.self, forKey: .manualOrder) ?? 0
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        systemInfoHistory = try container.decodeIfPresent([SystemInfoSnapshot].self, forKey: .systemInfoHistory) ?? []
        hardwareInfo = try container.decodeIfPresent(HardwareInfo.self, forKey: .hardwareInfo)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(host, forKey: .host)
        try container.encode(port, forKey: .port)
        try container.encode(username, forKey: .username)
        try container.encode(isLocal, forKey: .isLocal)
        try container.encode(noteSortMode, forKey: .noteSortMode)
        try container.encode(notesEntries, forKey: .notesEntries)
        try container.encode(systemInfoHistory, forKey: .systemInfoHistory)
        try container.encodeIfPresent(hardwareInfo, forKey: .hardwareInfo)
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
