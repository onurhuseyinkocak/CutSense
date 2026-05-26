import Foundation
import Testing
@testable import CutSense

// MARK: - Export pipeline verification tests

@Suite("Quality Gate Tests")
struct QualityGateTests {

    @Test("Pipeline export target is fixed social 1080x1920")
    func pipelineExportTargetIsFixedSocialResolution() {
        #expect(ExportService.socialExportRenderSize == CGSize(width: 1080, height: 1920))
    }

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

    @Test("Tech Influencer semantic combo density passes generic density gate")
    func techInfluencerSemanticComboDensityPasses() {
        let captions = [
            TestFixture.caption(start: 0, end: 2.2, text: "This AI tool builds apps", role: .hook, style: .hookImpact, behavior: .hookImpact),
            TestFixture.caption(start: 13.4, end: 18.0, text: "click generate and the result appears", role: .reveal, style: .neonGlow, behavior: .punchIn),
            TestFixture.caption(start: 30.6, end: 37.4, text: "follow for more and comment Vibe", role: .conclusion, style: .hookImpact, behavior: .conclusionHold),
        ]
        let decisions = (0..<20).map { index in
            TestFixture.editDecision(
                time: Double(index) * 0.85,
                type: index.isMultiple(of: 3) ? .sfx : .zoom,
                reason: "Tech semantic combo cue"
            )
        }
        let editPlan = EditPlan(
            decisions: decisions,
            template: .techInfluencer,
            totalEffects: decisions.count,
            averageIntensity: 0.25
        )
        let roughCut = TestFixture.roughCutResult(
            decisions: [
                RoughCutDecision(startTime: 0, endTime: 19.13, action: .keep, reason: "Tech semantic keep", confidence: 0.95, linkedTranscriptText: nil, requiresReview: false)
            ],
            originalDuration: 37.38,
            cleanDuration: 19.13
        )

        let report = QualityGateService.evaluate(
            captions: captions,
            editPlan: editPlan,
            roughCut: roughCut,
            template: .techInfluencer
        )

        let densityCheck = report.checks.first { $0.name == "Effect density" }
        #expect(densityCheck?.passed == true)
    }

    @Test("Warning-only score below production threshold fails quality gate")
    func warningOnlyLowScoreFailsQualityGate() {
        let captions = [
            TestFixture.caption(start: 0, end: 3, text: "Regular content", role: .regular),
            TestFixture.caption(start: 3, end: 6, text: "More regular content", role: .regular),
        ]
        let effects = (0..<8).map { index in
            TestFixture.editDecision(time: Double(index) * 0.35, type: .zoom)
        }
        let editPlan = EditPlan(
            decisions: effects,
            template: .viralCaption,
            totalEffects: effects.count,
            averageIntensity: 0.7
        )
        let roughCut = TestFixture.roughCutResult(
            decisions: [
                RoughCutDecision(startTime: 0, endTime: 6, action: .keep, reason: "Content", confidence: 0.9, linkedTranscriptText: nil, requiresReview: false)
            ],
            originalDuration: 10,
            cleanDuration: 6
        )

        let report = QualityGateService.evaluate(
            captions: captions,
            editPlan: editPlan,
            roughCut: roughCut,
            template: .viralCaption
        )

        #expect(report.score < 80)
        #expect(!report.passed)
    }

    @Test("Post-export verifier rejects missing output file")
    func postExportVerifierRejectsMissingOutputFile() async {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "cutsense-missing-\(UUID().uuidString).mp4")

        let report = await ExportVerifier.verify(
            outputURL: url,
            expectedDuration: 1,
            expectedResolution: "1080x1920"
        )

        #expect(!report.passed)
        #expect(report.failedChecks.contains("file missing"))
        #expect(report.failedChecks.contains("video track missing"))
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

    @Test("Captions are generated for reviewRequired segments that remain on timeline")
    func captionsForReviewRequiredSegments() {
        let segments = [
            TestFixture.segment(start: 0, end: 2, text: "Keep this", type: .contentSentence),
            TestFixture.segment(start: 3, end: 5, text: "Review this but keep it", type: .contentSentence),
        ]
        let transcription = TestFixture.transcription(segments: segments)
        let decisions = [
            RoughCutDecision(startTime: 0, endTime: 2, action: .keep, reason: "Content", confidence: 0.95, linkedTranscriptText: "Keep this", requiresReview: false),
            RoughCutDecision(startTime: 3, endTime: 5, action: .reviewRequired, reason: "Uncertain but timeline-safe", confidence: 0.55, linkedTranscriptText: "Review this but keep it", requiresReview: true),
        ]
        let roughCut = TestFixture.roughCutResult(
            decisions: decisions,
            originalDuration: 5,
            cleanDuration: 4
        )

        let captions = CaptionEngine.generateCaptions(
            from: transcription,
            roughCut: roughCut,
            template: .premiumFounder
        )

        #expect(captions.contains { $0.text.contains("Review this") })
    }

    @Test("Captions are generated when rough cut has no decisions")
    func captionsForNoDecisionRoughCut() {
        let segments = [
            TestFixture.segment(start: 0, end: 2, text: "Original transcript", type: .contentSentence),
        ]
        let transcription = TestFixture.transcription(segments: segments)
        let roughCut = TestFixture.roughCutResult(
            decisions: [],
            originalDuration: 2,
            cleanDuration: 2
        )

        let captions = CaptionEngine.generateCaptions(
            from: transcription,
            roughCut: roughCut,
            template: .premiumFounder
        )

        #expect(captions.count == 1)
        #expect(captions[0].text == "Original transcript")
    }

    @Test("Tech Influencer captions vary style by semantic event")
    func techInfluencerCaptionsVaryStyleBySemanticEvent() {
        let segments = [
            TestFixture.segment(start: 0.0, end: 2.0, text: "This AI tool builds apps", type: .contentSentence),
            TestFixture.segment(start: 2.6, end: 5.2, text: "Most people waste weeks coding the wrong thing", type: .contentSentence),
            TestFixture.segment(start: 5.8, end: 8.2, text: "Click generate and the result appears", type: .contentSentence),
            TestFixture.segment(start: 8.8, end: 11.2, text: "Then it launches the MVP faster", type: .contentSentence),
            TestFixture.segment(start: 11.8, end: 14.0, text: "Follow for more and comment Vibe", type: .contentSentence),
        ]
        let transcription = TestFixture.transcription(segments: segments, language: "en-US")
        let roughCut = TestFixture.roughCutAllKept(segments: segments, originalDuration: 14.0)

        let captions = CaptionEngine.generateCaptions(
            from: transcription,
            roughCut: roughCut,
            template: .techInfluencer
        )

        #expect(Set(captions.map(\.style)).count >= 4)
        #expect(captions.contains { $0.text.localizedStandardContains("wrong") && $0.style == .focusStatement })
        #expect(captions.contains { $0.text.localizedStandardContains("Click generate") && $0.style == .typewriterClean })
        #expect(captions.contains { $0.text.localizedStandardContains("Follow") && $0.style == .premiumLowerThird })
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
        #expect(editPlan.decisions.contains { $0.type == .zoom && $0.reason == "Founder hook push" })
        #expect(editPlan.decisions.contains { $0.type == .sfx && $0.reason == "Founder soft impact SFX" })
        #expect(!editPlan.decisions.contains { $0.type == .flash }, "Premium Founder should not use viral hook flashes")
        #expect(!editPlan.decisions.contains { $0.type == .shake }, "Premium Founder should not use viral hook shakes")
    }

    @Test("Transition behavior combines whoosh with camera motion")
    func transitionCombinesWhooshWithCameraMotion() {
        let captions = [
            TestFixture.caption(start: 2, end: 4, text: "Ama şimdi", role: .transition, style: .boldCenterViral, behavior: .transitionWhoosh),
        ]
        let roughCut = TestFixture.roughCutResult(
            decisions: [
                RoughCutDecision(startTime: 0, endTime: 5, action: .keep, reason: "Content", confidence: 0.9, linkedTranscriptText: nil, requiresReview: false)
            ],
            originalDuration: 5,
            cleanDuration: 5
        )

        let editPlan = EditDecisionEngine.generateEditPlan(
            captions: captions,
            roughCut: roughCut,
            template: .viralCaption
        )

        #expect(editPlan.decisions.contains { $0.type == .sfx && $0.reason == "Transition whoosh" })
        #expect(editPlan.decisions.contains { $0.type == .zoom && $0.reason == "Transition whip zoom" })
        #expect(editPlan.decisions.contains { $0.type == .flash && $0.reason == "Transition flash" })
    }

    @Test("Conclusion behavior combines riser with slow push")
    func conclusionCombinesRiserWithSlowPush() {
        let captions = [
            TestFixture.caption(start: 5, end: 7, text: "Birlikte büyüyelim", role: .conclusion, style: .hookImpact, behavior: .conclusionHold),
        ]
        let roughCut = TestFixture.roughCutResult(
            decisions: [
                RoughCutDecision(startTime: 0, endTime: 8, action: .keep, reason: "Content", confidence: 0.9, linkedTranscriptText: nil, requiresReview: false)
            ],
            originalDuration: 8,
            cleanDuration: 8
        )

        let editPlan = EditDecisionEngine.generateEditPlan(
            captions: captions,
            roughCut: roughCut,
            template: .viralCaption
        )

        #expect(editPlan.decisions.contains { $0.type == .zoom && $0.reason == "Conclusion slow push" })
        #expect(editPlan.decisions.contains { $0.type == .sfx && $0.reason == "Conclusion riser" })
        #expect(editPlan.decisions.contains { $0.type == .colorShift && $0.reason == "Conclusion mood" })
    }

    @Test("Tech keyword effects anchor to the spoken keyword timing")
    func techKeywordEffectsAnchorToSpokenKeywordTiming() {
        let captions = [
            CaptionSegment(
                startTime: 10.0,
                endTime: 13.0,
                text: "doğru şekilde yapay zekayı anlatman gerekiyor",
                role: .regular,
                style: .neonGlow,
                sceneBehavior: .keywordLockOn,
                wordTimings: [
                    (word: "doğru", start: 10.0, duration: 0.24),
                    (word: "şekilde", start: 10.32, duration: 0.30),
                    (word: "yapay", start: 10.92, duration: 0.28),
                    (word: "zekayı", start: 11.24, duration: 0.28),
                    (word: "anlatman", start: 11.62, duration: 0.34),
                    (word: "gerekiyor", start: 12.02, duration: 0.34)
                ]
            )
        ]
        let roughCut = TestFixture.roughCutResult(
            decisions: [
                RoughCutDecision(startTime: 0, endTime: 14, action: .keep, reason: "Content", confidence: 0.9, linkedTranscriptText: nil, requiresReview: false)
            ],
            originalDuration: 14,
            cleanDuration: 14
        )

        let editPlan = EditDecisionEngine.generateEditPlan(
            captions: captions,
            roughCut: roughCut,
            template: .techInfluencer
        )

        let zoom = editPlan.decisions.first { $0.reason == "Tech keyword controlled zoom" }
        #expect(zoom != nil)
        #expect(abs((zoom?.time ?? 0) - 10.60) < 0.001)
        #expect(abs((zoom?.duration ?? 0) - 0.64) < 0.001)
        #expect(!editPlan.decisions.contains { $0.reason == "Tech keyword click SFX" })
    }

    @Test("Tech trigger matching ignores AI substrings")
    func techTriggerMatchingIgnoresAISubstrings() {
        let captions = [
            TestFixture.caption(start: 0.0, end: 1.0, text: "paid email main flow", role: .regular),
            TestFixture.caption(start: 3.0, end: 4.0, text: "AI builds on web", role: .regular),
            TestFixture.caption(start: 6.0, end: 7.0, text: "App Store'a web'e gönderiyoruz", role: .regular),
        ]

        let planned = CaptionSceneEventPlanner.assignSceneBehaviors(
            to: captions,
            template: .techInfluencer
        )

        #expect(planned[0].sceneBehavior == .none)
        #expect(planned[1].sceneBehavior == .keywordLockOn)
        #expect(planned[2].sceneBehavior == .keywordLockOn)
    }

    @Test("Tech planner rejects UI and keyword false positives")
    func techPlannerRejectsUIAndKeywordFalsePositives() {
        let captions = [
            TestFixture.caption(start: 0.0, end: 1.0, text: "Secret sauce burada", role: .regular),
            TestFixture.caption(start: 3.0, end: 4.0, text: "Bu davranış çok açık", role: .regular),
            TestFixture.caption(start: 6.0, end: 7.0, text: "MVP değil sadece demo", role: .regular),
            TestFixture.caption(start: 9.0, end: 10.0, text: "deployment plan is clear", role: .regular),
            TestFixture.caption(start: 12.0, end: 13.0, text: "open source project", role: .regular),
            TestFixture.caption(start: 15.0, end: 16.0, text: "run rate looks stable", role: .regular),
            TestFixture.caption(start: 18.0, end: 19.0, text: "we deploy faster every week", role: .regular),
            TestFixture.caption(start: 21.0, end: 22.0, text: "I generate ideas", role: .regular),
            TestFixture.caption(start: 24.0, end: 25.0, text: "tap into momentum", role: .regular),
            TestFixture.caption(start: 27.0, end: 28.0, text: "press release lands today", role: .regular),
            TestFixture.caption(start: 30.0, end: 31.0, text: "select few creators respond", role: .regular),
            TestFixture.caption(start: 33.0, end: 34.0, text: "ad copy converts better", role: .regular),
            TestFixture.caption(start: 36.0, end: 37.0, text: "en baştan vazgeçiyor", role: .regular),
            TestFixture.caption(start: 39.0, end: 40.0, text: "now generate revenue", role: .regular),
            TestFixture.caption(start: 42.0, end: 43.0, text: "select a niche", role: .regular),
            TestFixture.caption(start: 45.0, end: 46.0, text: "copy this strategy", role: .regular),
            TestFixture.caption(start: 48.0, end: 49.0, text: "paste ideas together", role: .regular),
            TestFixture.caption(start: 51.0, end: 52.0, text: "tap a new market", role: .regular),
            TestFixture.caption(start: 54.0, end: 55.0, text: "press on through churn", role: .regular),
            TestFixture.caption(start: 57.0, end: 58.0, text: "copy the strategy", role: .regular),
            TestFixture.caption(start: 60.0, end: 61.0, text: "paste together a plan", role: .regular),
            TestFixture.caption(start: 63.0, end: 64.0, text: "click rate improved", role: .regular),
            TestFixture.caption(start: 66.0, end: 67.0, text: "stratejiyi kopyalıyoruz", role: .regular),
            TestFixture.caption(start: 69.0, end: 70.0, text: "fikirleri yapıştırıyoruz", role: .regular),
            TestFixture.caption(start: 72.0, end: 73.0, text: "takımı çalıştırıyorum", role: .regular),
            TestFixture.caption(start: 75.0, end: 76.0, text: "copy the app idea", role: .regular),
            TestFixture.caption(start: 78.0, end: 79.0, text: "selected customer segment", role: .regular),
            TestFixture.caption(start: 81.0, end: 82.2, text: "Şimdi generate'e basıyorum", role: .transition),
        ]

        let planned = CaptionSceneEventPlanner.assignSceneBehaviors(
            to: captions,
            template: .techInfluencer
        )

        for index in 0..<(planned.count - 1) {
            #expect(planned[index].sceneBehavior == .none)
        }
        #expect(planned.last?.sceneBehavior == .focusBlur)
    }

    @Test("Tech planner keeps real UI object actions")
    func techPlannerKeepsRealUIObjectActions() {
        let captions = [
            TestFixture.caption(start: 0.0, end: 1.0, text: "copy the API key from the field", role: .regular),
            TestFixture.caption(start: 2.0, end: 3.0, text: "select the deploy option in the menu", role: .regular),
            TestFixture.caption(start: 4.0, end: 5.0, text: "open the app", role: .regular),
            TestFixture.caption(start: 6.0, end: 7.0, text: "terminal içinde çalıştırıyorum", role: .regular)
        ]

        let planned = CaptionSceneEventPlanner.assignSceneBehaviors(
            to: captions,
            template: .techInfluencer
        )

        #expect(planned.allSatisfy { $0.sceneBehavior == .focusBlur })
    }

    @Test("Tech error screen actions stay UI intent instead of warning")
    func techErrorScreenActionsStayUIIntent() {
        let text = "hata ekranını açıyoruz"
        let captions = CaptionSceneEventPlanner.assignSceneBehaviors(
            to: [TestFixture.caption(start: 3.0, end: 4.6, text: text, role: .regular)],
            template: .techInfluencer
        )
        #expect(captions.first?.sceneBehavior == .focusBlur)

        var segment = TestFixture.segment(
            start: 3.0,
            end: 4.6,
            text: text,
            confidence: 0.96,
            type: .contentSentence
        )
        segment.wordTimings = [
            (word: "hata", start: 3.08, duration: 0.18),
            (word: "ekranını", start: 3.46, duration: 0.26),
            (word: "açıyoruz", start: 4.05, duration: 0.30)
        ]
        let transcription = TestFixture.transcription(segments: [segment])
        let timelinePlan = TechInfluencerTimelineAnalyzer.analyze(
            transcription: transcription,
            audioAnalysis: TestFixture.audioResult(duration: 5.0)
        )

        #expect(timelinePlan.events.contains { $0.kind == .uiAction && abs($0.anchorTime - 4.05) < 0.01 })
        #expect(!timelinePlan.events.contains { $0.kind == .warning })

        let roughCut = TestFixture.roughCutResult(
            decisions: [
                RoughCutDecision(startTime: 0, endTime: 5, action: .keep, reason: "Content", confidence: 0.9, linkedTranscriptText: nil, requiresReview: false)
            ],
            originalDuration: 5,
            cleanDuration: 5
        )
        let editPlan = EditDecisionEngine.generateEditPlan(
            captions: captions,
            roughCut: roughCut,
            template: .techInfluencer,
            timelinePlan: timelinePlan
        )
        let reasons = Set(editPlan.decisions.map(\.reason))

        #expect(reasons.contains("Tech UI focus zoom"))
        #expect(reasons.contains("Tech UI highlight pulse"))
        #expect(!reasons.contains("Tech warning amber accent"))
    }

