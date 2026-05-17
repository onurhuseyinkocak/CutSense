import Testing
import Foundation
@testable import CutSense

@Suite("TimelineMapper — source to clean coordinate remapping")
struct TimelineMapperTests {

    // MARK: - Helpers

    private func makeKeep(start: Double, end: Double) -> RoughCutDecision {
        RoughCutDecision(
            startTime: start, endTime: end, action: .keep,
            reason: "test", confidence: 0.9,
            linkedTranscriptText: nil, requiresReview: false
        )
    }

    private func makeCut(start: Double, end: Double) -> RoughCutDecision {
        RoughCutDecision(
            startTime: start, endTime: end, action: .cut,
            reason: "silence", confidence: 0.9,
            linkedTranscriptText: nil, requiresReview: false
        )
    }

    private func makeCaption(start: Double, end: Double, text: String = "test") -> CaptionSegment {
        CaptionSegment(
            startTime: start, endTime: end, text: text,
            role: .regular, style: .boldCenterViral
        )
    }

    private func makeEdit(time: Double, duration: Double = 0.5) -> EditDecision {
        EditDecision(
            time: time, duration: duration,
            type: .zoom, reason: "test", intensity: 0.5
        )
    }

    // MARK: - buildMapping

    @Test("buildMapping creates correct segments from keep decisions")
    func buildMappingBasic() {
        let decisions = [
            makeKeep(start: 0, end: 5),   // 0-5 in source → 0-5 in clean
            makeCut(start: 5, end: 8),     // 5-8 cut
            makeKeep(start: 8, end: 12),   // 8-12 in source → 5-9 in clean
        ]

        let mapping = TimelineMapper.buildMapping(from: decisions)

        #expect(mapping.count == 2)
        #expect(mapping[0].sourceStart == 0)
        #expect(mapping[0].sourceEnd == 5)
        #expect(mapping[0].cleanStart == 0)

        #expect(mapping[1].sourceStart == 8)
        #expect(mapping[1].sourceEnd == 12)
        #expect(mapping[1].cleanStart == 5)
    }

    @Test("buildMapping ignores cut and trim decisions")
    func buildMappingIgnoresNonKeep() {
        let decisions = [
            makeKeep(start: 2, end: 6),
            makeCut(start: 6, end: 10),
            RoughCutDecision(
                startTime: 10, endTime: 12, action: .trimStart,
                reason: "trim", confidence: 0.8,
                linkedTranscriptText: nil, requiresReview: false
            ),
            makeKeep(start: 12, end: 15),
        ]

        let mapping = TimelineMapper.buildMapping(from: decisions)
        #expect(mapping.count == 2)
        #expect(mapping[0].cleanStart == 0)
        #expect(mapping[1].cleanStart == 4) // 6-2 = 4s from first keep
    }

    @Test("buildMapping sorts keeps by startTime regardless of input order")
    func buildMappingSortsKeeps() {
        let decisions = [
            makeKeep(start: 10, end: 15),
            makeKeep(start: 0, end: 5),
        ]

        let mapping = TimelineMapper.buildMapping(from: decisions)
        #expect(mapping[0].sourceStart == 0)
        #expect(mapping[1].sourceStart == 10)
        #expect(mapping[1].cleanStart == 5) // after first 5s keep
    }

    @Test("buildMapping with single keep segment")
    func buildMappingSingleKeep() {
        let decisions = [makeKeep(start: 3, end: 10)]
        let mapping = TimelineMapper.buildMapping(from: decisions)

        #expect(mapping.count == 1)
        #expect(mapping[0].cleanStart == 0)
        #expect(mapping[0].duration == 7)
    }

    @Test("buildMapping empty decisions produces empty mapping")
    func buildMappingEmpty() {
        let mapping = TimelineMapper.buildMapping(from: [])
        #expect(mapping.isEmpty)
    }

    // MARK: - mapToClean

    @Test("mapToClean maps time within first keep segment")
    func mapToCleanFirstSegment() {
        let decisions = [
            makeKeep(start: 0, end: 5),
            makeCut(start: 5, end: 8),
            makeKeep(start: 8, end: 12),
        ]
        let mapping = TimelineMapper.buildMapping(from: decisions)

        let result = TimelineMapper.mapToClean(2.5, mapping: mapping)
        #expect(result == 2.5)
    }

