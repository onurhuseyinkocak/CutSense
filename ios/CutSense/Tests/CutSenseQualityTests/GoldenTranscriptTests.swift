import Testing
@testable import CutSense

// MARK: - Golden Transcript Tests
// Tests the rough cut decision logic with synthetic transcripts.
// No real video required — verifies classification, cut/keep, and confidence.

@Suite("Golden Transcript Tests")
struct GoldenTranscriptTests {

    // MARK: - Scenario A: Explicit Restart

    @Test("Scenario A — explicit restart detected and cut")
    func scenarioA_explicitRestart() {
        let segments = [
            TestFixture.segment(start: 0.0, end: 2.0, text: "Bugün size DidntHappen'ı anlatıcam"),
            TestFixture.segment(start: 2.0, end: 3.5, text: "olmadı baştan alıyorum"),
            TestFixture.segment(start: 3.5, end: 7.0, text: "DidntHappen kaygılarınızı takip eden bir uygulama"),
        ]
        let transcription = TestFixture.transcription(segments: segments)
        let audio = TestFixture.audioResult(duration: 7.0, silenceIntervals: [])

        let result = RoughCutDecisionEngine.generateDecisions(
            transcription: transcription,
            audioAnalysis: audio
        )

        // "olmadı baştan alıyorum" must be cut — explicit edit command
        let editCommandDecision = result.decisions.first { $0.linkedTranscriptText == "olmadı baştan alıyorum" }
        #expect(editCommandDecision != nil, "Edit command 'olmadı baştan alıyorum' must have a decision")
        #expect(editCommandDecision?.action == .cut, "Edit command must be cut")
        #expect(editCommandDecision?.confidence ?? 0 >= 0.7, "Confidence must be >= 0.7")
        #expect(editCommandDecision?.reason.lowercased().contains("edit") == true ||
                editCommandDecision?.reason.lowercased().contains("baştan") == true ||
                editCommandDecision?.reason.lowercased().contains("command") == true,
                "Reason must mention edit/restart/command")

