import XCTest
@testable import Mop_Up

/// The fixtures are real Mole 1.61.0 output, captured without a terminal
final class ReportParserTests: XCTestCase {

    static let cleanDryRun = """

    Clean Your Mac

    Dry Run Mode, Preview only, no deletions

    ◎ System caches need sudo, run sudo -v && mo clean --dry-run for full preview

    ⚙ Apple Silicon | Free space: 20.46GB
    ✓ Whitelist: 19 core patterns active
      ↳ /Users/me/Library/Caches/ms-playwright*

    ➤ User essentials
      → User app cache · 19 items, 707.2MB dry
      → User app logs · 46 items, 7.5MB dry
      ◎ Trash · skipped, grant Full Disk Access to your terminal

    ➤ Browsers
      ✓ Nothing to clean

    ➤ Developer tools
      → npm cache · would clean
      ⊙ Docker unused data · review with docker system df
      → Xcode DerivedData · 11 projects, 5.69GB
      → Homebrew cache · 12 items, 71.5MB dry

    ➤ Large files
      ⊙ Time Machine local snapshots · 12
      ⊙ Simulator data · 29.88GB · ~/Library/Developer/CoreSimulator/Devices

    ➤ Project artifacts
      ⊙ Build artifacts · 80+ dirs, 359.9MB+ · mo purge


    ======================================================================
    Dry run complete - no changes made
    Potential space: 6.77GB | Items: 169 | Categories: 5
    Detailed file list: /Users/me/.config/mole/clean-list.txt
    Use mo clean --whitelist to add protection rules
    ======================================================================
    """

    func testCleanSectionsAndKinds() {
        let report = MoleReport.parse(Self.cleanDryRun.components(separatedBy: "\n"))
        XCTAssertEqual(report.sections.map(\.title),
                       ["User essentials", "Browsers", "Developer tools", "Large files", "Project artifacts"])

        let essentials = report.sections[0]
        XCTAssertEqual(essentials.actions.count, 2)
        XCTAssertEqual(essentials.actions[0].title, "User app cache")
        XCTAssertEqual(essentials.actions[0].bytes, 707_200_000)
        XCTAssertEqual(essentials.warnings.first?.title, "Trash")
        XCTAssertEqual(essentials.bytes, 707_200_000 + 7_500_000)

        XCTAssertTrue(report.sections[1].isNothingToDo)

        let dev = report.sections[2]
        XCTAssertEqual(dev.actions.map(\.title), ["npm cache", "Xcode DerivedData", "Homebrew cache"])
        XCTAssertNil(dev.actions[0].bytes)
        XCTAssertEqual(dev.actions[1].bytes, 5_690_000_000)
        XCTAssertEqual(dev.reviews.map(\.title), ["Docker unused data"])

        XCTAssertEqual(report.sections[3].reviews[1].bytes, 29_880_000_000)
        XCTAssertEqual(report.sections[4].reviews[0].bytes, 359_900_000)
    }

    func testCleanPreambleIsNotASection() {
        let report = MoleReport.parse(Self.cleanDryRun.components(separatedBy: "\n"))
        XCTAssertTrue(report.preamble.contains { $0.title.hasPrefix("System caches need sudo") })
        XCTAssertFalse(report.sections.contains { $0.title.contains("Whitelist") })
    }

    func testCleanSummary() {
        let report = MoleReport.parse(Self.cleanDryRun.components(separatedBy: "\n"))
        XCTAssertEqual(report.headline, "Dry run complete - no changes made")
        XCTAssertEqual(report.summaryValue("Potential space"), "6.77GB")
        XCTAssertEqual(report.summaryValue("Items"), "169")
        XCTAssertEqual(report.summaryValue("Categories"), "5")
        XCTAssertNil(report.summaryValue("Tracked cleanup"))
    }

    func testRealCleanSummary() {
        let lines = """
        ======================================================================
        Cleanup complete
        Tracked cleanup: 6.71GB | Items cleaned: 165
        Free space: 27.17GB (+6.71GB)
        ======================================================================
        """.components(separatedBy: "\n")
        let report = MoleReport.parse(lines)
        XCTAssertEqual(report.summaryValue("Tracked cleanup"), "6.71GB")
        XCTAssertEqual(report.summaryValue("Items cleaned"), "165")
        XCTAssertEqual(report.summaryValue("Free space"), "27.17GB (+6.71GB)")
    }

    static let optimizeDryRun = """

    Optimize
    → DRY RUN MODE, No files will be modified

    ⚙ System  12/24 GB RAM | 416/460 GB Disk | Uptime 0d

    Performance diagnosis
      ✓ No sustained high-CPU bottleneck detected

    ➤ Finder Cache Refresh
      → QuickLook thumbnails refreshed
      → Icon services cache rebuilt

    ➤ Database Optimization
      ◎ Close these apps before database optimization: Mail Safari

    ➤ Shared File Lists
      - Shared file lists not readable (check directory permissions and Full Disk Access)

    ======================================================================
    Dry Run Complete, No Changes Made
    Would apply 3 optimizations
    12 unchanged | 2 skipped | 2 unavailable
    Run without --dry-run to apply these changes
    ======================================================================
    """

    func testOptimize() {
        let report = MoleReport.parse(Self.optimizeDryRun.components(separatedBy: "\n"))
        XCTAssertEqual(report.sections.map(\.title), ["Finder Cache Refresh", "Database Optimization", "Shared File Lists"])
        XCTAssertEqual(report.sections[0].actions.count, 2)
        XCTAssertEqual(report.sections[1].warnings.count, 1)
        XCTAssertEqual(report.sections[2].lines.first?.kind, .skipped)
        XCTAssertEqual(report.summary, ["Dry Run Complete, No Changes Made", "Would apply 3 optimizations",
                                        "12 unchanged | 2 skipped | 2 unavailable", "Run without --dry-run to apply these changes"])
    }