    @Test("mapToClean maps time within second keep segment with offset")
    func mapToCleanSecondSegment() {
        let decisions = [
            makeKeep(start: 0, end: 5),
            makeCut(start: 5, end: 8),
            makeKeep(start: 8, end: 12),
        ]
        let mapping = TimelineMapper.buildMapping(from: decisions)

        // Source time 10.0 is 2s into the second keep (8-12)
        // Clean start of second = 5, offset = 10-8 = 2 → clean time = 7
        let result = TimelineMapper.mapToClean(10.0, mapping: mapping)
        #expect(result == 7.0)
    }

    @Test("mapToClean returns nil for time in cut region")
    func mapToCleanCutRegion() {
        let decisions = [
            makeKeep(start: 0, end: 5),
            makeCut(start: 5, end: 8),
            makeKeep(start: 8, end: 12),
        ]
        let mapping = TimelineMapper.buildMapping(from: decisions)

        let result = TimelineMapper.mapToClean(6.5, mapping: mapping)
        #expect(result == nil)
    }

    @Test("mapToClean handles exact segment boundaries")
    func mapToCleanBoundaries() {
        let decisions = [
            makeKeep(start: 0, end: 5),
            makeCut(start: 5, end: 8),
            makeKeep(start: 8, end: 12),
        ]
        let mapping = TimelineMapper.buildMapping(from: decisions)

        // Start boundary of first keep
        #expect(TimelineMapper.mapToClean(0, mapping: mapping) == 0)
        // End boundary of first keep
        #expect(TimelineMapper.mapToClean(5, mapping: mapping) == 5)
        // Start boundary of second keep
        #expect(TimelineMapper.mapToClean(8, mapping: mapping) == 5)
        // End boundary of second keep
        #expect(TimelineMapper.mapToClean(12, mapping: mapping) == 9)
    }

    @Test("mapToClean returns nil for time before all keeps")
    func mapToCleanBeforeAllKeeps() {
        let decisions = [makeKeep(start: 5, end: 10)]
        let mapping = TimelineMapper.buildMapping(from: decisions)

        #expect(TimelineMapper.mapToClean(2, mapping: mapping) == nil)
    }

    @Test("mapToClean returns nil for time after all keeps")
    func mapToCleanAfterAllKeeps() {
        let decisions = [makeKeep(start: 0, end: 5)]
        let mapping = TimelineMapper.buildMapping(from: decisions)

        #expect(TimelineMapper.mapToClean(7, mapping: mapping) == nil)
    }

    // MARK: - remapCaptions

    @Test("remapCaptions shifts captions to clean timeline coordinates")
    func remapCaptionsBasic() {
        let decisions = [
            makeKeep(start: 0, end: 5),
            makeCut(start: 5, end: 10),
            makeKeep(start: 10, end: 20),
        ]
        let mapping = TimelineMapper.buildMapping(from: decisions)

        let captions = [
            makeCaption(start: 1, end: 3, text: "first"),     // in first keep
            makeCaption(start: 12, end: 15, text: "second"),   // in second keep: 12→7, 15→10
        ]

        let remapped = TimelineMapper.remapCaptions(captions, mapping: mapping)
        #expect(remapped.count == 2)
        #expect(remapped[0].startTime == 1)
        #expect(remapped[0].endTime == 3)
        #expect(remapped[0].text == "first")

        #expect(remapped[1].startTime == 7)  // 5 + (12-10)
        #expect(remapped[1].endTime == 10)   // 5 + (15-10)
        #expect(remapped[1].text == "second")
    }

    @Test("remapCaptions drops captions in cut regions")
    func remapCaptionsDropsCut() {
        let decisions = [
            makeKeep(start: 0, end: 5),
            makeCut(start: 5, end: 10),
            makeKeep(start: 10, end: 15),
        ]
        let mapping = TimelineMapper.buildMapping(from: decisions)

        let captions = [
            makeCaption(start: 1, end: 3, text: "keep"),
            makeCaption(start: 6, end: 8, text: "in cut"),   // should be dropped
            makeCaption(start: 11, end: 13, text: "keep2"),
        ]

        let remapped = TimelineMapper.remapCaptions(captions, mapping: mapping)
        #expect(remapped.count == 2)
        #expect(remapped[0].text == "keep")
        #expect(remapped[1].text == "keep2")
    }