    @Test("Tech UI action anchors on the action verb instead of screen noun")
    func techUIActionAnchorsOnActionVerb() {
        let captions = [
            CaptionSegment(
                startTime: 4.0,
                endTime: 6.0,
                text: "On this screen I click generate",
                role: .regular,
                style: .neonGlow,
                sceneBehavior: .focusBlur,
                wordTimings: [
                    (word: "On", start: 4.02, duration: 0.12),
                    (word: "this", start: 4.18, duration: 0.14),
                    (word: "screen", start: 4.38, duration: 0.22),
                    (word: "I", start: 4.92, duration: 0.08),
                    (word: "click", start: 5.26, duration: 0.18),
                    (word: "generate", start: 5.58, duration: 0.24)
                ]
            )
        ]
        let roughCut = TestFixture.roughCutResult(
            decisions: [
                RoughCutDecision(startTime: 0, endTime: 8, action: .keep, reason: "Content", confidence: 0.95, linkedTranscriptText: nil, requiresReview: false)
            ],
            originalDuration: 8,
            cleanDuration: 8
        )

        let editPlan = EditDecisionEngine.generateEditPlan(
            captions: captions,
            roughCut: roughCut,
            template: .techInfluencer
        )

        let zoom = editPlan.decisions.first { $0.reason == "Tech UI focus zoom" }
        #expect(zoom != nil)
        #expect(abs((zoom?.time ?? 0) - 4.88) < 0.001)
    }

    @Test("Tech Influencer skips bland opening hook effects")
    func techInfluencerSkipsBlandOpeningHookEffects() {
        let captions = [
            TestFixture.caption(start: 0.10, end: 1.20, text: "Hello everyone", role: .hook, style: .hookImpact, behavior: .hookImpact),
            TestFixture.caption(start: 6.00, end: 7.20, text: "comment Vibe below", role: .conclusion, style: .hookImpact, behavior: .conclusionHold),
        ]
        let roughCut = TestFixture.roughCutResult(
            decisions: [
                RoughCutDecision(startTime: 0, endTime: 8, action: .keep, reason: "Content", confidence: 0.95, linkedTranscriptText: nil, requiresReview: false)
            ],
            originalDuration: 8,
            cleanDuration: 8
        )

        let editPlan = EditDecisionEngine.generateEditPlan(
            captions: captions,
            roughCut: roughCut,
            template: .techInfluencer
        )

        #expect(!editPlan.decisions.contains { $0.reason.hasPrefix("Hook") })
        #expect(editPlan.decisions.contains { $0.reason == "CTA slow push" })
    }

    @Test("Tech quality gate does not require hook combo for bland opening")
    func techQualityGateDoesNotRequireHookComboForBlandOpening() {
        let captions = [
            TestFixture.caption(start: 0.10, end: 1.20, text: "Hello everyone", role: .hook, style: .hookImpact, behavior: .hookImpact),
            TestFixture.caption(start: 6.00, end: 7.20, text: "comment Vibe below", role: .conclusion, style: .hookImpact, behavior: .conclusionHold),
        ]
        let roughCut = TestFixture.roughCutResult(
            decisions: [
                RoughCutDecision(startTime: 0, endTime: 8, action: .keep, reason: "Content", confidence: 0.95, linkedTranscriptText: nil, requiresReview: false)
            ],
            originalDuration: 8,
            cleanDuration: 8
        )

        let editPlan = EditDecisionEngine.generateEditPlan(
            captions: captions,
            roughCut: roughCut,
            template: .techInfluencer
        )
        let report = QualityGateService.evaluate(
            captions: captions,
            editPlan: editPlan,
            roughCut: roughCut,
            template: .techInfluencer
        )
        let failedNames = Set(report.failedChecks.map(\.name))

        #expect(!failedNames.contains("Tech prompt hook combo"))
        #expect(!failedNames.contains("Tech event combos"))
    }

    @Test("Tech warning role emits warning accents instead of keyword effects")
    func techWarningRoleEmitsWarningAccentsInsteadOfKeywordEffects() {
        let captions = CaptionSceneEventPlanner.assignSceneBehaviors(
            to: [
                TestFixture.caption(
                    start: 3.0,
                    end: 4.4,
                    text: "Sakın bu hatayı yapmayın",
                    role: .warning,
                    style: .focusStatement
                )
            ],
            template: .techInfluencer
        )
        let roughCut = TestFixture.roughCutResult(
            decisions: [
                RoughCutDecision(startTime: 0, endTime: 6, action: .keep, reason: "Content", confidence: 0.95, linkedTranscriptText: nil, requiresReview: false)
            ],
            originalDuration: 6,
            cleanDuration: 6
        )

        let editPlan = EditDecisionEngine.generateEditPlan(
            captions: captions,
            roughCut: roughCut,
            template: .techInfluencer
        )

        #expect(captions.first?.sceneBehavior == .underlineReveal)
        #expect(editPlan.decisions.contains { $0.reason == "Tech warning amber accent" })
        #expect(!editPlan.decisions.contains { $0.reason == "Tech warning low impact SFX" })
        #expect(!editPlan.decisions.contains { $0.reason == "Tech keyword controlled zoom" })
        #expect(!editPlan.decisions.contains { $0.reason == "Tech keyword click SFX" })
    }

    @Test("Tech timeline treats transition UI text as UI action, not reveal")
    func techTimelineDoesNotPromoteBareTransitionToReveal() {
        var hook = TestFixture.segment(
            start: 0.0,
            end: 1.4,
            text: "This AI workflow saves hours",
            confidence: 0.96,
            type: .contentSentence
        )
        hook.wordTimings = [
            (word: "This", start: 0.05, duration: 0.12),
            (word: "AI", start: 0.24, duration: 0.16),
            (word: "workflow", start: 0.48, duration: 0.22),
            (word: "saves", start: 0.78, duration: 0.18),
            (word: "hours", start: 1.04, duration: 0.18),
        ]
        var transition = TestFixture.segment(
            start: 4.0,
            end: 5.6,
            text: "sonra dashboard'u açıyoruz",
            confidence: 0.95,
            type: .contentSentence
        )
        transition.wordTimings = [
            (word: "sonra", start: 4.00, duration: 0.20),
            (word: "dashboard'u", start: 4.32, duration: 0.34),
            (word: "açıyoruz", start: 4.82, duration: 0.32),
        ]
        let transcription = TestFixture.transcription(segments: [hook, transition])
        let timelinePlan = TechInfluencerTimelineAnalyzer.analyze(
            transcription: transcription,
            audioAnalysis: TestFixture.audioResult(duration: 6.0)
        )

        #expect(!timelinePlan.events.contains { $0.kind == .reveal && $0.text.contains("dashboard") })
        #expect(timelinePlan.events.contains { $0.kind == .uiAction && abs($0.anchorTime - 4.82) < 0.01 })
    }

    @Test("Tech reveal anchor prefers payoff word over earlier tech keyword")
    func techRevealAnchorPrefersPayoffWordOverEarlierTechKeyword() {
        var hook = TestFixture.segment(
            start: 0.0,
            end: 1.2,
            text: "This AI demo is fast",
            confidence: 0.96,
            type: .contentSentence
        )
        hook.wordTimings = [
            (word: "This", start: 0.05, duration: 0.12),
            (word: "AI", start: 0.24, duration: 0.14),
            (word: "demo", start: 0.46, duration: 0.18),
            (word: "is", start: 0.72, duration: 0.12),
            (word: "fast", start: 0.92, duration: 0.18),
        ]
        var reveal = TestFixture.segment(
            start: 3.0,
            end: 5.8,
            text: "AI builds the app and the result appears",
            confidence: 0.96,
            type: .contentSentence
        )
        reveal.wordTimings = [
            (word: "AI", start: 3.10, duration: 0.14),
            (word: "builds", start: 3.36, duration: 0.20),
            (word: "the", start: 3.66, duration: 0.10),
            (word: "app", start: 3.86, duration: 0.18),
            (word: "and", start: 4.20, duration: 0.10),
            (word: "the", start: 4.58, duration: 0.10),
            (word: "result", start: 4.88, duration: 0.22),
            (word: "appears", start: 5.24, duration: 0.24),
        ]
        let transcription = TestFixture.transcription(segments: [hook, reveal], language: "en-US")
        let timelinePlan = TechInfluencerTimelineAnalyzer.analyze(
            transcription: transcription,
            audioAnalysis: TestFixture.audioResult(duration: 6.0)
        )

        let revealEvent = timelinePlan.events.first { $0.kind == .reveal }
        #expect(abs((revealEvent?.anchorTime ?? 0) - 4.88) < 0.01)
    }

    @Test("Tech reveal anchor uses payoff before product fallback")
    func techRevealAnchorUsesPayoffBeforeProductFallback() {
        var hook = TestFixture.segment(
            start: 0.0,
            end: 1.2,
            text: "This AI demo is fast",
            confidence: 0.96,
            type: .contentSentence
        )
        hook.wordTimings = [
            (word: "This", start: 0.05, duration: 0.12),
            (word: "AI", start: 0.24, duration: 0.14),
            (word: "demo", start: 0.46, duration: 0.18),
            (word: "is", start: 0.72, duration: 0.12),
            (word: "fast", start: 0.92, duration: 0.18),
        ]
        var reveal = TestFixture.segment(
            start: 3.0,
            end: 6.0,
            text: "Vibe Coding ships and the result appears",
            confidence: 0.96,
            type: .contentSentence
        )
        reveal.wordTimings = [
            (word: "Vibe", start: 3.10, duration: 0.18),
            (word: "Coding", start: 3.34, duration: 0.22),
            (word: "ships", start: 3.72, duration: 0.20),
            (word: "and", start: 4.20, duration: 0.10),
            (word: "the", start: 4.58, duration: 0.10),
            (word: "result", start: 4.88, duration: 0.22),
            (word: "appears", start: 5.24, duration: 0.24),
        ]
        let timelinePlan = TechInfluencerTimelineAnalyzer.analyze(
            transcription: TestFixture.transcription(segments: [hook, reveal], language: "en-US"),
            audioAnalysis: TestFixture.audioResult(duration: 6.2)
        )

        let revealEvent = timelinePlan.events.first { $0.kind == .reveal }
        #expect(abs((revealEvent?.anchorTime ?? 0) - 4.88) < 0.01)
    }

    @Test("Tech neutral problem solution text is not warning")
    func techNeutralProblemSolutionTextIsNotWarning() {
        let segments = [
            TestFixture.segment(
                start: 0.0,
                end: 1.2,
                text: "This AI workflow saves hours",
                confidence: 0.96,
                type: .contentSentence
            ),
            TestFixture.segment(
                start: 4.0,
                end: 5.6,
                text: "This tool fixes the problem for users",
                confidence: 0.96,
                type: .contentSentence
            ),
        ]
        let timelinePlan = TechInfluencerTimelineAnalyzer.analyze(
            transcription: TestFixture.transcription(segments: segments, language: "en-US"),
            audioAnalysis: TestFixture.audioResult(duration: 6.0)
        )

        #expect(!timelinePlan.events.contains { $0.kind == .warning && $0.text.contains("problem") })
    }

    @Test("Tech Influencer edit plan uses event-tied combos without viral random effects")
    func techInfluencerUsesEventTiedCombos() {
        let captions = [
            TestFixture.caption(start: 0.10, end: 1.30, text: "This AI tool builds apps", role: .hook, style: .hookImpact, behavior: .hookImpact),
            TestFixture.caption(start: 3.10, end: 4.40, text: "the result appears now", role: .reveal, style: .neonGlow, behavior: .punchIn),
            TestFixture.caption(start: 7.00, end: 8.20, text: "comment Vibe below", role: .conclusion, style: .hookImpact, behavior: .conclusionHold),
        ]
        let roughCut = TestFixture.roughCutResult(
            decisions: [
                RoughCutDecision(startTime: 0, endTime: 8.5, action: .keep, reason: "Content", confidence: 0.9, linkedTranscriptText: nil, requiresReview: false)
            ],
            originalDuration: 8.5,
            cleanDuration: 8.5
        )

        let editPlan = EditDecisionEngine.generateEditPlan(
            captions: captions,
            roughCut: roughCut,
            template: .techInfluencer
        )
        let reasons = Set(editPlan.decisions.map(\.reason))

        #expect(!reasons.contains("Hook short riser"))
        #expect(reasons.contains("Hook slow push-in zoom"))
        #expect(reasons.contains("Hook sentence back zoom"))
        #expect(reasons.contains("Hook keyword impact SFX"))
        #expect(!reasons.contains("Tech reveal riser"))
        #expect(!reasons.contains("Tech reveal whoosh"))
        #expect(reasons.contains("Tech reveal zoom"))
        #expect(reasons.contains("Tech reveal impact SFX"))
        #expect(reasons.contains("CTA slow push"))
        #expect(reasons.contains("CTA notification ping"))
        #expect(editPlan.decisions.filter { $0.type == .sfx }.count <= 5)
        #expect(!editPlan.decisions.contains { $0.type == .flash })
        #expect(!editPlan.decisions.contains { $0.type == .shake })
    }

    @Test("Tech Influencer generated effects are covered by the formal cue spec")
    func techInfluencerGeneratedEffectsAreCoveredByFormalCueSpec() {
        let captions = [
            TestFixture.caption(start: 0.20, end: 1.60, text: "This AI tool builds apps", role: .hook, style: .hookImpact, behavior: .hookImpact),
            TestFixture.caption(start: 3.50, end: 4.80, text: "don't make this mistake", role: .warning, style: .neonGlow, behavior: .underlineReveal),
            TestFixture.caption(start: 7.50, end: 8.70, text: "now here is the demo", role: .transition, style: .typewriterClean, behavior: .transitionWhoosh),
            TestFixture.caption(start: 11.00, end: 12.30, text: "click the generate button", role: .regular, style: .neonGlow, behavior: .focusBlur),
            TestFixture.caption(start: 14.00, end: 15.30, text: "the AI app uses code", role: .keyword, style: .neonGlow, behavior: .keywordLockOn),
            TestFixture.caption(start: 18.00, end: 19.30, text: "the result appears now", role: .reveal, style: .neonGlow, behavior: .punchIn),
            TestFixture.caption(start: 24.00, end: 25.30, text: "follow and comment Vibe", role: .conclusion, style: .hookImpact, behavior: .conclusionHold),
        ]
        let roughCut = TestFixture.roughCutResult(
            decisions: [
                RoughCutDecision(startTime: 0, endTime: 27, action: .keep, reason: "Content", confidence: 0.95, linkedTranscriptText: nil, requiresReview: false)
            ],
            originalDuration: 27,
            cleanDuration: 27
        )

        let editPlan = EditDecisionEngine.generateEditPlan(
            captions: captions,
            roughCut: roughCut,
            template: .techInfluencer
        )
        let generatedReasons = Set(editPlan.decisions.map(\.reason))
        let unsupportedReasons = generatedReasons.filter { TechInfluencerEffectCue(reason: $0) == nil }
        let expectedCoreReasons: Set<String> = [
            "Hook keyword impact SFX",
            "Hook slow push-in zoom",
            "Hook sentence back zoom",
            "Tech UI focus zoom",
            "Tech UI highlight pulse",
            "Tech reveal zoom",
            "Tech reveal impact SFX",
            "CTA slow push",
            "CTA notification ping"
        ]

        #expect(unsupportedReasons.isEmpty, "Generated Tech effects must all be declared in the cue spec: \(unsupportedReasons.sorted())")
        #expect(expectedCoreReasons.isSubset(of: generatedReasons), "High-priority Tech combos should survive semantic pruning")
    }

    @Test("Tech Influencer quality gate accepts generated event-anchored plan")
    func techInfluencerQualityGateAcceptsGeneratedEventAnchoredPlan() {
        let captions = [
            TestFixture.caption(start: 0.20, end: 1.60, text: "This AI tool builds apps", role: .hook, style: .hookImpact, behavior: .hookImpact),
            TestFixture.caption(start: 4.00, end: 5.20, text: "the result appears now", role: .reveal, style: .neonGlow, behavior: .punchIn),
            TestFixture.caption(start: 8.00, end: 9.20, text: "comment Vibe below", role: .conclusion, style: .hookImpact, behavior: .conclusionHold),
        ]
        let keep = RoughCutDecision(
            startTime: 0,
            endTime: 10,
            action: .keep,
            reason: "Content",
            confidence: 0.95,
            linkedTranscriptText: nil,
            requiresReview: false
        )
        let roughCut = TestFixture.roughCutResult(
            decisions: [keep],
            originalDuration: 10,
            cleanDuration: 10
        )
        let editPlan = EditDecisionEngine.generateEditPlan(
            captions: captions,
            roughCut: roughCut,
            template: .techInfluencer
        )

        let report = QualityGateService.evaluate(
            captions: captions,
            editPlan: editPlan,
            roughCut: roughCut,
            template: .techInfluencer
        )

        #expect(report.checks.first { $0.name == "Tech event anchoring" }?.passed == true)
        #expect(report.checks.first { $0.name == "Tech event combos" }?.passed == true)
        #expect(report.passed)
    }

