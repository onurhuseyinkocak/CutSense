import Testing
import Foundation
@testable import CutSense

// MARK: - Caption Role Classifier

@Suite("CaptionRoleClassifier")
struct CaptionRoleClassifierTests {
    @Test("First segment is always hook")
    func firstSegmentHook() {
        let role = CaptionRoleClassifier.classify(
            text: "Hello everyone",
            index: 0,
            totalSegments: 5,
            previousRole: nil
        )
        #expect(role == .hook)
    }

    @Test("Last segment is conclusion")
    func lastSegmentConclusion() {
        let role = CaptionRoleClassifier.classify(
            text: "Thanks for watching",
            index: 4,
            totalSegments: 5,
            previousRole: .regular
        )
        #expect(role == .conclusion)
    }

    @Test("Turkish hook pattern detected")
    func turkishHookPattern() {
        let role = CaptionRoleClassifier.classify(
            text: "Dikkat bu çok önemli",
            index: 2,
            totalSegments: 10,
            previousRole: .regular
        )
        #expect(role == .hook)
    }

    @Test("Turkish warning pattern detected")
    func turkishWarningPattern() {
        let role = CaptionRoleClassifier.classify(
            text: "Sakın bunu yapma",
            index: 3,
            totalSegments: 10,
            previousRole: .regular
        )
        #expect(role == .warning)
    }

    @Test("Short punchy keyword after regular")
    func keywordDetection() {
        let role = CaptionRoleClassifier.classify(
            text: "Çok güzel",
            index: 3,
            totalSegments: 10,
            previousRole: .regular
        )
        #expect(role == .keyword)
    }

    @Test("Regular text stays regular")
    func regularText() {
        let role = CaptionRoleClassifier.classify(
            text: "Bu konuyu detaylı olarak ele alalım arkadaşlar",
            index: 3,
            totalSegments: 10,
            previousRole: .keyword
        )
        #expect(role == .regular)
    }
}

// MARK: - Caption Readability Guard

@Suite("CaptionReadabilityGuard")
struct CaptionReadabilityGuardTests {
    private func makeCaption(text: String, start: Double = 0, end: Double = 2) -> CaptionSegment {
        CaptionSegment(
            startTime: start,
            endTime: end,
            text: text,
            role: .regular,
            style: .minimalWellness
        )
    }

    @Test("Short caption passes through unchanged")
    func shortCaptionPassthrough() {
        let caption = makeCaption(text: "Hello world")
        let result = CaptionReadabilityGuard.validate([caption])
        #expect(result.count == 1)
        #expect(result[0].text == "Hello world")
    }

    @Test("Long caption gets line break")
    func longCaptionLineBreak() {
        // Exactly >40 chars but <=10 words — triggers line break, not split
        let caption = makeCaption(text: "This caption is definitely over forty characters long")
        let result = CaptionReadabilityGuard.validate([caption])
        #expect(result.count == 1)
        #expect(result[0].text.contains("\n"))
    }

    @Test("Caption with many words gets split into two")
    func manyWordsSplit() {
        let caption = makeCaption(
            text: "one two three four five six seven eight nine ten eleven twelve"
        )
        let result = CaptionReadabilityGuard.validate([caption])
        #expect(result.count == 2)
    }

    @Test("Minimum display duration enforced")
    func minDisplayDuration() {
        let caption = makeCaption(text: "Quick", start: 0, end: 0.2)
        let result = CaptionReadabilityGuard.validate([caption])
        #expect(result[0].endTime - result[0].startTime >= 0.8)
    }
}

// MARK: - Intensity Limiter

@Suite("IntensityLimiter")
struct IntensityLimiterTests {
    @Test("Low intensity limits effects per window")
    func lowIntensityLimit() {
        let decisions = (0..<10).map { i in
            EditDecision(
                time: Double(i),
                duration: 0.3,
                type: .zoom,
                reason: "test",
                intensity: 0.5
            )
        }
        let template = TemplateConfig.premiumFounder // low intensity
        let limited = IntensityLimiter.limit(decisions, template: template)
        #expect(limited.count <= 8) // max 4 per 10s window at low intensity
    }

    @Test("High intensity allows more effects")
    func highIntensityAllowsMore() {
        let decisions = (0..<10).map { i in
            EditDecision(
                time: Double(i),
                duration: 0.3,
                type: .sfx,
                reason: "test",
                intensity: 0.5
            )
        }
        let template = TemplateConfig.viralCaption // high intensity
        let limited = IntensityLimiter.limit(decisions, template: template)
        #expect(limited.count > 2)
    }
}

// MARK: - Over Editing Guard