    @Test("remapCaptions handles caption spanning segment boundary with fallback")
    func remapCaptionsBoundaryOvershoot() {
        let decisions = [
            makeKeep(start: 0, end: 5),
            makeCut(start: 5, end: 10),
        ]
        let mapping = TimelineMapper.buildMapping(from: decisions)

        // Caption starts in keep but endTime overshoots slightly past boundary
        let captions = [makeCaption(start: 3, end: 5.03, text: "boundary")]
        let remapped = TimelineMapper.remapCaptions(captions, mapping: mapping)

        #expect(remapped.count == 1)
        #expect(remapped[0].startTime == 3)
        // endTime: mapToClean(5.03) is nil, tries 4.98 which maps, or falls back to duration-based
        #expect(remapped[0].endTime >= 3.1) // at least minimum gap enforced
    }

    @Test("remapCaptions enforces minimum 0.1s duration")
    func remapCaptionsMinDuration() {
        let decisions = [makeKeep(start: 0, end: 10)]
        let mapping = TimelineMapper.buildMapping(from: decisions)

        let captions = [makeCaption(start: 5, end: 5.01, text: "tiny")]
        let remapped = TimelineMapper.remapCaptions(captions, mapping: mapping)

        #expect(remapped.count == 1)
        #expect(remapped[0].endTime >= remapped[0].startTime + 0.1)
    }

    @Test("remapCaptions preserves caption properties")
    func remapCaptionsPreservesProperties() {
        let decisions = [makeKeep(start: 0, end: 10)]
        let mapping = TimelineMapper.buildMapping(from: decisions)

        let caption = CaptionSegment(
            startTime: 2, endTime: 4, text: "important",
            role: .hook, style: .hookImpact, sceneBehavior: .hookImpact
        )
        let remapped = TimelineMapper.remapCaptions([caption], mapping: mapping)

        #expect(remapped.count == 1)
        #expect(remapped[0].text == "important")
        #expect(remapped[0].role == .hook)
        #expect(remapped[0].style == .hookImpact)
        #expect(remapped[0].sceneBehavior == .hookImpact)
    }

    // MARK: - remapEditDecisions

    @Test("remapEditDecisions shifts edit times to clean timeline")
    func remapEditDecisionsBasic() {
        let decisions = [
            makeKeep(start: 0, end: 5),
            makeCut(start: 5, end: 10),
            makeKeep(start: 10, end: 20),
        ]
        let mapping = TimelineMapper.buildMapping(from: decisions)

        let edits = [
            makeEdit(time: 2),      // in first keep → clean 2
            makeEdit(time: 13),     // in second keep → clean 8 (5 + 13-10)
        ]

        let remapped = TimelineMapper.remapEditDecisions(edits, mapping: mapping)
        #expect(remapped.count == 2)
        #expect(remapped[0].time == 2)
        #expect(remapped[1].time == 8)
    }

    @Test("remapEditDecisions drops edits in cut regions")
    func remapEditDecisionsDropsCut() {
        let decisions = [
            makeKeep(start: 0, end: 5),
            makeCut(start: 5, end: 10),
            makeKeep(start: 10, end: 15),
        ]
        let mapping = TimelineMapper.buildMapping(from: decisions)

        let edits = [
            makeEdit(time: 3),     // keep
            makeEdit(time: 7),     // cut → dropped
            makeEdit(time: 12),    // keep
        ]

        let remapped = TimelineMapper.remapEditDecisions(edits, mapping: mapping)
        #expect(remapped.count == 2)
    }

    @Test("remapEditDecisions preserves duration, type, reason, intensity")
    func remapEditDecisionsPreservesProperties() {
        let decisions = [makeKeep(start: 0, end: 10)]
        let mapping = TimelineMapper.buildMapping(from: decisions)

        let edit = EditDecision(
            time: 5, duration: 1.5,
            type: .shake, reason: "emphasis", intensity: 0.8
        )
        let remapped = TimelineMapper.remapEditDecisions([edit], mapping: mapping)

        #expect(remapped.count == 1)
        #expect(remapped[0].duration == 1.5)
        #expect(remapped[0].type == .shake)
        #expect(remapped[0].reason == "emphasis")
        #expect(remapped[0].intensity == 0.8)
    }

