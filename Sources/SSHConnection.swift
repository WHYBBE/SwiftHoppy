import Foundation

struct SSHConnection: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var host: String
    var port: Int
    var username: String
    var notes: String
    var kernelVersion: String
    var lastUpdateInfo: String
    var preferredAppPath: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String = "",
        host: String = "",
        port: Int = 22,
        username: String = "",
        notes: String = "",
        kernelVersion: String = "",
        lastUpdateInfo: String = "",
        preferredAppPath: String = "",
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.username = username
        self.notes = notes
        self.kernelVersion = kernelVersion
        self.lastUpdateInfo = lastUpdateInfo
        self.preferredAppPath = preferredAppPath
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var displayName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? host : name
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
