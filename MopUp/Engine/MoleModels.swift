import Foundation

// Decodable views of Mole's JSON output. Only the fields Mop Up shows are
// listed, and they're optional where Mole may leave them out, so a newer Mole
// adding or dropping a field doesn't break decoding.

/// `mole status --json`
struct SystemStatus: Decodable, Sendable {
    struct Hardware: Decodable, Sendable {
        let model: String?
        let cpuModel: String?
        let totalRam: String?
        let osVersion: String?

        enum CodingKeys: String, CodingKey {
            case model, cpuModel = "cpu_model", totalRam = "total_ram", osVersion = "os_version"
        }
    }

    struct CPU: Decodable, Sendable {
        let usage: Double?
    }

    struct Memory: Decodable, Sendable {
        let used: Int64?
        let total: Int64?
        let usedPercent: Double?

        enum CodingKeys: String, CodingKey {
            case used, total, usedPercent = "used_percent"
        }
    }

    struct Disk: Decodable, Sendable {
        let mount: String
        let used: Int64
        let total: Int64
        let external: Bool?

        var free: Int64 { max(total - used, 0) }
        var fraction: Double { total > 0 ? Double(used) / Double(total) : 0 }
    }

    struct Battery: Decodable, Sendable {
        let percent: Double?
        let status: String?
        let health: String?
        let cycleCount: Int?
        let capacity: Int?

        enum CodingKeys: String, CodingKey {
            case percent, status, health, cycleCount = "cycle_count", capacity
        }
    }

    struct Process: Decodable, Sendable, Identifiable {
        let pid: Int
        let name: String
        let cpu: Double?
        let memoryBytes: Int64?

        var id: Int { pid }

        enum CodingKeys: String, CodingKey {
            case pid, name, cpu, memoryBytes = "memory_bytes"
        }
    }

    let host: String?
    let uptime: String?
    let hardware: Hardware?
    let healthScore: Int?
    let healthScoreMsg: String?
    let cpu: CPU?
    let memory: Memory?
    let disks: [Disk]?
    let trashSize: Int64?
    let batteries: [Battery]?
    let topProcesses: [Process]?

    enum CodingKeys: String, CodingKey {
        case host, uptime, hardware, cpu, memory, disks, batteries
        case healthScore = "health_score", healthScoreMsg = "health_score_msg"
        case trashSize = "trash_size", topProcesses = "top_processes"
    }

    /// The startup disk
    var mainDisk: Disk? { disks?.first { $0.mount == "/" } ?? disks?.first }
}

/// One row of `mole uninstall --list`
struct InstalledApp: Decodable, Sendable, Identifiable, Hashable {
    let name: String
    let bundleID: String?
    let source: String?
    let uninstallName: String
    let path: String
    let size: String?

    var id: String { path }
    var sizeBytes: Int64? { size.flatMap(ByteSize.parse) }
    var isHomebrew: Bool { source == "Homebrew" }

    enum CodingKeys: String, CodingKey {
        case name, source, path, size
        case bundleID = "bundle_id", uninstallName = "uninstall_name"
    }
}

/// `mole analyze --json [path]`
struct DiskScan: Decodable, Sendable {
    struct Entry: Decodable, Sendable, Identifiable, Hashable {
        let name: String
        let path: String
        var size: Int64
        let isDir: Bool
        let scanStatus: String?
        let insight: Bool?
        let cleanable: Bool?

        var id: String { path }
        var isUnavailable: Bool { scanStatus == "unavailable" }

        enum CodingKeys: String, CodingKey {
            case name, path, size, insight, cleanable
            case isDir = "is_dir", scanStatus = "scan_status"
        }
    }

    struct LargeFile: Decodable, Sendable, Identifiable, Hashable {
        let name: String
        let path: String
        var size: Int64
        var id: String { path }
    }

    let path: String
    let overview: Bool?
    let scanStatus: String?
    var entries: [Entry]
    var largeFiles: [LargeFile]?
    var totalSize: Int64?

    enum CodingKeys: String, CodingKey {
        case path, overview, entries
        case scanStatus = "scan_status", largeFiles = "large_files", totalSize = "total_size"
    }
}

/// `mole history --json`
struct CleanupHistory: Decodable, Sendable {
    struct Session: Decodable, Sendable, Identifiable {
        struct Actions: Decodable, Sendable {
            let removed: Int?
            let trashed: Int?
            let skipped: Int?
            let failed: Int?
        }

        let command: String
        let runID: String?
        let startedAt: String
        let endedAt: String?
        let items: Int?
        let size: String?
        let actions: Actions?

        var id: String { (runID?.isEmpty == false ? runID! : startedAt) + command }

        var date: Date? { Self.formatter.date(from: startedAt) }

        static let formatter: DateFormatter = {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy-MM-dd HH:mm:ss"
            return f
        }()

        enum CodingKeys: String, CodingKey {
            case command, items, size, actions
            case runID = "run_id", startedAt = "started_at", endedAt = "ended_at"
        }
    }

    let sessions: [Session]
}

/// Mole prints sizes in decimal units ("707.2MB", "5.69GB", "1KB", "0B")
enum ByteSize {
    static func parse(_ text: String) -> Int64? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let match = trimmed.firstMatch(of: /^(\d+(?:\.\d+)?)\s*(B|KB|MB|GB|TB)$/.ignoresCase()),
              let value = Double(match.1) else { return nil }
        let multiplier: Double
        switch match.2.uppercased() {
        case "KB": multiplier = 1e3
        case "MB": multiplier = 1e6
        case "GB": multiplier = 1e9
        case "TB": multiplier = 1e12
        default: multiplier = 1
        }
        return Int64(value * multiplier)
    }

    /// "6.8 GB", in the same decimal units Finder uses
    static func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// "24 GB" for memory, in the binary units macOS uses for RAM
    static func formatMemory(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .memory)
    }

    /// Mole's "6.41GB" as "6.41 GB"; anything unparseable is returned as-is
    static func tidy(_ text: String) -> String {
        parse(text).map(format) ?? text
    }
}