    // MARK: - Multi-segment stress test

    @Test("Handles many alternating keep/cut segments")
    func manySegments() {
        // 10 keep segments of 2s each, separated by 1s cuts
        // Source: [0-2 keep][2-3 cut][3-5 keep][5-6 cut]...[27-29 keep]
        var allDecisions: [RoughCutDecision] = []
        var time = 0.0
        for _ in 0..<10 {
            allDecisions.append(makeKeep(start: time, end: time + 2))
            time += 2
            allDecisions.append(makeCut(start: time, end: time + 1))
            time += 1
        }

        let mapping = TimelineMapper.buildMapping(from: allDecisions)
        #expect(mapping.count == 10)

        // Total clean duration should be 10 * 2 = 20s
        let lastSeg = mapping.last!
        let totalClean = lastSeg.cleanStart + lastSeg.duration
        #expect(abs(totalClean - 20.0) < 0.001)

        // Test mapping of a time in the 5th keep segment
        // 5th keep: source 12-14, clean start = 4*2 = 8
        let cleanTime = TimelineMapper.mapToClean(13.0, mapping: mapping)
        #expect(cleanTime == 9.0) // 8 + (13-12)

        // Time in 5th cut region (14-15) should be nil
        #expect(TimelineMapper.mapToClean(14.5, mapping: mapping) == nil)
    }
}

@Suite("CaptionReadabilityGuard — UUID uniqueness and split behavior")
struct CaptionReadabilitySplitTests {

    private func makeCaption(text: String, start: Double = 0, end: Double = 5) -> CaptionSegment {
        CaptionSegment(
            startTime: start, endTime: end, text: text,
            role: .regular, style: .boldCenterViral
        )
    }

    @Test("Split captions get unique UUIDs")
    func splitCaptionsUniqueUUIDs() {
        // 12 words → should be split (maxWords = 10)
        let longText = "bir iki uc dort bes alti yedi sekiz dokuz on onbir oniki"
        let captions = [makeCaption(text: longText, start: 0, end: 6)]
        let result = CaptionReadabilityGuard.validate(captions)

        #expect(result.count == 2, "Long caption should be split into 2")
        #expect(result[0].id != result[1].id, "Split captions must have unique UUIDs")
    }

    @Test("Split captions divide time evenly")
    func splitCaptionsTimeDistribution() {
        let longText = "one two three four five six seven eight nine ten eleven twelve"
        let captions = [makeCaption(text: longText, start: 2, end: 8)]
        let result = CaptionReadabilityGuard.validate(captions)

        #expect(result.count == 2)
        #expect(result[0].startTime == 2)
        #expect(result[0].endTime == 5)   // midpoint
        #expect(result[1].startTime == 5)
        #expect(result[1].endTime == 8)
    }

    @Test("Split captions preserve role and style")
    func splitCaptionsPreserveMetadata() {
        let longText = "a b c d e f g h i j k l"
        let caption = CaptionSegment(
            startTime: 0, endTime: 6, text: longText,
            role: .hook, style: .hookImpact, sceneBehavior: .hookImpact
        )
        let result = CaptionReadabilityGuard.validate([caption])

        #expect(result.count == 2)
        for cap in result {
            #expect(cap.role == .hook)
            #expect(cap.style == .hookImpact)
        }
        // First half keeps original scene behavior, second half gets .none to avoid duplicates
        #expect(result[0].sceneBehavior == .hookImpact)
        #expect(result[1].sceneBehavior == .none)
    }

    @Test("Short captions get minimum display duration")
    func minDisplayDuration() {
        let captions = [makeCaption(text: "Hi", start: 5, end: 5.2)]
        let result = CaptionReadabilityGuard.validate(captions)

        #expect(result.count == 1)
        // minDisplayDuration = 0.8
        #expect(result[0].endTime == 5.8)
    }

    @Test("Normal-length captions pass through unchanged")
    func normalCaptionsUnchanged() {
        let captions = [makeCaption(text: "Normal text here", start: 1, end: 4)]
        let result = CaptionReadabilityGuard.validate(captions)

        #expect(result.count == 1)
        #expect(result[0].text == "Normal text here")
        #expect(result[0].startTime == 1)
        #expect(result[0].endTime == 4)
    }

