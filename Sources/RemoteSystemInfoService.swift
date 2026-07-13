import Foundation

struct RemoteSystemInfo {
    let kernelVersion: String
    let updateInfo: String
    let uptimeInfo: String
    let updateRecordedAt: Date?
    let recordedAt: Date
}

enum RemoteSystemInfoError: LocalizedError {
    case invalidHost
    case sshUnavailable
    case connectionFailed
    case localCommandFailed
    case cancelled
    case commandFailed(String)

    func message(language: AppLanguage) -> String {
        switch self {
        case .invalidHost:
            return language.text("请先填写有效的主机地址。", "Enter a valid host address first.")
        case .sshUnavailable:
            return language.text("系统未找到 ssh 命令。", "The system ssh command was not found.")
        case .connectionFailed:
            return language.text(
                "SSH 连接失败，请检查密钥、known_hosts 或远端可达性。",
                "SSH connection failed. Check keys, known_hosts, or remote reachability."
            )
        case .localCommandFailed:
            return language.text("本地命令执行失败。", "Local command failed.")
        case .cancelled:
            return language.text("操作已取消。", "Operation cancelled.")
        case .commandFailed(let message):
            return message
        }
    }

    var errorDescription: String? {
        message(language: .chinese)
    }
}

enum RemoteSystemInfoService {
    static func fetchHardware(
        for connection: SSHConnection,
        security: ResolvedSSHSecurity
    ) async throws -> HardwareInfo {
        try await runDetached {
            if connection.isLocal {
                return try fetchLocalHardware()
            }

            let host = connection.host.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !host.isEmpty else {
                throw RemoteSystemInfoError.invalidHost
            }

            let sshPath = "/usr/bin/ssh"
            guard FileManager.default.isExecutableFile(atPath: sshPath) else {
                throw RemoteSystemInfoError.sshUnavailable
            }

            let output = try runProcess(
                executablePath: sshPath,
                arguments: sshArguments(for: connection, security: security) + [hardwareCommand],
                environment: try processEnvironment(for: connection, security: security),
                fallbackError: .connectionFailed
            )
            return parseHardwareOutput(output)
        }
    }

    static func fetch(
        for connection: SSHConnection,
        security: ResolvedSSHSecurity
    ) async throws -> RemoteSystemInfo {
        try await runDetached {
            if connection.isLocal {
                return try fetchLocal()
            }

            let host = connection.host.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !host.isEmpty else {
                throw RemoteSystemInfoError.invalidHost
            }

            let sshPath = "/usr/bin/ssh"
            guard FileManager.default.isExecutableFile(atPath: sshPath) else {
                throw RemoteSystemInfoError.sshUnavailable
            }

            let remoteCommand = """
            \(Self.kernelAndUptimeProbe)
            \(Self.lastPackageChangeProbe)
            """

            let output = try runProcess(
                executablePath: sshPath,
                arguments: sshArguments(for: connection, security: security) + [remoteCommand],
                environment: try processEnvironment(for: connection, security: security),
                fallbackError: .connectionFailed
            )
            return parseRemoteSystemInfoOutput(output)
        }
    }

    /// Runs blocking process I/O off the main actor; respects task cancellation.
    private static func runDetached<T: Sendable>(_ work: @Sendable @escaping () throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask(priority: .userInitiated) {
                try work()
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else {
                throw CancellationError()
            }
            return result
        }
    }

    private static func fetchLocalHardware() throws -> HardwareInfo {
        let output = try runProcess(
            executablePath: "/bin/zsh",
            arguments: ["-lc", hardwareCommand],
            environment: ProcessInfo.processInfo.environment,
            fallbackError: .localCommandFailed
        )
        return parseHardwareOutput(output)
    }

    private static func fetchLocal() throws -> RemoteSystemInfo {
        let localCommand = """
        \(kernelAndUptimeProbe)
        \(lastPackageChangeProbe)
        """

        let output = try runProcess(
            executablePath: "/bin/zsh",
            arguments: ["-lc", localCommand],
            environment: ProcessInfo.processInfo.environment,
            fallbackError: .localCommandFailed
        )
        return parseRemoteSystemInfoOutput(output)
    }

