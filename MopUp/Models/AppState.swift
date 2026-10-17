import AppKit
import Observation
import SwiftUI

/// The screens in the sidebar
enum AppSection: String, CaseIterable, Identifiable {
    case home, clean, uninstall, tuneUp, space, history, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .clean: return "Clean Up"
        case .uninstall: return "Uninstall"
        case .tuneUp: return "Tune Up"
        case .space: return "Disk Space"
        case .history: return "History"
        case .about: return "About"
        }
    }

    var symbol: String {
        switch self {
        case .home: return "house.fill"
        case .clean: return "sparkles"
        case .uninstall: return "trash.fill"
        case .tuneUp: return "wrench.and.screwdriver.fill"
        case .space: return "chart.pie.fill"
        case .history: return "clock.arrow.circlepath"
        case .about: return "info.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .home: return AppColors.lilac
        case .clean: return AppColors.peach
        case .uninstall: return AppColors.periwinkle
        case .tuneUp: return AppColors.mint
        case .space: return AppColors.butter
        case .history: return AppColors.lilac
        case .about: return AppColors.mint
        }
    }
}

/// Everything the window shows. Each screen keeps its own model, so switching
/// screens mid-job doesn't lose a scan or a running clean.
@MainActor
@Observable
final class AppState {
    var section: AppSection = .home
    var hasFullDiskAccess = Permissions.hasFullDiskAccess()

    let jobs = JobGate()
    let status: StatusModel
    let clean: CleanModel
    let uninstall: UninstallModel
    let tuneUp: TuneUpModel
    let space: SpaceModel
    let history: HistoryModel

    init(engine: MoleEngine = .bundled) {
        status = StatusModel(engine: engine)
        clean = CleanModel(engine: engine, jobs: jobs)
        uninstall = UninstallModel(engine: engine, jobs: jobs)
        tuneUp = TuneUpModel(engine: engine, jobs: jobs)
        space = SpaceModel(engine: engine)
        history = HistoryModel(engine: engine)
    }

    func refreshPermissions() {
        hasFullDiskAccess = Permissions.hasFullDiskAccess()
    }
}

/// Only one job that changes the disk (clean, uninstall, tune-up) runs at a time
@MainActor
@Observable
final class JobGate {
    private(set) var running: String?

    var isBusy: Bool { running != nil }

    func begin(_ name: String) -> Bool {
        guard running == nil else { return false }
        running = name
        return true
    }

    func end() { running = nil }
}

enum Permissions {
    /// Full Disk Access can't be queried directly; the usual test is whether the
    /// user's TCC database (readable only with it) can be opened.
    static func hasFullDiskAccess() -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let probes = [
            home + "/Library/Application Support/com.apple.TCC/TCC.db",
            home + "/Library/Safari/Bookmarks.plist",
        ]
        for path in probes where FileManager.default.fileExists(atPath: path) {
            let fd = open(path, O_RDONLY)
            if fd >= 0 { close(fd); return true }
            return false
        }
        return false
    }

    static func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// Text from Mole is written for a terminal; this makes it read naturally in Mop Up
enum Friendly {
    static func detail(_ text: String?) -> String? {
        guard var text, !text.isEmpty else { return nil }
        text = text.replacingOccurrences(of: "grant Full Disk Access to your terminal", with: "needs Full Disk Access")
        text = text.replacingOccurrences(of: "your terminal", with: "Mop Up")
        text = text.replacing(/\s+dry$/, with: "")
        text = text.replacingOccurrences(of: "would clean", with: "")
        // Drop command-line hints that don't apply in the app
        let parts = text.components(separatedBy: " · ").filter { part in
            !part.hasPrefix("mo ") && !part.hasPrefix("review with ") && !part.contains("sudo ")
        }
        let joined = parts.joined(separator: " · ").trimmingCharacters(in: .whitespaces)
        return joined.isEmpty ? nil : joined
    }

    /// "~/Library/..." or "/..." found in a line's detail, for Show in Finder
    static func path(in text: String?) -> String? {
        guard let text else { return nil }
        for part in text.components(separatedBy: " · ") {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("/") { return trimmed }
            if trimmed.hasPrefix("~/") {
                return FileManager.default.homeDirectoryForCurrentUser.path + trimmed.dropFirst(1)
            }
        }
        return nil
    }
}