    @Test("Long single-line captions get line break")
    func longLineGetsLineBreak() {
        // 45 chars, > maxCharsPerLine (40), but <= 10 words
        let text = "Bu cok uzun bir cumle mesela soyle bakalim"
        let captions = [makeCaption(text: text)]
        let result = CaptionReadabilityGuard.validate(captions)

        #expect(result.count == 1) // not split, just line-broken
        #expect(result[0].text.contains("\n"), "Should insert line break")
    }

    @Test("Multiple captions processed independently")
    func multipleCaptions() {
        let captions = [
            makeCaption(text: "Short", start: 0, end: 2),
            makeCaption(text: "a b c d e f g h i j k l", start: 3, end: 9), // will split
            makeCaption(text: "Also short", start: 10, end: 12),
        ]
        let result = CaptionReadabilityGuard.validate(captions)

        #expect(result.count == 4) // 1 + 2 (split) + 1
        // All IDs unique
        let ids = Set(result.map(\.id))
        #expect(ids.count == 4, "All captions must have unique IDs")
    }
}

// MARK: - resolveOverlaps

@Suite("TimelineMapper — resolveOverlaps")
struct ResolveOverlapsTests {

    private func makeCaption(start: Double, end: Double, text: String = "test") -> CaptionSegment {
        CaptionSegment(startTime: start, endTime: end, text: text, role: .regular, style: .boldCenterViral)
    }

    @Test("Non-overlapping captions pass through unchanged")
    func nonOverlapping() {
        let captions = [
            makeCaption(start: 0, end: 2, text: "a"),
            makeCaption(start: 3, end: 5, text: "b"),
        ]
        let result = TimelineMapper.resolveOverlaps(captions)
        #expect(result.count == 2)
        #expect(result[0].endTime == 2)
        #expect(result[1].startTime == 3)
    }

    @Test("Overlapping captions get clamped")
    func overlapping() {
        let captions = [
            makeCaption(start: 0, end: 4, text: "a"),
            makeCaption(start: 3, end: 6, text: "b"),
        ]
        let result = TimelineMapper.resolveOverlaps(captions)
        #expect(result[0].endTime == 3) // clamped to b.startTime
        #expect(result[1].startTime == 3)
    }

    @Test("Severe overlap enforces minimum 0.1s duration")
    func severeOverlapMinDuration() {
        let captions = [
            makeCaption(start: 0, end: 5, text: "a"),
            makeCaption(start: 0.05, end: 3, text: "b"), // starts very close to a.start
        ]
        let result = TimelineMapper.resolveOverlaps(captions)
        // After sorting: a(0-5) then b(0.05-3). a.endTime clamped to 0.05, but that's only 0.05s duration, so min enforced to 0.1
        #expect(result[0].endTime - result[0].startTime >= 0.1)
    }

    @Test("Single caption passes through")
    func singleCaption() {
        let captions = [makeCaption(start: 1, end: 3)]
        let result = TimelineMapper.resolveOverlaps(captions)
        #expect(result.count == 1)
        #expect(result[0].startTime == 1)
        #expect(result[0].endTime == 3)
    }

    @Test("Empty array passes through")
    func emptyArray() {
        let result = TimelineMapper.resolveOverlaps([])
        #expect(result.isEmpty)
    }

    @Test("Three overlapping captions resolved sequentially")
    func threeOverlapping() {
        let captions = [
            makeCaption(start: 0, end: 4, text: "a"),
            makeCaption(start: 2, end: 6, text: "b"),
            makeCaption(start: 5, end: 8, text: "c"),
        ]
        let result = TimelineMapper.resolveOverlaps(captions)
        #expect(result[0].endTime == 2) // clamped to b.start
        #expect(result[1].endTime == 5) // clamped to c.start
        #expect(result[2].endTime == 8) // unchanged
    }
}

// MARK: - cleanDuration computation

@Suite("RoughCutDecisionEngine cleanDuration")
struct CleanDurationTests {