    static let uninstallDryRun = """
    → DRY RUN MODE, No app files or settings will be modified

    ◎ Matched 1 app(s):
    1. Battle.net  9.2MB  |  Last: 3w ago

    Proceed with uninstallation? [y/N]
    Files to be removed:
    ◎ Battle.net , 9.2MB
      ◎ Shared leftovers kept (cannot read /Volumes/Time Machine)
      ✓ /Applications/Battle.net.app , 9.2MB
      ✓ /Users/me/Library/Application Support/Battle.net , 1.1MB

    ➤ Remove 1 app, 9.2MB  Enter confirm, ESC cancel:

    ======================================================================
    Uninstall dry run complete
    Would remove 1 app, would free 9.2MB: Battle.net
    ======================================================================

    [DRY RUN] Would refresh LaunchServices and update Dock entries
    """

    func testUninstallPlan() {
        let plan = UninstallPlan.parse(Self.uninstallDryRun.components(separatedBy: "\n"))
        XCTAssertEqual(plan.matched, ["Battle.net  9.2MB  |  Last: 3w ago"])
        XCTAssertEqual(plan.apps.count, 1)
        XCTAssertEqual(plan.apps[0].name, "Battle.net")
        XCTAssertEqual(plan.apps[0].size, "9.2MB")
        XCTAssertEqual(plan.apps[0].files.map(\.path),
                       ["/Applications/Battle.net.app", "/Users/me/Library/Application Support/Battle.net"])
        XCTAssertEqual(plan.apps[0].files[1].size, "1.1MB")
        XCTAssertEqual(plan.apps[0].notes, ["Shared leftovers kept (cannot read /Volumes/Time Machine)"])
        XCTAssertEqual(plan.summary.last, "Would remove 1 app, would free 9.2MB: Battle.net")
    }

    func testCleanFileList() {
        let text = """
        # Mole Cleanup Preview - 2026-10-17 13:26:11
        #
        #   /Users/*/Library/Caches/com.example.app

        === User essentials ===
        /Users/me/Library/Caches/GeoServices  # 52.7MB
        /Users/me/Library/Caches/Homebrew  # 117.0MB

        === Developer tools ===
        /Users/me/Library/Developer/Xcode/DerivedData/App-abc  # 1.2GB
        """
        let files = CleanFileList.parse(text)
        XCTAssertEqual(files["User essentials"]?.map(\.path),
                       ["/Users/me/Library/Caches/GeoServices", "/Users/me/Library/Caches/Homebrew"])
        XCTAssertEqual(files["Developer tools"]?.first?.size, "1.2GB")
        XCTAssertEqual(files.count, 2)
    }

    func testByteSize() {
        XCTAssertEqual(ByteSize.parse("707.2MB"), 707_200_000)
        XCTAssertEqual(ByteSize.parse("1KB"), 1_000)
        XCTAssertEqual(ByteSize.parse("0B"), 0)
        XCTAssertEqual(ByteSize.parse("5.69GB"), 5_690_000_000)
        XCTAssertNil(ByteSize.parse("N/A (Steam-managed)"))
        XCTAssertNil(ByteSize.parse("--"))
    }

    func testLineSplitterHandlesSpinnersAndColour() {
        var splitter = LineSplitter()
        let raw = "\u{1B}[0;35m➤ Browsers\u{1B}[0m\nScanning...\r\u{1B}[2K  ✓ Nothing to clean\npartial"
        let lines = splitter.feed(Data(raw.utf8))
        XCTAssertEqual(lines, ["➤ Browsers", "  ✓ Nothing to clean"])
        XCTAssertEqual(splitter.finish(), "partial")
    }

    func testFriendlyDetail() {
        XCTAssertEqual(Friendly.detail("19 items, 707.2MB dry"), "19 items, 707.2MB")
        XCTAssertNil(Friendly.detail("would clean"))
        XCTAssertEqual(Friendly.detail("skipped, grant Full Disk Access to your terminal"), "skipped, needs Full Disk Access")
        XCTAssertEqual(Friendly.detail("80+ dirs, 359.9MB+ · mo purge"), "80+ dirs, 359.9MB+")
        XCTAssertEqual(Friendly.path(in: "29.88GB · ~/Library/Developer"),
                       FileManager.default.homeDirectoryForCurrentUser.path + "/Library/Developer")
    }

    func testStatusDecodes() throws {
        let json = """
        {"host":"Mac","uptime":"2h","hardware":{"model":"Mac mini","cpu_model":"Apple M4 Pro","total_ram":"24.0 GB","os_version":"macOS 27.0.1"},
         "health_score":84,"health_score_msg":"Good: Disk Almost Full","cpu":{"usage":12.9},
         "memory":{"used":12532842496,"total":25769803776,"used_percent":48.6},
         "disks":[{"mount":"/Volumes/X","used":1,"total":2,"external":true},{"mount":"/","used":471412391936,"total":494384795648,"external":false}],
         "trash_size":0,"batteries":null,"top_processes":[{"pid":1,"name":"launchd","cpu":0.1,"memory_bytes":100}]}
        """
        let status = try JSONDecoder().decode(SystemStatus.self, from: Data(json.utf8))
        XCTAssertEqual(status.healthScore, 84)
        XCTAssertEqual(status.mainDisk?.mount, "/")
        XCTAssertEqual(status.mainDisk?.free, 494384795648 - 471412391936)
        XCTAssertNil(status.batteries)
    }
}
