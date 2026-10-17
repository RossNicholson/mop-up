import Foundation

// Parsers for the plain-text reports Mole prints when there's no terminal.
//
// Mole's lines look like this:
//
//   ➤ Developer tools                         a section
//     → Xcode DerivedData · 11 projects, 5.69GB   something it will do / did
//     ✓ Nothing to clean                      fine as it is
//     ⊙ Simulator data · 29.88GB · ~/Library/…   worth a look, not touched
//     ◎ Trash · skipped, grant Full Disk Access    a warning
//   ======================================================================
//   Dry run complete - no changes made        the summary block
//   Potential space: 6.77GB | Items: 169 | Categories: 5
//   ======================================================================

/// One line inside a section of a Mole report
struct ReportLine: Hashable, Sendable, Identifiable {
    enum Kind: Sendable { case action, ok, review, warning, error, skipped, note }

    let kind: Kind
    let title: String
    let detail: String?
    /// First size found in the line (decimal units, as Mole prints them)
    let bytes: Int64?
    let id = UUID()

    static func == (lhs: ReportLine, rhs: ReportLine) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct ReportSection: Sendable, Identifiable {
    let title: String
    var lines: [ReportLine]
    var id: String { title }

    var bytes: Int64 { lines.filter { $0.kind == .action || $0.kind == .ok }.compactMap(\.bytes).reduce(0, +) }
    var actions: [ReportLine] { lines.filter { $0.kind == .action } }
    var reviews: [ReportLine] { lines.filter { $0.kind == .review } }
    var warnings: [ReportLine] { lines.filter { $0.kind == .warning || $0.kind == .error } }
    var isNothingToDo: Bool { lines.allSatisfy { $0.kind == .ok && $0.title.hasPrefix("Nothing to") } }
}

/// A whole Mole report: its sections plus the boxed summary at the end
struct MoleReport: Sendable {
    var sections: [ReportSection] = []
    /// Lines printed before the first section (system info, notices)
    var preamble: [ReportLine] = []
    /// The lines inside the ===== box at the end
    var summary: [String] = []

    var headline: String? { summary.first }

    /// The value after "Label:" in the summary, e.g. "Potential space" → "6.77GB"
    func summaryValue(_ label: String) -> String? {
        for line in summary {
            for part in line.components(separatedBy: " | ") {
                let pieces = part.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                if pieces.count == 2, pieces[0].caseInsensitiveCompare(label) == .orderedSame {
                    return pieces[1]
                }
            }
        }
        return nil
    }

    static func parse(_ lines: [String]) -> MoleReport {
        var report = MoleReport()
        var current: ReportSection?
        var ruleCount = 0

        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.count >= 20, line.allSatisfy({ $0 == "=" }) {
                ruleCount += 1
                continue
            }
            if ruleCount == 1 {
                if !line.isEmpty { report.summary.append(line) }
                continue
            }
            guard !line.isEmpty else { continue }

            if line.hasPrefix("➤ ") {
                if let current { report.sections.append(current) }
                current = ReportSection(title: String(line.dropFirst(2)), lines: [])
                continue
            }
            guard let parsed = parseLine(line) else { continue }
            if current != nil {
                current!.lines.append(parsed)
            } else {
                report.preamble.append(parsed)
            }
        }
        if let current { report.sections.append(current) }
        return report
    }

    static func parseLine(_ line: String) -> ReportLine? {
        guard let first = line.first else { return nil }
        let kind: ReportLine.Kind
        switch first {
        case "→": kind = .action
        case "✓": kind = .ok
        case "⊙": kind = .review
        case "◎": kind = .warning
        case "☻": kind = .error
        case "-": kind = .skipped
        case "•", "↳", "⚙", "ℹ": kind = .note
        default: return nil
        }
        let rest = line.dropFirst().trimmingCharacters(in: .whitespaces)
        guard !rest.isEmpty else { return nil }
        let parts = rest.components(separatedBy: " · ")
        let title = parts[0]
        let detail = parts.count > 1 ? parts.dropFirst().joined(separator: " · ") : nil
        return ReportLine(kind: kind, title: title, detail: detail, bytes: firstSize(in: detail ?? title))
    }

