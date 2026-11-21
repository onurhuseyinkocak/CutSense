import XCTest
import AVFoundation
@testable import CutSense

final class QuickSilencePlanTests: XCTestCase {
    private static var fixtureURL: URL {
        get throws {
            try XCTUnwrap(Bundle(for: QuickSilencePlanTests.self).url(forResource: "silence_fixture", withExtension: "mp4"))
        }
    }

    private static func fixturePlan(_ intensity: QuickSilenceEngine.CutIntensity = .tight) async throws -> QuickSilenceEngine.CutPlan {
        let analysis = try await QuickSilenceEngine.analyze(url: try Self.fixtureURL, language: .en) { _ in }
        return try QuickSilenceEngine.plan(analysis, settings: .init(intensity))
    }

    func testPlanFindsFourCutsForEveryIntensity() async throws {
        let analysis = try await QuickSilenceEngine.analyze(url: try Self.fixtureURL, language: .en) { _ in }
        for intensity in QuickSilenceEngine.CutIntensity.allCases {
            let plan = try QuickSilenceEngine.plan(analysis, settings: .init(intensity))
            // Hardcore may also take one sub-0.2 s breath mid-sentence; the four 2.5 s pauses must always be cut.
            let pauses = plan.cuts.filter { $0.range.upperBound - $0.range.lowerBound > 1 }
            XCTAssertEqual(pauses.count, 4, "\(intensity): \(plan.cuts.map(\.range))")
            if intensity != .hardcore { XCTAssertEqual(plan.cuts.count, 4, "\(intensity)") }
        }
    }

    func testRestoringCutAddsItsLength() async throws {
        var plan = try await Self.fixturePlan()
        let before = plan.outputDuration
        let keepCount = plan.keepRanges.count
        let cut = plan.cuts[1].range
        plan.cuts[1].isRestored = true
        XCTAssertEqual(plan.outputDuration - before, cut.upperBound - cut.lowerBound, accuracy: 1e-9)
        XCTAssertEqual(plan.keepRanges.count, keepCount - 1)  // cuts[1] is inner: two keeps join
    }

    func testOutputTimeBeforeInsideAndAfterCut() {
        let plan = QuickSilenceEngine.CutPlan(duration: 10, cuts: [
            .init(id: 0, range: 2...4, isRestored: false),
            .init(id: 1, range: 6...7, isRestored: true)
        ])
        XCTAssertEqual(plan.outputTime(forOriginal: 1), 1, accuracy: 1e-9)
        XCTAssertEqual(plan.outputTime(forOriginal: 3), 2, accuracy: 1e-9)
        XCTAssertEqual(plan.outputTime(forOriginal: 5), 3, accuracy: 1e-9)
        XCTAssertEqual(plan.outputTime(forOriginal: 6.5), 4.5, accuracy: 1e-9)  // restored cut is kept
        XCTAssertEqual(plan.outputDuration, 8, accuracy: 1e-9)
        XCTAssertEqual(plan.removedPercent, 20)
    }

    func testPlanRejectsSilence() {
        let analysis = QuickSilenceEngine.Analysis(windowRMS: Array(repeating: 0, count: 100), duration: 5)
        XCTAssertThrowsError(try QuickSilenceEngine.plan(analysis, settings: .init(.tight)))
    }

    func testExportWithRestoredCutMatchesPlanAndLeavesOneFile() async throws {
        var plan = try await Self.fixturePlan()
        plan.cuts[0].isRestored = true
        let tmp = FileManager.default.temporaryDirectory
        let managed = { Set((try? FileManager.default.contentsOfDirectory(atPath: tmp.path))?.filter { $0.hasPrefix("cutsense-") } ?? []) }
        let before = managed()
        let result = try await QuickSilenceEngine.export(url: try Self.fixtureURL, plan: plan, language: .en) { _ in }
        defer { try? FileManager.default.removeItem(at: result.outputURL) }
        XCTAssertEqual(managed().subtracting(before), [result.outputURL.lastPathComponent])
        let out = try await AVURLAsset(url: result.outputURL).load(.duration).seconds
        XCTAssertEqual(out, plan.outputDuration, accuracy: 0.2)
    }

    @MainActor
    func testPreviewItemMatchesPlanDuration() async throws {
        let plan = try await Self.fixturePlan(.balanced)
        let item = try await QuickSilenceEngine.makePreviewItem(url: try Self.fixtureURL, plan: plan)
        let duration = try await item.asset.load(.duration).seconds
        XCTAssertEqual(duration, plan.outputDuration, accuracy: 0.05)
    }
}