    @Test("Tech Influencer quality gate rejects duplicate semantic cue on one event")
    func techInfluencerQualityGateRejectsDuplicateSemanticCueOnOneEvent() {
        let captions = [
            TestFixture.caption(start: 0.20, end: 1.60, text: "This AI tool builds apps", role: .hook, style: .hookImpact, behavior: .hookImpact),
            TestFixture.caption(start: 4.00, end: 5.20, text: "the result appears now", role: .reveal, style: .neonGlow, behavior: .punchIn),
            TestFixture.caption(start: 8.00, end: 9.20, text: "comment Vibe below", role: .conclusion, style: .hookImpact, behavior: .conclusionHold),
        ]
        let roughCut = TestFixture.roughCutResult(
            decisions: [RoughCutDecision(startTime: 0, endTime: 10, action: .keep, reason: "Content", confidence: 0.95, linkedTranscriptText: nil, requiresReview: false)],
            originalDuration: 10,
            cleanDuration: 10
        )
        let generatedPlan = EditDecisionEngine.generateEditPlan(
            captions: captions,
            roughCut: roughCut,
            template: .techInfluencer
        )
        let duplicate = EditDecision(time: 8.05, duration: 0.14, type: .sfx, reason: "CTA notification ping", intensity: 0.28)
        let decisions = generatedPlan.decisions + [duplicate]
        let report = QualityGateService.evaluate(
            captions: captions,
            editPlan: EditPlan(decisions: decisions, template: .techInfluencer, totalEffects: decisions.count, averageIntensity: 0.25),
            roughCut: roughCut,
            template: .techInfluencer
        )

        let duplicateGuard = report.checks.first { $0.name == "Tech prompt duplicate cue guard" }
        #expect(duplicateGuard?.passed == false)
        #expect(duplicateGuard?.blocksExport == true)
        #expect(!report.passed)
    }

    @Test("Tech Influencer quality gate rejects reveal effects away from payoff word")
    func techInfluencerQualityGateRejectsRevealEffectsAwayFromPayoffWord() {
        let hook = TestFixture.caption(start: 0.20, end: 1.60, text: "This AI tool builds apps", role: .hook, style: .hookImpact, behavior: .hookImpact)
        let reveal = CaptionSegment(
            startTime: 3.00,
            endTime: 6.20,
            text: "watch the demo and the result appears",
            role: .reveal,
            style: .neonGlow,
            sceneBehavior: .punchIn,
            wordTimings: [
                (word: "watch", start: 3.05, duration: 0.18),
                (word: "the", start: 3.30, duration: 0.10),
                (word: "demo", start: 3.48, duration: 0.20),
                (word: "and", start: 4.20, duration: 0.12),
                (word: "the", start: 4.82, duration: 0.10),
                (word: "result", start: 5.05, duration: 0.20),
                (word: "appears", start: 5.38, duration: 0.24)
            ]
        )
        let cta = TestFixture.caption(start: 8.00, end: 9.20, text: "comment Vibe below", role: .conclusion, style: .hookImpact, behavior: .conclusionHold)
        let captions = [hook, reveal, cta]
        let roughCut = TestFixture.roughCutResult(
            decisions: [RoughCutDecision(startTime: 0, endTime: 10, action: .keep, reason: "Content", confidence: 0.95, linkedTranscriptText: nil, requiresReview: false)],
            originalDuration: 10,
            cleanDuration: 10
        )
        let generatedPlan = EditDecisionEngine.generateEditPlan(
            captions: captions,
            roughCut: roughCut,
            template: .techInfluencer
        )
        let shifted = generatedPlan.decisions.map { decision in
            switch decision.reason {
            case "Tech reveal zoom":
                EditDecision(time: 2.80, duration: decision.duration, type: decision.type, reason: decision.reason, intensity: decision.intensity)
            case "Tech reveal impact SFX":
                EditDecision(time: 3.05, duration: decision.duration, type: decision.type, reason: decision.reason, intensity: decision.intensity)
            default:
                decision
            }
        }
        let report = QualityGateService.evaluate(
            captions: captions,
            editPlan: EditPlan(decisions: shifted, template: .techInfluencer, totalEffects: shifted.count, averageIntensity: 0.25),
            roughCut: roughCut,
            template: .techInfluencer
        )

        let anchoring = report.checks.first { $0.name == "Tech event anchoring" }
        #expect(anchoring?.passed == false)
        #expect(anchoring?.blocksExport == true)
        #expect(!report.passed)
    }

    @Test("Tech Influencer generic business words do not spawn keyword or reveal effects")
    func techInfluencerGenericBusinessWordsDoNotSpawnKeywordOrRevealEffects() {
        let captions = [
            TestFixture.caption(start: 0.00, end: 1.20, text: "This AI workflow is practical", role: .hook, style: .hookImpact, behavior: .hookImpact),
            TestFixture.caption(start: 3.00, end: 4.20, text: "we build trust with users", role: .regular),
            TestFixture.caption(start: 6.00, end: 7.20, text: "fix the problem for teams", role: .regular),
            TestFixture.caption(start: 10.00, end: 11.20, text: "comment Vibe below", role: .conclusion, style: .hookImpact, behavior: .conclusionHold),
        ]
        let roughCut = TestFixture.roughCutResult(
            decisions: [RoughCutDecision(startTime: 0, endTime: 12, action: .keep, reason: "Content", confidence: 0.95, linkedTranscriptText: nil, requiresReview: false)],
            originalDuration: 12,
            cleanDuration: 12
        )

        let editPlan = EditDecisionEngine.generateEditPlan(
            captions: captions,
            roughCut: roughCut,
            template: .techInfluencer
        )

        #expect(!editPlan.decisions.contains { $0.reason == "Tech keyword controlled zoom" })
        #expect(!editPlan.decisions.contains { $0.reason == "Tech reveal impact SFX" })
    }

    @Test("Tech Influencer budgets effects by clean timeline duration")
    func techInfluencerBudgetsEffectsByCleanTimelineDuration() {
        let captions = [
            TestFixture.caption(start: 0.20, end: 1.60, text: "This AI tool builds apps", role: .hook, style: .hookImpact, behavior: .hookImpact),
            TestFixture.caption(start: 8.00, end: 9.20, text: "don't make this mistake", role: .warning, style: .neonGlow, behavior: .underlineReveal),
            TestFixture.caption(start: 16.00, end: 17.20, text: "click generate button", role: .regular, style: .neonGlow, behavior: .focusBlur),
            TestFixture.caption(start: 28.00, end: 29.30, text: "the result appears now", role: .reveal, style: .neonGlow, behavior: .punchIn),
            TestFixture.caption(start: 52.00, end: 53.20, text: "comment Vibe below", role: .conclusion, style: .hookImpact, behavior: .conclusionHold),
        ]
        let roughCut = TestFixture.roughCutResult(
            decisions: [RoughCutDecision(startTime: 0, endTime: 60, action: .keep, reason: "Content", confidence: 0.95, linkedTranscriptText: nil, requiresReview: false)],
            originalDuration: 60,
            cleanDuration: 10
        )

        let editPlan = EditDecisionEngine.generateEditPlan(
            captions: captions,
            roughCut: roughCut,
            template: .techInfluencer
        )

        #expect(editPlan.decisions.filter { $0.type == .sfx }.count <= 4)
        #expect(editPlan.decisions.filter { $0.reason == "Tech reveal impact SFX" }.count <= 1)
    }

    @Test("Tech Influencer quality gate rejects unsupported random effect")
    func techInfluencerQualityGateRejectsUnsupportedRandomEffect() {
        let captions = [
            TestFixture.caption(start: 0.20, end: 1.60, text: "This AI tool builds apps", role: .hook, style: .hookImpact, behavior: .hookImpact),
            TestFixture.caption(start: 4.00, end: 5.20, text: "the result appears now", role: .reveal, style: .neonGlow, behavior: .punchIn),
            TestFixture.caption(start: 8.00, end: 9.20, text: "comment Vibe below", role: .conclusion, style: .hookImpact, behavior: .conclusionHold),
        ]
        let keep = RoughCutDecision(
            startTime: 0,
            endTime: 10,
            action: .keep,
            reason: "Content",
            confidence: 0.95,
            linkedTranscriptText: nil,
            requiresReview: false
        )
        let roughCut = TestFixture.roughCutResult(
            decisions: [keep],
            originalDuration: 10,
            cleanDuration: 10
        )
        let generatedPlan = EditDecisionEngine.generateEditPlan(
            captions: captions,
            roughCut: roughCut,
            template: .techInfluencer
        )
        let decisions = generatedPlan.decisions + [
            EditDecision(time: 2.40, duration: 0.20, type: .sfx, reason: "Random viral whoosh", intensity: 0.70)
        ]
        let report = QualityGateService.evaluate(
            captions: captions,
            editPlan: EditPlan(decisions: decisions, template: .techInfluencer, totalEffects: decisions.count, averageIntensity: 0.3),
            roughCut: roughCut,
            template: .techInfluencer
        )

        let anchoring = report.checks.first { $0.name == "Tech event anchoring" }
        #expect(anchoring?.passed == false)
        #expect(anchoring?.blocksExport == true)
        #expect(!report.passed)
    }

    @Test("Tech Influencer quality gate rejects incomplete reveal combo")
    func techInfluencerQualityGateRejectsIncompleteRevealCombo() {
        let captions = [
            TestFixture.caption(start: 0.20, end: 1.60, text: "This AI tool builds apps", role: .hook, style: .hookImpact, behavior: .hookImpact),
            TestFixture.caption(start: 4.00, end: 5.20, text: "the result appears now", role: .reveal, style: .neonGlow, behavior: .punchIn),
            TestFixture.caption(start: 8.00, end: 9.20, text: "comment Vibe below", role: .conclusion, style: .hookImpact, behavior: .conclusionHold),
        ]
        let keep = RoughCutDecision(
            startTime: 0,
            endTime: 10,
            action: .keep,
            reason: "Content",
            confidence: 0.95,
            linkedTranscriptText: nil,
            requiresReview: false
        )
        let roughCut = TestFixture.roughCutResult(
            decisions: [keep],
            originalDuration: 10,
            cleanDuration: 10
        )
        let decisions = [
            EditDecision(time: 0.05, duration: 0.70, type: .sfx, reason: "Hook short riser", intensity: 0.26),
            EditDecision(time: 0.20, duration: 0.70, type: .zoom, reason: "Hook slow push-in zoom", intensity: 0.18),
            EditDecision(time: 0.90, duration: 0.70, type: .zoom, reason: "Hook sentence back zoom", intensity: 0.18),
            EditDecision(time: 0.20, duration: 0.16, type: .sfx, reason: "Hook keyword impact SFX", intensity: 0.38),
            EditDecision(time: 4.00, duration: 0.16, type: .sfx, reason: "Tech reveal impact SFX", intensity: 0.40),
            EditDecision(time: 7.15, duration: 0.85, type: .sfx, reason: "CTA music lift riser", intensity: 0.22),
            EditDecision(time: 8.00, duration: 0.14, type: .sfx, reason: "CTA notification ping", intensity: 0.28),
        ]
        let report = QualityGateService.evaluate(
            captions: captions,
            editPlan: EditPlan(decisions: decisions, template: .techInfluencer, totalEffects: decisions.count, averageIntensity: 0.3),
            roughCut: roughCut,
            template: .techInfluencer
        )

        let combos = report.checks.first { $0.name == "Tech event combos" }
        #expect(combos?.passed == false)
        #expect(combos?.blocksExport == true)
        #expect(combos?.detail.localizedStandardContains("reveal") == true)
        #expect(!report.passed)
    }

    @Test("Tech Influencer quality gate rejects incomplete topic shift combo")
    func techInfluencerQualityGateRejectsIncompleteTopicShiftCombo() {
        let captions = [
            TestFixture.caption(start: 0.20, end: 1.60, text: "This AI tool builds apps", role: .hook, style: .hookImpact, behavior: .hookImpact),
            TestFixture.caption(start: 4.00, end: 5.20, text: "now here is the demo", role: .transition, style: .typewriterClean, behavior: .transitionWhoosh),
            TestFixture.caption(start: 8.00, end: 9.20, text: "comment Vibe below", role: .conclusion, style: .hookImpact, behavior: .conclusionHold),
        ]
        let keep = RoughCutDecision(
            startTime: 0,
            endTime: 10,
            action: .keep,
            reason: "Content",
            confidence: 0.95,
            linkedTranscriptText: nil,
            requiresReview: false
        )
        let roughCut = TestFixture.roughCutResult(
            decisions: [keep],
            originalDuration: 10,
            cleanDuration: 10
        )
        let decisions = [
            EditDecision(time: 0.05, duration: 0.70, type: .sfx, reason: "Hook short riser", intensity: 0.26),
            EditDecision(time: 0.20, duration: 0.70, type: .zoom, reason: "Hook slow push-in zoom", intensity: 0.18),
            EditDecision(time: 0.90, duration: 0.70, type: .zoom, reason: "Hook sentence back zoom", intensity: 0.18),
            EditDecision(time: 0.20, duration: 0.16, type: .sfx, reason: "Hook keyword impact SFX", intensity: 0.38),
            EditDecision(time: 3.88, duration: 0.20, type: .sfx, reason: "Topic shift whoosh", intensity: 0.30),
            EditDecision(time: 7.15, duration: 0.85, type: .sfx, reason: "CTA music lift riser", intensity: 0.22),
            EditDecision(time: 8.00, duration: 0.14, type: .sfx, reason: "CTA notification ping", intensity: 0.28),
        ]

        let report = QualityGateService.evaluate(
            captions: captions,
            editPlan: EditPlan(decisions: decisions, template: .techInfluencer, totalEffects: decisions.count, averageIntensity: 0.3),
            roughCut: roughCut,
            template: .techInfluencer
        )

        let combos = report.checks.first { $0.name == "Tech event combos" }
        #expect(combos?.passed == false)
        #expect(combos?.blocksExport == true)
        #expect(combos?.detail.localizedStandardContains("topic shift") == true)
        #expect(!report.passed)
    }

    @Test("Tech Influencer quality gate keeps CTA slow push anchored across split CTA captions")
    func techInfluencerQualityGateAcceptsSplitCTASlowPush() {
        let captions = [
            TestFixture.caption(start: 0.84, end: 2.16, text: "Türkiye'de çok fazla", role: .hook, style: .hookImpact, behavior: .hookImpact),
            TestFixture.caption(start: 32.10, end: 33.30, text: "bu topluluğun bir parçası", role: .conclusion, style: .hookImpact, behavior: .conclusionHold),
            TestFixture.caption(start: 33.30, end: 34.80, text: "olmak istersen yorumlara Vibe yazıp", role: .conclusion, style: .hookImpact, behavior: .conclusionHold),
        ]
        let keep = RoughCutDecision(
            startTime: 0,
            endTime: 37,
            action: .keep,
            reason: "Content",
            confidence: 0.95,
            linkedTranscriptText: nil,
            requiresReview: false
        )
        let roughCut = TestFixture.roughCutResult(
            decisions: [keep],
            originalDuration: 37,
            cleanDuration: 37
        )
        let decisions = [
            EditDecision(time: 0.80, duration: 0.70, type: .sfx, reason: "Hook short riser", intensity: 0.26),
            EditDecision(time: 0.84, duration: 0.66, type: .zoom, reason: "Hook slow push-in zoom", intensity: 0.18),
            EditDecision(time: 1.50, duration: 0.66, type: .zoom, reason: "Hook sentence back zoom", intensity: 0.18),
            EditDecision(time: 1.50, duration: 0.16, type: .sfx, reason: "Hook keyword impact SFX", intensity: 0.38),
            EditDecision(time: 32.18, duration: 2.40, type: .zoom, reason: "CTA slow push", intensity: 0.18),
            EditDecision(time: 33.11, duration: 0.85, type: .sfx, reason: "CTA music lift riser", intensity: 0.22),
            EditDecision(time: 33.96, duration: 0.14, type: .sfx, reason: "CTA notification ping", intensity: 0.28),
        ]

        let report = QualityGateService.evaluate(
            captions: captions,
            editPlan: EditPlan(decisions: decisions, template: .techInfluencer, totalEffects: decisions.count, averageIntensity: 0.24),
            roughCut: roughCut,
            template: .techInfluencer
        )

        #expect(report.checks.first { $0.name == "Tech event anchoring" }?.passed == true)
        #expect(report.checks.first { $0.name == "Tech event combos" }?.passed == true)
        #expect(report.passed)
    }

    @Test("Tech Influencer quality gate rejects semantically present but visually weak zooms")
    func techInfluencerQualityGateRejectsWeakSemanticZooms() {
        let captions = [
            TestFixture.caption(start: 0.20, end: 1.60, text: "This AI tool builds apps", role: .hook, style: .hookImpact, behavior: .hookImpact),
            TestFixture.caption(start: 8.00, end: 9.20, text: "comment Vibe below", role: .conclusion, style: .hookImpact, behavior: .conclusionHold),
        ]
        let keep = RoughCutDecision(
            startTime: 0,
            endTime: 10,
            action: .keep,
            reason: "Content",
            confidence: 0.95,
            linkedTranscriptText: nil,
            requiresReview: false
        )
        let roughCut = TestFixture.roughCutResult(
            decisions: [keep],
            originalDuration: 10,
            cleanDuration: 10
        )
        let decisions = [
            EditDecision(time: 0.05, duration: 0.70, type: .sfx, reason: "Hook short riser", intensity: 0.26),
            EditDecision(time: 0.20, duration: 0.75, type: .zoom, reason: "Hook slow push-in zoom", intensity: 0.04),
            EditDecision(time: 0.95, duration: 0.65, type: .zoom, reason: "Hook sentence back zoom", intensity: 0.04),
            EditDecision(time: 0.20, duration: 0.16, type: .sfx, reason: "Hook keyword impact SFX", intensity: 0.38),
            EditDecision(time: 7.15, duration: 0.85, type: .sfx, reason: "CTA music lift riser", intensity: 0.22),
            EditDecision(time: 8.00, duration: 1.20, type: .zoom, reason: "CTA slow push", intensity: 0.18),
            EditDecision(time: 8.00, duration: 0.14, type: .sfx, reason: "CTA notification ping", intensity: 0.28),
        ]

        let report = QualityGateService.evaluate(
            captions: captions,
            editPlan: EditPlan(decisions: decisions, template: .techInfluencer, totalEffects: decisions.count, averageIntensity: 0.20),
            roughCut: roughCut,
            template: .techInfluencer
        )

        let strength = report.checks.first { $0.name == "Tech prompt zoom strength" }
        #expect(strength?.passed == false)
        #expect(strength?.blocksExport == true)
        #expect(!report.passed)
    }

