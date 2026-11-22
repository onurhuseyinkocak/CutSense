import XCTest
@testable import CutSense

final class KeepGateTests: XCTestCase {
    private func plan(kept: Int, total: Int = 5) -> QuickSilenceEngine.CutPlan {
        QuickSilenceEngine.CutPlan(duration: 60, cuts: (0..<total).map {
            .init(id: $0, range: Double($0 * 10)...Double($0 * 10 + 2), isRestored: $0 < kept)
        })
    }

    func testFreeUserCanKeepUpToThree() {
        XCTAssertEqual(KeepGate.freeLimit, 3)
        for kept in 0..<3 { XCTAssertTrue(KeepGate.canKeepAnother(plan(kept: kept), limited: true), "\(kept) kept") }
        XCTAssertFalse(KeepGate.canKeepAnother(plan(kept: 3), limited: true))
        // An intensity change can carry more than three keeps over; still no new keep.
        XCTAssertFalse(KeepGate.canKeepAnother(plan(kept: 4), limited: true))
    }

    func testUnlimitedAlwaysAllowed() {
        for kept in 0...5 { XCTAssertTrue(KeepGate.canKeepAnother(plan(kept: kept), limited: false)) }
    }

    func testCuttingOneBackReopensTheSlot() {
        var p = plan(kept: 3)
        XCTAssertFalse(KeepGate.canKeepAnother(p, limited: true))
        p.cuts[0].isRestored = false
        XCTAssertTrue(KeepGate.canKeepAnother(p, limited: true))
    }
}
