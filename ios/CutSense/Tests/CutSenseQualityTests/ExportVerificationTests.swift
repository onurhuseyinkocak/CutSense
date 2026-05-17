import Testing
@testable import CutSense

// MARK: - Export pipeline verification tests

@Suite("Quality Gate Tests")
struct QualityGateTests {

    @Test("Quality gate passes with good data")
    func qualityGatePasses() {
        let captions = [
            TestFixture.caption(start: 0, end: 2, text: "Hook caption", role: .hook),
            TestFixture.caption(start: 2, end: 5, text: "Main content here", role: .regular),
            TestFixture.caption(start: 5, end: 8, text: "Conclusion text", role: .conclusion),
        ]
        let editPlan = EditPlan(
            decisions: [
                TestFixture.editDecision(time: 0, type: .zoom, reason: "Hook emphasis"),
            ],
            template: .premiumFounder,
            totalEffects: 1,
            averageIntensity: 0.5
        )
        let roughCut = TestFixture.roughCutResult(
            decisions: [
                RoughCutDecision(startTime: 0, endTime: 10, action: .keep, reason: "Content", confidence: 0.9, linkedTranscriptText: nil, requiresReview: false)
            ],
            originalDuration: 10.0,
            cleanDuration: 8.0
        )

        let report = QualityGateService.evaluate(
            captions: captions,
            editPlan: editPlan,
            roughCut: roughCut,
            template: .premiumFounder
        )

        #expect(report.score > 0, "Quality score must be calculated")
        #expect(report.checks.count >= 5, "At least 5 quality checks must run")
    }

    @Test("Quality gate flags missing hook")
    func missingHookFlagged() {
        let captions = [
            TestFixture.caption(start: 0, end: 3, text: "Regular content", role: .regular),
            TestFixture.caption(start: 3, end: 6, text: "More content", role: .regular),
        ]
        let editPlan = EditPlan(
            decisions: [],
            template: .premiumFounder,
            totalEffects: 0,
            averageIntensity: 0
        )
        let roughCut = TestFixture.roughCutResult(
            decisions: [
                RoughCutDecision(startTime: 0, endTime: 10, action: .keep, reason: "Content", confidence: 0.9, linkedTranscriptText: nil, requiresReview: false)
            ],
            originalDuration: 10.0,
            cleanDuration: 6.0
        )

        let report = QualityGateService.evaluate(
            captions: captions,
            editPlan: editPlan,
            roughCut: roughCut,
            template: .premiumFounder
        )

        let hookCheck = report.checks.first { $0.name.lowercased().contains("hook") }
        #expect(hookCheck != nil, "Hook presence check must exist")
        if let hookCheck {
            #expect(!hookCheck.passed, "Missing hook must fail")
        }
    }

    @Test("Quality gate flags excessive effects")
    func excessiveEffectsFlagged() {
        let captions = [
            TestFixture.caption(start: 0, end: 10, text: "Content", role: .regular),
        ]
        // 20 effects in 10 seconds = 120/min — way over limit
        var effects: [EditDecision] = []
        for i in 0..<20 {
            effects.append(TestFixture.editDecision(time: Double(i) * 0.5, type: .zoom))
        }
        let editPlan = EditPlan(
            decisions: effects,
            template: .viralCaption,
            totalEffects: 20,
            averageIntensity: 0.8
        )
        let roughCut = TestFixture.roughCutResult(
            decisions: [
                RoughCutDecision(startTime: 0, endTime: 10, action: .keep, reason: "Content", confidence: 0.9, linkedTranscriptText: nil, requiresReview: false)
            ],
            originalDuration: 10.0,
            cleanDuration: 10.0
        )

        let report = QualityGateService.evaluate(
            captions: captions,
            editPlan: editPlan,
            roughCut: roughCut,
            template: .viralCaption
        )

        let densityCheck = report.checks.first { $0.name.lowercased().contains("density") || $0.name.lowercased().contains("effect") }
        #expect(densityCheck != nil, "Effect density check must exist")
        if let densityCheck {
            #expect(!densityCheck.passed, "120 effects/min must fail density check")
        }
    }
}

@Suite("TimelineMapper Quality Tests")
struct TimelineMapperQualityTests {