    @Test("Tech Influencer quality gate rejects monotone caption treatment")
    func techInfluencerQualityGateRejectsMonotoneCaptionTreatment() {
        let captions = [
            TestFixture.caption(start: 0.20, end: 1.60, text: "This AI tool builds apps", role: .hook, style: .neonGlow, behavior: .hookImpact),
            TestFixture.caption(start: 3.00, end: 4.30, text: "Most people waste weeks", role: .warning, style: .neonGlow, behavior: .underlineReveal),
            TestFixture.caption(start: 6.00, end: 7.20, text: "click generate now", role: .regular, style: .neonGlow, behavior: .focusBlur),
            TestFixture.caption(start: 10.00, end: 11.20, text: "the result appears", role: .reveal, style: .neonGlow, behavior: .punchIn),
            TestFixture.caption(start: 15.00, end: 16.20, text: "comment Vibe below", role: .conclusion, style: .neonGlow, behavior: .conclusionHold),
        ]
        let roughCut = TestFixture.roughCutResult(
            decisions: [
                RoughCutDecision(
                    startTime: 0,
                    endTime: 17,
                    action: .keep,
                    reason: "Content",
                    confidence: 0.95,
                    linkedTranscriptText: nil,
                    requiresReview: false
                )
            ],
            originalDuration: 17,
            cleanDuration: 17
        )
        let editPlan = EditDecisionEngine.generateEditPlan(
            captions: captions,
            roughCut: roughCut,
            template: .techInfluencer
        )

        let report = QualityGateService.evaluate(
            captions: captions,
            editPlan: editPlan,
            roughCut: roughCut,
            template: .techInfluencer
        )

        let variety = report.checks.first { $0.name == "Tech caption visual variety" }
        #expect(variety?.passed == false)
        #expect(variety?.blocksExport == true)
        #expect(!report.passed)
    }

    @Test("Tech Influencer quality gate rejects semantic cues lost after export remap")
    func techInfluencerQualityGateRejectsSemanticCueLossAfterExportRemap() {
        let captions = [
            TestFixture.caption(start: 0.20, end: 1.60, text: "This AI tool builds apps", role: .hook, style: .hookImpact, behavior: .hookImpact),
            TestFixture.caption(start: 4.00, end: 5.20, text: "the result appears now", role: .reveal, style: .neonGlow, behavior: .punchIn),
            TestFixture.caption(start: 8.00, end: 9.20, text: "comment Vibe below", role: .conclusion, style: .premiumLowerThird, behavior: .conclusionHold),
        ]
        let roughCut = TestFixture.roughCutResult(
            decisions: [
                RoughCutDecision(startTime: 0, endTime: 2, action: .keep, reason: "Hook keep", confidence: 0.95, linkedTranscriptText: nil, requiresReview: false),
                RoughCutDecision(startTime: 8, endTime: 10, action: .keep, reason: "CTA keep", confidence: 0.95, linkedTranscriptText: nil, requiresReview: false),
            ],
            originalDuration: 10,
            cleanDuration: 4
        )
        let decisions = [
            EditDecision(time: 0.05, duration: 0.70, type: .sfx, reason: "Hook short riser", intensity: 0.26),
            EditDecision(time: 0.20, duration: 0.70, type: .zoom, reason: "Hook slow push-in zoom", intensity: 0.18),
            EditDecision(time: 0.90, duration: 0.70, type: .zoom, reason: "Hook sentence back zoom", intensity: 0.18),
            EditDecision(time: 0.20, duration: 0.16, type: .sfx, reason: "Hook keyword impact SFX", intensity: 0.38),
            EditDecision(time: 3.30, duration: 0.65, type: .sfx, reason: "Tech reveal riser", intensity: 0.22),
            EditDecision(time: 3.90, duration: 0.16, type: .sfx, reason: "Tech reveal whoosh", intensity: 0.28),
            EditDecision(time: 3.76, duration: 0.72, type: .zoom, reason: "Tech reveal zoom", intensity: 0.26),
            EditDecision(time: 4.00, duration: 0.16, type: .sfx, reason: "Tech reveal impact SFX", intensity: 0.40),
            EditDecision(time: 7.15, duration: 0.85, type: .sfx, reason: "CTA music lift riser", intensity: 0.22),
            EditDecision(time: 8.00, duration: 1.20, type: .zoom, reason: "CTA slow push", intensity: 0.18),
            EditDecision(time: 8.00, duration: 0.14, type: .sfx, reason: "CTA notification ping", intensity: 0.28),
        ]

        let report = QualityGateService.evaluate(
            captions: captions,
            editPlan: EditPlan(decisions: decisions, template: .techInfluencer, totalEffects: decisions.count, averageIntensity: 0.25),
            roughCut: roughCut,
            template: .techInfluencer
        )

        let survivability = report.checks.first { $0.name == "Tech export-ready semantic survivability" }
        #expect(survivability?.passed == false)
        #expect(survivability?.blocksExport == true)
        #expect(!report.passed)
    }

    @Test("Tech Influencer long CTA caption anchors CTA push near the final phrase")
    func techInfluencerLongCTACaptionAnchorsCTAPushNearEnd() {
        let captions = [
            TestFixture.caption(start: 0.0, end: 1.22, text: "This is the hook line", role: .hook, style: .hookImpact, behavior: .hookImpact),
            TestFixture.caption(start: 1.22, end: 2.32, text: "Key insight here", role: .regular, style: .focusStatement, behavior: .none),
            TestFixture.caption(start: 2.32, end: 37.48, text: "Follow for more", role: .conclusion, style: .hookImpact, behavior: .conclusionHold),
        ]
        let keep = RoughCutDecision(
            startTime: 0,
            endTime: 37.48,
            action: .keep,
            reason: "Content",
            confidence: 0.95,
            linkedTranscriptText: nil,
            requiresReview: false
        )
        let roughCut = TestFixture.roughCutResult(
            decisions: [keep],
            originalDuration: 37.48,
            cleanDuration: 37.48
        )

        let editPlan = EditDecisionEngine.generateEditPlan(
            captions: captions,
            roughCut: roughCut,
            template: .techInfluencer
        )
        let ctaPush = editPlan.decisions.first { $0.reason == "CTA slow push" }
        let ctaPing = editPlan.decisions.first { $0.reason == "CTA notification ping" }

        #expect((ctaPush?.time ?? 0) > 34.0)
        #expect(!editPlan.decisions.contains { $0.reason == "CTA music lift riser" })
        #expect(abs((ctaPing?.time ?? 0) - 37.28) < 0.01)

        let report = QualityGateService.evaluate(
            captions: captions,
            editPlan: editPlan,
            roughCut: roughCut,
            template: .techInfluencer
        )

        #expect(report.checks.first { $0.name == "Tech event anchoring" }?.passed == true)
        #expect(report.checks.first { $0.name == "Tech event combos" }?.passed == true)
        #expect(report.passed)
    }

    @Test("Tech Influencer quality gate rejects reveal combos closer than prompt spacing")
    func techInfluencerQualityGateRejectsCloseRevealCombos() {
        let captions = [
            TestFixture.caption(start: 0.20, end: 1.60, text: "This AI tool builds apps", role: .hook, style: .hookImpact, behavior: .hookImpact),
            TestFixture.caption(start: 4.00, end: 5.20, text: "the result appears now", role: .reveal, style: .neonGlow, behavior: .punchIn),
            TestFixture.caption(start: 5.50, end: 6.60, text: "then the app launches", role: .reveal, style: .neonGlow, behavior: .punchIn),
            TestFixture.caption(start: 8.00, end: 9.20, text: "comment Vibe below", role: .conclusion, style: .hookImpact, behavior: .conclusionHold),
        ]
        let keep = RoughCutDecision(
            startTime: 0,
            endTime: 10,
            action: .keep,
            reason: "Content",
            confidence: 0.95,
            linkedTranscriptText: nil,
            requiresReview: false
        )
        let roughCut = TestFixture.roughCutResult(
            decisions: [keep],
            originalDuration: 10,
            cleanDuration: 10
        )
        let decisions = [
            EditDecision(time: 0.05, duration: 0.70, type: .sfx, reason: "Hook short riser", intensity: 0.26),
            EditDecision(time: 0.20, duration: 0.70, type: .zoom, reason: "Hook slow push-in zoom", intensity: 0.18),
            EditDecision(time: 0.90, duration: 0.70, type: .zoom, reason: "Hook sentence back zoom", intensity: 0.18),
            EditDecision(time: 0.20, duration: 0.16, type: .sfx, reason: "Hook keyword impact SFX", intensity: 0.38),
            EditDecision(time: 3.30, duration: 0.65, type: .sfx, reason: "Tech reveal riser", intensity: 0.22),
            EditDecision(time: 3.90, duration: 0.16, type: .sfx, reason: "Tech reveal whoosh", intensity: 0.28),
            EditDecision(time: 4.00, duration: 0.16, type: .sfx, reason: "Tech reveal impact SFX", intensity: 0.40),
            EditDecision(time: 4.80, duration: 0.65, type: .sfx, reason: "Tech reveal riser", intensity: 0.22),
            EditDecision(time: 5.40, duration: 0.16, type: .sfx, reason: "Tech reveal whoosh", intensity: 0.28),
            EditDecision(time: 5.50, duration: 0.16, type: .sfx, reason: "Tech reveal impact SFX", intensity: 0.40),
            EditDecision(time: 8.15, duration: 0.85, type: .sfx, reason: "CTA music lift riser", intensity: 0.22),
            EditDecision(time: 9.00, duration: 0.14, type: .sfx, reason: "CTA notification ping", intensity: 0.28),
        ]

        let report = QualityGateService.evaluate(
            captions: captions,
            editPlan: EditPlan(decisions: decisions, template: .techInfluencer, totalEffects: decisions.count, averageIntensity: 0.3),
            roughCut: roughCut,
            template: .techInfluencer
        )

        let spacing = report.checks.first { $0.name == "Tech prompt reveal combo spacing" }
        #expect(spacing?.passed == false)
        #expect(spacing?.blocksExport == true)
        #expect(!report.passed)
    }

    @Test("Tech Influencer export normalizer drops reveal combos compressed too close after rough cut")
    func techInfluencerExportNormalizerDropsCompressedRevealCombos() {
        let decisions = [
            EditDecision(time: 9.09, duration: 0.65, type: .sfx, reason: "Tech reveal riser", intensity: 0.22),
            EditDecision(time: 9.54, duration: 0.72, type: .zoom, reason: "Tech reveal zoom", intensity: 0.26),
            EditDecision(time: 9.69, duration: 0.16, type: .sfx, reason: "Tech reveal whoosh", intensity: 0.28),
            EditDecision(time: 9.79, duration: 0.16, type: .sfx, reason: "Tech reveal impact SFX", intensity: 0.40),
            EditDecision(time: 11.13, duration: 0.65, type: .sfx, reason: "Tech reveal riser", intensity: 0.22),
            EditDecision(time: 11.59, duration: 0.72, type: .zoom, reason: "Tech reveal zoom", intensity: 0.26),
            EditDecision(time: 11.73, duration: 0.16, type: .sfx, reason: "Tech reveal whoosh", intensity: 0.28),
            EditDecision(time: 11.83, duration: 0.16, type: .sfx, reason: "Tech reveal impact SFX", intensity: 0.40),
        ]

        let normalized = TechInfluencerEditDecisionNormalizer.exportReadyDecisions(
            decisions,
            templateId: "tech_influencer"
        )

        #expect(normalized.filter { $0.reason == "Tech reveal impact SFX" }.count == 1)
        #expect(normalized.contains { $0.reason == "Tech reveal impact SFX" && abs($0.time - 11.83) < 0.001 })
        #expect(!normalized.contains { $0.reason == "Tech reveal impact SFX" && abs($0.time - 9.79) < 0.001 })
    }

    @Test("Tech Influencer quality gate requires combo on every reveal event")
    func techInfluencerQualityGateRequiresEveryRevealCombo() {
        let captions = [
            TestFixture.caption(start: 0.20, end: 1.60, text: "This AI tool builds apps", role: .hook, style: .hookImpact, behavior: .hookImpact),
            TestFixture.caption(start: 4.00, end: 5.20, text: "the result appears now", role: .reveal, style: .neonGlow, behavior: .punchIn),
            TestFixture.caption(start: 8.50, end: 9.60, text: "then the launch result appears", role: .reveal, style: .neonGlow, behavior: .punchIn),
            TestFixture.caption(start: 12.00, end: 13.20, text: "comment Vibe below", role: .conclusion, style: .hookImpact, behavior: .conclusionHold),
        ]
        let keep = RoughCutDecision(
            startTime: 0,
            endTime: 14,
            action: .keep,
            reason: "Content",
            confidence: 0.95,
            linkedTranscriptText: nil,
            requiresReview: false
        )
        let roughCut = TestFixture.roughCutResult(
            decisions: [keep],
            originalDuration: 14,
            cleanDuration: 14
        )
        let decisions = [
            EditDecision(time: 0.05, duration: 0.70, type: .sfx, reason: "Hook short riser", intensity: 0.26),
            EditDecision(time: 0.20, duration: 0.70, type: .zoom, reason: "Hook slow push-in zoom", intensity: 0.18),
            EditDecision(time: 0.90, duration: 0.70, type: .zoom, reason: "Hook sentence back zoom", intensity: 0.18),
            EditDecision(time: 0.20, duration: 0.16, type: .sfx, reason: "Hook keyword impact SFX", intensity: 0.38),
            EditDecision(time: 3.30, duration: 0.65, type: .sfx, reason: "Tech reveal riser", intensity: 0.22),
            EditDecision(time: 3.90, duration: 0.16, type: .sfx, reason: "Tech reveal whoosh", intensity: 0.28),
            EditDecision(time: 4.00, duration: 0.16, type: .sfx, reason: "Tech reveal impact SFX", intensity: 0.40),
            EditDecision(time: 12.15, duration: 0.85, type: .sfx, reason: "CTA music lift riser", intensity: 0.22),
            EditDecision(time: 13.00, duration: 0.14, type: .sfx, reason: "CTA notification ping", intensity: 0.28),
        ]

        let report = QualityGateService.evaluate(
            captions: captions,
            editPlan: EditPlan(decisions: decisions, template: .techInfluencer, totalEffects: decisions.count, averageIntensity: 0.3),
            roughCut: roughCut,
            template: .techInfluencer
        )

        let combos = report.checks.first { $0.name == "Tech event combos" }
        #expect(combos?.passed == false)
        #expect(combos?.blocksExport == true)
        #expect(combos?.detail.localizedStandardContains("reveal") == true)
        #expect(!report.passed)
    }

    @Test("Tech Influencer coalesces adjacent planned and caption reveal combos")
    func techInfluencerCoalescesAdjacentPlannedAndCaptionRevealCombos() {
        let captions = [
            TestFixture.caption(start: 16.58, end: 17.96, text: "da bu yüzden Türkiye'nin", role: .reveal, style: .neonGlow, behavior: .punchIn),
            TestFixture.caption(start: 19.09, end: 20.52, text: "topluluğu Vibe Coding Turkey", role: .keyword, style: .neonGlow, behavior: .keywordLockOn),
        ]
        let roughCut = TestFixture.roughCutResult(
            decisions: [
                RoughCutDecision(startTime: 0.82, endTime: 36.66, action: .keep, reason: "Content", confidence: 0.9, linkedTranscriptText: nil, requiresReview: false)
            ],
            originalDuration: 37.4,
            cleanDuration: 35.84
        )
        let timelinePlan = TechInfluencerTimelinePlan(
            events: [
                TechInfluencerTimelinePlan.Event(
                    kind: .reveal,
                    anchorTime: 18.04,
                    sourceStart: 18.04,
                    sourceEnd: 20.60,
                    text: "ilk Vibe Coding topluluğu Vibe Coding Turkey",
                    confidence: 0.78,
                    reason: "result/reveal phrase"
                )
            ],
            sourceDuration: 37.4
        )

        let editPlan = EditDecisionEngine.generateEditPlan(
            captions: captions,
            roughCut: roughCut,
            template: .techInfluencer,
            timelinePlan: timelinePlan
        )

        let revealImpacts = editPlan.decisions.filter { $0.reason == "Tech reveal impact SFX" }
        #expect(revealImpacts.count == 1)
        #expect(abs((revealImpacts.first?.time ?? 0) - 18.04) < 0.001)
    }

    @Test("Tech Influencer coalesces adjacent planned reveal events")
    func techInfluencerCoalescesAdjacentPlannedRevealEvents() {
        let roughCut = TestFixture.roughCutResult(
            decisions: [
                RoughCutDecision(startTime: 0.82, endTime: 36.66, action: .keep, reason: "Content", confidence: 0.9, linkedTranscriptText: nil, requiresReview: false)
            ],
            originalDuration: 37.4,
            cleanDuration: 35.84
        )
        let timelinePlan = TechInfluencerTimelinePlan(
            events: [
                TechInfluencerTimelinePlan.Event(
                    kind: .reveal,
                    anchorTime: 16.58,
                    sourceStart: 15.16,
                    sourceEnd: 17.98,
                    text: "gerekiyor işte tam da bu yüzden Türkiye'nin",
                    confidence: 0.77,
                    reason: "result/reveal phrase"
                ),
                TechInfluencerTimelinePlan.Event(
                    kind: .reveal,
                    anchorTime: 18.04,
                    sourceStart: 18.04,
                    sourceEnd: 20.60,
                    text: "ilk Vibe Coding topluluğu Vibe Coding Turkey",
                    confidence: 0.78,
                    reason: "result/reveal phrase"
                )
            ],
            sourceDuration: 37.4
        )

        let editPlan = EditDecisionEngine.generateEditPlan(
            captions: [],
            roughCut: roughCut,
            template: .techInfluencer,
            timelinePlan: timelinePlan
        )

        let revealImpacts = editPlan.decisions.filter { $0.reason == "Tech reveal impact SFX" }
        #expect(revealImpacts.count == 1)
        #expect(abs((revealImpacts.first?.time ?? 0) - 18.04) < 0.001)
    }