    @Test("cleanDuration equals sum of keep segment durations")
    func cleanDurationEqualsKeepSum() {
        let segments = [
            TranscriptSegment(startTime: 0, endTime: 3, text: "Hello", confidence: 0.9, segmentType: .speech),
            TranscriptSegment(startTime: 3, endTime: 4, text: "", confidence: 1.0, segmentType: .silence),
            TranscriptSegment(startTime: 4, endTime: 7, text: "World", confidence: 0.9, segmentType: .speech),
        ]
        let transcription = TranscriptionResult(
            fullText: "Hello World", segments: segments, language: "en", overallConfidence: 0.9
        )
        let audio = AudioAnalysisResult(
            segments: [
                AudioSegment(startTime: 0, endTime: 3, type: .speech, energy: 0.4),
                AudioSegment(startTime: 3, endTime: 4, type: .silence, energy: 0.001),
                AudioSegment(startTime: 4, endTime: 7, type: .speech, energy: 0.4),
            ],
            silenceIntervals: [3.0...4.0],
            averageEnergy: 0.3, peakEnergy: 0.5, duration: 7
        )

        let result = RoughCutDecisionEngine.generateDecisions(
            transcription: transcription, audioAnalysis: audio
        )

        let keepSum = result.keepSegments.reduce(0.0) { $0 + ($1.endTime - $1.startTime) }
        #expect(abs(result.cleanDuration - keepSum) < 0.001, "cleanDuration must equal sum of keep segment durations")
    }

    @Test("cleanDuration excludes reviewRequired segments")
    func cleanDurationExcludesReview() {
        // Manually construct a result with review segments to verify
        let decisions = [
            RoughCutDecision(startTime: 0, endTime: 5, action: .keep, reason: "", confidence: 0.9, linkedTranscriptText: nil, requiresReview: false),
            RoughCutDecision(startTime: 5, endTime: 8, action: .reviewRequired, reason: "", confidence: 0.5, linkedTranscriptText: nil, requiresReview: true),
            RoughCutDecision(startTime: 8, endTime: 12, action: .keep, reason: "", confidence: 0.9, linkedTranscriptText: nil, requiresReview: false),
        ]
        let keepSegments = decisions.filter { $0.action == .keep }
        let cleanDuration = keepSegments.reduce(0.0) { $0 + ($1.endTime - $1.startTime) }
        // Keep: 5s + 4s = 9s. NOT 12s (which would include review segment)
        #expect(cleanDuration == 9)
    }
}

@Suite("QualityGateService — extended checks")
struct QualityGateExtendedTests {

    @Test("Audio quality check appears when provided")
    func audioQualityCheck() {
        let captions = [
            CaptionSegment(startTime: 0, endTime: 3, text: "Hook", role: .hook, style: .hookImpact),
            CaptionSegment(startTime: 3, endTime: 6, text: "End", role: .conclusion, style: .minimalWellness),
        ]
        let plan = EditPlan(decisions: [], template: .cleanExpert, totalEffects: 0, averageIntensity: 0)
        let roughCut = RoughCutResult(decisions: [], originalDuration: 8, cleanDuration: 6, keepSegments: [], cutSegments: [], reviewSegments: [])
        let audioReport = AudioQualityGuard.QualityReport(
            peakDB: -3, averageDB: -18, isClipping: false, isTooQuiet: false, dynamicRange: 15, passed: true
        )

        let report = QualityGateService.evaluate(
            captions: captions, editPlan: plan, roughCut: roughCut, template: .cleanExpert, audioQuality: audioReport
        )
        let audioCheck = report.checks.first { $0.name == "Audio quality" }
        #expect(audioCheck != nil, "Audio quality check should be present")
        #expect(audioCheck?.passed == true)
    }

    @Test("Clipping audio fails quality gate critically")
    func clippingAudioFails() {
        let captions = [
            CaptionSegment(startTime: 0, endTime: 3, text: "Hook", role: .hook, style: .hookImpact),
            CaptionSegment(startTime: 3, endTime: 6, text: "End", role: .conclusion, style: .minimalWellness),
        ]
        let plan = EditPlan(decisions: [], template: .cleanExpert, totalEffects: 0, averageIntensity: 0)
        let roughCut = RoughCutResult(decisions: [], originalDuration: 8, cleanDuration: 6, keepSegments: [], cutSegments: [], reviewSegments: [])
        let audioReport = AudioQualityGuard.QualityReport(
            peakDB: -0.5, averageDB: -10, isClipping: true, isTooQuiet: false, dynamicRange: 9.5, passed: false
        )

        let report = QualityGateService.evaluate(
            captions: captions, editPlan: plan, roughCut: roughCut, template: .cleanExpert, audioQuality: audioReport
        )
        let audioCheck = report.checks.first { $0.name == "Audio quality" }
        #expect(audioCheck?.passed == false)
        #expect(audioCheck?.severity == .critical)
    }