    @Test("Basic mapping keeps correct segments")
    func basicMapping() {
        let decisions = [
            RoughCutDecision(startTime: 0, endTime: 3, action: .keep, reason: "Content", confidence: 0.9, linkedTranscriptText: nil, requiresReview: false),
            RoughCutDecision(startTime: 3, endTime: 5, action: .cut, reason: "Silence", confidence: 0.8, linkedTranscriptText: nil, requiresReview: false),
            RoughCutDecision(startTime: 5, endTime: 8, action: .keep, reason: "Content", confidence: 0.9, linkedTranscriptText: nil, requiresReview: false),
        ]

        let mapping = TimelineMapper.buildMapping(from: decisions)
        #expect(mapping.count == 2, "Two keep segments = two mapping entries")

        // Source time 1.0 -> clean time 1.0 (first segment, no offset)
        let clean1 = TimelineMapper.mapToClean(1.0, mapping: mapping)
        #expect(clean1 != nil, "Time 1.0 is in first keep segment")
        #expect(abs((clean1 ?? 0) - 1.0) < 0.01, "First segment maps 1:1")

        // Source time 6.0 -> clean time 4.0 (second segment, 2s cut removed)
        let clean2 = TimelineMapper.mapToClean(6.0, mapping: mapping)
        #expect(clean2 != nil, "Time 6.0 is in second keep segment")
        #expect(abs((clean2 ?? 0) - 4.0) < 0.01, "Second segment offset by 2s cut")

        // Source time 4.0 -> nil (in cut region)
        let cleanCut = TimelineMapper.mapToClean(4.0, mapping: mapping)
        #expect(cleanCut == nil, "Time in cut region must return nil")
    }

    @Test("Caption remapping preserves order")
    func captionRemapping() {
        let decisions = [
            RoughCutDecision(startTime: 0, endTime: 5, action: .keep, reason: "Content", confidence: 0.9, linkedTranscriptText: nil, requiresReview: false),
            RoughCutDecision(startTime: 5, endTime: 8, action: .cut, reason: "Silence", confidence: 0.8, linkedTranscriptText: nil, requiresReview: false),
            RoughCutDecision(startTime: 8, endTime: 12, action: .keep, reason: "Content", confidence: 0.9, linkedTranscriptText: nil, requiresReview: false),
        ]
        let mapping = TimelineMapper.buildMapping(from: decisions)

        let captions = [
            TestFixture.caption(start: 1, end: 3, text: "First caption"),
            TestFixture.caption(start: 9, end: 11, text: "Second caption"),
        ]

        let remapped = TimelineMapper.remapCaptions(captions, mapping: mapping)
        #expect(remapped.count == 2, "Both captions should survive remapping")
        #expect(remapped[0].startTime < remapped[1].startTime, "Order must be preserved")
    }

    @Test("Overlap resolution clamps captions")
    func overlapResolution() {
        let captions = [
            TestFixture.caption(start: 0, end: 3, text: "First"),
            TestFixture.caption(start: 2, end: 5, text: "Second"), // overlaps with first
        ]
        let resolved = TimelineMapper.resolveOverlaps(captions)
        if resolved.count >= 2 {
            #expect(resolved[0].endTime <= resolved[1].startTime,
                    "Resolved captions must not overlap")
        }
    }
}

@Suite("Caption Engine Tests")
struct CaptionEngineTests {

    @Test("Hook caption assigned to first segment")
    func hookAssignment() {
        let segments = [
            TestFixture.segment(start: 0, end: 3, text: "Bugun cok onemli bir sey anlatacagim", type: .contentSentence),
            TestFixture.segment(start: 3, end: 6, text: "DidntHappen kaygilarinizi takip ediyor", type: .contentSentence),
        ]
        let transcription = TestFixture.transcription(segments: segments)
        let roughCut = TestFixture.roughCutAllKept(segments: segments, originalDuration: 6.0)

        let captions = CaptionEngine.generateCaptions(
            from: transcription,
            roughCut: roughCut,
            template: .premiumFounder
        )

        #expect(!captions.isEmpty, "Captions must be generated")
        let hookCaption = captions.first { $0.role == .hook }
        #expect(hookCaption != nil, "First segment should get hook role")
    }