    @Test("Tech Influencer timeline does not treat writing words as early CTA")
    func techInfluencerTimelineDoesNotTreatWritingWordsAsEarlyCTA() {
        let segments = [
            TestFixture.segment(start: 0.96, end: 3.96, text: "Türkiye'de çok fazla insanın harika fikirleri var"),
            TestFixture.segment(start: 4.32, end: 7.41, text: "ama çoğu kod yazmayı bilmediği için hayata geçemiyor"),
            TestFixture.segment(start: 10.23, end: 13.26, text: "için yıllarca yazılımcı olman gerekmiyor doğru fikri"),
            TestFixture.segment(start: 16.38, end: 18.78, text: "tam da bu yüzden Türkiye'nin ilk"),
            TestFixture.segment(start: 18.78, end: 21.69, text: "Vibe Coding topluluğu Vibe Coding Turkey kurdum kod"),
            TestFixture.segment(start: 32.16, end: 34.89, text: "bu topluluğun bir parçası olmak istersen yorumlara Vibe yazıp"),
            TestFixture.segment(start: 34.89, end: 36.51, text: "birlikte büyüyelim"),
        ]
        let transcription = TestFixture.transcription(segments: segments)
        let audio = TestFixture.audioResult(duration: 37.4)
        let timelinePlan = TechInfluencerTimelineAnalyzer.analyze(
            transcription: transcription,
            audioAnalysis: audio
        )

        #expect(!timelinePlan.events.contains { $0.kind == .cta && $0.anchorTime < 30 })
        #expect(timelinePlan.events.contains { $0.kind == .reveal && abs($0.anchorTime - 18.78) < 0.20 })

        let roughCut = TestFixture.roughCutResult(
            decisions: [
                RoughCutDecision(startTime: 0.86, endTime: 36.63, action: .keep, reason: "Content", confidence: 0.9, linkedTranscriptText: nil, requiresReview: false)
            ],
            originalDuration: 37.4,
            cleanDuration: 35.77
        )
        let captions = [
            TestFixture.caption(start: 0.88, end: 2.16, text: "Türkiye'de çok fazla", role: .hook, style: .hookImpact, behavior: .hookImpact),
            TestFixture.caption(start: 4.24, end: 5.49, text: "ama çoğu kod yazmayı", role: .regular, style: .focusStatement, behavior: .none),
            TestFixture.caption(start: 16.30, end: 18.70, text: "tam da bu yüzden Türkiye'nin ilk", role: .reveal, style: .neonGlow, behavior: .punchIn),
            TestFixture.caption(start: 32.08, end: 33.29, text: "bu topluluğun bir parçası", role: .conclusion, style: .hookImpact, behavior: .conclusionHold),
        ]
        let editPlan = EditDecisionEngine.generateEditPlan(
            captions: captions,
            roughCut: roughCut,
            template: .techInfluencer,
            timelinePlan: timelinePlan
        )
        let reasons = Set(editPlan.decisions.map(\.reason))

        #expect(reasons.contains("Tech reveal riser"))
        #expect(!reasons.contains("Tech reveal whoosh"))
        #expect(reasons.contains("Tech reveal impact SFX"))
        #expect(!editPlan.decisions.contains { $0.reason == "CTA notification ping" && $0.time < 30 })
    }

    @Test("Tech Influencer extracts UI action and reveal from one spoken segment")
    func techInfluencerExtractsMultipleSemanticEventsFromOneSegment() {
        var hook = TestFixture.segment(
            start: 0.0,
            end: 1.2,
            text: "This AI tool changes everything",
            confidence: 0.96,
            type: .contentSentence
        )
        hook.wordTimings = [
            (word: "This", start: 0.05, duration: 0.14),
            (word: "AI", start: 0.24, duration: 0.16),
            (word: "tool", start: 0.45, duration: 0.18),
            (word: "changes", start: 0.70, duration: 0.22),
            (word: "everything", start: 0.98, duration: 0.20),
        ]
        var demo = TestFixture.segment(
            start: 3.0,
            end: 6.8,
            text: "click generate and the result appears",
            confidence: 0.96,
            type: .contentSentence
        )
        demo.wordTimings = [
            (word: "click", start: 3.10, duration: 0.18),
            (word: "generate", start: 3.52, duration: 0.24),
            (word: "and", start: 4.30, duration: 0.12),
            (word: "the", start: 5.72, duration: 0.10),
            (word: "result", start: 6.00, duration: 0.22),
            (word: "appears", start: 6.32, duration: 0.24),
        ]
        let transcription = TestFixture.transcription(segments: [hook, demo], language: "en-US")
        let audio = TestFixture.audioResult(duration: 7.2)
        let timelinePlan = TechInfluencerTimelineAnalyzer.analyze(
            transcription: transcription,
            audioAnalysis: audio
        )

        let uiEvent = timelinePlan.events.first { $0.kind == .uiAction }
        let revealEvent = timelinePlan.events.first { $0.kind == .reveal }
        #expect(abs((uiEvent?.anchorTime ?? 0) - 3.10) < 0.01)
        #expect(abs((revealEvent?.anchorTime ?? 0) - 6.00) < 0.01)

        let roughCut = TestFixture.roughCutResult(
            decisions: [
                RoughCutDecision(startTime: 0, endTime: 7.2, action: .keep, reason: "Content", confidence: 0.95, linkedTranscriptText: nil, requiresReview: false)
            ],
            originalDuration: 7.2,
            cleanDuration: 7.2
        )
        let editPlan = EditDecisionEngine.generateEditPlan(
            captions: [],
            roughCut: roughCut,
            template: .techInfluencer,
            timelinePlan: timelinePlan
        )
        let reasons = Set(editPlan.decisions.map(\.reason))
        #expect(reasons.contains("Tech UI highlight pulse"))
        #expect(!reasons.contains("Tech UI focus zoom"))
        #expect(!reasons.contains("Tech UI click SFX"))
        #expect(!reasons.contains("Tech reveal riser"))
        #expect(!reasons.contains("Tech reveal whoosh"))
        #expect(reasons.contains("Tech reveal impact SFX"))

        let verification = TechInfluencerEditPlanVerifier.verify(
            captions: [],
            decisions: editPlan.decisions,
            transcription: transcription
        )
        #expect(verification.unanchoredDecisions.isEmpty)
        #expect(verification.missingCombos.isEmpty)
    }

    @Test("Tech Influencer English UI/reveal segment survives export remap")
    func techInfluencerEnglishUIRevealSegmentSurvivesExportRemap() {
        let transcription = TestFixture.transcription(segments: [
            timedSegment(start: 0.0, end: 2.2, text: "This AI tool builds apps in minutes", confidence: 0.96),
            timedSegment(start: 5.981228117913832, end: 10.467149206349207, text: "Most people waste weeks coding the wrong thing", confidence: 0.95),
            timedSegment(start: 13.457763265306122, end: 17.943684353741496, text: "click generate and the result appears", confidence: 0.96),
            timedSegment(start: 20.934298412698414, end: 24.67256598639456, text: "Vibe Coding Turkey launches the MVP faster", confidence: 0.94),
            timedSegment(start: 30.65379410430839, end: 37.38267573696145, text: "follow for more and comment Vibe", confidence: 0.94),
        ], language: "en-US")
        let roughCut = TestFixture.roughCutResult(
            decisions: [
                RoughCutDecision(startTime: 0.0, endTime: 2.3200000000000003, action: .keep, reason: "Tech semantic keep - hook", confidence: 0.9, linkedTranscriptText: nil, requiresReview: false),
                RoughCutDecision(startTime: 2.3200000000000003, endTime: 5.881228117913833, action: .cut, reason: "Tech pacing dead air/inter-idea gap", confidence: 0.9, linkedTranscriptText: nil, requiresReview: false),
                RoughCutDecision(startTime: 5.881228117913833, endTime: 10.587149206349206, action: .keep, reason: "Tech semantic keep - warning", confidence: 0.9, linkedTranscriptText: nil, requiresReview: false),
                RoughCutDecision(startTime: 10.587149206349206, endTime: 13.357763265306122, action: .cut, reason: "Tech pacing dead air/inter-idea gap", confidence: 0.9, linkedTranscriptText: nil, requiresReview: false),
                RoughCutDecision(startTime: 13.357763265306122, endTime: 18.063684353741497, action: .keep, reason: "Tech semantic keep - reveal,uiAction", confidence: 0.9, linkedTranscriptText: nil, requiresReview: false),
                RoughCutDecision(startTime: 18.063684353741497, endTime: 20.834298412698413, action: .cut, reason: "Tech pacing dead air/inter-idea gap", confidence: 0.9, linkedTranscriptText: nil, requiresReview: false),
                RoughCutDecision(startTime: 20.834298412698413, endTime: 24.79256598639456, action: .keep, reason: "Tech semantic keep - speech phrase", confidence: 0.9, linkedTranscriptText: nil, requiresReview: false),
                RoughCutDecision(startTime: 24.79256598639456, endTime: 30.553794104308388, action: .cut, reason: "Tech pacing dead air/inter-idea gap", confidence: 0.9, linkedTranscriptText: nil, requiresReview: false),
                RoughCutDecision(startTime: 30.553794104308388, endTime: 37.38267573696145, action: .keep, reason: "Tech semantic keep - cta", confidence: 0.9, linkedTranscriptText: nil, requiresReview: false),
            ],
            originalDuration: 37.38267573696145,
            cleanDuration: 22.518991383219962
        )
        let captions = CaptionEngine.generateCaptions(
            from: transcription,
            roughCut: roughCut,
            template: .techInfluencer
        )
        let timelinePlan = TechInfluencerTimelineAnalyzer.analyze(
            transcription: transcription,
            audioAnalysis: TestFixture.audioResult(duration: 37.38267573696145)
        )
        let editPlan = EditDecisionEngine.generateEditPlan(
            captions: captions,
            roughCut: roughCut,
            template: .techInfluencer,
            timelinePlan: timelinePlan
        )

        let report = QualityGateService.evaluate(
            captions: captions,
            editPlan: editPlan,
            roughCut: roughCut,
            template: .techInfluencer,
            transcription: transcription
        )
        let failedNames = Set(report.failedChecks.map(\.name))

        #expect(editPlan.decisions.count <= 8)
        #expect(editPlan.decisions.contains { $0.reason == "Tech UI highlight pulse" })
        #expect(!editPlan.decisions.contains { $0.reason == "Tech UI focus zoom" })
        #expect(!editPlan.decisions.contains { $0.reason == "Hook short riser" })
        #expect(!failedNames.contains("Tech export-ready semantic survivability"))
        #expect(!failedNames.contains("Tech event anchoring"))
        #expect(!failedNames.contains("Tech event combos"))
    }

    @Test("Tech Influencer treats explicit closing follow or comment phrase as CTA")
    func techInfluencerClosingFollowPhraseBeatsKeywordCTA() {
        var hook = TestFixture.segment(
            start: 0.0,
            end: 2.2,
            text: "This AI tool builds apps in minutes",
            confidence: 0.96,
            type: .contentSentence
        )
        hook.wordTimings = [
            (word: "This", start: 0.0, duration: 0.30),
            (word: "AI", start: 0.30, duration: 0.15),
            (word: "tool", start: 0.46, duration: 0.30),
            (word: "builds", start: 0.76, duration: 0.46),
            (word: "apps", start: 1.21, duration: 0.30),
            (word: "in", start: 1.52, duration: 0.15),
            (word: "minutes", start: 1.67, duration: 0.53),
        ]
        var cta = TestFixture.segment(
            start: 30.65,
            end: 37.38,
            text: "follow for more and comment Vibe",
            confidence: 0.94,
            type: .contentSentence
        )
        cta.wordTimings = [
            (word: "follow", start: 30.65, duration: 1.50),
            (word: "for", start: 32.15, duration: 0.75),
            (word: "more", start: 32.90, duration: 1.00),
            (word: "and", start: 33.89, duration: 0.75),
            (word: "comment", start: 34.64, duration: 1.74),
            (word: "Vibe", start: 36.39, duration: 1.00),
        ]
        let transcription = TestFixture.transcription(segments: [hook, cta], language: "en-US")
        let audio = TestFixture.audioResult(duration: 37.38)
        let timelinePlan = TechInfluencerTimelineAnalyzer.analyze(
            transcription: transcription,
            audioAnalysis: audio
        )

        #expect(timelinePlan.events.contains { $0.kind == .cta && abs($0.anchorTime - 34.64) < 0.01 })

        let roughCut = TestFixture.roughCutResult(
            decisions: [
                RoughCutDecision(startTime: 0, endTime: 37.38, action: .keep, reason: "Content", confidence: 0.95, linkedTranscriptText: nil, requiresReview: false)
            ],
            originalDuration: 37.38,
            cleanDuration: 37.38
        )
        let editPlan = EditDecisionEngine.generateEditPlan(
            captions: [],
            roughCut: roughCut,
            template: .techInfluencer,
            timelinePlan: timelinePlan
        )
        let reasons = Set(editPlan.decisions.map(\.reason))
        #expect(!reasons.contains("CTA music lift riser"))
        #expect(reasons.contains("CTA slow push"))
        #expect(reasons.contains("CTA notification ping"))
        #expect(abs((editPlan.decisions.first { $0.reason == "CTA notification ping" }?.time ?? 0) - 34.64) < 0.01)
    }

    @Test("Tech Influencer does not fabricate CTA from final non-CTA segment")
    func techInfluencerFinalBenefitWithoutCTAStaysNonCTA() {
        let segments = [
            TestFixture.segment(
                start: 0.0,
                end: 2.1,
                text: "This AI workflow saves hours",
                confidence: 0.95,
                type: .contentSentence
            ),
            TestFixture.segment(
                start: 18.0,
                end: 21.0,
                text: "the dashboard stays readable for users",
                confidence: 0.95,
                type: .contentSentence
            ),
        ]
        let transcription = TestFixture.transcription(segments: segments, language: "en-US")
        let audio = TestFixture.audioResult(duration: 21.0)
        let timelinePlan = TechInfluencerTimelineAnalyzer.analyze(
            transcription: transcription,
            audioAnalysis: audio
        )

        #expect(!timelinePlan.events.contains { $0.kind == .cta })

        let roughCut = TestFixture.roughCutResult(
            decisions: [
                RoughCutDecision(startTime: 0, endTime: 21, action: .keep, reason: "Content", confidence: 0.95, linkedTranscriptText: nil, requiresReview: false)
            ],
            originalDuration: 21,
            cleanDuration: 21
        )
        let editPlan = EditDecisionEngine.generateEditPlan(
            captions: [
                TestFixture.caption(start: 0, end: 2.1, text: "This AI workflow saves hours", role: .hook, style: .hookImpact, behavior: .hookImpact),
                TestFixture.caption(start: 18, end: 21, text: "the dashboard stays readable for users", role: .regular, style: .neonGlow, behavior: .none),
            ],
            roughCut: roughCut,
            template: .techInfluencer,
            timelinePlan: timelinePlan
        )
        let reasons = Set(editPlan.decisions.map(\.reason))
        #expect(!reasons.contains("CTA music lift riser"))
        #expect(!reasons.contains("CTA slow push"))
        #expect(!reasons.contains("CTA notification ping"))
    }

    @Test("Tech Influencer does not treat like/comment nouns as CTA")
    func techInfluencerDoesNotTreatLikeCommentNounsAsCTA() {
        let segments = [
            TestFixture.segment(
                start: 0.0,
                end: 2.1,
                text: "This AI workflow saves hours",
                confidence: 0.95,
                type: .contentSentence
            ),
            TestFixture.segment(
                start: 18.0,
                end: 21.0,
                text: "I don't like this bug in the comment parser",
                confidence: 0.95,
                type: .contentSentence
            ),
        ]
        let timelinePlan = TechInfluencerTimelineAnalyzer.analyze(
            transcription: TestFixture.transcription(segments: segments, language: "en-US"),
            audioAnalysis: TestFixture.audioResult(duration: 21.0)
        )

        #expect(!timelinePlan.events.contains { $0.kind == .cta })
    }

    @Test("Tech Influencer bare Turkish yorumlara does not become CTA")
    func techInfluencerBareYorumlaraDoesNotBecomeCTA() {
        let segments = [
            TestFixture.segment(
                start: 0.0,
                end: 2.1,
                text: "Bu AI workflow saatler kazandırır",
                confidence: 0.95,
                type: .contentSentence
            ),
            TestFixture.segment(
                start: 18.0,
                end: 21.0,
                text: "yorumlara göre karar veriyoruz",
                confidence: 0.95,
                type: .contentSentence
            )
        ]
        let timelinePlan = TechInfluencerTimelineAnalyzer.analyze(
            transcription: TestFixture.transcription(segments: segments, language: "tr-TR"),
            audioAnalysis: TestFixture.audioResult(duration: 21.0)
        )
        let nonClosingRole = CaptionRoleClassifier.classify(
            text: "yorumlara göre karar veriyoruz",
            index: 1,
            totalSegments: 3,
            previousRole: .regular,
            startTime: 18.0
        )

        #expect(!timelinePlan.events.contains { $0.kind == .cta })
        #expect(nonClosingRole != .conclusion)

        let roughCut = TestFixture.roughCutResult(
            decisions: [
                RoughCutDecision(startTime: 0, endTime: 21, action: .keep, reason: "Content", confidence: 0.95, linkedTranscriptText: nil, requiresReview: false)
            ],
            originalDuration: 21,
            cleanDuration: 21
        )
        let editPlan = EditDecisionEngine.generateEditPlan(
            captions: [
                TestFixture.caption(start: 0, end: 2.1, text: "Bu AI workflow saatler kazandırır", role: .hook, style: .hookImpact, behavior: .hookImpact),
                TestFixture.caption(start: 18, end: 21, text: "yorumlara göre karar veriyoruz", role: .conclusion, style: .premiumLowerThird, behavior: .conclusionHold)
            ],
            roughCut: roughCut,
            template: .techInfluencer,
            timelinePlan: timelinePlan
        )
        let reasons = Set(editPlan.decisions.map(\.reason))

        #expect(!reasons.contains("CTA slow push"))
        #expect(!reasons.contains("CTA notification ping"))
        #expect(!reasons.contains("CTA music lift riser"))
    }