    static func firstSize(in text: String) -> Int64? {
        guard let match = text.firstMatch(of: /(\d+(?:\.\d+)?)(B|KB|MB|GB|TB)\b/) else { return nil }
        return ByteSize.parse(String(match.1) + String(match.2))
    }
}

// MARK: - Clean preview file list

/// `~/.config/mole/clean-list.txt`, written by `mole clean --dry-run`: every
/// path the clean would touch, grouped by section
enum CleanFileList {
    struct Entry: Hashable, Sendable, Identifiable {
        let path: String
        let size: String?
        var id: String { path }
    }

    static var url: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/mole/clean-list.txt")
    }

    static func parse(_ text: String) -> [String: [Entry]] {
        var result: [String: [Entry]] = [:]
        var section: String?
        for raw in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("=== "), line.hasSuffix(" ===") {
                section = String(line.dropFirst(4).dropLast(4))
                continue
            }
            guard let section, line.hasPrefix("/") || line.hasPrefix("~") else { continue }
            let parts = line.components(separatedBy: "  # ")
            let path = parts[0].trimmingCharacters(in: .whitespaces)
            let size = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : nil
            result[section, default: []].append(Entry(path: path, size: size))
        }
        return result
    }
}

// MARK: - Uninstall preview

/// What `mole uninstall --dry-run <apps>` says it would remove
struct UninstallPlan: Sendable {
    struct File: Hashable, Sendable, Identifiable {
        let path: String
        let size: String?
        var id: String { path }
    }

    struct AppGroup: Sendable, Identifiable {
        let name: String
        let size: String?
        var files: [File] = []
        var notes: [String] = []
        var id: String { name }
    }

    /// "1. Battle.net  9.2MB  |  Last: 3w ago" lines: the apps Mole matched
    var matched: [String] = []
    var apps: [AppGroup] = []
    var summary: [String] = []

    static func parse(_ lines: [String]) -> UninstallPlan {
        var plan = UninstallPlan()
        var inFiles = false
        var ruleCount = 0
        for raw in lines {
            let indented = raw.hasPrefix("  ")
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.count >= 20, line.allSatisfy({ $0 == "=" }) { ruleCount += 1; continue }
            if ruleCount == 1 { if !line.isEmpty { plan.summary.append(line) }; continue }
            if line.firstMatch(of: /^\d+\.\s/) != nil, !inFiles {
                plan.matched.append(line.replacing(/^\d+\.\s+/, with: ""))
                continue
            }
            if line.hasPrefix("Files to be removed") { inFiles = true; continue }
            guard inFiles, let icon = line.first else { continue }
            if icon == "➤" { inFiles = false; continue }
            let body = line.dropFirst().trimmingCharacters(in: .whitespaces)
            let (name, size) = splitSize(body)
            if !indented, icon == "◎" {
                plan.apps.append(AppGroup(name: name, size: size))
            } else if indented, !plan.apps.isEmpty {
                if icon == "✓" || body.hasPrefix("/") || body.hasPrefix("~") {
                    plan.apps[plan.apps.count - 1].files.append(File(path: name, size: size))
                } else {
                    plan.apps[plan.apps.count - 1].notes.append(body)
                }
            }
        }
        return plan
    }

    /// "/Applications/Foo.app , 9.2MB" → ("/Applications/Foo.app", "9.2MB")
    static func splitSize(_ text: String) -> (String, String?) {
        guard let range = text.range(of: " , ", options: .backwards) else { return (text, nil) }
        return (String(text[..<range.lowerBound]), String(text[range.upperBound...]))
    }
}
