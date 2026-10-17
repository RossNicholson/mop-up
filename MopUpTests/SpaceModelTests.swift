import XCTest
@testable import Mop_Up

/// Disk Space must never show files that are gone, even though Mole's scan
/// cache still lists a changed folder for up to 30 minutes
@MainActor
final class SpaceModelTests: XCTestCase {
    private var dir: URL!

    override func setUp() async throws {
        dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("MopUpTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("sub"), withIntermediateDirectories: true)
        try Data(count: 3_000_000).write(to: dir.appendingPathComponent("sub/keep.bin"))
        try Data(count: 5_000_000).write(to: dir.appendingPathComponent("gone.bin"))
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testFileDeletedElsewhereDisappears() async throws {
        let first = SpaceModel(engine: .bundled)
        await first.open(dir.path)
        XCTAssertTrue(first.current?.entries.contains { $0.name == "gone.bin" } == true)

        // Deleted in Finder, so Mole's cache still remembers it
        try FileManager.default.removeItem(at: dir.appendingPathComponent("gone.bin"))

        let second = SpaceModel(engine: .bundled)
        await second.open(dir.path)
        let scan = try XCTUnwrap(second.current)
        XCTAssertEqual(scan.entries.map(\.name), ["sub"])
        XCTAssertLessThan(scan.totalSize ?? .max, 4_500_000, "the total must not still count the deleted file")
    }
}