    @Test("Tech Influencer follow up and save file wording stay non-CTA")
    func techInfluencerFollowUpAndSaveFileStayNonCTA() {
        let segments = [
            TestFixture.segment(
                start: 0.0,
                end: 2.0,
                text: "This AI workflow saves hours",
                confidence: 0.95,
                type: .contentSentence
            ),
            TestFixture.segment(
                start: 18.0,
                end: 20.0,
                text: "we follow up after launch",
                confidence: 0.95,
                type: .contentSentence
            ),
            TestFixture.segment(
                start: 21.0,
                end: 23.0,
                text: "save the file before export",
                confidence: 0.95,
                type: .contentSentence
            )
        ]
        let timelinePlan = TechInfluencerTimelineAnalyzer.analyze(
            transcription: TestFixture.transcription(segments: segments, language: "en-US"),
            audioAnalysis: TestFixture.audioResult(duration: 23.0)
        )

        #expect(!timelinePlan.events.contains { $0.kind == .cta })

        let roughCut = TestFixture.roughCutResult(
            decisions: [
                RoughCutDecision(startTime: 0, endTime: 23, action: .keep, reason: "Content", confidence: 0.95, linkedTranscriptText: nil, requiresReview: false)
            ],
            originalDuration: 23,
            cleanDuration: 23
        )
        let editPlan = EditDecisionEngine.generateEditPlan(
            captions: [],
            roughCut: roughCut,
            template: .techInfluencer,
            timelinePlan: timelinePlan
        )
        let reasons = Set(editPlan.decisions.map(\.reason))

        #expect(!reasons.contains("CTA slow push"))
        #expect(!reasons.contains("CTA notification ping"))
    }

    @Test("Tech Influencer follow for more remains CTA")
    func techInfluencerFollowForMoreRemainsCTA() {
        var cta = TestFixture.segment(
            start: 18.0,
            end: 20.4,
            text: "follow for more",
            confidence: 0.95,
            type: .contentSentence
        )
        cta.wordTimings = [
            (word: "follow", start: 18.10, duration: 0.32),
            (word: "for", start: 18.52, duration: 0.18),
            (word: "more", start: 18.82, duration: 0.26)
        ]
        let timelinePlan = TechInfluencerTimelineAnalyzer.analyze(
            transcription: TestFixture.transcription(segments: [
                TestFixture.segment(start: 0, end: 2, text: "This AI tool saves hours", confidence: 0.95, type: .contentSentence),
                cta
            ], language: "en-US"),
            audioAnalysis: TestFixture.audioResult(duration: 20.4)
        )

        #expect(timelinePlan.events.contains { $0.kind == .cta && abs($0.anchorTime - 18.10) < 0.01 })

        let roughCut = TestFixture.roughCutResult(
            decisions: [
                RoughCutDecision(startTime: 0, endTime: 20.4, action: .keep, reason: "Content", confidence: 0.95, linkedTranscriptText: nil, requiresReview: false)
            ],
            originalDuration: 20.4,
            cleanDuration: 20.4
        )
        let editPlan = EditDecisionEngine.generateEditPlan(
            captions: [],
            roughCut: roughCut,
            template: .techInfluencer,
            timelinePlan: timelinePlan
        )
        let reasons = Set(editPlan.decisions.map(\.reason))

        #expect(reasons.contains("CTA slow push"))
        #expect(reasons.contains("CTA notification ping"))
    }

    @Test("Tech Influencer business generated language does not become reveal")
    func techInfluencerBusinessGeneratedLanguageDoesNotBecomeReveal() {
        let text = "the press release generated a select few qualified leads"
        let segment = TestFixture.segment(
            start: 4.0,
            end: 6.6,
            text: text,
            confidence: 0.96,
            type: .contentSentence
        )
        let timelinePlan = TechInfluencerTimelineAnalyzer.analyze(
            transcription: TestFixture.transcription(segments: [segment], language: "en-US"),
            audioAnalysis: TestFixture.audioResult(duration: 8.0)
        )

        #expect(!timelinePlan.events.contains { $0.kind == .reveal })
        #expect(!timelinePlan.events.contains { $0.kind == .uiAction })

        let roughCut = TestFixture.roughCutResult(
            decisions: [
                RoughCutDecision(startTime: 0, endTime: 8, action: .keep, reason: "Content", confidence: 0.95, linkedTranscriptText: nil, requiresReview: false)
            ],
            originalDuration: 8,
            cleanDuration: 8
        )
        let editPlan = EditDecisionEngine.generateEditPlan(
            captions: [
                TestFixture.caption(start: 4, end: 6.6, text: text, role: .reveal, style: .premiumLowerThird, behavior: .punchIn)
            ],
            roughCut: roughCut,
            template: .techInfluencer,
            timelinePlan: timelinePlan
        )
        let reasons = Set(editPlan.decisions.map(\.reason))

        #expect(!reasons.contains("Tech reveal zoom"))
        #expect(!reasons.contains("Tech reveal impact SFX"))
        #expect(!reasons.contains("Tech UI focus zoom"))
        #expect(!reasons.contains("Tech UI click SFX"))
    }

    @Test("Tech Influencer generated app stays a product reveal")
    func techInfluencerGeneratedAppStaysProductReveal() {
        var segment = TestFixture.segment(
            start: 4.0,
            end: 6.2,
            text: "the AI generated the app",
            confidence: 0.96,
            type: .contentSentence
        )
        segment.wordTimings = [
            (word: "the", start: 4.04, duration: 0.12),
            (word: "AI", start: 4.24, duration: 0.14),
            (word: "generated", start: 4.58, duration: 0.32),
            (word: "the", start: 4.98, duration: 0.12),
            (word: "app", start: 5.18, duration: 0.20)
        ]
        let timelinePlan = TechInfluencerTimelineAnalyzer.analyze(
            transcription: TestFixture.transcription(segments: [segment], language: "en-US"),
            audioAnalysis: TestFixture.audioResult(duration: 8.0)
        )

        #expect(timelinePlan.events.contains { $0.kind == .reveal && abs($0.anchorTime - 4.58) < 0.01 })
        #expect(!timelinePlan.events.contains { $0.kind == .uiAction })

        let roughCut = TestFixture.roughCutResult(
            decisions: [
                RoughCutDecision(startTime: 0, endTime: 8, action: .keep, reason: "Content", confidence: 0.95, linkedTranscriptText: nil, requiresReview: false)
            ],
            originalDuration: 8,
            cleanDuration: 8
        )
        let editPlan = EditDecisionEngine.generateEditPlan(
            captions: [],
            roughCut: roughCut,
            template: .techInfluencer,
            timelinePlan: timelinePlan
        )
        let reasons = Set(editPlan.decisions.map(\.reason))

        #expect(reasons.contains("Tech reveal zoom"))
        #expect(reasons.contains("Tech reveal impact SFX"))
    }

    @Test("Tech Influencer explicit English CTA anchors the latest action")
    func techInfluencerExplicitEnglishCTAAnchorsLatestAction() {
        var cta = TestFixture.segment(
            start: 18.0,
            end: 21.4,
            text: "save this for later and drop a comment",
            confidence: 0.96,
            type: .contentSentence
        )
        cta.wordTimings = [
            (word: "save", start: 18.10, duration: 0.22),
            (word: "this", start: 18.40, duration: 0.16),
            (word: "for", start: 18.66, duration: 0.12),
            (word: "later", start: 18.88, duration: 0.24),
            (word: "and", start: 19.34, duration: 0.14),
            (word: "drop", start: 19.72, duration: 0.20),
            (word: "a", start: 19.98, duration: 0.08),
            (word: "comment", start: 20.14, duration: 0.30)
        ]
        let timelinePlan = TechInfluencerTimelineAnalyzer.analyze(
            transcription: TestFixture.transcription(segments: [
                TestFixture.segment(start: 0, end: 2, text: "This AI tool saves hours", confidence: 0.95, type: .contentSentence),
                cta
            ], language: "en-US"),
            audioAnalysis: TestFixture.audioResult(duration: 21.4)
        )

        #expect(timelinePlan.events.contains { $0.kind == .cta && abs($0.anchorTime - 19.72) < 0.01 })

        let roughCut = TestFixture.roughCutResult(
            decisions: [
                RoughCutDecision(startTime: 0, endTime: 21.4, action: .keep, reason: "Content", confidence: 0.95, linkedTranscriptText: nil, requiresReview: false)
            ],
            originalDuration: 21.4,
            cleanDuration: 21.4
        )
        let editPlan = EditDecisionEngine.generateEditPlan(
            captions: [],
            roughCut: roughCut,
            template: .techInfluencer,
            timelinePlan: timelinePlan
        )
        let reasons = Set(editPlan.decisions.map(\.reason))

        #expect(reasons.contains("CTA slow push"))
        #expect(reasons.contains("CTA notification ping"))
    }

    @Test("Tech Influencer explicit Turkish CTA anchors the latest action")
    func techInfluencerExplicitTurkishCTAAnchorsLatestAction() {
        var cta = TestFixture.segment(
            start: 18.0,
            end: 21.2,
            text: "daha fazlası için takip et ve yorum bırak",
            confidence: 0.96,
            type: .contentSentence
        )
        cta.wordTimings = [
            (word: "daha", start: 18.05, duration: 0.18),
            (word: "fazlası", start: 18.30, duration: 0.28),
            (word: "için", start: 18.66, duration: 0.16),
            (word: "takip", start: 18.92, duration: 0.22),
            (word: "et", start: 19.20, duration: 0.12),
            (word: "ve", start: 19.42, duration: 0.10),
            (word: "yorum", start: 19.68, duration: 0.20),
            (word: "bırak", start: 19.96, duration: 0.24)
        ]
        let timelinePlan = TechInfluencerTimelineAnalyzer.analyze(
            transcription: TestFixture.transcription(segments: [
                TestFixture.segment(start: 0, end: 2, text: "Bu AI workflow saatler kazandırır", confidence: 0.95, type: .contentSentence),
                cta
            ], language: "tr-TR"),
            audioAnalysis: TestFixture.audioResult(duration: 21.2)
        )

        #expect(timelinePlan.events.contains { $0.kind == .cta && abs($0.anchorTime - 19.68) < 0.01 })

        let roughCut = TestFixture.roughCutResult(
            decisions: [
                RoughCutDecision(startTime: 0, endTime: 21.2, action: .keep, reason: "Content", confidence: 0.95, linkedTranscriptText: nil, requiresReview: false)
            ],
            originalDuration: 21.2,
            cleanDuration: 21.2
        )
        let editPlan = EditDecisionEngine.generateEditPlan(
            captions: [],
            roughCut: roughCut,
            template: .techInfluencer,
            timelinePlan: timelinePlan
        )
        let reasons = Set(editPlan.decisions.map(\.reason))

        #expect(reasons.contains("CTA slow push"))
        #expect(reasons.contains("CTA notification ping"))
    }

    @Test("Tech Influencer Turkish generated app anchors reveal on creation verb")
    func techInfluencerTurkishGeneratedAppAnchorsRevealOnCreationVerb() {
        var segment = TestFixture.segment(
            start: 4.0,
            end: 6.3,
            text: "yapay zeka uygulamayı oluşturdu",
            confidence: 0.96,
            type: .contentSentence
        )
        segment.wordTimings = [
            (word: "yapay", start: 4.05, duration: 0.18),
            (word: "zeka", start: 4.30, duration: 0.18),
            (word: "uygulamayı", start: 4.62, duration: 0.34),
            (word: "oluşturdu", start: 5.05, duration: 0.34)
        ]
        let timelinePlan = TechInfluencerTimelineAnalyzer.analyze(
            transcription: TestFixture.transcription(segments: [segment], language: "tr-TR"),
            audioAnalysis: TestFixture.audioResult(duration: 8.0)
        )

        #expect(timelinePlan.events.contains { $0.kind == .reveal && abs($0.anchorTime - 5.05) < 0.01 })
        #expect(!timelinePlan.events.contains { $0.kind == .uiAction })

        let roughCut = TestFixture.roughCutResult(
            decisions: [
                RoughCutDecision(startTime: 0, endTime: 8, action: .keep, reason: "Content", confidence: 0.95, linkedTranscriptText: nil, requiresReview: false)
            ],
            originalDuration: 8,
            cleanDuration: 8
        )
        let editPlan = EditDecisionEngine.generateEditPlan(
            captions: [],
            roughCut: roughCut,
            template: .techInfluencer,
            timelinePlan: timelinePlan
        )
        let reasons = Set(editPlan.decisions.map(\.reason))

        #expect(reasons.contains("Tech reveal zoom"))
        #expect(reasons.contains("Tech reveal impact SFX"))
    }

    @Test("Tech Influencer Turkish creation verb alone does not become reveal")
    func techInfluencerTurkishCreationVerbAloneDoesNotBecomeReveal() {
        let text = "topluluk güven oluşturdu"
        let segment = TestFixture.segment(
            start: 4.0,
            end: 6.1,
            text: text,
            confidence: 0.96,
            type: .contentSentence
        )
        let timelinePlan = TechInfluencerTimelineAnalyzer.analyze(
            transcription: TestFixture.transcription(segments: [segment], language: "tr-TR"),
            audioAnalysis: TestFixture.audioResult(duration: 8.0)
        )

        #expect(!timelinePlan.events.contains { $0.kind == .reveal })
        #expect(!timelinePlan.events.contains { $0.kind == .uiAction })

        let roughCut = TestFixture.roughCutResult(
            decisions: [
                RoughCutDecision(startTime: 0, endTime: 8, action: .keep, reason: "Content", confidence: 0.95, linkedTranscriptText: nil, requiresReview: false)
            ],
            originalDuration: 8,
            cleanDuration: 8
        )
        let editPlan = EditDecisionEngine.generateEditPlan(
            captions: [
                TestFixture.caption(start: 4, end: 6.1, text: text, role: .reveal, style: .premiumLowerThird, behavior: .punchIn)
            ],
            roughCut: roughCut,
            template: .techInfluencer,
            timelinePlan: timelinePlan
        )
        let reasons = Set(editPlan.decisions.map(\.reason))

        #expect(!reasons.contains("Tech reveal zoom"))
        #expect(!reasons.contains("Tech reveal impact SFX"))
        #expect(!reasons.contains("Tech UI focus zoom"))
        #expect(!reasons.contains("Tech UI click SFX"))
    }

    @Test("Tech Influencer Turkish result payoff wins over earlier creation verb")
    func techInfluencerTurkishResultPayoffWinsOverEarlierCreationVerb() {
        var segment = TestFixture.segment(
            start: 4.0,
            end: 6.8,
            text: "model taslağı oluşturdu ve sonuç çıktı",
            confidence: 0.96,
            type: .contentSentence
        )
        segment.wordTimings = [
            (word: "model", start: 4.08, duration: 0.18),
            (word: "taslağı", start: 4.34, duration: 0.24),
            (word: "oluşturdu", start: 4.76, duration: 0.30),
            (word: "ve", start: 5.16, duration: 0.10),
            (word: "sonuç", start: 5.38, duration: 0.20),
            (word: "çıktı", start: 5.68, duration: 0.24)
        ]
        let timelinePlan = TechInfluencerTimelineAnalyzer.analyze(
            transcription: TestFixture.transcription(segments: [segment], language: "tr-TR"),
            audioAnalysis: TestFixture.audioResult(duration: 8.0)
        )

        #expect(timelinePlan.events.contains { $0.kind == .reveal && abs($0.anchorTime - 5.38) < 0.01 })
    }