@Suite("OverEditingGuard")
struct OverEditingGuardTests {
    @Test("Same-type effects respect minimum gap")
    func sameTypeGap() {
        let decisions = [
            EditDecision(time: 0, duration: 0.3, type: .zoom, reason: "a", intensity: 0.5),
            EditDecision(time: 1, duration: 0.3, type: .zoom, reason: "b", intensity: 0.5),
            EditDecision(time: 5, duration: 0.3, type: .zoom, reason: "c", intensity: 0.5),
        ]
        let filtered = OverEditingGuard.filter(decisions, totalDuration: 60)
        // time=1 should be removed (within 1.5s of time=0)
        #expect(filtered.count == 2)
    }

    @Test("Different types at same time are allowed")
    func differentTypesAllowed() {
        let decisions = [
            EditDecision(time: 0, duration: 0.3, type: .zoom, reason: "a", intensity: 0.5),
            EditDecision(time: 0, duration: 0.3, type: .sfx, reason: "b", intensity: 0.5),
        ]
        let filtered = OverEditingGuard.filter(decisions, totalDuration: 60)
        #expect(filtered.count == 2)
    }

    @Test("Per-minute cap enforced")
    func perMinuteCap() {
        // 50 effects in 60s = 50/min — exceeds 40/min cap
        let decisions = (0..<50).map { i in
            EditDecision(
                time: Double(i) * 1.2,
                duration: 0.3,
                type: EditType.allCases[i % EditType.allCases.count],
                reason: "test",
                intensity: 0.5
            )
        }
        let filtered = OverEditingGuard.filter(decisions, totalDuration: 60)
        #expect(filtered.count <= 40) // max 40 per minute
    }
}

// MARK: - Quality Gate

@Suite("QualityGateService")
struct QualityGateServiceTests {
    @Test("Empty captions fail quality gate")
    func emptyCaptionsFail() {
        let plan = EditPlan(
            decisions: [],
            template: .premiumFounder,
            totalEffects: 0,
            averageIntensity: 0
        )
        let roughCut = RoughCutResult(
            decisions: [],
            originalDuration: 60,
            cleanDuration: 55,
            keepSegments: [],
            cutSegments: [],
            reviewSegments: []
        )
        let report = QualityGateService.evaluate(
            captions: [],
            editPlan: plan,
            roughCut: roughCut,
            template: .premiumFounder
        )
        #expect(!report.passed)
    }

    @Test("Good content passes quality gate")
    func goodContentPasses() {
        let captions = [
            CaptionSegment(startTime: 0, endTime: 3, text: "Hook opening", role: .hook, style: .hookImpact),
            CaptionSegment(startTime: 3, endTime: 6, text: "Main content here", role: .regular, style: .minimalWellness),
            CaptionSegment(startTime: 6, endTime: 9, text: "Conclusion wrap up", role: .conclusion, style: .minimalWellness),
        ]
        let plan = EditPlan(
            decisions: [],
            template: .cleanExpert,
            totalEffects: 0,
            averageIntensity: 0
        )
        let roughCut = RoughCutResult(
            decisions: [],
            originalDuration: 12,
            cleanDuration: 9,
            keepSegments: [],
            cutSegments: [],
            reviewSegments: []
        )
        let report = QualityGateService.evaluate(
            captions: captions,
            editPlan: plan,
            roughCut: roughCut,
            template: .cleanExpert
        )
        #expect(report.passed)
        #expect(report.score >= 70)
    }
}

// MARK: - Audio Quality Guard

@Suite("AudioQualityGuard")
struct AudioQualityGuardTests {
    @Test("Empty samples fail")
    func emptySamplesFail() {
        let report = AudioQualityGuard.analyze(samples: [])
        #expect(!report.passed)
        #expect(report.isTooQuiet)
    }

    @Test("Normal audio passes")
    func normalAudioPasses() {
        // Generate speech-like audio with good dynamic range
        var samples = [Float]()
        for i in 0..<16000 {
            // Loud sections (0.7 amplitude) alternating with quiet sections (0.03)
            let envelope: Float = (i % 4000) < 2000 ? 0.7 : 0.03
            samples.append(Float(sin(Double(i) * 0.1)) * envelope)
        }
        let report = AudioQualityGuard.analyze(samples: samples)
        #expect(!report.isClipping)
        #expect(!report.isTooQuiet)
        #expect(report.passed)
    }

    @Test("Clipping detected")
    func clippingDetected() {
        let samples = [Float](repeating: 0.99, count: 1000)
        let report = AudioQualityGuard.analyze(samples: samples)
        #expect(report.isClipping)
    }
}

// MARK: - Transcript Cleanup

