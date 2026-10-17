import XCTest
@testable import Mop_Up

/// Runs the bundled Mole for real, with read-only commands only (status, app
/// list, previews), to catch a Mole update that changes its output.
final class EngineTests: XCTestCase {
    let engine = MoleEngine.bundled

    func testEngineIsBundled() {
        XCTAssertTrue(engine.isAvailable, "Mole should be in the app's Resources")
        XCTAssertNotEqual(engine.version, "?")
    }

    func testStatus() async throws {
        let status = try await engine.json(SystemStatus.self, ["status", "--json"])
        XCTAssertNotNil(status.healthScore)
        XCTAssertNotNil(status.mainDisk)
    }

    func testAppList() async throws {
        let apps = try await engine.json([InstalledApp].self, ["uninstall", "--list"])
        XCTAssertFalse(apps.isEmpty)
        XCTAssertTrue(apps.allSatisfy { !$0.uninstallName.isEmpty && $0.path.hasSuffix(".app") })
    }

    func testAnalyzeFolder() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mopup-analyze-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("sub"), withIntermediateDirectories: true)
        try Data(count: 50_000).write(to: dir.appendingPathComponent("sub/big.bin"))
        try Data(count: 10).write(to: dir.appendingPathComponent("small.txt"))
        defer { try? FileManager.default.removeItem(at: dir) }

        let scan = try await engine.json(DiskScan.self, ["analyze", "--json", dir.path])
        XCTAssertEqual(Set(scan.entries.map(\.name)), ["sub", "small.txt"])
        XCTAssertEqual(scan.entries.first { $0.name == "sub" }?.isDir, true)
    }

    func testOptimizePreviewParses() async throws {
        let output = try await engine.run(["optimize", "--dry-run"])
        let report = MoleReport.parse(output.lines)
        XCTAssertGreaterThan(report.sections.count, 5, output.text)
        XCTAssertFalse(report.summary.isEmpty, output.text)
    }

    func testCleanPreviewParses() async throws {
        let output = try await engine.run(["clean", "--dry-run"])
        let report = MoleReport.parse(output.lines)
        XCTAssertTrue(report.sections.contains { $0.title == "User essentials" }, output.text)
        XCTAssertNotNil(report.headline, output.text)
    }

    func testCancelStopsMole() async throws {
        let engine = self.engine
        let task = Task { try await engine.run(["clean", "--dry-run"]) }
        try await Task.sleep(for: .seconds(2))
        let started = Date()
        task.cancel()
        _ = try? await task.value
        XCTAssertLessThan(Date().timeIntervalSince(started), 10)
    }
}
