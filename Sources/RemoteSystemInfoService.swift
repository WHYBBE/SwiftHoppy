import Foundation

struct RemoteSystemInfo {
    let kernelVersion: String
    let updateInfo: String
    let uptimeInfo: String
    let recordedAt: Date
}

enum RemoteSystemInfoError: LocalizedError {
    case invalidHost
    case sshUnavailable
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidHost:
            return "请先填写有效的主机地址。"
        case .sshUnavailable:
            return "系统未找到 ssh 命令。"
        case .commandFailed(let message):
            return message
        }
    }
}

enum RemoteSystemInfoService {
    static func fetch(for connection: SSHConnection) async throws -> RemoteSystemInfo {
        let host = connection.host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else {
            throw RemoteSystemInfoError.invalidHost
        }

        let sshPath = "/usr/bin/ssh"
        guard FileManager.default.isExecutableFile(atPath: sshPath) else {
            throw RemoteSystemInfoError.sshUnavailable
        }

        let remoteCommand = #"""
        uname -srmo 2>/dev/null
        if command -v apt >/dev/null 2>&1; then
            stat -c '%y' /var/lib/apt/periodic/update-success-stamp 2>/dev/null || stat -c '%y' /var/lib/apt/lists 2>/dev/null | head -n 1
        elif command -v dnf >/dev/null 2>&1; then
            stat -c '%y' /var/cache/dnf 2>/dev/null
        elif command -v yum >/dev/null 2>&1; then
            stat -c '%y' /var/cache/yum 2>/dev/null
        elif command -v zypper >/dev/null 2>&1; then
            stat -c '%y' /var/cache/zypp 2>/dev/null
        elif [ -f /var/log/pacman.log ]; then
            tail -n 1 /var/log/pacman.log 2>/dev/null
        elif command -v pkg >/dev/null 2>&1; then
            stat -f '%Sm' -t '%Y-%m-%d %H:%M:%S %z' /var/db/pkg/local.sqlite 2>/dev/null || stat -f '%Sm' -t '%Y-%m-%d %H:%M:%S %z' /var/db/pkg/repo-FreeBSD.sqlite 2>/dev/null
        elif command -v sw_vers >/dev/null 2>&1; then
            sw_vers 2>/dev/null | tr '\n' ' '
        fi
        if [ -r /proc/uptime ]; then
            awk '{print int($1)}' /proc/uptime 2>/dev/null
        elif uptime -p >/dev/null 2>&1; then
            uptime -p 2>/dev/null
        else
            uptime 2>/dev/null
        fi
        """#

        let process = Process()
        process.executableURL = URL(fileURLWithPath: sshPath)
        process.arguments = sshArguments(for: connection) + [remoteCommand]
        process.environment = try askpassEnvironment(for: connection)

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        process.standardInput = FileHandle(forReadingAtPath: "/dev/null")

        try process.run()
        process.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(decoding: outputData, as: UTF8.self)
        let error = String(decoding: errorData, as: UTF8.self)

        guard process.terminationStatus == 0 else {
            let message = error.trimmingCharacters(in: .whitespacesAndNewlines)
            throw RemoteSystemInfoError.commandFailed(message.isEmpty ? "SSH 连接失败，请检查密钥、known_hosts 或远端可达性。" : message)
        }

        let lines = output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let kernelVersion = lines.first ?? "Unknown"
        let updateInfo = lines.dropFirst().first ?? "未检测到更新信息"
        let uptimeInfo = formatUptime(lines.dropFirst(2).first ?? "")
        return RemoteSystemInfo(kernelVersion: kernelVersion, updateInfo: updateInfo, uptimeInfo: uptimeInfo, recordedAt: .now)
    }

    private static func formatUptime(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        if let seconds = Int(trimmed) {
            return formatDuration(seconds: seconds)
        }

        if let pretty = parsePrettyUptime(trimmed) {
            return pretty
        }

        if let classic = parseClassicUptime(trimmed) {
            return classic
        }

        return ""
    }

    private static func parsePrettyUptime(_ raw: String) -> String? {
        let normalized = raw.lowercased().replacingOccurrences(of: "up ", with: "")
        let parts = normalized
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        var totalMinutes = 0

        for part in parts {
            let tokens = part.split(separator: " ")
            guard let valueToken = tokens.first, let value = Int(valueToken) else { continue }

            if part.contains("week") {
                totalMinutes += value * 7 * 24 * 60
            } else if part.contains("day") {
                totalMinutes += value * 24 * 60
            } else if part.contains("hour") {
                totalMinutes += value * 60
            } else if part.contains("minute") {
                totalMinutes += value
            }
        }

        guard totalMinutes > 0 else { return nil }
        return formatDuration(seconds: totalMinutes * 60)
    }

    private static func parseClassicUptime(_ raw: String) -> String? {
        let lowercased = raw.lowercased()
        guard let upRange = lowercased.range(of: " up ") else { return nil }
        var uptimePart = String(lowercased[upRange.upperBound...])

        if let usersRange = uptimePart.range(of: #",\\s+\d+\s+user"#, options: .regularExpression) {
            uptimePart = String(uptimePart[..<usersRange.lowerBound])
        } else if let loadRange = uptimePart.range(of: ", load average:") {
            uptimePart = String(uptimePart[..<loadRange.lowerBound])
        }

        uptimePart = uptimePart.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !uptimePart.isEmpty else { return nil }

        var totalMinutes = 0
        for part in uptimePart.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }) {
            if let dayMatch = part.range(of: #"^(\d+)\s+day[s]?$"#, options: .regularExpression) {
                let value = Int(part[dayMatch].split(separator: " ").first ?? "") ?? 0
                totalMinutes += value * 24 * 60
                continue
            }

            if let hourMinuteMatch = part.range(of: #"^(\d+):(\d+)$"#, options: .regularExpression) {
                let value = String(part[hourMinuteMatch]).split(separator: ":")
                if value.count == 2 {
                    totalMinutes += (Int(value[0]) ?? 0) * 60
                    totalMinutes += Int(value[1]) ?? 0
                }
                continue
            }

            if let minuteMatch = part.range(of: #"^(\d+)\s+min[s]?$"#, options: .regularExpression) {
                let value = Int(part[minuteMatch].split(separator: " ").first ?? "") ?? 0
                totalMinutes += value
                continue
            }
        }

        guard totalMinutes > 0 else { return nil }
        return formatDuration(seconds: totalMinutes * 60)
    }

    private static func formatDuration(seconds: Int) -> String {
        guard seconds > 0 else { return "" }

        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60

        var parts: [String] = []
        if days > 0 { parts.append("\(days)d") }
        if hours > 0 { parts.append("\(hours)h") }
        if minutes > 0 || parts.isEmpty { parts.append("\(minutes)m") }
        return parts.joined(separator: " ")
    }

    private static func sshArguments(for connection: SSHConnection) -> [String] {
        var arguments = [
            "-o", "PreferredAuthentications=publickey,keyboard-interactive,password",
            "-o", "NumberOfPasswordPrompts=1",
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "ConnectTimeout=8"
        ]

        if connection.port != 22 {
            arguments += ["-p", String(connection.port)]
        }

        arguments.append(connection.destination)
        return arguments
    }

    private static func askpassEnvironment(for connection: SSHConnection) throws -> [String: String] {
        let helperURL = try makeAskpassHelper()
        var environment = ProcessInfo.processInfo.environment
        environment["SSH_ASKPASS"] = helperURL.path
        environment["SSH_ASKPASS_REQUIRE"] = "force"
        environment["SSH_ASKPASS_PROMPT"] = "Enter SSH password for \(connection.destination)"
        environment["LC_ALL"] = "en_US.UTF-8"
        environment["LANG"] = "en_US.UTF-8"
        return environment
    }

    private static func makeAskpassHelper() throws -> URL {
        let helperURL = FileManager.default.temporaryDirectory.appendingPathComponent("swiftgnuinfo-ssh-askpass.sh")
        let script = #"""
        #!/bin/sh
        export LC_ALL=en_US.UTF-8
        export LANG=en_US.UTF-8
        /usr/bin/osascript <<'APPLESCRIPT'
        set promptText to system attribute "SSH_ASKPASS_PROMPT"
        try
            display dialog promptText with title "SwiftGNUInfo" default answer "" with hidden answer buttons {"Cancel", "OK"} default button "OK"
            text returned of result
        on error number -128
            error number 1
        end try
        APPLESCRIPT
        """#
        try script.write(to: helperURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helperURL.path)
        return helperURL
    }
}