    @Test("Caption text within readable length")
    func readableLength() {
        let longText = String(repeating: "word ", count: 20)
        let segments = [
            TestFixture.segment(start: 0, end: 5, text: longText, type: .contentSentence),
        ]
        let transcription = TestFixture.transcription(segments: segments)
        let roughCut = TestFixture.roughCutAllKept(segments: segments, originalDuration: 5.0)

        let captions = CaptionEngine.generateCaptions(
            from: transcription,
            roughCut: roughCut,
            template: .premiumFounder
        )

        for caption in captions {
            #expect(caption.text.count <= 100,
                    "Caption text must be <=100 chars for readability (got \(caption.text.count))")
        }
    }

    @Test("No captions for cut segments")
    func noCaptionsForCut() {
        // Use non-adjacent times so cut segment doesn't overlap keep boundary
        let segments = [
            TestFixture.segment(start: 0, end: 2.5, text: "Keep this", type: .contentSentence),
            TestFixture.segment(start: 3.5, end: 6, text: "Cut this filler", type: .filler),
        ]
        let transcription = TestFixture.transcription(segments: segments)
        let roughCut = TestFixture.roughCutResult(
            decisions: [
                RoughCutDecision(startTime: 0, endTime: 2.5, action: .keep, reason: "Content", confidence: 0.95, linkedTranscriptText: "Keep this", requiresReview: false),
                RoughCutDecision(startTime: 3.5, endTime: 6, action: .cut, reason: "Filler", confidence: 0.9, linkedTranscriptText: "Cut this filler", requiresReview: false),
            ],
            originalDuration: 6.0,
            cleanDuration: 2.5
        )

        let captions = CaptionEngine.generateCaptions(
            from: transcription,
            roughCut: roughCut,
            template: .premiumFounder
        )

        let cutCaption = captions.first { $0.text.contains("Cut this") }
        #expect(cutCaption == nil, "Cut segments must NOT get captions")
    }
}

@Suite("Edit Decision Engine Tests")
struct EditDecisionEngineTests {

    @Test("Hook caption gets SFX")
    func hookGetsSFX() {
        let captions = [
            TestFixture.caption(start: 0, end: 3, text: "Hook!", role: .hook, style: .hookImpact, behavior: .hookImpact),
        ]
        let roughCut = TestFixture.roughCutResult(
            decisions: [
                RoughCutDecision(startTime: 0, endTime: 3, action: .keep, reason: "Content", confidence: 0.9, linkedTranscriptText: nil, requiresReview: false)
            ],
            originalDuration: 3.0,
            cleanDuration: 3.0
        )
        let editPlan = EditDecisionEngine.generateEditPlan(
            captions: captions,
            roughCut: roughCut,
            template: .premiumFounder
        )

        let sfx = editPlan.decisions.filter { $0.type == .sfx }
        #expect(!sfx.isEmpty, "Hook caption should generate at least one SFX")
    }

    @Test("Regular caption gets minimal effects")
    func regularMinimalEffects() {
        let captions = [
            TestFixture.caption(start: 0, end: 3, text: "Normal content", role: .regular, behavior: .none),
        ]
        let roughCut = TestFixture.roughCutResult(
            decisions: [
                RoughCutDecision(startTime: 0, endTime: 3, action: .keep, reason: "Content", confidence: 0.9, linkedTranscriptText: nil, requiresReview: false)
            ],
            originalDuration: 3.0,
            cleanDuration: 3.0
        )
        let editPlan = EditDecisionEngine.generateEditPlan(
            captions: captions,
            roughCut: roughCut,
            template: .cleanExpert
        )

        // Clean expert template should have minimal effects for regular content
        let effectCount = editPlan.decisions.count
        #expect(effectCount <= 2, "Regular content on cleanExpert should have <=2 effects (got \(effectCount))")
    }

    @Test("Edit plan has valid intensity range")
    func validIntensity() {
        let captions = [
            TestFixture.caption(start: 0, end: 3, text: "Hook!", role: .hook, behavior: .hookImpact),
            TestFixture.caption(start: 3, end: 6, text: "Content", role: .regular, behavior: .none),
            TestFixture.caption(start: 6, end: 9, text: "Conclusion", role: .conclusion, behavior: .conclusionHold),
        ]
        let roughCut = TestFixture.roughCutResult(
            decisions: [
                RoughCutDecision(startTime: 0, endTime: 9, action: .keep, reason: "Content", confidence: 0.9, linkedTranscriptText: nil, requiresReview: false)
            ],
            originalDuration: 9.0,
            cleanDuration: 9.0
        )
        let editPlan = EditDecisionEngine.generateEditPlan(
            captions: captions,
            roughCut: roughCut,
            template: .viralCaption
        )

        for decision in editPlan.decisions {
            #expect(decision.intensity >= 0 && decision.intensity <= 1.0,
                    "Intensity must be 0-1, got \(decision.intensity) for \(decision.type)")
        }
    }
}