    @Test("Tech Influencer real-device Turkish case survives dense rough cut remap")
    func techInfluencerRealDeviceTurkishCaseSurvivesDenseRoughCutRemap() {
        var productReveal = timedSegment(
            start: 18.78,
            end: 22.05,
            text: "Vibe Coding topluluğu Vibe Coding Turkey kurdum kod bilmeyen",
            confidence: 0.720
        )
        productReveal.rawConfidence = 0.22985716
        let transcription = TestFixture.transcription(segments: [
            timedSegment(start: 0.96, end: 3.96, text: "Türkiye'de çok fazla insanın harika fikirleri var", confidence: 0.954),
            timedSegment(start: 4.32, end: 7.41, text: "ama çoğu kod yazmayı bilmediği için hayata geçemiyor", confidence: 0.870),
            timedSegment(start: 7.68, end: 10.23, text: "ben buna ayar oluyorum artık uygulama yapmak", confidence: 0.914),
            timedSegment(start: 10.23, end: 13.26, text: "için yıllarca yazılımcı olman gerekmiyor doğru fikri", confidence: 0.902),
            timedSegment(start: 13.26, end: 16.38, text: "doğru şekilde yapay zeka anlatman gerekiyor işte", confidence: 0.897),
            timedSegment(start: 16.38, end: 18.78, text: "tam da bu yüzden Türkiye'nin ilk", confidence: 0.790),
            productReveal,
            timedSegment(start: 22.05, end: 24.60, text: "insanlar da ürün çıkarabilsin fikirlerin", confidence: 0.680),
            timedSegment(start: 24.60, end: 27.18, text: "MVP'ye çevirebilsinler App Store'a", confidence: 0.680),
            timedSegment(start: 27.18, end: 29.64, text: "ya da web'e gönderip kullanıcıya", confidence: 0.680),
            timedSegment(start: 29.64, end: 32.31, text: "ulaşabilsinler eğer sen de bu", confidence: 0.680),
            timedSegment(start: 32.31, end: 35.10, text: "topluluğun bir parçası olmak istersen yorumlara Vibe yazıp", confidence: 0.944),
            timedSegment(start: 35.10, end: 36.51, text: "birlikte büyüyelim", confidence: 0.958),
        ])
        let roughCut = TestFixture.roughCutResult(
            decisions: [
                RoughCutDecision(startTime: 0, endTime: 0.86, action: .cut, reason: "Tech pacing dead air/inter-idea gap", confidence: 0.88, linkedTranscriptText: nil, requiresReview: false),
                RoughCutDecision(startTime: 0.86, endTime: 4.01, action: .keep, reason: "Tech semantic keep", confidence: 0.89, linkedTranscriptText: nil, requiresReview: false),
                RoughCutDecision(startTime: 4.01, endTime: 4.27, action: .cut, reason: "Tech pacing silence", confidence: 0.86, linkedTranscriptText: nil, requiresReview: false),
                RoughCutDecision(startTime: 4.27, endTime: 7.46, action: .keep, reason: "Tech semantic keep", confidence: 0.89, linkedTranscriptText: nil, requiresReview: false),
                RoughCutDecision(startTime: 7.46, endTime: 7.62, action: .cut, reason: "Tech pacing silence", confidence: 0.86, linkedTranscriptText: nil, requiresReview: false),
                RoughCutDecision(startTime: 7.62, endTime: 8.84, action: .keep, reason: "Tech semantic keep", confidence: 0.89, linkedTranscriptText: nil, requiresReview: false),
                RoughCutDecision(startTime: 8.84, endTime: 9.12, action: .cut, reason: "Tech pacing silence", confidence: 0.86, linkedTranscriptText: nil, requiresReview: false),
                RoughCutDecision(startTime: 9.12, endTime: 12.17, action: .keep, reason: "Tech semantic keep", confidence: 0.89, linkedTranscriptText: nil, requiresReview: false),
                RoughCutDecision(startTime: 12.17, endTime: 12.34, action: .cut, reason: "Tech pacing silence", confidence: 0.86, linkedTranscriptText: nil, requiresReview: false),
                RoughCutDecision(startTime: 12.34, endTime: 15.80, action: .keep, reason: "Tech semantic keep", confidence: 0.89, linkedTranscriptText: nil, requiresReview: false),
                RoughCutDecision(startTime: 15.80, endTime: 16.06, action: .cut, reason: "Tech pacing silence", confidence: 0.86, linkedTranscriptText: nil, requiresReview: false),
                RoughCutDecision(startTime: 16.06, endTime: 36.63, action: .keep, reason: "Tech semantic keep", confidence: 0.89, linkedTranscriptText: nil, requiresReview: false),
                RoughCutDecision(startTime: 36.63, endTime: 37.38, action: .cut, reason: "Tech pacing dead air/inter-idea gap", confidence: 0.88, linkedTranscriptText: nil, requiresReview: false),
            ],
            originalDuration: 37.38,
            cleanDuration: 34.64
        )
        let captions = CaptionEngine.generateCaptions(
            from: transcription,
            roughCut: roughCut,
            template: .techInfluencer
        )
        let timelinePlan = TechInfluencerTimelineAnalyzer.analyze(
            transcription: transcription,
            audioAnalysis: TestFixture.audioResult(duration: 37.38)
        )
        #expect(timelinePlan.events.contains { $0.kind == .reveal && abs($0.anchorTime - 18.78) < 0.25 })
        let editPlan = EditDecisionEngine.generateEditPlan(
            captions: captions,
            roughCut: roughCut,
            template: .techInfluencer,
            timelinePlan: timelinePlan
        )

        let report = QualityGateService.evaluate(
            captions: captions,
            editPlan: editPlan,
            roughCut: roughCut,
            template: .techInfluencer,
            transcription: transcription
        )
        let failedNames = Set(report.failedChecks.map(\.name))

        #expect(longestStyleRun(captions) <= 3)
        #expect(editPlan.decisions.count <= 9)
        #expect(!editPlan.decisions.contains { $0.reason == "Hook short riser" })
        #expect(!editPlan.decisions.contains { $0.reason == "Topic shift whoosh" })
        #expect(!editPlan.decisions.contains { $0.reason == "Tech keyword click SFX" })
        #expect(!failedNames.contains("Transcript artifact cleanup"))
        #expect(!failedNames.contains("Review required"))
        #expect(!failedNames.contains("Tech caption visual variety"))
        #expect(!failedNames.contains("Tech export-ready semantic survivability"))
        #expect(!failedNames.contains("Tech event anchoring"))
        #expect(!failedNames.contains("Tech event combos"))
    }

    @Test("Tech Influencer rough cut trusts post-processed product and CTA terms")
    func techInfluencerRoughCutTrustsPostProcessedProductAndCTATerms() {
        var product = timedSegment(
            start: 18.78,
            end: 22.05,
            text: "Vibe Coding topluluğu Vibe Coding Turkey kurdum kod bilmeyen",
            confidence: 0.72
        )
        product.rawConfidence = 0.23
        var cta = timedSegment(
            start: 32.31,
            end: 35.10,
            text: "topluluğun bir parçası olmak istersen yorumlara Vibe yazıp",
            confidence: 0.94
        )
        cta.rawConfidence = 0.58
        let transcription = TestFixture.transcription(segments: [
            timedSegment(start: 0.96, end: 3.96, text: "Türkiye'de çok fazla insanın harika fikirleri var", confidence: 0.95),
            product,
            cta,
        ])
        let audio = TestFixture.audioResult(duration: 36.0)
        let timelinePlan = TechInfluencerTimelineAnalyzer.analyze(
            transcription: transcription,
            audioAnalysis: audio
        )
        #expect(timelinePlan.events.contains { $0.kind == .reveal && abs($0.anchorTime - product.startTime) < 0.25 })

        let roughCut = RoughCutDecisionEngine.generateTechInfluencerDecisions(
            transcription: transcription,
            audioAnalysis: audio,
            takeGroups: [],
            timelinePlan: timelinePlan
        )

        #expect(!roughCut.decisions.contains { $0.requiresReview })
        #expect(roughCut.keepSegments.contains { $0.startTime <= product.startTime && $0.endTime >= product.endTime })
    }

    @Test("Tech Influencer hook zoom pushes in then backs out over the spoken hook")
    func techInfluencerHookZoomUsesTwoPhaseCameraMove() {
        let captions = [
            TestFixture.caption(
                start: 0.0,
                end: 2.2,
                text: "This AI tool builds apps in minutes",
                role: .hook,
                style: .hookImpact,
                behavior: .hookImpact
            )
        ]
        let roughCut = TestFixture.roughCutResult(
            decisions: [
                RoughCutDecision(startTime: 0, endTime: 3, action: .keep, reason: "Content", confidence: 0.9, linkedTranscriptText: nil, requiresReview: false)
            ],
            originalDuration: 3,
            cleanDuration: 3
        )

        let editPlan = EditDecisionEngine.generateEditPlan(
            captions: captions,
            roughCut: roughCut,
            template: .techInfluencer
        )

        let pushIn = editPlan.decisions.first { $0.reason == "Hook slow push-in zoom" }
        let backZoom = editPlan.decisions.first { $0.reason == "Hook sentence back zoom" }
        #expect(pushIn != nil)
        #expect(backZoom != nil)
        #expect(abs((pushIn?.time ?? -1) - 0.0) < 0.001)
        #expect(abs((pushIn?.duration ?? 0) - 1.1) < 0.001)
        #expect(abs((backZoom?.time ?? 0) - 1.1) < 0.001)
        #expect(abs((backZoom?.duration ?? 0) - 1.1) < 0.001)
        #expect((pushIn?.intensity ?? 1) <= 0.18)
        #expect((backZoom?.intensity ?? 1) <= 0.18)
    }

    @Test("Tech Influencer hook zoom ignores too-early terminal word split")
    func techInfluencerHookZoomAvoidsTooFastEarlySentenceSplit() {
        let captions = [
            CaptionSegment(
                startTime: 0.0,
                endTime: 2.4,
                text: "Wait. This AI tool builds apps",
                role: .hook,
                style: .hookImpact,
                sceneBehavior: .hookImpact,
                wordTimings: [
                    (word: "Wait.", start: 0.20, duration: 0.32),
                    (word: "This", start: 0.62, duration: 0.18),
                    (word: "AI", start: 0.86, duration: 0.18),
                    (word: "tool", start: 1.12, duration: 0.20),
                    (word: "builds", start: 1.48, duration: 0.22),
                    (word: "apps", start: 1.86, duration: 0.24)
                ]
            )
        ]
        let roughCut = TestFixture.roughCutResult(
            decisions: [
                RoughCutDecision(startTime: 0, endTime: 3, action: .keep, reason: "Content", confidence: 0.9, linkedTranscriptText: nil, requiresReview: false)
            ],
            originalDuration: 3,
            cleanDuration: 3
        )

        let editPlan = EditDecisionEngine.generateEditPlan(
            captions: captions,
            roughCut: roughCut,
            template: .techInfluencer
        )

        let pushIn = editPlan.decisions.first { $0.reason == "Hook slow push-in zoom" }
        let backZoom = editPlan.decisions.first { $0.reason == "Hook sentence back zoom" }

        #expect(pushIn != nil)
        #expect(backZoom != nil)
        #expect((pushIn?.duration ?? 0) >= 0.75)
        #expect(abs((pushIn?.duration ?? 0) - 1.2) < 0.001)
        #expect(abs((backZoom?.time ?? 0) - 1.2) < 0.001)
    }

    @Test("Tech Influencer keeps ordinary silence trims as hard cuts")
    func techInfluencerDoesNotAddWhooshForOrdinarySilenceCut() {
        let firstKeep = RoughCutDecision(
            startTime: 0,
            endTime: 2,
            action: .keep,
            reason: "Content",
            confidence: 0.95,
            linkedTranscriptText: nil,
            requiresReview: false
        )
        let silenceCut = RoughCutDecision(
            startTime: 2,
            endTime: 2.7,
            action: .cut,
            reason: "Silence",
            confidence: 0.95,
            linkedTranscriptText: nil,
            requiresReview: false
        )
        let secondKeep = RoughCutDecision(
            startTime: 2.7,
            endTime: 5,
            action: .keep,
            reason: "Content",
            confidence: 0.95,
            linkedTranscriptText: nil,
            requiresReview: false
        )
        let roughCut = TestFixture.roughCutResult(
            decisions: [firstKeep, silenceCut, secondKeep],
            originalDuration: 5,
            cleanDuration: 4.3
        )

        let editPlan = EditDecisionEngine.generateEditPlan(
            captions: [],
            roughCut: roughCut,
            template: .techInfluencer
        )

        #expect(editPlan.decisions.isEmpty)
        #expect(!editPlan.decisions.contains { $0.reason == "Cut whoosh" })
        #expect(!editPlan.decisions.contains { $0.reason == "Cut impact SFX" })
    }

    @Test("Tech Influencer UI action ties zoom highlight and click to the spoken UI word")
    func techInfluencerUIActionTiesZoomHighlightAndClickToUIWord() {
        let captions = [
            CaptionSegment(
                startTime: 4.0,
                endTime: 6.0,
                text: "click this button to open the dashboard",
                role: .regular,
                style: .neonGlow,
                sceneBehavior: .focusBlur,
                wordTimings: [
                    (word: "click", start: 4.10, duration: 0.18),
                    (word: "this", start: 4.34, duration: 0.16),
                    (word: "button", start: 4.56, duration: 0.22),
                    (word: "to", start: 4.86, duration: 0.10),
                    (word: "open", start: 5.02, duration: 0.18),
                    (word: "the", start: 5.24, duration: 0.12),
                    (word: "dashboard", start: 5.42, duration: 0.28)
                ]
            )
        ]
        let roughCut = TestFixture.roughCutResult(
            decisions: [
                RoughCutDecision(startTime: 0, endTime: 7, action: .keep, reason: "Content", confidence: 0.9, linkedTranscriptText: nil, requiresReview: false)
            ],
            originalDuration: 7,
            cleanDuration: 7
        )

        let editPlan = EditDecisionEngine.generateEditPlan(
            captions: captions,
            roughCut: roughCut,
            template: .techInfluencer
        )

        let zoom = editPlan.decisions.first { $0.reason == "Tech UI focus zoom" }
        let highlight = editPlan.decisions.first { $0.reason == "Tech UI highlight pulse" }
        let click = editPlan.decisions.first { $0.reason == "Tech UI click SFX" }
        #expect(zoom != nil)
        #expect(highlight != nil)
        #expect(click != nil)
        #expect(abs((zoom?.time ?? 0) - 3.72) < 0.001)
        #expect(abs((highlight?.time ?? 0) - 4.10) < 0.001)
        #expect(abs((click?.time ?? 0) - 4.14) < 0.001)
    }

    @Test("Tech workflow verb near UI context emits UI effects")
    func techWorkflowVerbNearUIContextEmitsUIEffects() {
        var segment = TestFixture.segment(
            start: 3.0,
            end: 5.2,
            text: "now generate in dashboard",
            confidence: 0.96,
            type: .contentSentence
        )
        segment.wordTimings = [
            (word: "now", start: 3.10, duration: 0.16),
            (word: "generate", start: 3.42, duration: 0.24),
            (word: "in", start: 3.78, duration: 0.10),
            (word: "dashboard", start: 4.06, duration: 0.28)
        ]
        let transcription = TestFixture.transcription(segments: [segment], language: "en-US")
        let timelinePlan = TechInfluencerTimelineAnalyzer.analyze(
            transcription: transcription,
            audioAnalysis: TestFixture.audioResult(duration: 5.5)
        )

        #expect(timelinePlan.events.contains { $0.kind == .uiAction })

        let roughCut = TestFixture.roughCutResult(
            decisions: [
                RoughCutDecision(startTime: 0, endTime: 5.5, action: .keep, reason: "Content", confidence: 0.9, linkedTranscriptText: nil, requiresReview: false)
            ],
            originalDuration: 5.5,
            cleanDuration: 5.5
        )
        let editPlan = EditDecisionEngine.generateEditPlan(
            captions: [],
            roughCut: roughCut,
            template: .techInfluencer,
            timelinePlan: timelinePlan
        )
        let reasons = Set(editPlan.decisions.map(\.reason))

        #expect(reasons.contains("Tech UI focus zoom"))
        #expect(reasons.contains("Tech UI highlight pulse"))
    }

    @Test("Tech Influencer negated UI action stays warning without UI effects")
    func techInfluencerNegatedUIActionDoesNotEmitUICues() {
        var segment = TestFixture.segment(
            start: 3.0,
            end: 6.6,
            text: "don't make this mistake now don't click deploy",
            confidence: 0.96,
            type: .contentSentence
        )
        segment.wordTimings = [
            (word: "don't", start: 3.10, duration: 0.18),
            (word: "make", start: 3.36, duration: 0.20),
            (word: "this", start: 3.68, duration: 0.16),
            (word: "mistake", start: 4.02, duration: 0.26),
            (word: "now", start: 4.82, duration: 0.18),
            (word: "don't", start: 5.18, duration: 0.18),
            (word: "click", start: 5.52, duration: 0.18),
            (word: "deploy", start: 5.88, duration: 0.24)
        ]
        let transcription = TestFixture.transcription(segments: [segment], language: "en-US")
        let timelinePlan = TechInfluencerTimelineAnalyzer.analyze(
            transcription: transcription,
            audioAnalysis: TestFixture.audioResult(duration: 7.0)
        )

        #expect(timelinePlan.events.contains { $0.kind == .warning })
        #expect(!timelinePlan.events.contains { $0.kind == .uiAction })

        let roughCut = TestFixture.roughCutResult(
            decisions: [
                RoughCutDecision(startTime: 0, endTime: 7, action: .keep, reason: "Content", confidence: 0.9, linkedTranscriptText: nil, requiresReview: false)
            ],
            originalDuration: 7,
            cleanDuration: 7
        )
        let editPlan = EditDecisionEngine.generateEditPlan(
            captions: [],
            roughCut: roughCut,
            template: .techInfluencer,
            timelinePlan: timelinePlan
        )
        let reasons = Set(editPlan.decisions.map(\.reason))

        #expect(reasons.contains("Tech warning amber accent"))
        #expect(!reasons.contains("Tech UI focus zoom"))
        #expect(!reasons.contains("Tech UI highlight pulse"))
        #expect(!reasons.contains("Tech UI click SFX"))
    }

    @Test("Tech warning sentence with UI mention stays a single warning intent")
    func techWarningSentenceWithUIMentionStaysSingleWarningIntent() {
        let text = "this mistake happens when you click deploy"
        var segment = TestFixture.segment(
            start: 3.0,
            end: 6.4,
            text: text,
            confidence: 0.96,
            type: .contentSentence
        )
        segment.wordTimings = [
            (word: "this", start: 3.10, duration: 0.14),
            (word: "mistake", start: 3.40, duration: 0.26),
            (word: "happens", start: 3.84, duration: 0.24),
            (word: "when", start: 4.34, duration: 0.16),
            (word: "you", start: 4.66, duration: 0.12),
            (word: "click", start: 5.05, duration: 0.18),
            (word: "deploy", start: 5.42, duration: 0.24)
        ]
        let transcription = TestFixture.transcription(segments: [segment], language: "en-US")
        let timelinePlan = TechInfluencerTimelineAnalyzer.analyze(
            transcription: transcription,
            audioAnalysis: TestFixture.audioResult(duration: 7.0)
        )

        #expect(timelinePlan.events.contains { $0.kind == .warning })
        #expect(!timelinePlan.events.contains { $0.kind == .uiAction })

        let role = CaptionRoleClassifier.classify(
            text: text,
            index: 1,
            totalSegments: 3,
            previousRole: .regular,
            startTime: 3.0
        )
        let captions = CaptionSceneEventPlanner.assignSceneBehaviors(
            to: [TestFixture.caption(start: 3.0, end: 6.4, text: text, role: role, style: .focusStatement)],
            template: .techInfluencer
        )
        #expect(role == .warning)
        #expect(captions.first?.sceneBehavior == .underlineReveal)

        let roughCut = TestFixture.roughCutResult(
            decisions: [
                RoughCutDecision(startTime: 0, endTime: 7, action: .keep, reason: "Content", confidence: 0.9, linkedTranscriptText: nil, requiresReview: false)
            ],
            originalDuration: 7,
            cleanDuration: 7
        )
        let editPlan = EditDecisionEngine.generateEditPlan(
            captions: [],
            roughCut: roughCut,
            template: .techInfluencer,
            timelinePlan: timelinePlan
        )
        let reasons = Set(editPlan.decisions.map(\.reason))

        #expect(reasons.contains("Tech warning amber accent"))
        #expect(!reasons.contains("Tech UI focus zoom"))
        #expect(!reasons.contains("Tech UI highlight pulse"))
        #expect(!reasons.contains("Tech UI click SFX"))
    }