    @Test("Continuity check appears when provided")
    func continuityCheck() {
        let captions = [
            CaptionSegment(startTime: 0, endTime: 3, text: "Hook", role: .hook, style: .hookImpact),
            CaptionSegment(startTime: 3, endTime: 6, text: "End", role: .conclusion, style: .minimalWellness),
        ]
        let plan = EditPlan(decisions: [], template: .cleanExpert, totalEffects: 0, averageIntensity: 0)
        let roughCut = RoughCutResult(decisions: [], originalDuration: 8, cleanDuration: 6, keepSegments: [], cutSegments: [], reviewSegments: [])
        let continuity = ContinuityChecker.ContinuityResult(
            transitions: [], smoothTransitions: 3, roughTransitions: 0, overallScore: 85
        )

        let report = QualityGateService.evaluate(
            captions: captions, editPlan: plan, roughCut: roughCut, template: .cleanExpert, continuity: continuity
        )
        let contCheck = report.checks.first { $0.name == "Continuity" }
        #expect(contCheck != nil)
        #expect(contCheck?.passed == true)
    }
}

@Suite("QualityReport originalDuration computation")
struct QualityReportTests {

    @Test("Quality report uses correct originalDuration from decisions")
    func qualityReportOriginalDuration() {
        // Simulate what ExportScreen.qualityReport does
        let decisions = [
            RoughCutDecision(startTime: 0, endTime: 10, action: .keep, reason: "", confidence: 0.9, linkedTranscriptText: nil, requiresReview: false),
            RoughCutDecision(startTime: 10, endTime: 15, action: .cut, reason: "", confidence: 0.9, linkedTranscriptText: nil, requiresReview: false),
            RoughCutDecision(startTime: 15, endTime: 25, action: .keep, reason: "", confidence: 0.9, linkedTranscriptText: nil, requiresReview: false),
        ]

        let keepSegs = decisions.filter { $0.action == .keep }
        let cutSegs = decisions.filter { $0.action == .cut || $0.action == .trimStart || $0.action == .trimEnd }
        var keepDuration: Double = 0
        for seg in keepSegs { keepDuration += seg.endTime - seg.startTime }
        var cutDuration: Double = 0
        for seg in cutSegs { cutDuration += seg.endTime - seg.startTime }

        let roughCut = RoughCutResult(
            decisions: decisions,
            originalDuration: keepDuration + cutDuration,
            cleanDuration: keepDuration,
            keepSegments: keepSegs,
            cutSegments: cutSegs,
            reviewSegments: []
        )

        #expect(roughCut.originalDuration == 25, "originalDuration should be total of keep + cut")
        #expect(roughCut.cleanDuration == 20, "cleanDuration should be total of keep only")

        // Content retention = clean/original = 20/25 = 80%
        let retention = roughCut.cleanDuration / roughCut.originalDuration
        #expect(retention > 0.5, "Content retention should be reasonable, not 0%")
    }

    @Test("Quality report with zero cut segments has 100% retention")
    func qualityReportNoCuts() {
        let decisions = [
            RoughCutDecision(startTime: 0, endTime: 30, action: .keep, reason: "", confidence: 0.9, linkedTranscriptText: nil, requiresReview: false),
        ]

        let keepSegs = decisions.filter { $0.action == .keep }
        var keepDuration: Double = 0
        for seg in keepSegs { keepDuration += seg.endTime - seg.startTime }

        let roughCut = RoughCutResult(
            decisions: decisions,
            originalDuration: keepDuration,
            cleanDuration: keepDuration,
            keepSegments: keepSegs,
            cutSegments: [],
            reviewSegments: []
        )

        let retention = roughCut.cleanDuration / roughCut.originalDuration
        #expect(retention == 1.0, "No cuts = 100% retention")
    }
}