@Suite("TranscriptCleanupAnalyzer")
struct TranscriptCleanupAnalyzerTests {
    private func makeSegment(text: String, start: Double = 0, end: Double = 1) -> TranscriptSegment {
        TranscriptSegment(
            startTime: start,
            endTime: end,
            text: text,
            confidence: 0.9,
            segmentType: .speech
        )
    }

    @Test("Filler words detected")
    func fillerDetection() {
        let segments = [
            makeSegment(text: "şey", start: 0, end: 0.5),
            makeSegment(text: "Bu konu önemli", start: 1, end: 3),
        ]
        let result = TranscriptCleanupAnalyzer.analyze(segments)
        #expect(result.fillersRemoved == 1)
        #expect(result.segments[0].segmentType == .filler)
    }

    @Test("Restart detected between similar segments")
    func restartDetection() {
        let segments = [
            makeSegment(text: "Bu konuyu anlatmak istiyorum", start: 0, end: 2),
            makeSegment(text: "Bu konuyu anlatmak istiyorum aslında çok basit", start: 2, end: 5),
        ]
        let result = TranscriptCleanupAnalyzer.analyze(segments)
        #expect(result.restartsDetected >= 1)
    }
}

// MARK: - Best Take Selector

@Suite("BestTakeSelector")
struct BestTakeSelectorTests {
    @Test("Later take with higher confidence wins")
    func laterBetterTakeWins() {
        let takes = [
            TranscriptSegment(startTime: 0, endTime: 2, text: "Bugün hakkında konuşacağız", confidence: 0.6, segmentType: .speech),
            TranscriptSegment(startTime: 3, endTime: 5, text: "Bugün bu konu hakkında konuşacağız", confidence: 0.9, segmentType: .speech),
        ]
        let bestIndex = BestTakeSelector.selectBest(from: takes)
        #expect(bestIndex == 1) // Second take is better
    }
}

// MARK: - Continuity Checker

@Suite("ContinuityChecker")
struct ContinuityCheckerTests {
    @Test("Adjacent segments are smooth")
    func adjacentSmooth() {
        let decisions = [
            RoughCutDecision(startTime: 0, endTime: 3, action: .keep, reason: "kept", confidence: 1, linkedTranscriptText: nil, requiresReview: false),
            RoughCutDecision(startTime: 3.1, endTime: 6, action: .keep, reason: "kept", confidence: 1, linkedTranscriptText: nil, requiresReview: false),
        ]
        let result = ContinuityChecker.check(keptDecisions: decisions)
        #expect(result.smoothTransitions == 1)
        #expect(result.roughTransitions == 0)
    }

    @Test("Large gap flagged as rough")
    func largeGapRough() {
        let decisions = [
            RoughCutDecision(startTime: 0, endTime: 3, action: .keep, reason: "kept", confidence: 1, linkedTranscriptText: nil, requiresReview: false),
            RoughCutDecision(startTime: 8, endTime: 12, action: .keep, reason: "kept", confidence: 1, linkedTranscriptText: nil, requiresReview: false),
        ]
        let result = ContinuityChecker.check(keptDecisions: decisions)
        #expect(result.roughTransitions == 1)
    }
}

// MARK: - Template Config

@Suite("TemplateConfig")
struct TemplateConfigTests {
    @Test("Five presets exist")
    func fivePresetsExist() {
        #expect(TemplateConfig.all.count == 5)
    }

    @Test("Premium Founder is low intensity")
    func premiumFounderLow() {
        #expect(TemplateConfig.premiumFounder.intensity == .low)
    }

    @Test("Viral Caption is high intensity")
    func viralCaptionHigh() {
        #expect(TemplateConfig.viralCaption.intensity == .high)
    }

    @Test("Each template has unique ID")
    func uniqueIDs() {
        let ids = TemplateConfig.all.map(\.id)
        #expect(Set(ids).count == 5)
    }
}

// MARK: - Confidence-Based Review

@Suite("ConfidenceBasedReview")
struct ConfidenceBasedReviewTests {
    private func makeSegment(
        text: String,
        type: TranscriptSegment.SegmentType,
        aiConfidence: Float?,
        aiReason: String? = nil
    ) -> TranscriptSegment {
        TranscriptSegment(
            startTime: 0, endTime: 1, text: text,
            confidence: 0.9, segmentType: type,
            aiConfidence: aiConfidence, aiReason: aiReason
        )
    }

    private func makeAudio() -> AudioAnalysisResult {
        AudioAnalysisResult(
            segments: [AudioSegment(startTime: 0, endTime: 10, type: .speech, energy: 0.5)],
            silenceIntervals: [],
            averageEnergy: 0.3,
            peakEnergy: 0.8,
            duration: 10
        )
    }

