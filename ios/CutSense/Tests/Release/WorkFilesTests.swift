import XCTest
@testable import CutSense

@MainActor
final class WorkFilesTests: XCTestCase {
    private var created: [URL] = []

    override func tearDown() async throws {
        for url in created { try? FileManager.default.removeItem(at: url) }
        created = []
    }

    private func make(_ name: String, in dir: URL = FileManager.default.temporaryDirectory, bytes: Int = 16) throws -> URL {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appending(path: name)
        try Data(count: bytes).write(to: url)
        created.append(url)
        return url
    }

    private func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    func testUnmanagedFilesSurviveDeleteAndEnd() throws {
        let fixture = try make("fixture-\(UUID().uuidString).mp4")
        XCTAssertFalse(WorkFiles.isManaged(fixture))
        WorkFiles.delete(fixture)
        XCTAssertTrue(exists(fixture))
        let session = WorkSession()
        session.begin(input: fixture)
        session.setOutput(fixture)
        session.end()
        XCTAssertTrue(exists(fixture))
    }

    func testSweepAtLaunchRemovesManagedAndLegacyInputs() throws {
        let imported = try make("\(UUID().uuidString).mov", in: WorkFiles.importsDirectory)
        let export = try make("cutsense-\(UUID().uuidString).mp4")
        let legacy = try make("input-\(UUID().uuidString).mov")
        let other = try make("keep-\(UUID().uuidString).mov")
        WorkFiles.sweepAtLaunch()
        XCTAssertFalse(exists(imported))
        XCTAssertFalse(exists(export))
        XCTAssertFalse(exists(legacy))
        XCTAssertTrue(exists(other))
    }

    func testDiscardOutputKeepsInput() throws {
        let input = try make("\(UUID().uuidString).mov", in: WorkFiles.importsDirectory)
        let output = try make("cutsense-\(UUID().uuidString).mp4")
        let session = WorkSession()
        session.begin(input: input)
        session.setOutput(output)
        session.discardOutput()
        XCTAssertFalse(exists(output))
        XCTAssertTrue(exists(input))
        XCTAssertNil(session.outputURL)
    }

    func testSecondSetOutputDeletesFirst() throws {
        let first = try make("cutsense-\(UUID().uuidString).mp4")
        let second = try make("cutsense-\(UUID().uuidString).mp4")
        let session = WorkSession()
        session.setOutput(first)
        session.setOutput(second)
        XCTAssertFalse(exists(first))
        XCTAssertTrue(exists(second))
    }

    func testEndRemovesInputAndOutput() throws {
        let input = try make("\(UUID().uuidString).mov", in: WorkFiles.importsDirectory)
        let output = try make("cutsense-\(UUID().uuidString).mp4")
        let session = WorkSession()
        session.begin(input: input)
        session.setOutput(output)
        XCTAssertEqual(session.urlsInUse.count, 2)
        session.end()
        XCTAssertFalse(exists(input))
        XCTAssertFalse(exists(output))
        XCTAssertTrue(session.urlsInUse.isEmpty)
    }

    func testClearUnusedKeepsInUseAndReturnsFreedBytes() throws {
        WorkFiles.sweepAtLaunch()
        let kept = try make("cutsense-\(UUID().uuidString).mp4", bytes: 1000)
        let a = try make("\(UUID().uuidString).mov", in: WorkFiles.importsDirectory, bytes: 2000)
        let b = try make("cutsense-\(UUID().uuidString).mp4", bytes: 3000)
        let freed = WorkFiles.clearUnused(keeping: [kept])
        XCTAssertEqual(freed, 5000)
        XCTAssertTrue(exists(kept))
        XCTAssertFalse(exists(a))
        XCTAssertFalse(exists(b))
    }

    func testUsageBytesMatchesWrittenBytes() throws {
        let before = WorkFiles.usageBytes()
        _ = try make("cutsense-\(UUID().uuidString).mp4", bytes: 4096)
        _ = try make("\(UUID().uuidString).mov", in: WorkFiles.importsDirectory, bytes: 1024)
        XCTAssertEqual(WorkFiles.usageBytes() - before, 5120)
        XCTAssertGreaterThan(WorkFiles.availableBytes(), 0)
    }
}