// MARK: - RoughCutDecisionEngine segment type handling

@Suite("RoughCutDecisionEngine segment type routing")
struct SegmentTypeRoutingTests {

    private func makeAudio(duration: Double) -> AudioAnalysisResult {
        AudioAnalysisResult(
            segments: [AudioSegment(startTime: 0, endTime: duration, type: .speech, energy: 0.4)],
            silenceIntervals: [],
            averageEnergy: 0.3, peakEnergy: 0.5, duration: duration
        )
    }

    @Test("Filler segments produce cut decisions")
    func fillerSegmentsCut() {
        // Short filler (< 1s) → auto-cut. Long filler (>= 1s) → review.
        let segments = [
            TranscriptSegment(startTime: 0, endTime: 0.5, text: "um", confidence: 0.8, segmentType: .filler),
            TranscriptSegment(startTime: 0.5, endTime: 5, text: "Hello world", confidence: 0.9, segmentType: .speech),
        ]
        let transcription = TranscriptionResult(fullText: "um Hello world", segments: segments, language: "en", overallConfidence: 0.85)
        let result = RoughCutDecisionEngine.generateDecisions(transcription: transcription, audioAnalysis: makeAudio(duration: 5))

        let fillerDecisions = result.decisions.filter { $0.linkedTranscriptText == "um" }
        #expect(!fillerDecisions.isEmpty)
        #expect(fillerDecisions.allSatisfy { $0.action == .cut })
    }

    @Test("Suspected restart segments produce cut decisions when AI confidence high")
    func restartSegmentsCut() {
        // Restarts auto-cut only when aiConfidence >= 0.85
        let segments = [
            TranscriptSegment(startTime: 0, endTime: 3, text: "So today we", confidence: 0.9, segmentType: .suspectedRestart, aiConfidence: 0.90),
            TranscriptSegment(startTime: 3, endTime: 7, text: "Today we discuss Swift", confidence: 0.9, segmentType: .speech),
        ]
        let transcription = TranscriptionResult(fullText: "So today we Today we discuss Swift", segments: segments, language: "en", overallConfidence: 0.8)
        let result = RoughCutDecisionEngine.generateDecisions(transcription: transcription, audioAnalysis: makeAudio(duration: 7))

        let restartDecisions = result.decisions.filter { $0.linkedTranscriptText == "So today we" }
        #expect(!restartDecisions.isEmpty)
        #expect(restartDecisions.allSatisfy { $0.action == .cut })
    }

    @Test("Suspected duplicate segments produce cut with review")
    func duplicateSegmentsReview() {
        let segments = [
            TranscriptSegment(startTime: 0, endTime: 4, text: "Swift is great", confidence: 0.9, segmentType: .speech),
            TranscriptSegment(startTime: 4, endTime: 8, text: "Swift is great", confidence: 0.85, segmentType: .suspectedDuplicate),
        ]
        let transcription = TranscriptionResult(fullText: "Swift is great Swift is great", segments: segments, language: "en", overallConfidence: 0.87)
        let result = RoughCutDecisionEngine.generateDecisions(transcription: transcription, audioAnalysis: makeAudio(duration: 8))

        let dupDecisions = result.decisions.filter { $0.linkedTranscriptText == "Swift is great" && $0.startTime == 4 }
        #expect(!dupDecisions.isEmpty)
        #expect(dupDecisions.allSatisfy { $0.action == .cut })
        #expect(dupDecisions.allSatisfy { $0.requiresReview == true })
    }

    @Test("Content sentence segments are kept")
    func contentSentencesKept() {
        let segments = [
            TranscriptSegment(startTime: 0, endTime: 5, text: "Welcome to the show", confidence: 0.95, segmentType: .contentSentence),
        ]
        let transcription = TranscriptionResult(fullText: "Welcome to the show", segments: segments, language: "en", overallConfidence: 0.95)
        let result = RoughCutDecisionEngine.generateDecisions(transcription: transcription, audioAnalysis: makeAudio(duration: 5))

        let contentDecisions = result.decisions.filter { $0.linkedTranscriptText == "Welcome to the show" }
        #expect(!contentDecisions.isEmpty)
        #expect(contentDecisions.allSatisfy { $0.action == .keep })
    }
}
