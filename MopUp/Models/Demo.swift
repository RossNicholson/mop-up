#if DEBUG
import Foundation

/// Sample data for screenshots: launch with `-demo YES`. Nothing here comes
/// from (or touches) the real Mac, apart from app icons looked up by path.
extension AppState {
    func loadDemo() {
        hasFullDiskAccess = true
        status.loadDemo(Self.demoStatus)
        clean.loadDemo(.preview(MoleReport.parse(Self.demoClean.components(separatedBy: "\n")), files: [:]))
        tuneUp.loadDemo(.done(MoleReport.parse(Self.demoTuneUp.components(separatedBy: "\n"))))
        uninstall.loadDemo(Self.demoApps, selected: ["VLC", "Steam"])
        space.loadDemo(Self.demoSpace)
        history.loadDemo(Self.demoHistory)
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ json: String) -> T {
        try! JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    static var demoStatus: SystemStatus {
        decode(SystemStatus.self, """
        {"host":"MacBook-Pro","uptime":"3d 4h",
         "hardware":{"model":"MacBook Pro","cpu_model":"Apple M4","total_ram":"16.0 GB","os_version":"macOS 27.0"},
         "health_score":91,"health_score_msg":"Excellent: Running smoothly",
         "cpu":{"usage":14.2},
         "memory":{"used":9856000000,"total":17179869184,"used_percent":57.4},
         "disks":[{"mount":"/","used":712400000000,"total":994662584320,"external":false}],
         "trash_size":2310000000,
         "batteries":[{"percent":87,"status":"discharging","health":"Good","cycle_count":142,"capacity":96}]}
        """)
    }

    static let demoClean = """
    ➤ User essentials
      → User app cache · 42 items, 1.84GB dry
      → User app logs · 63 items, 48.2MB dry
      → Trash · 12 items, 2.31GB dry
    ➤ Browsers
      → Safari cache · 3 items, 412.6MB dry
      → Chrome cache · 6 items, 1.27GB dry
    ➤ Developer tools
      → npm cache · 2.04GB dry
      → Xcode DerivedData · 9 projects, 6.12GB
      → Homebrew cache · 31 items, 860.4MB dry
    ➤ Apps & utilities
      → Spotify cache · 4 items, 734.9MB dry
      → Slack cache · 5 items, 318.1MB dry
    ➤ App leftovers
      → Leftovers from 6 deleted apps · 24 items, 1.03GB dry
    ➤ Large files
      ⊙ Simulator data · 18.40GB · ~/Library/Developer/CoreSimulator/Devices
      ⊙ iPhone backups · 42.70GB · ~/Library/Application Support/MobileSync/Backup
    ======================================================================
    Dry run complete - no changes made
    Potential space: 16.98GB | Items: 196 | Categories: 5
    ======================================================================
    """

    static let demoTuneUp = """
    ➤ Finder Cache Refresh
      → QuickLook thumbnails refreshed
      → Icon services cache rebuilt
    ➤ App State Cleanup
      → App saved states optimized
    ➤ Broken Config Repair
      → All preference files valid
    ➤ Network Cache Refresh
      → DNS cache refreshed
    ➤ Spotlight Optimization
      → Spotlight index already optimal
    ➤ Login Items
      → Login items all healthy (6 checked)
    ➤ Launch Agents Cleanup
      → Removed 2 broken launch agents
    ➤ Disk Health
      → Startup disk verified
    ======================================================================
    Optimization complete
    Applied 6 optimizations
    11 unchanged | 0 skipped
    ======================================================================
    """

    static var demoApps: [InstalledApp] {
        let apps: [(String, String, String?, String)] = [
            ("Xcode", "/Applications/Xcode.app", nil, "3.90GB"),
            ("Blender", "/Applications/Blender.app", "Homebrew", "950.6MB"),
            ("OrbStack", "/Applications/OrbStack.app", "Homebrew", "736.6MB"),
            ("Unity Hub", "/Applications/Unity Hub.app", nil, "565.4MB"),
            ("VLC", "/Applications/VLC.app", "Homebrew", "154.3MB"),
            ("1Blocker", "/Applications/1Blocker.app", nil, "109.3MB"),
            ("Steam", "/Applications/Steam.app", nil, "11.3MB"),
        ]
        return apps.map { name, path, source, size in
            InstalledApp(name: name, bundleID: nil, source: source ?? "App",
                         uninstallName: name, path: path, size: size)
        }
    }

    static var demoSpace: DiskScan {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        func entry(_ name: String, _ path: String, _ size: Int64, cleanable: Bool = false) -> DiskScan.Entry {
            DiskScan.Entry(name: name, path: path, size: size, isDir: true, scanStatus: "complete",
                           insight: nil, cleanable: cleanable)
        }
        return DiskScan(path: "/", overview: true, scanStatus: "complete", entries: [
            entry("Home", home, 402_300_000_000),
            entry("User Library", home + "/Library", 118_600_000_000),
            entry("iPhone backups", home + "/Library/Application Support/MobileSync/Backup", 42_700_000_000),
            entry("Applications", "/Applications", 41_200_000_000),
            entry("Xcode Simulators", home + "/Library/Developer/CoreSimulator/Devices", 18_400_000_000),
            entry("Xcode DerivedData", home + "/Library/Developer/Xcode/DerivedData", 6_120_000_000, cleanable: true),
            entry("npm Cache", home + "/.npm", 2_040_000_000, cleanable: true),
            entry("Homebrew Cache", home + "/Library/Caches/Homebrew", 860_400_000, cleanable: true),
        ], largeFiles: nil, totalSize: 712_400_000_000)
    }

    static var demoHistory: [CleanupHistory.Session] {
        decode(CleanupHistory.self, """
        {"sessions":[
          {"command":"clean","run_id":"a","started_at":"2026-10-17 09:12:40","items":196,"size":"16.98GB"},
          {"command":"uninstall","run_id":"b","started_at":"2026-10-15 18:03:11","items":2,"size":"165.6MB"},
          {"command":"optimize","run_id":"c","started_at":"2026-10-12 21:44:02","items":6,"size":"0B"},
          {"command":"clean","run_id":"d","started_at":"2026-10-03 08:30:57","items":341,"size":"9.42GB"}
        ]}
        """).sessions
    }
}

#endif
