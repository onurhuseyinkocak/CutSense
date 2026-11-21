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
        let mask = WaveformTimeline.cutMask(count: 84, plan: plan)
        XCTAssertTrue(mask[10] && mask[19])
        XCTAssertFalse(mask[9] || mask[20] || mask[45], "restored cuts and untouched slots stay kept")
    }
}