    @Test("Tech generic workflow verbs without UI context do not emit UI effects")
    func techGenericWorkflowVerbsWithoutUIContextDoNotEmitUIEffects() {
        let segments = [
            TestFixture.segment(
                start: 3.0,
                end: 4.8,
                text: "we deploy faster every week",
                confidence: 0.96,
                type: .contentSentence
            ),
            TestFixture.segment(
                start: 6.0,
                end: 7.2,
                text: "I generate ideas",
                confidence: 0.96,
                type: .contentSentence
            ),
            TestFixture.segment(
                start: 8.4,
                end: 10.0,
                text: "generate ideas while the dashboard loads",
                confidence: 0.96,
                type: .contentSentence
            ),
            TestFixture.segment(
                start: 11.0,
                end: 12.6,
                text: "the dashboard improves after we deploy faster",
                confidence: 0.96,
                type: .contentSentence
            )
        ]
        let transcription = TestFixture.transcription(segments: segments, language: "en-US")
        let timelinePlan = TechInfluencerTimelineAnalyzer.analyze(
            transcription: transcription,
            audioAnalysis: TestFixture.audioResult(duration: 13.0)
        )

        #expect(!timelinePlan.events.contains { $0.kind == .uiAction })

        let roughCut = TestFixture.roughCutResult(
            decisions: [
                RoughCutDecision(startTime: 0, endTime: 13, action: .keep, reason: "Content", confidence: 0.9, linkedTranscriptText: nil, requiresReview: false)
            ],
            originalDuration: 13,
            cleanDuration: 13
        )
        let editPlan = EditDecisionEngine.generateEditPlan(
            captions: [],
            roughCut: roughCut,
            template: .techInfluencer,
            timelinePlan: timelinePlan
        )
        let reasons = Set(editPlan.decisions.map(\.reason))

        #expect(!reasons.contains("Tech UI focus zoom"))
        #expect(!reasons.contains("Tech UI highlight pulse"))
        #expect(!reasons.contains("Tech UI click SFX"))
    }

    @Test("Tech metaphorical UI words do not emit UI effects")
    func techMetaphoricalUIWordsDoNotEmitUIEffects() {
        let segments = [
            TestFixture.segment(
                start: 3.0,
                end: 4.2,
                text: "we tap into momentum",
                confidence: 0.96,
                type: .contentSentence
            ),
            TestFixture.segment(
                start: 5.0,
                end: 6.4,
                text: "the press release lands today",
                confidence: 0.96,
                type: .contentSentence
            ),
            TestFixture.segment(
                start: 7.2,
                end: 8.7,
                text: "only a select few creators respond",
                confidence: 0.96,
                type: .contentSentence
            ),
            TestFixture.segment(
                start: 9.4,
                end: 10.8,
                text: "ad copy converts better",
                confidence: 0.96,
                type: .contentSentence
            ),
            TestFixture.segment(
                start: 11.4,
                end: 12.7,
                text: "en baştan vazgeçiyor",
                confidence: 0.96,
                type: .contentSentence
            ),
            TestFixture.segment(
                start: 13.4,
                end: 14.8,
                text: "now generate revenue",
                confidence: 0.96,
                type: .contentSentence
            ),
            TestFixture.segment(
                start: 15.4,
                end: 16.7,
                text: "select a niche",
                confidence: 0.96,
                type: .contentSentence
            ),
            TestFixture.segment(
                start: 17.4,
                end: 18.7,
                text: "copy this strategy",
                confidence: 0.96,
                type: .contentSentence
            ),
            TestFixture.segment(
                start: 19.4,
                end: 20.7,
                text: "paste ideas together",
                confidence: 0.96,
                type: .contentSentence
            ),
            TestFixture.segment(
                start: 21.4,
                end: 22.7,
                text: "tap a new market",
                confidence: 0.96,
                type: .contentSentence
            ),
            TestFixture.segment(
                start: 23.4,
                end: 24.7,
                text: "press on through churn",
                confidence: 0.96,
                type: .contentSentence
            ),
            TestFixture.segment(
                start: 25.4,
                end: 26.7,
                text: "paste together a plan",
                confidence: 0.96,
                type: .contentSentence
            ),
            TestFixture.segment(
                start: 27.4,
                end: 28.7,
                text: "click rate improved",
                confidence: 0.96,
                type: .contentSentence
            ),
            TestFixture.segment(
                start: 29.4,
                end: 30.7,
                text: "stratejiyi kopyalıyoruz",
                confidence: 0.96,
                type: .contentSentence
            ),
            TestFixture.segment(
                start: 31.4,
                end: 32.7,
                text: "fikirleri yapıştırıyoruz",
                confidence: 0.96,
                type: .contentSentence
            ),
            TestFixture.segment(
                start: 33.4,
                end: 34.7,
                text: "takımı çalıştırıyorum",
                confidence: 0.96,
                type: .contentSentence
            ),
            TestFixture.segment(
                start: 35.4,
                end: 36.7,
                text: "copy the app idea",
                confidence: 0.96,
                type: .contentSentence
            ),
            TestFixture.segment(
                start: 37.4,
                end: 38.7,
                text: "selected customer segment",
                confidence: 0.96,
                type: .contentSentence
            )
        ]
        let transcription = TestFixture.transcription(segments: segments, language: "en-US")
        let timelinePlan = TechInfluencerTimelineAnalyzer.analyze(
            transcription: transcription,
            audioAnalysis: TestFixture.audioResult(duration: 39.0)
        )

        #expect(!timelinePlan.events.contains { $0.kind == .uiAction })

        let roughCut = TestFixture.roughCutResult(
            decisions: [
                RoughCutDecision(startTime: 0, endTime: 39, action: .keep, reason: "Content", confidence: 0.9, linkedTranscriptText: nil, requiresReview: false)
            ],
            originalDuration: 39,
            cleanDuration: 39
        )
        let editPlan = EditDecisionEngine.generateEditPlan(
            captions: [],
            roughCut: roughCut,
            template: .techInfluencer,
            timelinePlan: timelinePlan
        )
        let reasons = Set(editPlan.decisions.map(\.reason))

        #expect(!reasons.contains("Tech UI focus zoom"))
        #expect(!reasons.contains("Tech UI highlight pulse"))
        #expect(!reasons.contains("Tech UI click SFX"))
    }

    @Test("Tech close UI reveal pair survives as a composed beat")
    func techCloseUIRevealPairSurvivesAsComposedBeat() {
        var segment = TestFixture.segment(
            start: 3.0,
            end: 4.7,
            text: "click generate result appears",
            confidence: 0.96,
            type: .contentSentence
        )
        segment.wordTimings = [
            (word: "click", start: 3.10, duration: 0.18),
            (word: "generate", start: 3.36, duration: 0.20),
            (word: "result", start: 3.86, duration: 0.22),
            (word: "appears", start: 4.18, duration: 0.24)
        ]
        let transcription = TestFixture.transcription(segments: [segment], language: "en-US")
        let timelinePlan = TechInfluencerTimelineAnalyzer.analyze(
            transcription: transcription,
            audioAnalysis: TestFixture.audioResult(duration: 5.0)
        )

        #expect(timelinePlan.events.contains { $0.kind == .uiAction })
        #expect(timelinePlan.events.contains { $0.kind == .reveal })

        let roughCut = TestFixture.roughCutResult(
            decisions: [
                RoughCutDecision(startTime: 0, endTime: 5, action: .keep, reason: "Content", confidence: 0.9, linkedTranscriptText: nil, requiresReview: false)
            ],
            originalDuration: 5,
            cleanDuration: 5
        )
        let editPlan = EditDecisionEngine.generateEditPlan(
            captions: [],
            roughCut: roughCut,
            template: .techInfluencer,
            timelinePlan: timelinePlan
        )
        let reasons = Set(editPlan.decisions.map(\.reason))

        #expect(reasons.contains("Tech UI highlight pulse"))
        #expect(reasons.contains("Tech reveal zoom"))
        #expect(reasons.contains("Tech reveal impact SFX"))
        #expect(!reasons.contains("Tech UI focus zoom"))
        #expect(!reasons.contains("Tech UI click SFX"))
    }

    @Test("Tech quality gate rejects extra UI focus on coupled UI reveal beat")
    func techQualityGateRejectsExtraUIFocusOnCoupledUIRevealBeat() {
        let text = "click generate result appears"
        var segment = TestFixture.segment(
            start: 3.0,
            end: 4.7,
            text: text,
            confidence: 0.96,
            type: .contentSentence
        )
        segment.wordTimings = [
            (word: "click", start: 3.10, duration: 0.18),
            (word: "generate", start: 3.36, duration: 0.20),
            (word: "result", start: 3.86, duration: 0.22),
            (word: "appears", start: 4.18, duration: 0.24)
        ]
        let transcription = TestFixture.transcription(segments: [segment], language: "en-US")
        let timelinePlan = TechInfluencerTimelineAnalyzer.analyze(
            transcription: transcription,
            audioAnalysis: TestFixture.audioResult(duration: 5.0)
        )
        let caption = CaptionSegment(
            startTime: 3.0,
            endTime: 4.7,
            text: text,
            role: .regular,
            style: .neonGlow,
            sceneBehavior: .focusBlur,
            wordTimings: segment.wordTimings
        )
        let roughCut = TestFixture.roughCutResult(
            decisions: [
                RoughCutDecision(startTime: 0, endTime: 5, action: .keep, reason: "Content", confidence: 0.9, linkedTranscriptText: nil, requiresReview: false)
            ],
            originalDuration: 5,
            cleanDuration: 5
        )
        let generatedPlan = EditDecisionEngine.generateEditPlan(
            captions: [caption],
            roughCut: roughCut,
            template: .techInfluencer,
            timelinePlan: timelinePlan
        )
        let extraFocus = EditDecision(time: 2.72, duration: 0.76, type: .zoom, reason: "Tech UI focus zoom", intensity: 0.24)
        let extraClick = EditDecision(time: 3.14, duration: 0.12, type: .sfx, reason: "Tech UI click SFX", intensity: 0.28)
        let decisions = generatedPlan.decisions + [extraFocus, extraClick]
        let report = QualityGateService.evaluate(
            captions: [caption],
            editPlan: EditPlan(decisions: decisions, template: .techInfluencer, totalEffects: decisions.count, averageIntensity: 0.25),
            roughCut: roughCut,
            template: .techInfluencer,
            transcription: transcription
        )

        let comboCheck = report.checks.first { $0.name == "Tech event combos" }
        #expect(comboCheck?.passed == false)
        #expect(comboCheck?.blocksExport == true)
        #expect(comboCheck?.detail.contains("coupled UI->reveal") == true)
    }

    @Test("Tech reveal before UI action does not form a composed beat")
    func techRevealBeforeUIActionDoesNotFormComposedBeat() {
        var segment = TestFixture.segment(
            start: 3.0,
            end: 5.8,
            text: "the result appears then click the button",
            confidence: 0.96,
            type: .contentSentence
        )
        segment.wordTimings = [
            (word: "the", start: 3.08, duration: 0.10),
            (word: "result", start: 3.26, duration: 0.22),
            (word: "appears", start: 3.62, duration: 0.24),
            (word: "then", start: 4.32, duration: 0.18),
            (word: "click", start: 4.72, duration: 0.18),
            (word: "the", start: 4.96, duration: 0.10),
            (word: "button", start: 5.16, duration: 0.22)
        ]
        let transcription = TestFixture.transcription(segments: [segment], language: "en-US")
        let timelinePlan = TechInfluencerTimelineAnalyzer.analyze(
            transcription: transcription,
            audioAnalysis: TestFixture.audioResult(duration: 6.0)
        )

        #expect(timelinePlan.events.contains { $0.kind == .reveal })
        #expect(!timelinePlan.events.contains { $0.kind == .uiAction })
    }

    @Test("Tech delayed UI reveal bridge does not form a composed beat")
    func techDelayedUIRevealBridgeDoesNotFormComposedBeat() {
        var segment = TestFixture.segment(
            start: 3.0,
            end: 6.5,
            text: "click generate and later the result appears",
            confidence: 0.96,
            type: .contentSentence
        )
        segment.wordTimings = [
            (word: "click", start: 3.10, duration: 0.18),
            (word: "generate", start: 3.48, duration: 0.22),
            (word: "and", start: 4.02, duration: 0.12),
            (word: "later", start: 4.44, duration: 0.22),
            (word: "the", start: 5.34, duration: 0.10),
            (word: "result", start: 5.70, duration: 0.22),
            (word: "appears", start: 6.02, duration: 0.24)
        ]
        let transcription = TestFixture.transcription(segments: [segment], language: "en-US")
        let timelinePlan = TechInfluencerTimelineAnalyzer.analyze(
            transcription: transcription,
            audioAnalysis: TestFixture.audioResult(duration: 6.8)
        )

        #expect(timelinePlan.events.contains { $0.kind == .reveal })
        #expect(!timelinePlan.events.contains { $0.kind == .uiAction })

        let roughCut = TestFixture.roughCutResult(
            decisions: [
                RoughCutDecision(startTime: 0, endTime: 6.8, action: .keep, reason: "Content", confidence: 0.9, linkedTranscriptText: nil, requiresReview: false)
            ],
            originalDuration: 6.8,
            cleanDuration: 6.8
        )
        let editPlan = EditDecisionEngine.generateEditPlan(
            captions: [],
            roughCut: roughCut,
            template: .techInfluencer,
            timelinePlan: timelinePlan
        )
        let reasons = Set(editPlan.decisions.map(\.reason))

        #expect(reasons.contains("Tech reveal zoom"))
        #expect(!reasons.contains("Tech UI focus zoom"))
        #expect(!reasons.contains("Tech UI highlight pulse"))
        #expect(!reasons.contains("Tech UI click SFX"))
    }

    @Test("Tech distant UI and reveal words do not form a stacked combo")
    func techDistantUIRevealWordsDoNotFormStackedCombo() {
        var segment = TestFixture.segment(
            start: 3.0,
            end: 8.0,
            text: "click generate and after the pause the result appears",
            confidence: 0.96,
            type: .contentSentence
        )
        segment.wordTimings = [
            (word: "click", start: 3.10, duration: 0.18),
            (word: "generate", start: 3.52, duration: 0.24),
            (word: "and", start: 4.04, duration: 0.12),
            (word: "after", start: 4.68, duration: 0.18),
            (word: "the", start: 5.22, duration: 0.10),
            (word: "pause", start: 5.72, duration: 0.20),
            (word: "the", start: 6.18, duration: 0.10),
            (word: "result", start: 6.40, duration: 0.22),
            (word: "appears", start: 6.72, duration: 0.24)
        ]
        let transcription = TestFixture.transcription(segments: [segment], language: "en-US")
        let timelinePlan = TechInfluencerTimelineAnalyzer.analyze(
            transcription: transcription,
            audioAnalysis: TestFixture.audioResult(duration: 8.4)
        )

        #expect(timelinePlan.events.contains { $0.kind == .reveal })
        #expect(!timelinePlan.events.contains { $0.kind == .uiAction })

        let roughCut = TestFixture.roughCutResult(
            decisions: [
                RoughCutDecision(startTime: 0, endTime: 8.4, action: .keep, reason: "Content", confidence: 0.9, linkedTranscriptText: nil, requiresReview: false)
            ],
            originalDuration: 8.4,
            cleanDuration: 8.4
        )
        let editPlan = EditDecisionEngine.generateEditPlan(
            captions: [],
            roughCut: roughCut,
            template: .techInfluencer,
            timelinePlan: timelinePlan
        )
        let reasons = Set(editPlan.decisions.map(\.reason))

        #expect(reasons.contains("Tech reveal zoom"))
        #expect(!reasons.contains("Tech UI focus zoom"))
        #expect(!reasons.contains("Tech UI highlight pulse"))
        #expect(!reasons.contains("Tech UI click SFX"))
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

    private func timedSegment(
        start: Double,
        end: Double,
        text: String,
        confidence: Float
    ) -> TranscriptSegment {
        var segment = TestFixture.segment(
            start: start,
            end: end,
            text: text,
            confidence: confidence,
            type: .contentSentence
        )
        segment.wordTimings = proportionalWordTimings(text: text, start: start, end: end)
        return segment
    }

    private func proportionalWordTimings(
        text: String,
        start: Double,
        end: Double
    ) -> [(word: String, start: Double, duration: Double)] {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty, end > start else { return [] }

        let duration = (end - start) / Double(words.count)
        return words.enumerated().map { index, word in
            (word: word, start: start + Double(index) * duration, duration: duration)
        }
    }

    private func longestStyleRun(_ captions: [CaptionSegment]) -> Int {
        let sorted = captions.sorted { $0.startTime < $1.startTime }
        guard let first = sorted.first else { return 0 }

        var currentStyle = first.style
        var currentRun = 0
        var longestRun = 0
        for caption in sorted {
            if caption.style == currentStyle {
                currentRun += 1
            } else {
                longestRun = max(longestRun, currentRun)
                currentStyle = caption.style
                currentRun = 1
            }
        }
        return max(longestRun, currentRun)
    }
}
