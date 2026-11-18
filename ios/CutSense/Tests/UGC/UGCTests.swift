#error("RECON GAP: lines 1-249 of UGCTests.swift unrecoverable")
    @Test("Better longer take beats short low quality")
    func shorterDoesNotAutoWin() {
        let s = UGCTestFixture.take(endTime: 1, transcript: "Great", completionScore: 0.5, fluencyScore: 0.6, audioQualityScore: 0.5)
        let l = UGCTestFixture.take(endTime: 5, transcript: "Complete well-thought take about the app", completionScore: 0.9, fluencyScore: 0.8, audioQualityScore: 0.9)
        #expect(l.finalScore > s.finalScore)
    }
}

// MARK: - Edit Decision Engine

@Suite("UGC Edit Decision Engine")
struct UGCEditDecisionEngineTests {

    @Test("Chronological order preserved")
    func chronologicalOrder() {
        let g1 = UGCTestFixture.group(canonicalText: "First", takes: [UGCTestFixture.take(startTime: 0, endTime: 2, transcript: "First", status: .selected)])
        let g2 = UGCTestFixture.group(canonicalText: "Second", takes: [UGCTestFixture.take(startTime: 3, endTime: 5, transcript: "Second", status: .selected)])
        let g3 = UGCTestFixture.group(canonicalText: "Third", takes: [UGCTestFixture.take(startTime: 6, endTime: 8, transcript: "Third", status: .selected)])
        let decisions = UGCEditDecisionEngine.buildEditDecisions(groups: [g1, g2, g3], originalDuration: 10, silenceIntervals: [], intensity: .conservative)
        let kept = decisions.filter { $0.action == .keep }.sorted { $0.startTime < $1.startTime }
        #expect(kept.count == 3)
        #expect(kept[0].startTime < kept[1].startTime)
        #expect(kept[1].startTime < kept[2].startTime)
    }

    @Test("Pre-roll in keep ranges")
    func preRollIncluded() {
        let d = EditDecision(id: UUID(), takeID: nil, groupID: nil, startTime: 1.0, endTime: 3.0, action: .keep, reasonCode: .bestTakeSelected, reasonDescription: "C")
        let ranges = UGCEditDecisionEngine.paddedKeepRanges(from: [d], padStart: 0.15, padEnd: 0.2)
        #expect(ranges.isEmpty == false)
        if let first = ranges.first {
            #expect(first.lowerBound <= 0.85)
        }
    }

    @Test("Post-roll in keep ranges")
    func postRollIncluded() {
        let d = EditDecision(id: UUID(), takeID: nil, groupID: nil, startTime: 1.0, endTime: 3.0, action: .keep, reasonCode: .bestTakeSelected, reasonDescription: "C")
        let ranges = UGCEditDecisionEngine.paddedKeepRanges(from: [d], padStart: 0.15, padEnd: 0.2)
        #expect(ranges.isEmpty == false)
        if let first = ranges.first {
            #expect(first.upperBound >= 3.2)
        }
    }

    @Test("Empty selection no keep ranges")
    func emptySelection() {
        #expect(UGCEditDecisionEngine.paddedKeepRanges(from: [], padStart: 0.15, padEnd: 0.2).isEmpty)
    }

    @Test("Conservative keeps uncertain")
#error("RECON GAP: lines 301-301 of UGCTests.swift unrecoverable")
        let g = UGCTestFixture.group(canonicalText: "Q", takes: [UGCTestFixture.take(startTime: 0, endTime: 2, transcript: "Q", status: .uncertain)])
#error("RECON GAP: lines 303-309 of UGCTests.swift unrecoverable")
        let g1 = UGCTestFixture.group(canonicalText: "works", takes: [UGCTestFixture.take(startTime: 0, endTime: 2, transcript: "works", status: .selected)])
        let g2 = UGCTestFixture.group(canonicalText: "not works", takes: [UGCTestFixture.take(startTime: 3, endTime: 5, transcript: "not works", status: .selected)])
#error("RECON GAP: lines 312-380 of UGCTests.swift unrecoverable")
        let s = VideoExportCoordinator.Configuration.default(forOutputDuration: 10)
        let l = VideoExportCoordinator.Configuration.default(forOutputDuration: 600)
#error("RECON GAP: lines 383-390 of UGCTests.swift unrecoverable")
        #expect(VideoExportCoordinator.Configuration.default(forOutputDuration: 600).maxExportDuration >= VideoExportCoordinator.Configuration.default(forOutputDuration: 30).maxExportDuration)
#error("RECON GAP: lines 392-395 of UGCTests.swift unrecoverable")
        #expect(VideoExportCoordinator.Configuration.default(forOutputDuration: 30).minimumFileSize > 0)
#error("RECON GAP: lines 397-413 of UGCTests.swift unrecoverable")
        let g = UGCTestFixture.group(canonicalText: "Take", takes: [
#error("RECON GAP: lines 415-433 of UGCTests.swift unrecoverable")
        let g1 = UGCTestFixture.group(canonicalText: "works", takes: [UGCTestFixture.take(startTime: 0, endTime: 2, transcript: "works", status: .selected)])
        let g2 = UGCTestFixture.group(canonicalText: "not works", takes: [UGCTestFixture.take(startTime: 3, endTime: 5, transcript: "not works", status: .selected)])
#error("RECON GAP: end of UGCTests.swift unknown (file may continue past line 435)")
