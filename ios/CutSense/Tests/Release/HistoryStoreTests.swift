import XCTest
@testable import CutSense

@MainActor
final class HistoryStoreTests: XCTestCase {
    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "history-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func entry(original: Double = 60, output: Double = 45, date: Date = Date()) -> HistoryEntry {
        HistoryEntry(id: UUID(), date: date, originalDuration: original, outputDuration: output,
                     removedPercent: Int((1 - output / original) * 100), intensity: "balanced",
                     isCustom: false, resolution: "1080p", hasThumbnail: true)
    }

    private let thumb = Data(repeating: 0xAB, count: 1_000)
    private var jsonURL: URL { directory.appending(path: "history.json") }
    private var thumbsURL: URL { directory.appending(path: "thumbs") }
    private func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }
    private func thumbFiles() -> [URL] { (try? FileManager.default.contentsOfDirectory(at: thumbsURL, includingPropertiesForKeys: nil)) ?? [] }

    func testAddPutsNewestFirstAndSumsRemovedSeconds() {
        let store = HistoryStore(directory: directory)
        let first = entry(original: 60, output: 45)
        let second = entry(original: 100, output: 70)
        store.add(first, thumbnail: thumb)
        store.add(second, thumbnail: nil)
        XCTAssertEqual(store.entries.map(\.id), [second.id, first.id])
        XCTAssertEqual(store.removedSeconds, 45, accuracy: 0.001)
        XCTAssertTrue(store.entries[1].hasThumbnail)
        XCTAssertFalse(store.entries[0].hasThumbnail)
        XCTAssertTrue(exists(store.thumbnailURL(for: first.id)))
    }

    func testCapDropsOldestWithThumbnails() {
        let store = HistoryStore(directory: directory)
        let added = (0..<205).map { _ in entry() }
        for item in added { store.add(item, thumbnail: thumb) }
        XCTAssertEqual(store.entries.count, HistoryStore.cap)
        XCTAssertEqual(store.entries.first?.id, added.last?.id)
        for dropped in added.prefix(5) {
            XCTAssertFalse(exists(store.thumbnailURL(for: dropped.id)))
            XCTAssertFalse(store.entries.contains { $0.id == dropped.id })
        }
        XCTAssertEqual(thumbFiles().count, HistoryStore.cap)
    }

    func testDeleteRemovesEntryAndThumbnail() {
        let store = HistoryStore(directory: directory)
        let item = entry()
        store.add(item, thumbnail: thumb)
        store.delete(id: item.id)
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertFalse(exists(store.thumbnailURL(for: item.id)))
    }

    func testClearEmptiesJSONAndThumbs() throws {
        let store = HistoryStore(directory: directory)
        for _ in 0..<3 { store.add(entry(), thumbnail: thumb) }
        store.clear()
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertTrue(thumbFiles().isEmpty)
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: jsonURL)) as? [String: Any]
        XCTAssertEqual((json?["entries"] as? [Any])?.count, 0)
    }

    func testPersistsAcrossInstances() {
        let store = HistoryStore(directory: directory)
        // Whole seconds: JSON round-trips Date at sub-millisecond precision loss otherwise.
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        store.add(entry(date: date), thumbnail: thumb)
        store.add(entry(date: date), thumbnail: nil)
        XCTAssertEqual(HistoryStore(directory: directory).entries, store.entries)
    }

    func testCorruptFileStartsEmptyAndRecovers() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json {".utf8).write(to: jsonURL)
        let store = HistoryStore(directory: directory)
        XCTAssertTrue(store.entries.isEmpty)
        store.add(entry(), thumbnail: nil)
        XCTAssertEqual(HistoryStore(directory: directory).entries.count, 1)
    }

    func testOrphanThumbnailRemovedOnLoad() throws {
        let store = HistoryStore(directory: directory)
        let kept = entry()
        store.add(kept, thumbnail: thumb)
        let orphan = store.thumbnailURL(for: UUID())
        try thumb.write(to: orphan)
        _ = HistoryStore(directory: directory)
        XCTAssertFalse(exists(orphan))
        XCTAssertTrue(exists(store.thumbnailURL(for: kept.id)))
    }

    func testBudgets() throws {
        let store = HistoryStore(directory: directory)
        let big = entry()
        store.add(big, thumbnail: Data(count: HistoryStore.maxThumbnailBytes + 1))
        XCTAssertFalse(store.entries[0].hasThumbnail)
        XCTAssertFalse(exists(store.thumbnailURL(for: big.id)))

        for _ in 0..<HistoryStore.cap { store.add(entry(), thumbnail: nil) }
        let size = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: jsonURL.path)[.size] as? Int)
        XCTAssertLessThan(size, 64_000)
    }

    func testDirectoryExcludedFromBackup() throws {
        _ = HistoryStore(directory: directory)
        XCTAssertEqual(try directory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
    }
}