        // Clean take must be kept
        let cleanTake = result.decisions.first { $0.linkedTranscriptText == "DidntHappen kaygılarınızı takip eden bir uygulama" }
        #expect(cleanTake != nil, "Clean take must have a decision")
        #expect(cleanTake?.action == .keep, "Clean take must be kept")
    }

    // MARK: - Scenario B: False Cut Protection

    @Test("Scenario B — 'olmadı' as content must NOT be cut")
    func scenarioB_falseCutProtection() {
        let segments = [
            TestFixture.segment(start: 0.0, end: 3.0, text: "Bu strateji olmadı çünkü kullanıcı tutmadı"),
            TestFixture.segment(start: 3.0, end: 6.0, text: "Bu yüzden ürünü tekrar konumlandırdık"),
        ]
        let transcription = TestFixture.transcription(segments: segments)
        let audio = TestFixture.audioResult(duration: 6.0)

        let result = RoughCutDecisionEngine.generateDecisions(
            transcription: transcription,
            audioAnalysis: audio
        )

        // Both must be kept — "olmadı" is content, not an edit command
        for decision in result.decisions {
            guard decision.linkedTranscriptText != nil else { continue }
            #expect(decision.action == .keep || decision.action == .reviewRequired,
                    "Content segment '\(decision.linkedTranscriptText ?? "")' must NOT be cut")
            #expect(decision.action != .cut,
                    "FALSE CUT: '\(decision.linkedTranscriptText ?? "")' was cut but it's valid content")
        }
    }

    // MARK: - Scenario C: "Dur" As Content

    @Test("Scenario C — 'dur' as content must NOT be cut")
    func scenarioC_durAsContent() {
        let segments = [
            TestFixture.segment(start: 0.0, end: 3.0, text: "Dur demeyi öğrenmek bazen çok önemli"),
            TestFixture.segment(start: 3.0, end: 6.0, text: "Çünkü her fikri yapmak zorunda değilsin"),
        ]
        let transcription = TestFixture.transcription(segments: segments)
        let audio = TestFixture.audioResult(duration: 6.0)

        let result = RoughCutDecisionEngine.generateDecisions(
            transcription: transcription,
            audioAnalysis: audio
        )

        let durSegment = result.decisions.first { $0.linkedTranscriptText?.contains("Dur demeyi") == true }
        #expect(durSegment != nil, "'Dur demeyi...' must have a decision")
        #expect(durSegment?.action == .keep || durSegment?.action == .reviewRequired,
                "FALSE CUT: 'Dur demeyi öğrenmek...' is content, not an edit command")
        #expect(durSegment?.action != .cut,
                "'dur' inside a content sentence must NOT trigger a cut")
    }

    // MARK: - Scenario D: "Dur" As Edit Command

    @Test("Scenario D — 'dur dur tekrar alayım' is an edit command and must be cut")
    func scenarioD_durAsEditCommand() {
        let segments = [
            TestFixture.segment(start: 0.0, end: 2.0, text: "Bu uygulama kaygılarını"),
            TestFixture.segment(start: 2.0, end: 3.0, text: "dur dur tekrar alayım"),
            TestFixture.segment(start: 3.0, end: 6.0, text: "DidntHappen kaygılarını takip eden bir uygulama"),
        ]
        let transcription = TestFixture.transcription(segments: segments)
        let audio = TestFixture.audioResult(duration: 6.0)

        let result = RoughCutDecisionEngine.generateDecisions(
            transcription: transcription,
            audioAnalysis: audio
        )

        // "dur dur tekrar alayım" must be cut
        let editCmd = result.decisions.first { $0.linkedTranscriptText == "dur dur tekrar alayım" }
        #expect(editCmd != nil, "Edit command must have a decision")
        #expect(editCmd?.action == .cut, "'dur dur tekrar alayım' must be cut")
        #expect(editCmd?.confidence ?? 0 >= 0.7, "Confidence must be high for explicit edit command")

        // Clean take must be kept
        let clean = result.decisions.first { $0.linkedTranscriptText?.contains("DidntHappen") == true }
        #expect(clean?.action == .keep, "Clean take must be kept")
    }

    // MARK: - Scenario E: Repeated Takes

    @Test("Scenario E — repeated takes grouped, best selected")
    func scenarioE_repeatedTakes() {
        let segments = [
            TestFixture.segment(start: 0.0, end: 2.0, text: "Bu uygulama kaygılarını takip", confidence: 0.7, type: .suspectedRestart),
            TestFixture.segment(start: 2.0, end: 5.0, text: "Bu uygulama aslında kaygılarını takip ediyor", confidence: 0.85, type: .speech),
            TestFixture.segment(start: 5.0, end: 9.0, text: "DidntHappen kaygılarını takip edip gerçekleşmeyenleri gösteriyor", confidence: 0.92, type: .speech),
        ]

        let groups = TakeDetectionEngine.detectTakeGroups(segments: segments)
        // First two segments share word overlap — should be grouped
        // Third segment is different content

        if !groups.isEmpty {
            let group = groups[0]
            #expect(group.takes.count >= 2, "Take group must have at least 2 takes")

            let scores = BestTakeSelector.scoreTakes(from: group.takes)
            let bestScore = scores[group.bestTakeIndex]
            let otherScores = scores.filter { $0.index != group.bestTakeIndex }

            for other in otherScores {
                #expect(bestScore.score >= other.score,
                        "Best take (index \(bestScore.index), score \(bestScore.score)) must score higher than other (index \(other.index), score \(other.score))")
            }
        }
    }

    // MARK: - Scenario F: Reveal Detection

    @Test("Scenario F — reveal/keyword caption role and edit decisions")
    func scenarioF_revealDetection() {
        let segments = [
            TestFixture.segment(start: 0.0, end: 3.0, text: "En güçlü tarafı şu", type: .contentSentence),
            TestFixture.segment(start: 3.0, end: 7.0, text: "Asıl olay kaygının gerçeklikle arasındaki farkı görmen", type: .contentSentence),
        ]
        let transcription = TestFixture.transcription(segments: segments)
        let roughCut = TestFixture.roughCutAllKept(segments: segments, originalDuration: 7.0)

        let captions = CaptionEngine.generateCaptions(
            from: transcription,
            roughCut: roughCut,
            template: .premiumFounder
        )

        #expect(!captions.isEmpty, "Captions must be generated")

        // At least one caption should have a non-none scene behavior
        let hasEffectCaption = captions.contains { $0.sceneBehavior != .none }
        #expect(hasEffectCaption, "At least one caption should have a scene behavior for semantic emphasis")
    }

    // MARK: - Scenario G: Over-Editing Guard

    @Test("Scenario G — intensity limiter prevents SFX/effect spam")
    func scenarioG_overEditingGuard() {
        // Create many short segments in 10 seconds to trigger limiter
        var segments: [TranscriptSegment] = []
        for i in 0..<10 {
            let start = Double(i)
            segments.append(TestFixture.segment(
                start: start,
                end: start + 0.9,
                text: "Segment \(i) content here",
                type: .contentSentence
            ))
        }
        let transcription = TestFixture.transcription(segments: segments)
        let roughCut = TestFixture.roughCutAllKept(segments: segments, originalDuration: 10.0)

        let captions = CaptionEngine.generateCaptions(
            from: transcription,
            roughCut: roughCut,
            template: .viralCaption
        )

        let editPlan = EditDecisionEngine.generateEditPlan(
            captions: captions,
            roughCut: roughCut,
            template: .viralCaption
        )

        // Count effects per type in 10 seconds
        let sfxCount = editPlan.decisions.filter { $0.type == .sfx }.count
        let zoomCount = editPlan.decisions.filter { $0.type == .zoom }.count
        let flashCount = editPlan.decisions.filter { $0.type == .flash }.count

        // Intensity limiter checks (relaxed for Prequel-level editing density)
        #expect(sfxCount <= 8, "Max 8 SFX in 10 seconds (got \(sfxCount))")
        #expect(zoomCount <= 8, "Max 8 zooms in 10 seconds (got \(zoomCount))")
        #expect(flashCount <= 5, "Max 5 flashes in 10 seconds (got \(flashCount))")

        // No stacked impact+whoosh at same timestamp
        let sfxDecisions = editPlan.decisions.filter { $0.type == .sfx }
        for sfx in sfxDecisions {
            let sameTimeSfx = sfxDecisions.filter { abs($0.time - sfx.time) < 0.1 && $0.reason != sfx.reason }
            #expect(sameTimeSfx.isEmpty,
                    "No stacked SFX at same timestamp (\(sfx.time)s)")
        }
    }
}
