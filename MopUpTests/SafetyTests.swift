import XCTest
@testable import Mop_Up

/// A stand-in for Mole: a bash script in a temporary folder, so these tests
/// can act out cancelling, uninstalling and failures without touching the Mac
private struct FakeMole {
    let root: URL
    var engine: MoleEngine { MoleEngine(root: root) }
    var log: URL { root.appendingPathComponent("calls.log") }

    init(_ script: String) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("fake-mole-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try ("LOG=\"\(root.path)/calls.log\"\n" + script).write(to: root.appendingPathComponent("mole"), atomically: true, encoding: .utf8)
    }

    func calls() -> [String] {
        ((try? String(contentsOf: log, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
}

private func app(_ name: String, _ path: String, homebrew: Bool = false, token: String? = nil) -> InstalledApp {
    InstalledApp(name: name, bundleID: nil, source: homebrew ? "Homebrew" : "App",
                 uninstallName: token ?? name, path: path, size: "10MB")
}

final class EngineSafetyTests: XCTestCase {
    func testCancelStopsWhatMoleIsWaitingOn() async throws {
        // Mole waiting on a long command: cancelling has to stop that too,
        // or the command keeps the output open and the job never ends
        let fake = try FakeMole("echo start\nsleep 30\necho end\n")
        defer { fake.remove() }
        let engine = fake.engine
        let task = Task { try await engine.run(["clean"]) }
        try await Task.sleep(for: .milliseconds(500))
        let started = Date()
        task.cancel()
        _ = try? await task.value
        XCTAssertLessThan(Date().timeIntervalSince(started), 6)
    }

    func testCancelledBeforeStartingNeverStarts() async throws {
        let fake = try FakeMole("echo ran >> \"$LOG\"\n")
        defer { fake.remove() }
        let engine = fake.engine
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await engine.run(["clean"])
        }
        do {
            _ = try await task.value
            XCTFail("a cancelled run shouldn't succeed")
        } catch is CancellationError {}
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(fake.calls(), [], "Mole never ran")
    }

    func testFinishesWhenSomethingKeepsTheOutputOpen() async throws {
        // A background process Mole started outlives it with the pipe open
        let fake = try FakeMole("(sleep 20 &)\necho done\n")
        defer { fake.remove() }
        let started = Date()
        let output = try await fake.engine.run(["status"])
        XCTAssertEqual(output.lines, ["done"])
        XCTAssertLessThan(Date().timeIntervalSince(started), 6)
    }
}

@MainActor
final class StatusStreamTests: XCTestCase {
    func testStreamRestartsAfterMoleStops() async throws {
        let fake = try FakeMole("""
        if [[ "$*" == *--watch* ]]; then echo watch >> "$LOG"; echo '{"health_score": 90}'; exit 1; fi
        echo '{"health_score": 90}'
        """)
        defer { fake.remove() }
        let model = StatusModel(engine: fake.engine)
        model.restartDelay = .milliseconds(200)
        model.startWatching()
        defer { model.stopWatching() }
        for _ in 0..<50 where fake.calls().count < 2 {
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertGreaterThanOrEqual(fake.calls().count, 2, "the stream started again after Mole stopped")
    }
}

final class UninstallSafetyTests: XCTestCase {
    let chrome = app("Google Chrome", "/Applications/Google Chrome.app", homebrew: true, token: "google-chrome")
    let roblox = app("Roblox Studio", "/Applications/RobloxStudio.app")
    let foo = app("Foo", "/Applications/Foo.app")
    let fooToo = app("Foo", "/Users/me/Applications/Foo.app")
    let notesPro = app("Notes Pro", "/Applications/Notes.app")
    let notes = app("Notes", "/Applications/Notes Classic.app")

    var all: [InstalledApp] { [chrome, roblox, foo, fooToo, notesPro, notes] }

    func testTermsAreNamesMoleMatchesExactly() throws {
        // A cask token like "google-chrome" matches nothing in Mole; the folder name does
        let terms = try UninstallModel.terms(for: [chrome, roblox], among: all).get()
        XCTAssertEqual(terms, ["Google Chrome", "RobloxStudio"])
    }

    func testAFolderNameAnotherAppUsesFallsBackToTheAppName() throws {
        // "Notes" is Notes Pro's folder and the other app's name
        XCTAssertEqual(try UninstallModel.terms(for: [notesPro], among: all).get(), ["Notes Pro"])
    }

    func testTwoAppsWithTheSameNameAreRefused() {
        guard case let .failure(problem) = UninstallModel.terms(for: [fooToo], among: all) else {
            return XCTFail("Mole could pick either copy")
        }
        XCTAssertTrue(problem.message.contains("same name"))
    }

    func testAnAppThatsGoneIsRefused() {
        guard case .failure = UninstallModel.terms(for: [roblox], among: [chrome]) else {
            return XCTFail("its name could match something else now")
        }
    }

    static let plan = UninstallPlan.parse("""
    ◎ Matched 2 app(s):
    1. Google Chrome  779.9MB  |  Last: 4d ago
    2. Roblox Studio  1.15GB  |  Last: 2w ago
    Files to be removed:
    ◎ Google Chrome [Brew] , 779.9MB
      ✓ /Applications/Google Chrome.app , 779.9MB
      ✓ ~/Library/Application Support/Google/Chrome , 1.1GB
    ◎ Roblox Studio , 1.15GB
      ✓ /Applications/RobloxStudio.app , 1.15GB
    """.components(separatedBy: "\n"))

    func testPlanReadsHomebrewApps() {
        XCTAssertEqual(Self.plan.apps.map(\.name), ["Google Chrome", "Roblox Studio"])
        XCTAssertEqual(Self.plan.apps.map(\.isHomebrew), [true, false])
    }

    func testPlanMustBeExactlyTheChosenApps() {
        XCTAssertNil(UninstallModel.mismatch(Self.plan, chosen: [chrome, roblox]))
        XCTAssertNotNil(UninstallModel.mismatch(Self.plan, chosen: [chrome]), "it lists an app that wasn't picked")
        XCTAssertNotNil(UninstallModel.mismatch(Self.plan, chosen: [chrome, roblox, foo]), "it left one out")
    }

    private func output(_ text: String, code: Int32 = 0) -> MoleEngine.Output {
        MoleEngine.Output(exitCode: code, lines: text.components(separatedBy: "\n"))
    }

    private let rule = String(repeating: "=", count: 70)

    func testOutcomeReadsMolesSummary() {
        let done = UninstallModel.outcome(output("\(rule)\nUninstall complete\nRemoved 1 app, freed 1.1GB: RobloxStudio\n\(rule)"), removing: [roblox])
        guard case let .done(_, complete, homebrew) = done else { return XCTFail("\(done)") }
        XCTAssertTrue(complete)
        XCTAssertEqual(homebrew, [])

        let partial = UninstallModel.outcome(output("\(rule)\nUninstall incomplete\n◎ Failed: Google Chrome could not be removed\n\(rule)"), removing: [chrome])
        guard case let .done(_, partlyComplete, brew) = partial else { return XCTFail("\(partial)") }
        XCTAssertFalse(partlyComplete)
        XCTAssertEqual(brew, ["Google Chrome"])
    }

    func testNothingRemovedIsAFailure() {
        for text in ["Warning: No application found matching 'Foo'\nNo matching applications found.",
                     "Proceed with uninstallation? [y/N] Aborted.",
                     "☻ Admin access denied",
                     "\(rule)\nUninstall complete\nNo applications were uninstalled.\n\(rule)"] {
            guard case .failed = UninstallModel.outcome(output(text), removing: [foo]) else {
                return XCTFail("should fail: \(text)")
            }
        }
    }
}

@MainActor
final class UninstallFlowTests: XCTestCase {
    /// Lists two apps, plans whatever it's given, and logs real removals
    private func fakeUninstaller() throws -> FakeMole {
        try FakeMole("""
        if [[ "$2" == "--list" ]]; then
          echo '[{"name": "Alpha", "bundle_id": "a", "source": "App", "uninstall_name": "Alpha", "path": "/Applications/Alpha.app", "size": "1MB"},'
          echo ' {"name": "Beta", "bundle_id": "b", "source": "App", "uninstall_name": "Beta", "path": "/Applications/Beta.app", "size": "1MB"}]'
          exit 0
        fi
        if [[ "$2" == "--dry-run" ]]; then
          sleep 1
          echo "Files to be removed:"
          for name in "${@:3}"; do echo "◎ $name , 1MB"; echo "  ✓ /Applications/$name.app , 1MB"; done
          exit 0
        fi
        echo "remove ${*:2}" >> "$LOG"
        echo "======================================================================"
        echo "Uninstall complete"
        echo "Removed 1 app, freed 1MB: ${*:2}"
        echo "======================================================================"
        """)
    }

    func testOnlyTheConfirmedAppsAreRemoved() async throws {
        let fake = try fakeUninstaller()
        defer { fake.remove() }
        let model = UninstallModel(engine: fake.engine, jobs: JobGate())
        await model.load()
        let alpha = try XCTUnwrap(model.apps.first { $0.name == "Alpha" })
        let beta = try XCTUnwrap(model.apps.first { $0.name == "Beta" })
        model.selection = [alpha.id]
        model.plan()
        XCTAssertFalse(model.canChangeSelection)
        // Ticked while the plan was being made: it was never shown, so it stays
        model.selection.insert(beta.id)
        for _ in 0..<50 {
            if case .confirm = model.phase { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        guard case let .confirm(plan, apps) = model.phase else { return XCTFail("\(model.phase)") }
        XCTAssertEqual(plan.apps.map(\.name), ["Alpha"])
        XCTAssertEqual(apps.map(\.name), ["Alpha"])

        model.remove()
        for _ in 0..<50 {
            if case .done = model.phase { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertEqual(fake.calls(), ["remove Alpha"])
        guard case let .done(_, complete, _) = model.phase else { return XCTFail("\(model.phase)") }
        XCTAssertTrue(complete)
    }
}

final class CleanAndTuneUpEndingTests: XCTestCase {
    private func report(_ headline: String) -> MoleReport {
        let rule = String(repeating: "=", count: 70)
        return MoleReport.parse(["➤ User essentials", "  → User app cache · 1 item, 1MB", rule, headline, rule])
    }

    func testCleanEndings() {
        XCTAssertEqual(report("Cleanup complete").ending, .finished)
        XCTAssertEqual(report("Dry run complete - no changes made").ending, .finished)
        XCTAssertEqual(report("Cleanup incomplete").ending, .incomplete)
        XCTAssertEqual(report("Dry run incomplete").ending, .incomplete)
        XCTAssertEqual(report("Cleanup interrupted").ending, .stopped)
        XCTAssertEqual(report("Dry run cancelled").ending, .stopped)
        XCTAssertEqual(MoleReport.parse(["➤ User essentials"]).ending, .incomplete, "no summary at all")
    }

    func testStalePreviews() {
        let now = Date()
        XCTAssertFalse(CleanModel.isStale(now.addingTimeInterval(-60), now: now))
        XCTAssertTrue(CleanModel.isStale(now.addingTimeInterval(-16 * 60), now: now))
    }

    func testAFileListFromAnEarlierScanIsIgnored() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("clean-list-\(UUID().uuidString).txt")
        try "=== User essentials ===\n/Users/me/Library/Caches/Old  # 1MB\n".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-3600)], ofItemAtPath: url.path)
        XCTAssertEqual(CleanFileList.load(from: url, writtenSince: Date().addingTimeInterval(-60)), [:])
        XCTAssertEqual(CleanFileList.load(from: url, writtenSince: Date().addingTimeInterval(-7200)).count, 1)
    }

    @MainActor
    func testTuneUpEndings() {
        let rule = String(repeating: "=", count: 70)
        let lines = ["➤ Finder", "  ✓ Refreshed Finder", rule, "Optimization Complete", rule]
        let finished = MoleReport.parse(lines)
        let stopped = MoleReport.parse(Array(lines.prefix(2)))
        let ok = MoleEngine.Output(exitCode: 0, lines: lines)
        let interrupted = MoleEngine.Output(exitCode: 130, lines: Array(lines.prefix(2)))

        if case let .done(_, done) = TuneUpModel.outcome(finished, output: ok, dryRun: false, cancelled: false) {
            XCTAssertTrue(done)
        } else { XCTFail("a finished tune-up") }
        if case let .done(_, done) = TuneUpModel.outcome(stopped, output: interrupted, dryRun: false, cancelled: true) {
            XCTAssertFalse(done, "cancelled partway is not 'All tuned up'")
        } else { XCTFail("a stopped tune-up still shows what ran") }
        if case .idle = TuneUpModel.outcome(stopped, output: interrupted, dryRun: true, cancelled: true) {} else {
            XCTFail("a cancelled check goes back to the start")
        }
        if case .failed = TuneUpModel.outcome(stopped, output: interrupted, dryRun: true, cancelled: false) {} else {
            XCTFail("a check that didn't finish isn't a plan")
        }
    }
}
