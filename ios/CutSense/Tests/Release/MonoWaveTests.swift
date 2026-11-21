import XCTest
@testable import CutSense

final class MonoWaveTests: XCTestCase {
    func testEmptyInputGivesFloorBars() {
        XCTAssertEqual(MonoWave.bars(from: []), Array(repeating: 0.06, count: 84))
        XCTAssertEqual(MonoWave.bars(from: [], count: 10).count, 10)
    }

    func testAllZerosStayAtFloor() {
        XCTAssertEqual(MonoWave.bars(from: Array(repeating: 0, count: 500)), Array(repeating: 0.06, count: 84))
    }

    func testCountAndRange() {
        for input in [(0..<1000).map { Float(abs(sin(Double($0) * 0.05))) * 0.3 }, [0.2, 0.5, 0.01]] {
            let bars = MonoWave.bars(from: input)
            XCTAssertEqual(bars.count, 84, "fewer samples than bars still yields count bars")
            XCTAssertTrue(bars.allSatisfy { $0 >= 0.06 && $0 <= 1 })
            XCTAssertEqual(bars.max(), 1)
        }
    }

    func testRampIsNonDecreasing() {
        let bars = MonoWave.bars(from: (0..<840).map { Float($0) / 840 })
        XCTAssertEqual(zip(bars, bars.dropFirst()).filter { $0 > $1 }.count, 0)
        XCTAssertLessThan(bars[0], bars[42])
    }

    func testCutMaskMarksCoveredSlots() {
        let plan = QuickSilenceEngine.CutPlan(duration: 84, cuts: [
            .init(id: 0, range: 10...20, isRestored: false),
            .init(id: 1, range: 40...50, isRestored: true),
        ])
        let cover = WaveformTimeline.coverage(count: 84, plan: plan)
        XCTAssertEqual(cover[10], 1)
        XCTAssertEqual(cover[19], 1)
        XCTAssertEqual(cover[9] + cover[20] + cover[45], 0, "restored cuts and untouched slots stay kept")
    }

    func testCoverageScalesWithVideoLength() {
        // 10-min video: a 0.4 s pause in a ~7.1 s slot barely dims it (the old midpoint rule dimmed it fully).
        let long = QuickSilenceEngine.CutPlan(duration: 600, cuts: [.init(id: 0, range: 101...101.4, isRestored: false)])
        let longCover = WaveformTimeline.coverage(count: 84, plan: long)
        XCTAssertEqual(longCover[14], 0.4 / (600.0 / 84), accuracy: 1e-9)
        XCTAssertEqual(longCover.filter { $0 > 0 }.count, 1)

        // 10-s video: a 2 s pause still fully dims the slots it spans.
        let short = QuickSilenceEngine.CutPlan(duration: 10, cuts: [.init(id: 0, range: 3...5, isRestored: false)])
        let shortCover = WaveformTimeline.coverage(count: 84, plan: short)
        XCTAssertEqual(shortCover[30], 1, accuracy: 1e-9)
        XCTAssertEqual(shortCover[0], 0)

        // Kept share across slots equals the plan's kept share, so compaction matches the real cut ratio.
        for plan in [long, short] {
            let kept = WaveformTimeline.coverage(count: 84, plan: plan).reduce(0) { $0 + (1 - $1) } / 84
            XCTAssertEqual(kept, plan.outputDuration / plan.duration, accuracy: 1e-9)
        }
    }
}