    /// Kernel + uptime probe shared by local and remote fetches.
    private static var kernelAndUptimeProbe: String {
        #"""
        printf 'KERNEL=%s\n' "$(uname -srmo 2>/dev/null || uname -srm 2>/dev/null)"
        if [ -r /proc/uptime ]; then
            printf 'UPTIME=%s\n' "$(awk '{print int($1)}' /proc/uptime 2>/dev/null)"
        elif uptime -p >/dev/null 2>&1; then
            printf 'UPTIME=%s\n' "$(uptime -p 2>/dev/null)"
        else
            printf 'UPTIME=%s\n' "$(uptime 2>/dev/null)"
        fi
        """#
    }

    /// Detect last real package install/upgrade (not apt index refresh / cache mtime).
    private static var lastPackageChangeProbe: String {
        #"""
        UPDATE_LINE=""
        UPDATE_TS=""

        # --- Debian/Ubuntu: dpkg.log records install/upgrade (not apt update) ---
        if [ -z "$UPDATE_TS" ]; then
            for f in /var/log/dpkg.log /var/log/dpkg.log.1; do
                if [ -r "$f" ]; then
                    line=$(grep -E ' (upgrade|install) ' "$f" 2>/dev/null | tail -n 1)
                    if [ -n "$line" ]; then
                        UPDATE_LINE="dpkg: $(echo "$line" | tr -s ' ')"
                        ts=$(date -d "$(echo "$line" | awk '{print $1" "$2}')" +%s 2>/dev/null || true)
                        if [ -z "$ts" ]; then
                            ts=$(date -j -f "%Y-%m-%d %H:%M:%S" "$(echo "$line" | awk '{print $1" "$2}')" +%s 2>/dev/null || true)
                        fi
                        if [ -n "$ts" ]; then UPDATE_TS="$ts"; fi
                        break
                    fi
                fi
            done
        fi

        # apt history (transaction Start-Date) as fallback
        if [ -z "$UPDATE_TS" ] && [ -r /var/log/apt/history.log ]; then
            block=$(awk '
                /^Start-Date:/ { start=$0; has_change=0 }
                /^(Install|Upgrade|Remove|Purge):/ { has_change=1 }
                /^End-Date:/ {
                    if (has_change) { last_start=start; last_end=$0 }
                }
                END {
                    if (last_start != "") print last_start
                }
            ' /var/log/apt/history.log 2>/dev/null)
            if [ -n "$block" ]; then
                raw=$(echo "$block" | sed 's/^Start-Date:[[:space:]]*//')
                UPDATE_LINE="apt: $raw"
                ts=$(date -d "$raw" +%s 2>/dev/null || true)
                if [ -z "$ts" ]; then
                    ts=$(date -j -f "%Y-%m-%d  %H:%M:%S" "$raw" +%s 2>/dev/null || date -j -f "%Y-%m-%d %H:%M:%S" "$raw" +%s 2>/dev/null || true)
                fi
                if [ -n "$ts" ]; then UPDATE_TS="$ts"; fi
            fi
        fi

        # --- Fedora/RHEL: dnf history or dnf.rpm.log ---
        if [ -z "$UPDATE_TS" ] && command -v dnf >/dev/null 2>&1; then
            hist=$(dnf history list 2>/dev/null | awk 'NR>2 && $1 ~ /^[0-9]+$/ {print; exit}')
            if [ -n "$hist" ]; then
                UPDATE_LINE="dnf: $(echo "$hist" | tr -s ' ')"
                # Columns often: ID | Command | Date and time | ...
                raw=$(echo "$hist" | awk -F'|' '{gsub(/^ +| +$/,"",$3); print $3}')
                if [ -n "$raw" ]; then
                    ts=$(date -d "$raw" +%s 2>/dev/null || true)
                    if [ -n "$ts" ]; then UPDATE_TS="$ts"; fi
                fi
            fi
        fi
        if [ -z "$UPDATE_TS" ] && [ -r /var/log/dnf.rpm.log ]; then
            line=$(grep -E ' (Installed|Upgraded|Erased): ' /var/log/dnf.rpm.log 2>/dev/null | tail -n 1)
            if [ -n "$line" ]; then
                UPDATE_LINE="dnf.rpm: $(echo "$line" | tr -s ' ')"
                raw=$(echo "$line" | awk '{print $1" "$2}')
                ts=$(date -d "$raw" +%s 2>/dev/null || true)
                if [ -n "$ts" ]; then UPDATE_TS="$ts"; fi
            fi
        fi

        # --- yum.log (older EL) ---
        if [ -z "$UPDATE_TS" ] && [ -r /var/log/yum.log ]; then
            line=$(grep -E ' (Installed|Updated|Erased): ' /var/log/yum.log 2>/dev/null | tail -n 1)
            if [ -n "$line" ]; then
                UPDATE_LINE="yum: $(echo "$line" | tr -s ' ')"
                # Format: Mon DD HH:MM:SS ...
                raw=$(echo "$line" | awk '{print $1" "$2" "$3}')
                year=$(date +%Y)
                ts=$(date -d "$raw $year" +%s 2>/dev/null || true)
                if [ -n "$ts" ]; then UPDATE_TS="$ts"; fi
            fi
        fi

        # --- openSUSE: zypp history ---
        if [ -z "$UPDATE_TS" ] && [ -r /var/log/zypp/history ]; then
            line=$(grep -E '^\|?(install|upgrade|remove)\|' /var/log/zypp/history 2>/dev/null | tail -n 1)
            if [ -z "$line" ]; then
                line=$(grep -E '^(install|upgrade|remove)\|' /var/log/zypp/history 2>/dev/null | tail -n 1)
            fi
            # Actual format: 2024-01-15 12:34:56|install|pkg|...
            line=$(grep -E '^[0-9]{4}-[0-9]{2}-[0-9]{2} ' /var/log/zypp/history 2>/dev/null | grep -E '\|(install|patch|upgrade|remove)\|' | tail -n 1)
            if [ -n "$line" ]; then
                UPDATE_LINE="zypp: $(echo "$line" | tr -s ' ' | cut -c1-160)"
                raw=$(echo "$line" | awk -F'|' '{print $1}')
                ts=$(date -d "$raw" +%s 2>/dev/null || true)
                if [ -n "$ts" ]; then UPDATE_TS="$ts"; fi
            fi
        fi

        # --- Arch: pacman.log ALPM install/upgrade ---
        if [ -z "$UPDATE_TS" ] && [ -r /var/log/pacman.log ]; then
            line=$(grep -E '\[ALPM\] (upgraded|installed) ' /var/log/pacman.log 2>/dev/null | tail -n 1)
            if [ -n "$line" ]; then
                UPDATE_LINE="pacman: $(echo "$line" | tr -s ' ' | cut -c1-160)"
                # [2024-06-10T12:34:56+0000]
                raw=$(echo "$line" | sed -n 's/^\[\([^]]*\)\].*/\1/p')
                if [ -n "$raw" ]; then
                    ts=$(date -d "$raw" +%s 2>/dev/null || true)
                    if [ -z "$ts" ]; then
                        ts=$(date -j -f "%Y-%m-%dT%H:%M:%S%z" "$raw" +%s 2>/dev/null || true)
                    fi
                    if [ -n "$ts" ]; then UPDATE_TS="$ts"; fi
                fi
            fi
        fi

        # --- Alpine: apk log ---
        if [ -z "$UPDATE_TS" ] && [ -r /var/log/apk.log ]; then
            line=$(tail -n 5 /var/log/apk.log 2>/dev/null | grep -E ' (OK|installing|upgrading|Purging) ' | tail -n 1)
            if [ -n "$line" ]; then
                UPDATE_LINE="apk: $(echo "$line" | tr -s ' ' | cut -c1-160)"
                ts=$(stat -c '%Y' /var/log/apk.log 2>/dev/null || true)
                if [ -n "$ts" ]; then UPDATE_TS="$ts"; fi
            fi
        fi
        # apk installed DB changes on real package ops (better than repo cache)
        if [ -z "$UPDATE_TS" ] && command -v apk >/dev/null 2>&1; then
            for db in /lib/apk/db/installed /var/lib/apk/db/installed; do
                if [ -r "$db" ]; then
                    UPDATE_LINE="apk db: $(stat -c '%y' "$db" 2>/dev/null | cut -d. -f1)"
                    UPDATE_TS=$(stat -c '%Y' "$db" 2>/dev/null || true)
                    break
                fi
            done
        fi

        # --- FreeBSD pkg: per-package install timestamp ---
        if [ -z "$UPDATE_TS" ] && command -v pkg >/dev/null 2>&1; then
            line=$(pkg query -a '%t %n-%v' 2>/dev/null | sort -n | tail -n 1)
            if [ -n "$line" ]; then
                UPDATE_LINE="pkg: $(echo "$line" | tr -s ' ')"
                UPDATE_TS=$(echo "$line" | awk '{print $1}')
            fi
        fi

        # --- macOS: software update history (not receipts dir mtime) ---
        if [ -z "$UPDATE_TS" ] && command -v softwareupdate >/dev/null 2>&1; then
            hist=$(softwareupdate --history 2>/dev/null)
            if [ -n "$hist" ]; then
                # Prefer lines that look like history rows with a date (skip headers)
                line=$(echo "$hist" | awk 'NF>=3 && $0 !~ /Display Name|----|Version/ {line=$0} END {print line}' | tr -s ' ')
                if [ -n "$line" ]; then
                    UPDATE_LINE="macos: $line"
                    # Try to pull a trailing date-like token; leave TS empty if unparsable
                    raw=$(echo "$line" | grep -oE '[0-9]{1,2}/[0-9]{1,2}/[0-9]{2,4}[^[:space:]]*' | tail -n 1)
                    if [ -n "$raw" ]; then
                        ts=$(date -j -f "%m/%d/%Y" "$raw" +%s 2>/dev/null || date -j -f "%m/%d/%y" "$raw" +%s 2>/dev/null || true)
                        if [ -n "$ts" ]; then UPDATE_TS="$ts"; fi
                    fi
                fi
            fi
        fi
        if [ -z "$UPDATE_TS" ] && command -v sw_vers >/dev/null 2>&1; then
            # Last resort on macOS: do not use receipts folder mtime (almost always wrong).
            if [ -z "$UPDATE_LINE" ]; then
                UPDATE_LINE="macos: $(sw_vers -productName 2>/dev/null) $(sw_vers -productVersion 2>/dev/null)"
            fi
        fi

        printf 'UPDATE=%s\n' "$UPDATE_LINE"
        printf 'UPDATE_TS=%s\n' "$UPDATE_TS"
        """#
    }

    private static func parseRemoteSystemInfoOutput(_ output: String) -> RemoteSystemInfo {
        let lines = output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let values = parseKeyValueLines(lines)

        let kernelVersion = values["KERNEL", default: "Unknown"]
        // Keep empty when unknown; UI localizes the placeholder.
        let updateInfo = values["UPDATE", default: ""]
        let uptimeInfo = formatUptime(values["UPTIME", default: ""])
        let updateRecordedAt = values["UPDATE_TS"].flatMap { value -> Date? in
            guard let seconds = TimeInterval(value.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
            return Date(timeIntervalSince1970: seconds)
        }
        return RemoteSystemInfo(
            kernelVersion: kernelVersion,
            updateInfo: updateInfo,
            uptimeInfo: uptimeInfo,
            updateRecordedAt: updateRecordedAt,
            recordedAt: .now
        )
    }

    private static func parseHardwareOutput(_ output: String) -> HardwareInfo {
        let lines = output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let values = parseKeyValueLines(lines)
        let memoryTotal = values["MEM_BYTES"].flatMap { Int64($0) }.map(formatBytes) ?? ""

        return HardwareInfo(
            osName: values["OS", default: ""],
            architecture: values["ARCH", default: ""],
            cpuModel: values["CPU_MODEL", default: ""],
            cpuCores: values["CPU_CORES", default: ""],
            memoryTotal: memoryTotal,
            recordedAt: .now
        )
    }

    private static func parseKeyValueLines(_ lines: [String]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: lines.compactMap { line -> (String, String)? in
            guard let separatorIndex = line.firstIndex(of: "=") else { return nil }
            let key = String(line[..<separatorIndex])
            let value = String(line[line.index(after: separatorIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            return (key, value)
        })
    }

    private static func runProcess(
        executablePath: String,
        arguments: [String],
        environment: [String: String],
        fallbackError: RemoteSystemInfoError
    ) throws -> String {
        try Task.checkCancellation()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.environment = environment

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        process.standardInput = FileHandle(forReadingAtPath: "/dev/null")

        try process.run()

        // Poll so cooperative cancellation can terminate the child process.
        while process.isRunning {
            if Task.isCancelled {
                process.terminate()
                throw CancellationError()
            }
            Thread.sleep(forTimeInterval: 0.05)
        }

        if Task.isCancelled {
            throw CancellationError()
        }

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(decoding: outputData, as: UTF8.self)
        let error = String(decoding: errorData, as: UTF8.self)

        // SIGTERM after cancel often yields non-zero status; treat as cancellation.
        if process.terminationReason == .uncaughtSignal {
            throw CancellationError()
        }

        guard process.terminationStatus == 0 else {
            let message = error.trimmingCharacters(in: .whitespacesAndNewlines)
            if message.isEmpty {
                throw fallbackError
            }
            throw RemoteSystemInfoError.commandFailed(message)
        }

        return output
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

    private static func formatBytes(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "" }
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = Double(bytes)
        var unitIndex = 0
        while value >= 1024, unitIndex < units.count - 1 {
            value /= 1024
            unitIndex += 1
        }

        if value >= 10 || unitIndex == 0 {
            return "\(Int(value.rounded())) \(units[unitIndex])"
        }
        return String(format: "%.1f %@", value, units[unitIndex])
    }

    private static var hardwareCommand: String {
        #"""
        os_name=""
        if [ -r /etc/os-release ]; then
            os_name=$(awk -F= '/^PRETTY_NAME=/ {gsub(/^"|"$/, "", $2); print $2; exit}' /etc/os-release 2>/dev/null)
        fi
        if [ -z "$os_name" ] && command -v sw_vers >/dev/null 2>&1; then
            os_name="$(sw_vers -productName 2>/dev/null) $(sw_vers -productVersion 2>/dev/null)"
        fi
        if [ -z "$os_name" ]; then
            os_name=$(uname -sr 2>/dev/null)
        fi
        printf 'OS=%s\n' "$os_name"

        printf 'ARCH=%s\n' "$(uname -m 2>/dev/null)"

        cpu_model=""
        if command -v sysctl >/dev/null 2>&1; then
            cpu_model=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || true)
        fi
        if [ -z "$cpu_model" ] && [ -r /proc/cpuinfo ]; then
            cpu_model=$(awk -F: '/model name|Hardware|Processor/ {gsub(/^[ \t]+/, "", $2); print $2; exit}' /proc/cpuinfo 2>/dev/null)
        fi
        if [ -z "$cpu_model" ] && command -v lscpu >/dev/null 2>&1; then
            cpu_model=$(lscpu 2>/dev/null | awk -F: '/Model name/ {gsub(/^[ \t]+/, "", $2); print $2; exit}')
        fi
        printf 'CPU_MODEL=%s\n' "$cpu_model"

        cpu_cores=""
        if command -v nproc >/dev/null 2>&1; then
            cpu_cores=$(nproc 2>/dev/null)
        fi
        if [ -z "$cpu_cores" ] && command -v getconf >/dev/null 2>&1; then
            cpu_cores=$(getconf _NPROCESSORS_ONLN 2>/dev/null)
        fi
        if [ -z "$cpu_cores" ] && command -v sysctl >/dev/null 2>&1; then
            cpu_cores=$(sysctl -n hw.ncpu 2>/dev/null)
        fi
        printf 'CPU_CORES=%s\n' "$cpu_cores"

        mem_bytes=""
        if [ -r /proc/meminfo ]; then
            mem_bytes=$(awk '/MemTotal/ {printf "%.0f", $2 * 1024; exit}' /proc/meminfo 2>/dev/null)
        fi
        if [ -z "$mem_bytes" ] && command -v sysctl >/dev/null 2>&1; then
            mem_bytes=$(sysctl -n hw.memsize 2>/dev/null || sysctl -n hw.physmem 2>/dev/null || true)
        fi
        printf 'MEM_BYTES=%s\n' "$mem_bytes"
        """#
    }


    private static func sshArguments(
        for connection: SSHConnection,
        security: ResolvedSSHSecurity
    ) -> [String] {
        var arguments = [
            "-o", "StrictHostKeyChecking=\(security.hostKeyPolicy.sshOptionValue)",
            "-o", "ConnectTimeout=8"
        ]

        switch security.passwordAuthPolicy {
        case .allowPasswordPrompt:
            arguments += [
                "-o", "PreferredAuthentications=publickey,keyboard-interactive,password",
                "-o", "NumberOfPasswordPrompts=1",
                "-o", "BatchMode=no"
            ]
        case .publicKeyOnly:
            arguments += [
                "-o", "PreferredAuthentications=publickey",
                "-o", "PubkeyAuthentication=yes",
                "-o", "PasswordAuthentication=no",
                "-o", "KbdInteractiveAuthentication=no",
                "-o", "NumberOfPasswordPrompts=0",
                "-o", "BatchMode=yes"
            ]
        }

        if security.hostKeyPolicy == .off {
            arguments += ["-o", "UserKnownHostsFile=/dev/null"]
        }

        if let identity = connection.expandedIdentityFile {
            arguments += ["-i", identity]
            // Avoid trying every default key when a specific identity is set.
            if !connection.extraSSHOptionLines.contains(where: { $0.lowercased().hasPrefix("identitiesonly=") }) {
                arguments += ["-o", "IdentitiesOnly=yes"]
            }
        }

        if let jump = connection.trimmedProxyJump {
            arguments += ["-J", jump]
        }

        for option in connection.extraSSHOptionLines {
            let lower = option.lowercased()
            // Avoid overriding policies already set by the app security settings.
            if lower.hasPrefix("stricthostkeychecking=") { continue }
            if lower.hasPrefix("userknownhostsfile=") && security.hostKeyPolicy == .off { continue }
            if lower.hasPrefix("batchmode=") { continue }
            if lower.hasPrefix("passwordauthentication=") { continue }
            if lower.hasPrefix("preferredauthentications=") { continue }
            if lower.hasPrefix("numberofpasswordprompts=") { continue }
            arguments += ["-o", option]
        }

        if connection.port != 22 {
            arguments += ["-p", String(connection.port)]
        }

        arguments.append(connection.destination)
        return arguments
    }

    private static func processEnvironment(
        for connection: SSHConnection,
        security: ResolvedSSHSecurity
    ) throws -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["LC_ALL"] = "en_US.UTF-8"
        environment["LANG"] = "en_US.UTF-8"

        switch security.passwordAuthPolicy {
        case .allowPasswordPrompt:
            let helperURL = try makeAskpassHelper()
            environment["SSH_ASKPASS"] = helperURL.path
            environment["SSH_ASKPASS_REQUIRE"] = "force"
            environment["SSH_ASKPASS_PROMPT"] = "Enter SSH password for \(connection.destination)"
        case .publicKeyOnly:
            environment.removeValue(forKey: "SSH_ASKPASS")
            environment.removeValue(forKey: "SSH_ASKPASS_REQUIRE")
            environment.removeValue(forKey: "SSH_ASKPASS_PROMPT")
            environment["SSH_ASKPASS_REQUIRE"] = "never"
        }

        return environment
    }

    private static func makeAskpassHelper() throws -> URL {
        let helperURL = FileManager.default.temporaryDirectory.appendingPathComponent("swifthoppy-ssh-askpass.sh")
        let script = #"""
        #!/bin/sh
        export LC_ALL=en_US.UTF-8
        export LANG=en_US.UTF-8
        /usr/bin/osascript <<'APPLESCRIPT'
        set promptText to system attribute "SSH_ASKPASS_PROMPT"
        try
            display dialog promptText with title "SwiftHoppy" default answer "" with hidden answer buttons {"Cancel", "OK"} default button "OK"
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