    @Test("High-confidence filler is hard cut")
    func highConfidenceFillerCut() {
        let seg = makeSegment(text: "um", type: .filler, aiConfidence: 0.95, aiReason: "Pure filler")
        let transcript = TranscriptionResult(fullText: "um", segments: [seg], language: "en", overallConfidence: 0.9)
        let result = RoughCutDecisionEngine.generateDecisions(transcription: transcript, audioAnalysis: makeAudio())
        let decision = result.decisions.first { $0.linkedTranscriptText == "um" }
        #expect(decision?.action == .cut)
        #expect(decision?.requiresReview == false)
    }

    @Test("Low-confidence filler flagged for review")
    func lowConfidenceFillerReview() {
        let seg = makeSegment(text: "şey gibi", type: .filler, aiConfidence: 0.55, aiReason: "Might be filler")
        let transcript = TranscriptionResult(fullText: "şey gibi", segments: [seg], language: "tr", overallConfidence: 0.9)
        let result = RoughCutDecisionEngine.generateDecisions(transcription: transcript, audioAnalysis: makeAudio())
        let decision = result.decisions.first { $0.linkedTranscriptText == "şey gibi" }
        #expect(decision?.action == .reviewRequired)
        #expect(decision?.requiresReview == true)
        #expect(decision?.reason.contains("uncertain") == true)
    }

    @Test("High-confidence restart is hard cut")
    func highConfidenceRestartCut() {
        let seg = makeSegment(text: "bugün ben", type: .suspectedRestart, aiConfidence: 0.85, aiReason: "Incomplete start")
        let transcript = TranscriptionResult(fullText: "bugün ben", segments: [seg], language: "tr", overallConfidence: 0.9)
        let result = RoughCutDecisionEngine.generateDecisions(transcription: transcript, audioAnalysis: makeAudio())
        let decision = result.decisions.first { $0.linkedTranscriptText == "bugün ben" }
        #expect(decision?.action == .cut)
        #expect(decision?.requiresReview == false)
    }

    @Test("Low-confidence restart flagged for review")
    func lowConfidenceRestartReview() {
        let seg = makeSegment(text: "bugün ben", type: .suspectedRestart, aiConfidence: 0.45, aiReason: "Might be restart or real content")
        let transcript = TranscriptionResult(fullText: "bugün ben", segments: [seg], language: "tr", overallConfidence: 0.9)
        let result = RoughCutDecisionEngine.generateDecisions(transcription: transcript, audioAnalysis: makeAudio())
        let decision = result.decisions.first { $0.linkedTranscriptText == "bugün ben" }
        #expect(decision?.action == .reviewRequired)
        #expect(decision?.requiresReview == true)
    }

    @Test("Low-confidence content kept but flagged for review")
    func lowConfidenceContentReview() {
        let seg = makeSegment(text: "kese kağıdı", type: .contentSentence, aiConfidence: 0.60, aiReason: "Contains 'kes' but seems like content")
        let transcript = TranscriptionResult(fullText: "kese kağıdı", segments: [seg], language: "tr", overallConfidence: 0.9)
        let result = RoughCutDecisionEngine.generateDecisions(transcription: transcript, audioAnalysis: makeAudio())
        let decision = result.decisions.first { $0.linkedTranscriptText == "kese kağıdı" }
        #expect(decision?.action == .keep)
        #expect(decision?.requiresReview == true)
    }

    @Test("No AI confidence (heuristic path) uses defaults")
    func heuristicFallbackNoReview() {
        let seg = makeSegment(text: "eee", type: .filler, aiConfidence: nil)
        let transcript = TranscriptionResult(fullText: "eee", segments: [seg], language: "tr", overallConfidence: 0.9)
        let result = RoughCutDecisionEngine.generateDecisions(transcription: transcript, audioAnalysis: makeAudio())
        let decision = result.decisions.first { $0.linkedTranscriptText == "eee" }
        #expect(decision?.action == .cut)
        #expect(decision?.requiresReview == false)
    }

    @Test("AI reason propagated to decision")
    func aiReasonPropagated() {
        let seg = makeSegment(text: "bunu kes", type: .filler, aiConfidence: 0.92, aiReason: "Speaker directing editor to cut")
        let transcript = TranscriptionResult(fullText: "bunu kes", segments: [seg], language: "tr", overallConfidence: 0.9)
        let result = RoughCutDecisionEngine.generateDecisions(transcription: transcript, audioAnalysis: makeAudio())
        let decision = result.decisions.first { $0.linkedTranscriptText == "bunu kes" }
        #expect(decision?.reason == "Speaker directing editor to cut")
    }
}
