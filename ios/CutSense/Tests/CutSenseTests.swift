import Testing
import Foundation
import AVFoundation
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

    @Test("Turkish hook pattern detected in opening window")
    func turkishHookPattern() {
        let role = CaptionRoleClassifier.classify(
            text: "Dikkat bu çok önemli",
            index: 0,
            totalSegments: 10,
            previousRole: nil,
            startTime: 0.4
        )
        #expect(role == .hook)
    }

    @Test("Mid-video dikkat keeps warning meaning")
    func midVideoDikkatIsWarning() {
        let role = CaptionRoleClassifier.classify(
            text: "Dikkat bu ayarı prod'da açma",
            index: 5,
            totalSegments: 10,
            previousRole: .regular,
            startTime: 18
        )
        #expect(role == .warning)
    }

    @Test("Opening stop doing remains hook")
    func openingStopDoingIsHook() {
        let role = CaptionRoleClassifier.classify(
            text: "Stop doing this in Cursor",
            index: 0,
            totalSegments: 8,
            previousRole: nil,
            startTime: 0.3
        )
        #expect(role == .hook)
    }

    @Test("Closing conclusion beats reveal wording")
    func closingConclusionBeatsRevealWording() {
        let role = CaptionRoleClassifier.classify(
            text: "Sonuç olarak yorumlara yaz",
            index: 7,
            totalSegments: 8,
            previousRole: .regular,
            startTime: 24
        )
        #expect(role == .conclusion)
    }

    @Test("Generic real-device status is not reveal")
    func genericRealDeviceStatusIsNotReveal() {
        let role = CaptionRoleClassifier.classify(
            text: "Gerçek cihazda build aldım",
            index: 4,
            totalSegments: 9,
            previousRole: .regular,
            startTime: 14
        )
        #expect(role == .regular)
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

    @Test("High priority hook combo survives dense window")
    func highPriorityHookComboSurvivesDenseWindow() {
        var decisions = (0..<12).map { i in
            EditDecision(
                time: Double(i) * 0.35,
                duration: 0.3,
                type: .zoom,
                reason: "Subtle push zoom",
                intensity: 0.3
            )
        }
        decisions.append(EditDecision(time: 3.0, duration: 0.8, type: .zoom, reason: "Hook push-pull zoom", intensity: 1.0))
        decisions.append(EditDecision(time: 3.0, duration: 0.22, type: .sfx, reason: "Hook impact SFX", intensity: 0.8))
        decisions.append(EditDecision(time: 3.0, duration: 0.18, type: .flash, reason: "Hook flash", intensity: 0.5))

        let limited = IntensityLimiter.limit(decisions, template: .viralCaption)

        #expect(limited.contains { $0.reason == "Hook push-pull zoom" })
        #expect(limited.contains { $0.reason == "Hook impact SFX" })
        #expect(limited.contains { $0.reason == "Hook flash" })
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

    @Test("Different SFX lanes can stack at the same edit point")
    func differentSFXLanesCanStack() {
        let decisions = [
            EditDecision(time: 1.0, duration: 0.2, type: .sfx, reason: "Cut whoosh", intensity: 0.55),
            EditDecision(time: 1.0, duration: 0.2, type: .sfx, reason: "Hook impact SFX", intensity: 0.8),
            EditDecision(time: 0.2, duration: 0.8, type: .sfx, reason: "Conclusion riser", intensity: 0.45),
        ]

        let filtered = OverEditingGuard.filter(decisions, totalDuration: 10)

        #expect(filtered.count == 3)
        #expect(filtered.contains { $0.reason == "Cut whoosh" })
        #expect(filtered.contains { $0.reason == "Hook impact SFX" })
        #expect(filtered.contains { $0.reason == "Conclusion riser" })
    }

    @Test("Repeated whooshes still respect lane gap")
    func repeatedWhooshesRespectLaneGap() {
        let decisions = [
            EditDecision(time: 1.0, duration: 0.2, type: .sfx, reason: "Cut whoosh", intensity: 0.55),
            EditDecision(time: 1.2, duration: 0.2, type: .sfx, reason: "Transition whoosh", intensity: 0.65),
            EditDecision(time: 1.6, duration: 0.2, type: .sfx, reason: "Transition whoosh", intensity: 0.65),
        ]

        let filtered = OverEditingGuard.filter(decisions, totalDuration: 10)

        #expect(filtered.count == 2)
        #expect(filtered.contains { abs($0.time - 1.0) < 0.001 })
        #expect(filtered.contains { abs($0.time - 1.6) < 0.001 })
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

    @Test("Punch accents can be closer than generic repeated zooms")
    func punchAccentsUseShorterGap() {
        let decisions = [
            EditDecision(time: 0, duration: 0.45, type: .zoom, reason: "Punch camera punch", intensity: 0.8),
            EditDecision(time: 0.8, duration: 0.45, type: .zoom, reason: "Punch camera punch", intensity: 0.8),
            EditDecision(time: 1.2, duration: 0.45, type: .zoom, reason: "Punch camera punch", intensity: 0.8),
        ]

        let filtered = OverEditingGuard.filter(decisions, totalDuration: 10)

        #expect(filtered.count == 2)
        #expect(filtered.contains { abs($0.time - 0.8) < 0.001 })
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

    @Test("Low-confidence transcript fails quality gate")
    func lowConfidenceTranscriptFails() {
        let captions = [
            CaptionSegment(startTime: 0, endTime: 3, text: "Hook opening", role: .hook, style: .hookImpact),
            CaptionSegment(startTime: 3, endTime: 6, text: "Misheard caption", role: .regular, style: .minimalWellness),
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
        let transcription = TranscriptionResult(
            fullText: "Hook opening misheard caption conclusion wrap up",
            segments: [
                TranscriptSegment(startTime: 0, endTime: 3, text: "Hook opening", confidence: 0.92, segmentType: .speech),
                TranscriptSegment(startTime: 3, endTime: 6, text: "Misheard caption", confidence: 0.31, segmentType: .speech),
                TranscriptSegment(startTime: 6, endTime: 9, text: "Conclusion wrap up", confidence: 0.91, segmentType: .speech),
            ],
            language: "tr",
            overallConfidence: 0.71
        )

        let report = QualityGateService.evaluate(
            captions: captions,
            editPlan: plan,
            roughCut: roughCut,
            template: .cleanExpert,
            transcription: transcription
        )

        #expect(!report.passed)
        #expect(report.failedChecks.contains { $0.name == "Transcription confidence" })
    }

    @Test("Corrected transcript display confidence cannot bypass raw ASR quality")
    func correctedTranscriptPreservesRawConfidenceForQualityGate() {
        let rawSegment = TranscriptSegment(
            startTime: 0,
            endTime: 3,
            text: "MVP'ye çevir bil sinler",
            confidence: 0.42,
            segmentType: .speech
        )
        let corrected = TranscriptPostProcessor.corrected(
            TranscriptionResult(
                fullText: rawSegment.text,
                segments: [rawSegment],
                language: "tr",
                overallConfidence: 0.42
            )
        )
        let captions = [
            CaptionSegment(startTime: 0, endTime: 3, text: corrected.fullText, role: .hook, style: .hookImpact),
            CaptionSegment(startTime: 3, endTime: 4, text: "sonuç hazır", role: .conclusion, style: .minimalWellness),
        ]
        let roughCut = RoughCutResult(
            decisions: [
                RoughCutDecision(startTime: 0, endTime: 3, action: .keep, reason: "Content", confidence: 0.9, linkedTranscriptText: corrected.fullText, requiresReview: false),
            ],
            originalDuration: 4,
            cleanDuration: 3,
            keepSegments: [
                RoughCutDecision(startTime: 0, endTime: 3, action: .keep, reason: "Content", confidence: 0.9, linkedTranscriptText: corrected.fullText, requiresReview: false),
            ],
            cutSegments: [],
            reviewSegments: []
        )

        let report = QualityGateService.evaluate(
            captions: captions,
            editPlan: EditPlan(decisions: [], template: .cleanExpert, totalEffects: 0, averageIntensity: 0),
            roughCut: roughCut,
            template: .cleanExpert,
            transcription: corrected
        )
        let transcriptionCheck = report.failedChecks.first { $0.name == "Transcription confidence" }

        #expect(corrected.overallConfidence >= 0.68)
        #expect(corrected.qualityConfidence == 0.42)
        #expect(corrected.segments.first?.rawConfidence == 0.42)
        #expect(!report.passed)
        #expect(transcriptionCheck?.blocksExport == true)
    }

    @Test("Partial transcript fails quality gate even with high confidence")
    func partialTranscriptFailsQualityGate() {
        let segments = [
            TranscriptSegment(startTime: 0, endTime: 2, text: "This AI tool builds apps", confidence: 0.95, segmentType: .speech),
            TranscriptSegment(startTime: 2, endTime: 4, text: "then exports them fast", confidence: 0.94, segmentType: .speech),
        ]
        let captions = [
            CaptionSegment(startTime: 0, endTime: 2, text: "This AI tool", role: .hook, style: .hookImpact),
            CaptionSegment(startTime: 2, endTime: 4, text: "exports them fast", role: .conclusion, style: .minimalWellness),
        ]
        let keep = RoughCutDecision(startTime: 0, endTime: 4, action: .keep, reason: "Content", confidence: 0.9, linkedTranscriptText: "This AI tool builds apps then exports them fast", requiresReview: false)
        let transcription = TranscriptionResult(
            fullText: segments.map(\.text).joined(separator: " "),
            segments: segments,
            language: "en",
            overallConfidence: 0.95,
            rawOverallConfidence: 0.95,
            recognitionStatus: .partialTimedOut
        )

        let report = QualityGateService.evaluate(
            captions: captions,
            editPlan: EditPlan(decisions: [], template: .cleanExpert, totalEffects: 0, averageIntensity: 0),
            roughCut: RoughCutResult(
                decisions: [keep],
                originalDuration: 5,
                cleanDuration: 4,
                keepSegments: [keep],
                cutSegments: [],
                reviewSegments: []
            ),
            template: .cleanExpert,
            transcription: transcription
        )
        let transcriptionCheck = report.failedChecks.first { $0.name == "Transcription confidence" }

        #expect(!report.passed)
        #expect(transcriptionCheck?.blocksExport == true)
        #expect(transcriptionCheck?.detail.contains("partial_timed_out") == true)
    }

    @Test("Unresolved ASR artifacts fail quality gate")
    func unresolvedASRArtifactsFail() {
        let segment = TranscriptSegment(
            startTime: 0,
            endTime: 3,
            text: "ürün çıkarabilsin fikirlerin en VP",
            confidence: 0.82,
            segmentType: .speech
        )
        let captions = [
            CaptionSegment(startTime: 0, endTime: 3, text: segment.text, role: .hook, style: .hookImpact),
            CaptionSegment(startTime: 3, endTime: 4, text: "bitti", role: .conclusion, style: .minimalWellness),
        ]
        let decisions = [
            RoughCutDecision(startTime: 0, endTime: 3, action: .keep, reason: "Content", confidence: 0.9, linkedTranscriptText: segment.text, requiresReview: false),
        ]
        let report = QualityGateService.evaluate(
            captions: captions,
            editPlan: EditPlan(decisions: [], template: .viralCaption, totalEffects: 0, averageIntensity: 0),
            roughCut: RoughCutResult(
                decisions: decisions,
                originalDuration: 3,
                cleanDuration: 3,
                keepSegments: decisions,
                cutSegments: [],
                reviewSegments: []
            ),
            template: .viralCaption,
            transcription: TranscriptionResult(
                fullText: segment.text,
                segments: [segment],
                language: "tr",
                overallConfidence: 0.82
            )
        )

        #expect(!report.passed)
        #expect(report.failedChecks.contains { $0.name == "Transcript artifact cleanup" })
    }

    @Test("Current physical-device ASR artifacts block quality gate")
    func currentPhysicalDeviceASRArtifactsBlockQualityGate() {
        let segments = [
            TranscriptSegment(
                startTime: 18.78,
                endTime: 21.69,
                text: "Vibe Coding topluluğu by Holding turkey kurdum cod",
                confidence: 0.72,
                segmentType: .speech
            ),
            TranscriptSegment(
                startTime: 34.89,
                endTime: 36.51,
                text: "vay biraz birlikte büyüyelim",
                confidence: 0.92,
                segmentType: .speech
            ),
        ]
        let captions = segments.enumerated().map { index, segment in
            CaptionSegment(
                startTime: segment.startTime,
                endTime: segment.endTime,
                text: segment.text,
                role: index == 0 ? .hook : .conclusion,
                style: .hookImpact
            )
        }
        let decisions = segments.map {
            RoughCutDecision(
                startTime: $0.startTime,
                endTime: $0.endTime,
                action: .keep,
                reason: "Content",
                confidence: 0.9,
                linkedTranscriptText: $0.text,
                requiresReview: false
            )
        }

        let report = QualityGateService.evaluate(
            captions: captions,
            editPlan: EditPlan(decisions: [], template: .viralCaption, totalEffects: 0, averageIntensity: 0),
            roughCut: RoughCutResult(
                decisions: decisions,
                originalDuration: 36.51,
                cleanDuration: 4.53,
                keepSegments: decisions,
                cutSegments: [],
                reviewSegments: []
            ),
            template: .viralCaption,
            transcription: TranscriptionResult(
                fullText: segments.map(\.text).joined(separator: " "),
                segments: segments,
                language: "tr",
                overallConfidence: 0.82
            )
        )

        #expect(!report.passed)
        #expect(report.failedChecks.contains { $0.name == "Transcript artifact cleanup" && $0.blocksExport })
    }

    @Test("Second physical-device ASR artifact set blocks quality gate")
    func secondPhysicalDeviceASRArtifactsBlockQualityGate() {
        let segments = [
            TranscriptSegment(
                startTime: 17.52,
                endTime: 20.22,
                text: "Türkiye'nin ilk Vibe Coding topluluğu vay Kolding",
                confidence: 0.72,
                segmentType: .speech
            ),
            TranscriptSegment(
                startTime: 22.89,
                endTime: 26.31,
                text: "çıkarabilirsin fikirlerine MHP'ye çevirebilsinler web",
                confidence: 0.68,
                segmentType: .speech
            ),
            TranscriptSegment(
                startTime: 26.31,
                endTime: 27.78,
                text: "ya da And roid 'de ya da",
                confidence: 0.64,
                segmentType: .speech
            ),
            TranscriptSegment(
                startTime: 27.78,
                endTime: 30.66,
                text: "Apple Store 'da yayınlayabilir sin ler diye eğer",
                confidence: 0.71,
                segmentType: .speech
            ),
            TranscriptSegment(
                startTime: 32.22,
                endTime: 35.19,
                text: "istersen yorumlara var biraz birlikte büyüyelim",
                confidence: 0.69,
                segmentType: .speech
            ),
        ]
        let captions = segments.enumerated().map { index, segment in
            CaptionSegment(
                startTime: segment.startTime,
                endTime: segment.endTime,
                text: segment.text,
                role: index == 0 ? .hook : .regular,
                style: .boldCenterViral,
                wordTimings: segment.wordTimings
            )
        }
        let decisions = segments.map {
            RoughCutDecision(
                startTime: $0.startTime,
                endTime: $0.endTime,
                action: .keep,
                reason: "Content",
                confidence: 0.9,
                linkedTranscriptText: $0.text,
                requiresReview: false
            )
        }

        let report = QualityGateService.evaluate(
            captions: captions,
            editPlan: EditPlan(decisions: [], template: .viralCaption, totalEffects: 0, averageIntensity: 0),
            roughCut: RoughCutResult(
                decisions: decisions,
                originalDuration: 36.5,
                cleanDuration: 12,
                keepSegments: decisions,
                cutSegments: [],
                reviewSegments: []
            ),
            template: .viralCaption,
            transcription: TranscriptionResult(
                fullText: segments.map(\.text).joined(separator: " "),
                segments: segments,
                language: "tr",
                overallConfidence: 0.80
            )
        )

        #expect(!report.passed)
        #expect(report.failedChecks.contains { $0.name == "Transcript artifact cleanup" && $0.blocksExport })
    }

    @Test("Caption word timing artifacts are reported even when display text is corrected")
    func captionWordTimingArtifactsReported() {
        let captions = [
            CaptionSegment(
                startTime: 0,
                endTime: 3,
                text: "Vibe Coding Turkey kurdum",
                role: .hook,
                style: .hookImpact,
                wordTimings: [
                    (word: "BAP", start: 0, duration: 0.5),
                    (word: "Holding", start: 0.5, duration: 0.5),
                    (word: "Turkey", start: 1.0, duration: 0.5),
                    (word: "kurdum", start: 1.5, duration: 0.5),
                ]
            ),
            CaptionSegment(startTime: 3, endTime: 4, text: "büyüyelim", role: .conclusion, style: .hookImpact),
        ]
        let decisions = [
            RoughCutDecision(startTime: 0, endTime: 4, action: .keep, reason: "Content", confidence: 0.9, linkedTranscriptText: nil, requiresReview: false),
        ]

        let report = QualityGateService.evaluate(
            captions: captions,
            editPlan: EditPlan(decisions: [], template: .viralCaption, totalEffects: 0, averageIntensity: 0),
            roughCut: RoughCutResult(
                decisions: decisions,
                originalDuration: 5,
                cleanDuration: 4,
                keepSegments: decisions,
                cutSegments: [],
                reviewSegments: []
            ),
            template: .viralCaption
        )

        #expect(report.failedChecks.contains { $0.name == "Caption timing token alignment" })
        #expect(report.failedChecks.contains { $0.name == "Caption timing artifact cleanup" })
        #expect(report.failedChecks.contains { $0.name == "Caption timing artifact cleanup" && $0.blocksExport })
        #expect(!report.passed)
    }

    @Test("Warning-only score below production threshold fails quality gate")
    func warningOnlyLowScoreFailsQualityGate() {
        let captions = [
            CaptionSegment(startTime: 0, endTime: 3, text: "Regular content", role: .regular, style: .minimalWellness),
            CaptionSegment(startTime: 3, endTime: 6, text: "More regular content", role: .regular, style: .minimalWellness),
        ]
        let effects = (0..<8).map { index in
            EditDecision(time: Double(index) * 0.35, duration: 0.2, type: .zoom, reason: "dense effect", intensity: 0.7)
        }
        let report = QualityGateService.evaluate(
            captions: captions,
            editPlan: EditPlan(decisions: effects, template: .viralCaption, totalEffects: effects.count, averageIntensity: 0.7),
            roughCut: RoughCutResult(
                decisions: [
                    RoughCutDecision(startTime: 0, endTime: 6, action: .keep, reason: "Content", confidence: 0.9, linkedTranscriptText: nil, requiresReview: false)
                ],
                originalDuration: 10,
                cleanDuration: 6,
                keepSegments: [],
                cutSegments: [],
                reviewSegments: []
            ),
            template: .viralCaption
        )

        #expect(report.score < 80)
        #expect(!report.passed)
    }

    @Test("High-intensity viral template allows dense combo effect pacing")
    func highIntensityViralTemplateAllowsDenseComboPacing() {
        let captions = [
            CaptionSegment(startTime: 0, endTime: 3, text: "Hook opening", role: .hook, style: .hookImpact),
            CaptionSegment(startTime: 3, endTime: 30, text: "Main content here", role: .regular, style: .boldCenterViral),
            CaptionSegment(startTime: 30, endTime: 34.37, text: "Conclusion wrap up", role: .conclusion, style: .hookImpact),
        ]
        let totalEffects = 40
        let report = QualityGateService.evaluate(
            captions: captions,
            editPlan: EditPlan(
                decisions: (0..<totalEffects).map { index in
                    EditDecision(time: Double(index) * 0.8, duration: 0.2, type: .zoom, reason: "combo", intensity: 0.6)
                },
                template: .viralCaption,
                totalEffects: totalEffects,
                averageIntensity: 0.6
            ),
            roughCut: RoughCutResult(
                decisions: [
                    RoughCutDecision(startTime: 0, endTime: 34.37, action: .keep, reason: "Content", confidence: 0.9, linkedTranscriptText: nil, requiresReview: false)
                ],
                originalDuration: 37.38,
                cleanDuration: 34.37,
                keepSegments: [],
                cutSegments: [],
                reviewSegments: []
            ),
            template: .viralCaption
        )

        #expect(report.checks.first { $0.name == "Effect density" }?.passed == true)
        #expect(report.passed)
        #expect(report.score == 100)
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

    @Test("Odd WhatsApp frame rates export at nearest common cadence")
    func oddWhatsAppFrameRatesUseNearestCommonCadence() {
        let frameDuration = ExportService.frameDuration(for: 600.0 / 19.0)

        #expect(frameDuration == CMTime(value: 1, timescale: 30))
        #expect(abs(CMTimeGetSeconds(frameDuration) - (1.0 / 30.0)) < 0.0001)
    }
}

// MARK: - Caption Engine

@Suite("CaptionEngine")
struct CaptionEngineConfidenceTests {
    @Test("Low-confidence transcript segments are not captioned")
    func lowConfidenceSegmentsAreNotCaptioned() {
        let segments = [
            TranscriptSegment(startTime: 0, endTime: 2, text: "Reliable opening", confidence: 0.92, segmentType: .speech),
            TranscriptSegment(startTime: 2, endTime: 4, text: "Badly misheard words", confidence: 0.31, segmentType: .speech),
            TranscriptSegment(startTime: 4, endTime: 6, text: "Reliable ending", confidence: 0.88, segmentType: .speech),
        ]
        let transcription = TranscriptionResult(
            fullText: segments.map(\.text).joined(separator: " "),
            segments: segments,
            language: "tr",
            overallConfidence: 0.70
        )
        let roughCut = RoughCutResult(
            decisions: [
                RoughCutDecision(startTime: 0, endTime: 6, action: .keep, reason: "Content", confidence: 0.9, linkedTranscriptText: nil, requiresReview: false)
            ],
            originalDuration: 6,
            cleanDuration: 6,
            keepSegments: [],
            cutSegments: [],
            reviewSegments: []
        )

        let captions = CaptionEngine.generateCaptions(
            from: transcription,
            roughCut: roughCut,
            template: .cleanExpert
        )

        #expect(captions.contains { $0.text == "Reliable opening" })
        #expect(captions.contains { $0.text == "Reliable ending" })
        #expect(!captions.contains { $0.text == "Badly misheard words" })
    }

    @Test("Caption engine rewrites raw ASR timing tokens to match corrected display text")
    func captionEngineAlignsCorrectedTimingTokens() {
        var segment = TranscriptSegment(
            startTime: 0,
            endTime: 2,
            text: "Vibe Coding Turkey kurdum",
            confidence: 0.92,
            segmentType: .speech
        )
        segment.wordTimings = [
            (word: "BAP", start: 0.0, duration: 0.4),
            (word: "Holding", start: 0.4, duration: 0.4),
            (word: "Turkey", start: 0.8, duration: 0.4),
            (word: "kurdum", start: 1.2, duration: 0.4),
        ]
        let roughCutDecision = RoughCutDecision(
            startTime: 0,
            endTime: 2,
            action: .keep,
            reason: "Content",
            confidence: 0.92,
            linkedTranscriptText: segment.text,
            requiresReview: false
        )
        let transcription = TranscriptionResult(
            fullText: segment.text,
            segments: [segment],
            language: "tr",
            overallConfidence: 0.92
        )

        let captions = CaptionEngine.generateCaptions(
            from: transcription,
            roughCut: RoughCutResult(
                decisions: [roughCutDecision],
                originalDuration: 2,
                cleanDuration: 2,
                keepSegments: [roughCutDecision],
                cutSegments: [],
                reviewSegments: []
            ),
            template: .viralCaption
        )

        #expect(captions.first?.wordTimings.map(\.word) == ["Vibe", "Coding", "Turkey", "kurdum"])
    }
}

@Suite("SpeechTranscriptionFallbackPolicy")
struct SpeechTranscriptionFallbackPolicyTests {
    @Test("High-confidence tech terms do not force English fallback")
    func highConfidenceTechTermsDoNotForceEnglishFallback() {
        let result = TranscriptionResult(
            fullText: "Bu AI tool MVP için App Store ve web export hazırlıyor",
            segments: [
                TranscriptSegment(
                    startTime: 0,
                    endTime: 4,
                    text: "Bu AI tool MVP için App Store ve web export hazırlıyor",
                    confidence: 0.91,
                    segmentType: .speech
                )
            ],
            language: "tr",
            overallConfidence: 0.91
        )

        let shouldFallback = SpeechTranscriptionService.shouldAttemptEnglishFallback(
            for: result,
            durationSeconds: 37,
            primaryLanguage: "tr"
        )

        #expect(!shouldFallback)
    }

    @Test("Low-confidence mixed tech terms still trigger English fallback")
    func lowConfidenceMixedTechTermsTriggerEnglishFallback() {
        let result = TranscriptionResult(
            fullText: "Bu AI tool MVP için App Store ve web export hazırlıyor",
            segments: [
                TranscriptSegment(
                    startTime: 0,
                    endTime: 4,
                    text: "Bu AI tool MVP için App Store ve web export hazırlıyor",
                    confidence: 0.74,
                    segmentType: .speech
                )
            ],
            language: "tr",
            overallConfidence: 0.74
        )

        let shouldFallback = SpeechTranscriptionService.shouldAttemptEnglishFallback(
            for: result,
            durationSeconds: 37,
            primaryLanguage: "tr"
        )

        #expect(shouldFallback)
    }

    @Test("Known ASR artifacts trigger English fallback")
    func knownASRArtifactsTriggerEnglishFallback() {
        let result = TranscriptionResult(
            fullText: "Türkiye'nin ilk Vibe Coding topluluğu by Holding turkey kurdum cod",
            segments: [
                TranscriptSegment(
                    startTime: 18,
                    endTime: 22,
                    text: "Türkiye'nin ilk Vibe Coding topluluğu by Holding turkey kurdum cod",
                    confidence: 0.90,
                    segmentType: .speech
                )
            ],
            language: "tr",
            overallConfidence: 0.90
        )

        let shouldFallback = SpeechTranscriptionService.shouldAttemptEnglishFallback(
            for: result,
            durationSeconds: 37,
            primaryLanguage: "tr"
        )

        #expect(shouldFallback)
    }
}

@Suite("TranscriptPostProcessor")
struct TranscriptPostProcessorTests {
    private func timedSegment(
        start: Double,
        end: Double,
        text: String,
        confidence: Float,
        segmentType: TranscriptSegment.SegmentType = .speech
    ) -> TranscriptSegment {
        var segment = TranscriptSegment(
            startTime: start,
            endTime: end,
            text: text,
            confidence: confidence,
            segmentType: segmentType
        )
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        let duration = max(0.01, end - start)
        let wordDuration = duration / Double(max(1, words.count))
        segment.wordTimings = words.enumerated().map { index, word in
            (
                word: word,
                start: start + Double(index) * wordDuration,
                duration: wordDuration
            )
        }
        return segment
    }

    @Test("Mixed Turkish English product terms are corrected before quality gate")
    func mixedLanguageProductTermsAreCorrectedBeforeQualityGate() {
        let segments = [
            TranscriptSegment(startTime: 0.96, endTime: 3.84, text: "Türkiye'de çok fazla insanın harika fikirleri var", confidence: 0.95, segmentType: .speech),
            TranscriptSegment(startTime: 4.08, endTime: 6.33, text: "ama çoğu daha kod yazmayı bilmediği için", confidence: 0.94, segmentType: .speech),
            TranscriptSegment(startTime: 6.33, endTime: 8.88, text: "en baştan vazgeçiyor ben buna ayar oluyorum", confidence: 0.82, segmentType: .speech),
            TranscriptSegment(startTime: 9.21, endTime: 12.21, text: "artık uygulama yapmak için yıllarca yazılımcı olman gerekmiyor", confidence: 0.87, segmentType: .speech),
            TranscriptSegment(startTime: 12.42, endTime: 15.42, text: "doğru fikri doğru şekilde yapay zekayı anlatman gerek", confidence: 0.88, segmentType: .speech),
            TranscriptSegment(startTime: 15.81, endTime: 18.03, text: "işte tam da bu yüzden Türkiye'nin ilk", confidence: 0.84, segmentType: .speech),
            TranscriptSegment(startTime: 18.03, endTime: 20.67, text: "VİP Kolding topluluğu Way coin turkey kurdum", confidence: 0.25, segmentType: .speech),
            TranscriptSegment(startTime: 21.06, endTime: 23.34, text: "co bilmeyen insanlar da ürün çıkar abil sin", confidence: 0.55, segmentType: .speech),
            TranscriptSegment(startTime: 23.43, endTime: 25.74, text: "fikrine VP 'ye çevire bil sin App Store", confidence: 0.38, segmentType: .speech),
            TranscriptSegment(startTime: 25.74, endTime: 27.15, text: "'a ya da web 'e göndere bil", confidence: 0.39, segmentType: .speech),
            TranscriptSegment(startTime: 27.15, endTime: 29.31, text: "sin sen de bu topluluğun bir parçası", confidence: 0.83, segmentType: .speech),
            TranscriptSegment(startTime: 29.31, endTime: 32.37, text: "olmak istersen yorumlara vip biraz birlikte büyüyelim", confidence: 0.78, segmentType: .speech),
        ]
        let transcription = TranscriptPostProcessor.corrected(
            TranscriptionResult(
                fullText: segments.map(\.text).joined(separator: " "),
                segments: segments,
                language: "tr",
                overallConfidence: 0.70
            )
        )

        #expect(transcription.segments[6].text == "Vibe Coding topluluğu Vibe Coding Turkey kurdum")
        #expect(transcription.segments[6].confidence >= 0.72)
        #expect(transcription.segments[7].text == "kod bilmeyen insanlar da ürün çıkarabilsin")
        #expect(transcription.segments[8].text == "fikrini MVP'ye çevirebilsin App Store'a")
        #expect(transcription.segments[9].text == "ya da web'e")
        #expect(transcription.segments[10].text == "gönderebilsin sen de bu topluluğun bir parçası")
        #expect(transcription.segments[11].text.contains("yorumlara Vibe yazıp"))

        let decisions = transcription.segments.map {
            RoughCutDecision(
                startTime: $0.startTime,
                endTime: $0.endTime,
                action: .keep,
                reason: "Content",
                confidence: $0.confidence,
                linkedTranscriptText: $0.text,
                requiresReview: false
            )
        }
        let cleanDuration = decisions.reduce(0.0) { $0 + ($1.endTime - $1.startTime) }
        let roughCut = RoughCutResult(
            decisions: decisions,
            originalDuration: 33.2,
            cleanDuration: cleanDuration,
            keepSegments: decisions,
            cutSegments: [],
            reviewSegments: []
        )
        let captions = CaptionEngine.generateCaptions(
            from: transcription,
            roughCut: roughCut,
            template: .viralCaption
        )
        let report = QualityGateService.evaluate(
            captions: captions,
            editPlan: EditPlan(decisions: [], template: .viralCaption, totalEffects: 0, averageIntensity: 0),
            roughCut: roughCut,
            template: .viralCaption,
            transcription: transcription
        )

        #expect(captions.count == transcription.segments.count)
        #expect(!report.failedChecks.contains { $0.name == "Transcription confidence" })
        #expect(!report.failedChecks.contains { $0.name == "Caption coverage" })
    }

    @Test("Real device split mixed-language errors are stitched across segment boundaries")
    func realDeviceSplitErrorsAreStitchedAcrossSegments() {
        let segments = [
            TranscriptSegment(startTime: 22.56, endTime: 24.69, text: "da ürün çıkarabilsin fikirlerin en", confidence: 0.55, segmentType: .speech),
            TranscriptSegment(startTime: 24.69, endTime: 27.27, text: "MVP'ye çevir bil sinler App Store 'a", confidence: 0.38, segmentType: .speech),
            TranscriptSegment(startTime: 27.27, endTime: 29.97, text: "ya da web 'e gönderip kullanıcıya ulaş", confidence: 0.62, segmentType: .speech),
            TranscriptSegment(startTime: 29.97, endTime: 32.73, text: "abil sinler eğer sen de bu topluluğun", confidence: 0.60, segmentType: .speech),
        ]

        let transcription = TranscriptPostProcessor.corrected(
            TranscriptionResult(
                fullText: segments.map(\.text).joined(separator: " "),
                segments: segments,
                language: "tr",
                overallConfidence: 0.54
            )
        )

        #expect(transcription.segments[0].text == "da ürün çıkarabilsin fikirlerini")
        #expect(transcription.segments[1].text == "MVP'ye çevirebilsinler App Store'a")
        #expect(transcription.segments[2].text == "ya da web'e gönderip kullanıcıya")
        #expect(transcription.segments[3].text == "ulaşabilsinler eğer sen de bu topluluğun")
        #expect(transcription.overallConfidence >= 0.68)
    }

    @Test("Physical device split brand and CTA artifacts are stitched across segment boundaries")
    func physicalDeviceBrandAndCTASplitsAreCorrected() {
        var brandStart = TranscriptSegment(startTime: 16.38, endTime: 18.78, text: "tam da bu yüzden Türkiye'nin ilk BAP", confidence: 0.79, segmentType: .speech)
        brandStart.wordTimings = [
            (word: "tam", start: 16.38, duration: 0.2),
            (word: "da", start: 16.58, duration: 0.2),
            (word: "bu", start: 16.78, duration: 0.2),
            (word: "yüzden", start: 16.98, duration: 0.3),
            (word: "Türkiye'nin", start: 17.28, duration: 0.4),
            (word: "ilk", start: 17.68, duration: 0.2),
            (word: "BAP", start: 17.88, duration: 0.3),
        ]
        var brandContinuation = TranscriptSegment(startTime: 18.78, endTime: 22.05, text: "Holding topluluğu Vibe Coding Turkey kurdum kod bilmeyen", confidence: 0.72, segmentType: .speech)
        brandContinuation.wordTimings = [
            (word: "Holding", start: 18.78, duration: 0.35),
            (word: "topluluğu", start: 19.13, duration: 0.35),
            (word: "Vibe", start: 19.48, duration: 0.25),
            (word: "Coding", start: 19.73, duration: 0.25),
            (word: "Turkey", start: 19.98, duration: 0.25),
            (word: "kurdum", start: 20.23, duration: 0.25),
            (word: "kod", start: 20.48, duration: 0.2),
            (word: "bilmeyen", start: 20.68, duration: 0.35),
        ]
        let segments = [
            brandStart,
            brandContinuation,
            TranscriptSegment(startTime: 32.31, endTime: 35.1, text: "topluluğun bir parçası olmak istersen yorumlara vay", confidence: 0.94, segmentType: .speech),
            TranscriptSegment(startTime: 35.1, endTime: 36.51, text: "biraz birlikte büyüyelim", confidence: 0.95, segmentType: .speech),
        ]

        let transcription = TranscriptPostProcessor.corrected(
            TranscriptionResult(
                fullText: segments.map(\.text).joined(separator: " "),
                segments: segments,
                language: "tr",
                overallConfidence: 0.85
            )
        )

        #expect(transcription.segments[0].text == "tam da bu yüzden Türkiye'nin ilk")
        #expect(transcription.segments[1].text == "Vibe Coding topluluğu Vibe Coding Turkey kurdum kod bilmeyen")
        #expect(Array(transcription.segments[1].wordTimings.map(\.word).prefix(3)) == ["Vibe", "Coding", "topluluğu"])
        #expect(transcription.segments[2].text == "topluluğun bir parçası olmak istersen yorumlara Vibe yazıp")
        #expect(transcription.segments[3].text == "birlikte büyüyelim")
        #expect(!transcription.fullText.localizedStandardContains("BAP"))
        #expect(!transcription.fullText.localizedStandardContains("yorumlara vay"))
    }

    @Test("Current physical device single-segment brand and CTA artifacts are corrected")
    func currentPhysicalDeviceSingleSegmentArtifactsAreCorrected() {
        var brand = TranscriptSegment(
            startTime: 18.78,
            endTime: 21.69,
            text: "Vibe Coding topluluğu by Holding turkey kurdum cod",
            confidence: 0.72,
            segmentType: .speech
        )
        brand.wordTimings = [
            (word: "Vibe", start: 18.78, duration: 0.25),
            (word: "Coding", start: 19.03, duration: 0.25),
            (word: "topluluğu", start: 19.28, duration: 0.35),
            (word: "by", start: 19.63, duration: 0.2),
            (word: "Holding", start: 19.83, duration: 0.35),
            (word: "turkey", start: 20.18, duration: 0.25),
            (word: "kurdum", start: 20.43, duration: 0.3),
            (word: "cod", start: 20.73, duration: 0.2),
        ]
        var cta = TranscriptSegment(
            startTime: 34.89,
            endTime: 36.51,
            text: "vay biraz birlikte büyüyelim",
            confidence: 0.92,
            segmentType: .speech
        )
        cta.wordTimings = [
            (word: "vay", start: 34.89, duration: 0.25),
            (word: "biraz", start: 35.14, duration: 0.3),
            (word: "birlikte", start: 35.44, duration: 0.4),
            (word: "büyüyelim", start: 35.84, duration: 0.45),
        ]

        let transcription = TranscriptPostProcessor.corrected(
            TranscriptionResult(
                fullText: [brand.text, cta.text].joined(separator: " "),
                segments: [brand, cta],
                language: "tr",
                overallConfidence: 0.82
            )
        )

        #expect(transcription.segments[0].text == "Vibe Coding topluluğu Vibe Coding Turkey kurdum kod")
        #expect(transcription.segments[0].wordTimings.map(\.word) == ["Vibe", "Coding", "topluluğu", "Vibe", "Coding", "Turkey", "kurdum", "kod"])
        #expect(transcription.segments[1].text == "Vibe yazıp birlikte büyüyelim")
        #expect(!transcription.fullText.localizedStandardContains("by Holding"))
        #expect(!transcription.fullText.split(whereSeparator: \.isWhitespace).contains("cod"))
        #expect(!transcription.fullText.localizedStandardContains("vay biraz"))
    }

    @Test("Current physical device CTA continuation is stitched")
    func currentPhysicalDeviceCTAContinuationIsStitched() {
        let previous = TranscriptSegment(
            startTime: 32.16,
            endTime: 34.89,
            text: "bu topluluğun bir parçası olmak istersen yorumlara",
            confidence: 0.88,
            segmentType: .speech
        )
        let current = TranscriptSegment(
            startTime: 34.89,
            endTime: 36.51,
            text: "vay biraz birlikte büyüyelim",
            confidence: 0.92,
            segmentType: .speech
        )

        let transcription = TranscriptPostProcessor.corrected(
            TranscriptionResult(
                fullText: [previous.text, current.text].joined(separator: " "),
                segments: [previous, current],
                language: "tr",
                overallConfidence: 0.90
            )
        )

        #expect(transcription.segments[0].text == "bu topluluğun bir parçası olmak istersen yorumlara Vibe yazıp")
        #expect(transcription.segments[1].text == "birlikte büyüyelim")
        #expect(!transcription.fullText.localizedStandardContains("yorumlara vay"))
        #expect(!transcription.fullText.localizedStandardContains("vay biraz"))
    }

    @Test("Second physical device artifact set is normalized")
    func secondPhysicalDeviceArtifactSetIsNormalized() {
        let segments = [
            TranscriptSegment(startTime: 17.52, endTime: 20.22, text: "Türkiye'nin ilk Vibe Coding topluluğu vay Kolding", confidence: 0.72, segmentType: .speech),
            TranscriptSegment(startTime: 20.22, endTime: 22.89, text: "turkey kurdum kod bilmeyen insanlar da ürün", confidence: 0.70, segmentType: .speech),
            TranscriptSegment(startTime: 22.89, endTime: 26.31, text: "çıkarabilirsin fikirlerine MHP'ye çevirebilsinler web", confidence: 0.68, segmentType: .speech),
            TranscriptSegment(startTime: 26.31, endTime: 27.78, text: "ya da And roid 'de ya da", confidence: 0.64, segmentType: .speech),
            TranscriptSegment(startTime: 27.78, endTime: 30.66, text: "Apple Store 'da yayınlayabilir sin ler diye eğer", confidence: 0.71, segmentType: .speech),
            TranscriptSegment(startTime: 32.22, endTime: 35.19, text: "istersen yorumlara var biraz birlikte büyüyelim", confidence: 0.69, segmentType: .speech),
        ]

        let transcription = TranscriptPostProcessor.corrected(
            TranscriptionResult(
                fullText: segments.map(\.text).joined(separator: " "),
                segments: segments,
                language: "tr",
                overallConfidence: 0.80
            )
        )

        #expect(transcription.segments[0].text == "Türkiye'nin ilk Vibe Coding topluluğu Vibe Coding")
        #expect(transcription.segments[1].text == "Turkey kurdum kod bilmeyen insanlar da ürün")
        #expect(transcription.segments[2].text == "çıkarabilsin fikirlerini MVP'ye çevirebilsinler web")
        #expect(transcription.segments[3].text == "ya da Android'de ya da")
        #expect(transcription.segments[4].text == "Apple Store'da yayınlayabilsinler diye eğer")
        #expect(transcription.segments[5].text == "istersen yorumlara Vibe yazıp birlikte büyüyelim")
        #expect(!transcription.fullText.localizedStandardContains("Kolding"))
        #expect(!transcription.fullText.localizedStandardContains("MHP"))
        #expect(!transcription.fullText.localizedStandardContains("And roid"))
        #expect(!transcription.fullText.localizedStandardContains("var biraz"))
    }

    @Test("Latest physical device quality failure is normalized before export gate")
    func latestPhysicalDeviceQualityFailureIsNormalizedBeforeExportGate() {
        let rawSegments = [
            timedSegment(start: 0.99, end: 3.99, text: "Türkiye'de çok fazla insanın harika fikirleri var", confidence: 0.9526),
            timedSegment(start: 4.32, end: 6.24, text: "ama daha kod yaza madığı için en", confidence: 0.859),
            timedSegment(start: 6.24, end: 9.9, text: "baştan vazgeçiyor artık bir uygulama yapmak için", confidence: 0.9296),
            timedSegment(start: 9.96, end: 13.26, text: "yıllarca yazılımcı olman gerekmiyor doğru fikri doğru", confidence: 0.949),
            timedSegment(start: 13.26, end: 16.44, text: "şekilde e'ye anlatmayi öğrenmen gerek işte tam", confidence: 0.7494),
            timedSegment(start: 16.44, end: 18.69, text: "da bu yüzden Türkiye'nin ilk var Kolding", confidence: 0.6451),
            timedSegment(start: 18.69, end: 22.71, text: "topluluğu by Cording Turkey kurdum g bilmeyen insanlar", confidence: 0.68),
            timedSegment(start: 22.71, end: 25.14, text: "da ürün yapabilirsin MVP çıkarabilsin", confidence: 0.68),
            timedSegment(start: 25.14, end: 27.39, text: "App Store'a ve web'e yollayıp", confidence: 0.68),
            timedSegment(start: 27.39, end: 29.79, text: "gerçek insanlara ulaşabilsin diye sen", confidence: 0.8133),
            timedSegment(start: 29.79, end: 31.8, text: "de bu topluluğun bir parçası olmak istiyorsan", confidence: 0.829),
            timedSegment(start: 31.92, end: 36.72, text: "yorumları vip yaz birlikte büyüyelim gene olmadı", confidence: 0.6447),
            timedSegment(start: 36.72, end: 37.71, text: "ama izleyebiliriz yani", confidence: 0.961),
        ]
        let transcription = TranscriptPostProcessor.corrected(
            TranscriptionResult(
                fullText: rawSegments.map(\.text).joined(separator: " "),
                segments: rawSegments,
                language: "tr",
                overallConfidence: 0.7979
            )
        )

        #expect(transcription.segments[1].text == "ama daha kod yazamadığı için")
        #expect(transcription.segments[4].text == "şekilde yapay zekayı anlatmayı öğrenmen gerek işte tam")
        #expect(transcription.segments[5].text == "da bu yüzden Türkiye'nin ilk Vibe Coding")
        #expect(transcription.segments[6].text == "topluluğu Vibe Coding Turkey kurdum kod bilmeyen insanlar")
        #expect(transcription.segments[7].text == "da ürün çıkarabilsin fikirlerini MVP'ye çevirebilsinler")
        #expect(transcription.segments[11].text == "yorumlara Vibe yazıp birlikte büyüyelim")
        #expect(!transcription.fullText.localizedStandardContains("Kolding"))
        #expect(!transcription.fullText.localizedStandardContains("Cording"))
        #expect(!transcription.fullText.localizedStandardContains("g bilmeyen"))
        #expect(!transcription.fullText.localizedStandardContains("gene olmadı"))

        let audio = AudioAnalysisResult(
            segments: [
                AudioSegment(startTime: 0, endTime: 37.9, type: .speech, energy: 0.5)
            ],
            silenceIntervals: [
                7.2...7.85,
                15.3...15.65,
                20.6...21.3,
                33.65...34.7,
                35.15...36.0,
            ],
            averageEnergy: 0.3,
            peakEnergy: 0.8,
            duration: 37.9
        )
        let roughCut = RoughCutDecisionEngine.generateDecisions(
            transcription: transcription,
            audioAnalysis: audio
        )
        let captions = CaptionEngine.generateCaptions(
            from: transcription,
            roughCut: roughCut,
            template: .techInfluencer
        )
        let editPlan = EditDecisionEngine.generateEditPlan(
            captions: captions,
            roughCut: roughCut,
            template: .techInfluencer
        )
        let audioQuality = AudioQualityGuard.QualityReport(
            peakDB: -15.9,
            averageDB: -33.4,
            isClipping: false,
            isTooQuiet: true,
            dynamicRange: 17.5,
            passed: false
        )
        let report = QualityGateService.evaluate(
            captions: captions,
            editPlan: editPlan,
            roughCut: roughCut,
            template: .techInfluencer,
            transcription: transcription,
            audioQuality: audioQuality
        )
        let failedNames = Set(report.failedChecks.map(\.name))

        #expect(roughCut.cutSegments.contains { $0.linkedTranscriptText == "ama izleyebiliriz yani" && !$0.requiresReview })
        #expect(!failedNames.contains("Caption timing artifact cleanup"))
        #expect(!failedNames.contains("Transcript artifact cleanup"))
        #expect(!failedNames.contains("Cut trust"))
        #expect(failedNames.contains("Audio quality"))
        #expect(
            report.passed == false,
            "failed=\(report.failedChecks.map { "\($0.name): \($0.detail)" }) score=\(report.score)"
        )
    }

    @Test("Simulator ASR split variants are corrected before captioning")
    func simulatorASRSplitVariantsAreCorrected() {
        let segments = [
            TranscriptSegment(startTime: 19.11, endTime: 22.65, text: "topluluğu Bolding turkey kurdum kod bilmeyen insanlar da", confidence: 0.55, segmentType: .speech),
            TranscriptSegment(startTime: 22.65, endTime: 24.99, text: "ürün çıkarabilsin fikirlerin en VP", confidence: 0.42, segmentType: .speech),
            TranscriptSegment(startTime: 24.99, endTime: 27.42, text: "'ye çevirebilsinler App Store'a ya", confidence: 0.58, segmentType: .speech),
            TranscriptSegment(startTime: 27.42, endTime: 30.18, text: "da web'e gönderip kullanıcıya ulaş abil", confidence: 0.60, segmentType: .speech),
            TranscriptSegment(startTime: 30.18, endTime: 32.82, text: "sinler eğer sen de bu topluluğun bir", confidence: 0.61, segmentType: .speech),
        ]

        let transcription = TranscriptPostProcessor.corrected(
            TranscriptionResult(
                fullText: segments.map(\.text).joined(separator: " "),
                segments: segments,
                language: "tr",
                overallConfidence: 0.55
            )
        )

        #expect(transcription.segments[0].text == "topluluğu Vibe Coding Turkey kurdum kod bilmeyen insanlar da")
        #expect(transcription.segments[1].text == "ürün çıkarabilsin fikirlerini")
        #expect(transcription.segments[2].text == "MVP'ye çevirebilsinler App Store'a")
        #expect(transcription.segments[3].text == "ya da web'e gönderip kullanıcıya")
        #expect(transcription.segments[4].text == "ulaşabilsinler eğer sen de bu topluluğun bir")
        #expect(transcription.overallConfidence >= 0.68)
    }

    @Test("Latest simulator ASR tech variant is normalized")
    func latestSimulatorASRTechVariantIsNormalized() {
        let segments = [
            timedSegment(start: 0.92, end: 3.97, text: "Türkiye'de çok fazla insanın harika fikirleri var", confidence: 0.784),
            timedSegment(start: 4.24, end: 6.72, text: "ama çoğu kod yazmayı bilmediği için hayata", confidence: 0.784),
            timedSegment(start: 6.72, end: 9.55, text: "geçire miyor ben buna ayar oluyorum artık", confidence: 0.784),
            timedSegment(start: 9.55, end: 12.12, text: "uygulama yapmak için yıllarca yazılımcı olman gerekmiyor", confidence: 0.784),
            timedSegment(start: 12.38, end: 15.16, text: "doğru fikri doğru şekilde yapay zekaya anlatman", confidence: 0.735),
            timedSegment(start: 15.16, end: 17.98, text: "gerekiyor işte tam da bu yüzden Türkiye'nin", confidence: 0.774),
            timedSegment(start: 18.04, end: 20.60, text: "ilk Vibe Coding toplu vay Coding Turkey", confidence: 0.784),
            timedSegment(start: 20.60, end: 25.46, text: "kurdun koy duymayan insanlar dövün çıkarabilsin fikirlerine VPN çevire", confidence: 0.68),
            timedSegment(start: 25.46, end: 27.80, text: "bilsinler app Store ya da web e", confidence: 0.486),
            timedSegment(start: 27.80, end: 32.14, text: "gönderip kullanıcıya ulaşabilsin ler eğer sen de", confidence: 0.734),
            timedSegment(start: 32.18, end: 34.88, text: "bu topluluğun bir parçası olmak istersen yorumları", confidence: 0.698),
            timedSegment(start: 34.88, end: 36.54, text: "Vibe yazıp birlikte büyüyelim", confidence: 0.72),
        ]

        let transcription = TranscriptPostProcessor.corrected(
            TranscriptionResult(
                fullText: segments.map(\.text).joined(separator: " "),
                segments: segments,
                language: "tr",
                overallConfidence: 0.729
            )
        )

        #expect(transcription.segments[2].text == "geçiremiyor ben buna ayar oluyorum artık")
        #expect(transcription.segments[4].text == "doğru fikri doğru şekilde yapay zekaya anlatman")
        #expect(transcription.segments[6].text == "ilk Vibe Coding topluluğu Vibe Coding Turkey")
        #expect(transcription.segments[7].text == "kurdum kod bilmeyen insanlar da ürün çıkarabilsin fikirlerini MVP'ye çevirebilsinler")
        #expect(transcription.segments[8].text == "App Store'a ya da web'e")
        #expect(transcription.segments[9].text == "gönderip kullanıcıya ulaşabilsinler eğer sen de")
        #expect(transcription.segments[10].text == "bu topluluğun bir parçası olmak istersen yorumlara Vibe yazıp")
        #expect(transcription.segments[11].text == "birlikte büyüyelim")
        #expect(!transcription.fullText.localizedStandardContains("toplu vay"))
        #expect(!transcription.fullText.localizedStandardContains("kurdun koy"))
        #expect(!transcription.fullText.localizedStandardContains("VPN çevire"))
        #expect(!transcription.fullText.localizedStandardContains("web e"))
        #expect(!transcription.fullText.localizedStandardContains("ulaşabilsin ler"))
        #expect(!transcription.fullText.localizedStandardContains("yorumları"))
    }

    @Test("Valid mixed Turkish English phrasing is preserved by transcript corrections")
    func validMixedTurkishEnglishPhrasingIsPreserved() {
        let segment = timedSegment(
            start: 0,
            end: 5,
            text: "Bu AI tool ile fikrini MVP'ye çevirebilirsin ve App Store'a çıkarabilirsin",
            confidence: 0.91
        )
        let aiDirection = timedSegment(
            start: 5.2,
            end: 8.1,
            text: "doğru fikri yapay zekaya anlatman gerekiyor",
            confidence: 0.89
        )

        let transcription = TranscriptPostProcessor.corrected(
            TranscriptionResult(
                fullText: [segment.text, aiDirection.text].joined(separator: " "),
                segments: [segment, aiDirection],
                language: "tr",
                overallConfidence: 0.90
            )
        )

        #expect(transcription.segments[0].text == segment.text)
        #expect(transcription.segments[1].text == aiDirection.text)
        #expect(transcription.fullText.localizedStandardContains("çıkarabilirsin"))
        #expect(transcription.fullText.localizedStandardContains("yapay zekaya anlatman"))
    }

    @Test("Latest simulator ASR captions avoid sub-half-second fragments")
    func latestSimulatorASRCaptionsAvoidSubHalfSecondFragments() {
        let segments = [
            timedSegment(start: 0.92, end: 3.97, text: "Türkiye'de çok fazla insanın harika fikirleri var", confidence: 0.784),
            timedSegment(start: 4.24, end: 6.72, text: "ama çoğu kod yazmayı bilmediği için hayata", confidence: 0.784),
            timedSegment(start: 6.72, end: 9.55, text: "geçire miyor ben buna ayar oluyorum artık", confidence: 0.784),
            timedSegment(start: 9.55, end: 12.12, text: "uygulama yapmak için yıllarca yazılımcı olman gerekmiyor", confidence: 0.784),
            timedSegment(start: 12.38, end: 15.16, text: "doğru fikri doğru şekilde yapay zekaya anlatman", confidence: 0.735),
            timedSegment(start: 15.16, end: 17.98, text: "gerekiyor işte tam da bu yüzden Türkiye'nin", confidence: 0.774),
            timedSegment(start: 18.04, end: 20.60, text: "ilk Vibe Coding toplu vay Coding Turkey", confidence: 0.784),
            timedSegment(start: 20.60, end: 25.46, text: "kurdun koy duymayan insanlar dövün çıkarabilsin fikirlerine VPN çevire", confidence: 0.68),
            timedSegment(start: 25.46, end: 27.80, text: "bilsinler app Store ya da web e", confidence: 0.486),
            timedSegment(start: 27.80, end: 32.14, text: "gönderip kullanıcıya ulaşabilsin ler eğer sen de", confidence: 0.734),
            timedSegment(start: 32.18, end: 34.88, text: "bu topluluğun bir parçası olmak istersen yorumları", confidence: 0.698),
            timedSegment(start: 34.88, end: 36.54, text: "Vibe yazıp birlikte büyüyelim", confidence: 0.72),
        ]
        let transcription = TranscriptPostProcessor.corrected(
            TranscriptionResult(
                fullText: segments.map(\.text).joined(separator: " "),
                segments: segments,
                language: "tr",
                overallConfidence: 0.729
            )
        )
        let roughCut = RoughCutResult(
            decisions: [
                RoughCutDecision(startTime: 0, endTime: 0.82, action: .cut, reason: "Tech pacing dead air/inter-idea gap", confidence: 0.88, linkedTranscriptText: nil, requiresReview: false),
                RoughCutDecision(startTime: 0.82, endTime: 36.66, action: .keep, reason: "Tech semantic keep - cta,hook,keyword,reveal,warning", confidence: 0.729, linkedTranscriptText: nil, requiresReview: false),
                RoughCutDecision(startTime: 36.66, endTime: 37.38, action: .cut, reason: "Tech pacing dead air/inter-idea gap", confidence: 0.88, linkedTranscriptText: nil, requiresReview: false),
            ],
            originalDuration: 37.38,
            cleanDuration: 35.84,
            keepSegments: [
                RoughCutDecision(startTime: 0.82, endTime: 36.66, action: .keep, reason: "Tech semantic keep - cta,hook,keyword,reveal,warning", confidence: 0.729, linkedTranscriptText: nil, requiresReview: false)
            ],
            cutSegments: [
                RoughCutDecision(startTime: 0, endTime: 0.82, action: .cut, reason: "Tech pacing dead air/inter-idea gap", confidence: 0.88, linkedTranscriptText: nil, requiresReview: false),
                RoughCutDecision(startTime: 36.66, endTime: 37.38, action: .cut, reason: "Tech pacing dead air/inter-idea gap", confidence: 0.88, linkedTranscriptText: nil, requiresReview: false),
            ],
            reviewSegments: []
        )

        let captions = CaptionEngine.generateCaptions(
            from: transcription,
            roughCut: roughCut,
            template: .techInfluencer
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
            template: .techInfluencer,
            transcription: transcription
        )
        let failedNames = Set(report.failedChecks.map(\.name))

        #expect(!captions.contains { $0.endTime - $0.startTime < 0.5 })
        #expect(!failedNames.contains("Caption timing"))
        #expect(!failedNames.contains("Transcript artifact cleanup"))
        #expect(!failedNames.contains("Caption timing artifact cleanup"))
    }

    @Test("Simulator ASR second-pass product artifact is normalized")
    func simulatorASRSecondPassProductArtifactIsNormalized() {
        let segment = timedSegment(
            start: 20.60,
            end: 25.46,
            text: "kurdum kod bilmeyen insanlar dövün çıkarabilsin fikirlerine VPN çevirebilsinler",
            confidence: 0.72
        )

        let transcription = TranscriptPostProcessor.corrected(
            TranscriptionResult(
                fullText: segment.text,
                segments: [segment],
                language: "tr",
                overallConfidence: 0.72
            )
        )

        #expect(transcription.segments[0].text == "kurdum kod bilmeyen insanlar ürün çıkarabilsin fikirlerini MVP'ye çevirebilsinler")
        #expect(!transcription.fullText.localizedStandardContains("dövün çıkarabilsin"))
        #expect(!transcription.fullText.localizedStandardContains("VPN çevire"))
    }

    @Test("Unresolved simulator product artifact is blocked by quality gate")
    func unresolvedSimulatorProductArtifactIsBlockedByQualityGate() {
        let segment = timedSegment(
            start: 20.60,
            end: 25.46,
            text: "kurdum kod bilmeyen insanlar dövün çıkarabilsin fikirlerine VPN çevirebilsinler",
            confidence: 0.72
        )
        let captions = [
            CaptionSegment(startTime: 0, endTime: 1, text: "Hook line", role: .hook, style: .hookImpact),
            CaptionSegment(startTime: segment.startTime, endTime: segment.endTime, text: segment.text, role: .regular, style: .focusStatement),
            CaptionSegment(startTime: 34, endTime: 36, text: "Vibe yazıp birlikte büyüyelim", role: .conclusion, style: .hookImpact),
        ]
        let roughCutDecision = RoughCutDecision(
            startTime: 0,
            endTime: 36,
            action: .keep,
            reason: "Content",
            confidence: 0.9,
            linkedTranscriptText: nil,
            requiresReview: false
        )
        let report = QualityGateService.evaluate(
            captions: captions,
            editPlan: EditPlan(decisions: [], template: .techInfluencer, totalEffects: 0, averageIntensity: 0),
            roughCut: RoughCutResult(
                decisions: [roughCutDecision],
                originalDuration: 36,
                cleanDuration: 36,
                keepSegments: [roughCutDecision],
                cutSegments: [],
                reviewSegments: []
            ),
            template: .techInfluencer,
            transcription: TranscriptionResult(
                fullText: segment.text,
                segments: [segment],
                language: "tr",
                overallConfidence: 0.72
            )
        )

        #expect(report.failedChecks.contains { $0.name == "Transcript artifact cleanup" && $0.blocksExport })
        #expect(!report.passed)
    }

    @Test("Latest simulator CTA case artifact is normalized")
    func latestSimulatorCTACaseArtifactIsNormalized() {
        let segment = timedSegment(
            start: 32.18,
            end: 36.54,
            text: "bu topluluğun bir parçası olmak istersen yorumları Vibe yazıp birlikte büyüyelim",
            confidence: 0.72
        )

        let transcription = TranscriptPostProcessor.corrected(
            TranscriptionResult(
                fullText: segment.text,
                segments: [segment],
                language: "tr",
                overallConfidence: 0.72
            )
        )

        #expect(transcription.segments[0].text == "bu topluluğun bir parçası olmak istersen yorumlara Vibe yazıp birlikte büyüyelim")
        #expect(!transcription.fullText.localizedStandardContains("yorumları Vibe yazıp"))
    }

    @Test("Caption display artifact is blocked even without word timings")
    func captionDisplayArtifactIsBlockedWithoutWordTimings() {
        let keep = RoughCutDecision(
            startTime: 0,
            endTime: 6,
            action: .keep,
            reason: "Content",
            confidence: 0.9,
            linkedTranscriptText: nil,
            requiresReview: false
        )
        let captions = [
            CaptionSegment(startTime: 0, endTime: 2, text: "Strong hook", role: .hook, style: .hookImpact),
            CaptionSegment(startTime: 2.1, endTime: 3.2, text: "parçası olmak istersen yorumları", role: .conclusion, style: .premiumLowerThird),
            CaptionSegment(startTime: 3.3, endTime: 5, text: "yorumları Vibe yazıp", role: .conclusion, style: .premiumLowerThird),
        ]

        let report = QualityGateService.evaluate(
            captions: captions,
            editPlan: EditPlan(decisions: [], template: .cleanExpert, totalEffects: 0, averageIntensity: 0),
            roughCut: RoughCutResult(
                decisions: [keep],
                originalDuration: 6,
                cleanDuration: 6,
                keepSegments: [keep],
                cutSegments: [],
                reviewSegments: []
            ),
            template: .cleanExpert
        )

        #expect(report.failedChecks.contains { $0.name == "Caption timing artifact cleanup" && $0.blocksExport })
        #expect(!report.passed)
    }

    @Test("Transcript corrections realign word timings with corrected text")
    func transcriptCorrectionsRealignWordTimings() {
        var segment = TranscriptSegment(
            startTime: 19.11,
            endTime: 22.65,
            text: "topluluğu Bolding turkey kurdum",
            confidence: 0.55,
            segmentType: .speech
        )
        segment.wordTimings = [
            (word: "topluluğu", start: 19.11, duration: 0.4),
            (word: "Bolding", start: 19.51, duration: 0.4),
            (word: "turkey", start: 19.91, duration: 0.4),
            (word: "kurdum", start: 20.31, duration: 0.4),
        ]

        let transcription = TranscriptPostProcessor.corrected(
            TranscriptionResult(
                fullText: segment.text,
                segments: [segment],
                language: "tr",
                overallConfidence: 0.55
            )
        )

        #expect(transcription.segments[0].text == "topluluğu Vibe Coding Turkey kurdum")
        #expect(transcription.segments[0].wordTimings.map(\.word) == ["topluluğu", "Vibe", "Coding", "Turkey", "kurdum"])
        #expect(!transcription.segments[0].wordTimings.map(\.word).contains("Bolding"))
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

    @Test("Audio analysis quality ignores silence bed for spoken loudness")
    func audioAnalysisQualityUsesAudibleWindows() {
        let segments = [
            AudioSegment(startTime: 0, endTime: 1, type: .silence, energy: 0.0005),
            AudioSegment(startTime: 1, endTime: 2, type: .speech, energy: 0.040),
            AudioSegment(startTime: 2, endTime: 3, type: .speech, energy: 0.035),
            AudioSegment(startTime: 3, endTime: 4, type: .silence, energy: 0.0006),
        ]
        let result = AudioAnalysisResult(
            segments: segments,
            silenceIntervals: [0.0...1.0, 3.0...4.0],
            averageEnergy: 0.020,
            peakEnergy: 0.12,
            duration: 4
        )

        let report = AudioQualityGuard.analyze(audioAnalysis: result)

        #expect(!report.isTooQuiet)
        #expect(report.passed)
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

// MARK: - Transcription Validation

@Suite("TranscriptionValidator")
struct TranscriptionValidatorTests {
    private func result(
        fullText: String,
        segments: [TranscriptSegment]
    ) -> TranscriptionResult {
        TranscriptionResult(
            fullText: fullText,
            segments: segments,
            language: "tr",
            overallConfidence: 0.9
        )
    }

    @Test("Empty transcript is rejected before rough cut")
    func emptyTranscriptRejected() {
        var didThrow = false
        do {
            _ = try TranscriptionValidator.validated(result(fullText: "", segments: []))
        } catch {
            didThrow = true
        }

        #expect(didThrow)
    }

    @Test("Only filler transcript is rejected")
    func fillerOnlyTranscriptRejected() {
        let segment = TranscriptSegment(
            startTime: 0,
            endTime: 0.5,
            text: "eee",
            confidence: 0.9,
            segmentType: .filler
        )

        var didThrow = false
        do {
            _ = try TranscriptionValidator.validated(result(fullText: "eee", segments: [segment]))
        } catch {
            didThrow = true
        }

        #expect(didThrow)
    }

    @Test("Speech transcript is accepted")
    func speechTranscriptAccepted() throws {
        let segment = TranscriptSegment(
            startTime: 0,
            endTime: 2,
            text: "Bugun iyi calisiyoruz",
            confidence: 0.9,
            segmentType: .speech
        )

        let validated = try TranscriptionValidator.validated(
            result(fullText: "Bugun iyi calisiyoruz", segments: [segment])
        )

        #expect(validated.segments.count == 1)
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
    @Test("MVP exposes only Tech Influencer")
    func mvpExposesOnlyTechInfluencer() {
        #expect(TemplateConfig.all.map(\.id) == ["tech_influencer"])
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
        #expect(Set(ids).count == ids.count)
    }

    @Test("Viral caption dim words remain readable over dark card")
    func viralCaptionDimWordsReadable() {
        let dim = TemplateConfig.viralCaption.captionTheme.karaokeDim

        #expect(dim.r >= 0.8)
        #expect(dim.g >= 0.8)
        #expect(dim.b >= 0.8)
        #expect(dim.a >= 0.8)
    }
}

@Suite("CaptionTextLayout")
struct CaptionTextLayoutTests {
    @Test("Word ranges preserve manual line breaks")
    func wordRangesPreserveManualLineBreaks() {
        let text = "ama çoğu kod yazmayı\nbilmediği için hayata geçemiyor"
        let words = CaptionTextLayout.words(in: text)
        let ranges = CaptionTextLayout.wordRanges(in: text)
        let reconstructed = ranges.map { (text as NSString).substring(with: $0) }

        #expect(words == reconstructed)
        #expect(text.contains("\n"))
        #expect(reconstructed.contains("bilmediği"))
    }

    @Test("Mismatched raw ASR timing tokens are not trusted")
    func mismatchedRawASRTimingTokensAreNotTrusted() {
        let words = CaptionTextLayout.words(in: "Vibe Coding Turkey kurdum")
        let timings = [
            (word: "BAP", start: 0.0, duration: 0.2),
            (word: "Holding", start: 0.2, duration: 0.2),
            (word: "Turkey", start: 0.4, duration: 0.2),
            (word: "kurdum", start: 0.6, duration: 0.2),
        ]

        #expect(!CaptionTextLayout.canUseWordTimings(displayWords: words, wordTimings: timings))
    }

    @Test("Matching corrected timing tokens are trusted")
    func matchingCorrectedTimingTokensAreTrusted() {
        let words = CaptionTextLayout.words(in: "MVP'ye çevirebilsinler App Store'a")
        let timings = [
            (word: "MVP'ye", start: 0.0, duration: 0.2),
            (word: "çevirebilsinler", start: 0.2, duration: 0.2),
            (word: "App", start: 0.4, duration: 0.2),
            (word: "Store'a", start: 0.6, duration: 0.2),
        ]

        #expect(CaptionTextLayout.canUseWordTimings(displayWords: words, wordTimings: timings))
    }
}

// MARK: - Confidence-Based Review

@Suite("ConfidenceBasedReview")
struct ConfidenceBasedReviewTests {
    private func makeSegment(
        text: String,
        type: TranscriptSegment.SegmentType,
        aiConfidence: Float?,
        aiReason: String? = nil,
        confidence: Float = 0.9
    ) -> TranscriptSegment {
        TranscriptSegment(
            startTime: 0, endTime: 1, text: text,
            confidence: confidence, segmentType: type,
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
        #expect(decision?.reason.contains("Review") == true)
    }

    @Test("High-confidence edit command is cut even when longer than one second")
    func highConfidenceEditCommandCut() {
        let seg = makeSegment(text: "olmadı baştan alıyorum", type: .editCommand, aiConfidence: 0.92, aiReason: "Speaker directs editor to restart")
        let transcript = TranscriptionResult(fullText: "olmadı baştan alıyorum", segments: [seg], language: "tr", overallConfidence: 0.9)
        let result = RoughCutDecisionEngine.generateDecisions(transcription: transcript, audioAnalysis: makeAudio())
        let decision = result.decisions.first { $0.linkedTranscriptText == "olmadı baştan alıyorum" }
        #expect(decision?.action == .cut)
        #expect(decision?.requiresReview == false)
    }

    @Test("High-confidence restart is hard cut")
    func highConfidenceRestartCut() {
        let first = TranscriptSegment(
            startTime: 0,
            endTime: 1.5,
            text: "bugün ben bu uygulama",
            confidence: 0.9,
            segmentType: .suspectedRestart,
            aiConfidence: 0.9,
            aiReason: "Incomplete start"
        )
        let second = TranscriptSegment(
            startTime: 1.6,
            endTime: 4,
            text: "bugün ben bu uygulama gerçekten faydalı diyorum",
            confidence: 0.9,
            segmentType: .contentSentence
        )
        let transcript = TranscriptionResult(
            fullText: "\(first.text) \(second.text)",
            segments: [first, second],
            language: "tr",
            overallConfidence: 0.9
        )
        let result = RoughCutDecisionEngine.generateDecisions(transcription: transcript, audioAnalysis: makeAudio())
        let decision = result.decisions.first { $0.linkedTranscriptText == first.text }
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

    @Test("Low transcript confidence cannot produce destructive edit command cut")
    func lowTranscriptConfidenceCommandReview() {
        let seg = makeSegment(
            text: "insanlar da ürün çıkar abil sin fikirlerin",
            type: .editCommand,
            aiConfidence: 0.98,
            aiReason: "Speaker explicitly instructs editor to cut",
            confidence: 0.53
        )
        let transcript = TranscriptionResult(fullText: seg.text, segments: [seg], language: "tr", overallConfidence: 0.53)
        let result = RoughCutDecisionEngine.generateDecisions(transcription: transcript, audioAnalysis: makeAudio())
        let decision = result.decisions.first { $0.linkedTranscriptText == seg.text }
        #expect(decision?.action == .reviewRequired)
        #expect(decision?.isTimelineIncluded == true)
        #expect(decision?.requiresReview == true)
    }

    @Test("Low transcript confidence cannot produce destructive duplicate cut")
    func lowTranscriptConfidenceDuplicateReview() {
        let seg = makeSegment(
            text: "'a ya da web 'e gönderip kullanıcıya",
            type: .suspectedDuplicate,
            aiConfidence: 0.97,
            aiReason: "Near-identical repetition",
            confidence: 0.52
        )
        let transcript = TranscriptionResult(fullText: seg.text, segments: [seg], language: "tr", overallConfidence: 0.52)
        let result = RoughCutDecisionEngine.generateDecisions(transcription: transcript, audioAnalysis: makeAudio())
        let decision = result.decisions.first { $0.linkedTranscriptText == seg.text }
        #expect(decision?.action == .reviewRequired)
        #expect(decision?.isTimelineIncluded == true)
    }

    @Test("Raw low transcript confidence keeps content but requires review")
    func rawLowTranscriptConfidenceContentReview() {
        var seg = makeSegment(
            text: "MVP'ye çevirebilsinler App Store'a gönderebilsinler",
            type: .contentSentence,
            aiConfidence: nil,
            confidence: 0.86
        )
        seg.rawConfidence = 0.44
        let transcript = TranscriptionResult(fullText: seg.text, segments: [seg], language: "tr", overallConfidence: 0.86, rawOverallConfidence: 0.44)

        let result = RoughCutDecisionEngine.generateDecisions(transcription: transcript, audioAnalysis: makeAudio())
        let decision = result.decisions.first { $0.linkedTranscriptText == seg.text }

        #expect(decision?.action == .keep)
        #expect(decision?.requiresReview == true)
        #expect(decision?.confidence == 0.44)
    }

    @Test("Tech rough cut protects continuation gap inside one sentence")
    func techRoughCutProtectsSentenceContinuationGap() {
        let first = TranscriptSegment(
            startTime: 0,
            endTime: 1.5,
            text: "This AI tool can build apps",
            confidence: 0.94,
            segmentType: .contentSentence
        )
        let second = TranscriptSegment(
            startTime: 2.1,
            endTime: 4.0,
            text: "and deploy them to users",
            confidence: 0.93,
            segmentType: .contentSentence
        )
        let transcript = TranscriptionResult(
            fullText: "\(first.text) \(second.text)",
            segments: [first, second],
            language: "en",
            overallConfidence: 0.94
        )
        let audio = AudioAnalysisResult(
            segments: [],
            silenceIntervals: [1.5...2.1],
            averageEnergy: 0.2,
            peakEnergy: 0.8,
            duration: 5
        )

        let result = RoughCutDecisionEngine.generateTechInfluencerDecisions(
            transcription: transcript,
            audioAnalysis: audio
        )
        let cutsInContinuationGap = result.cutSegments.filter {
            $0.startTime < 2.1 && $0.endTime > 1.5
        }

        #expect(cutsInContinuationGap.isEmpty)
        #expect(result.keepSegments.contains { $0.startTime <= 0.01 && $0.endTime >= 4.0 })
    }

    @Test("Tech rough cut can remove hard-boundary dead air")
    func techRoughCutCutsHardBoundaryDeadAir() {
        let first = TranscriptSegment(
            startTime: 0,
            endTime: 1.5,
            text: "This AI tool can build apps.",
            confidence: 0.94,
            segmentType: .contentSentence
        )
        let second = TranscriptSegment(
            startTime: 2.1,
            endTime: 4.0,
            text: "Now open the dashboard",
            confidence: 0.93,
            segmentType: .contentSentence
        )
        let transcript = TranscriptionResult(
            fullText: "\(first.text) \(second.text)",
            segments: [first, second],
            language: "en",
            overallConfidence: 0.94
        )
        let audio = AudioAnalysisResult(
            segments: [],
            silenceIntervals: [1.5...2.1],
            averageEnergy: 0.2,
            peakEnergy: 0.8,
            duration: 5
        )

        let result = RoughCutDecisionEngine.generateTechInfluencerDecisions(
            transcription: transcript,
            audioAnalysis: audio
        )
        let cutsInBoundaryGap = result.cutSegments.filter {
            $0.startTime < 2.1 && $0.endTime > 1.5
        }

        #expect(!cutsInBoundaryGap.isEmpty)
    }

    @Test("Duplicate label without adjacent lexical evidence stays in timeline")
    func duplicateWithoutEvidenceReview() {
        let segments = [
            TranscriptSegment(
                startTime: 0,
                endTime: 2,
                text: "ama çoğu kod yazmayı bilmediği için hayata geçemiyor",
                confidence: 0.86,
                segmentType: .contentSentence
            ),
            TranscriptSegment(
                startTime: 2,
                endTime: 4,
                text: "ben buna ayar oluyorum artık uygulama yapmak",
                confidence: 0.91,
                segmentType: .suspectedDuplicate,
                aiConfidence: 0.96,
                aiReason: "Near-identical repetition of previous content"
            ),
            TranscriptSegment(
                startTime: 4,
                endTime: 6,
                text: "için yıllarca yazılımcı olman gerekmiyor doğru fikri",
                confidence: 0.90,
                segmentType: .contentSentence
            ),
        ]
        let transcript = TranscriptionResult(
            fullText: segments.map(\.text).joined(separator: " "),
            segments: segments,
            language: "tr",
            overallConfidence: 0.89
        )
        let result = RoughCutDecisionEngine.generateDecisions(transcription: transcript, audioAnalysis: makeAudio())
        let decision = result.decisions.first { $0.linkedTranscriptText == segments[1].text }
        #expect(decision?.action == .reviewRequired)
        #expect(decision?.isTimelineIncluded == true)
    }

    @Test("Restart label without adjacent prefix evidence stays in timeline")
    func restartWithoutEvidenceReview() {
        let segments = [
            TranscriptSegment(
                startTime: 0,
                endTime: 2,
                text: "doğru şekilde yapay zeka anlatman gerekiyor",
                confidence: 0.91,
                segmentType: .suspectedRestart,
                aiConfidence: 0.95,
                aiReason: "False start repeated better next"
            ),
            TranscriptSegment(
                startTime: 2,
                endTime: 4,
                text: "işte tam da bu yüzden Türkiye'nin ilk topluluğunu kurdum",
                confidence: 0.88,
                segmentType: .contentSentence
            ),
        ]
        let transcript = TranscriptionResult(
            fullText: segments.map(\.text).joined(separator: " "),
            segments: segments,
            language: "tr",
            overallConfidence: 0.9
        )
        let result = RoughCutDecisionEngine.generateDecisions(transcription: transcript, audioAnalysis: makeAudio())
        let decision = result.decisions.first { $0.linkedTranscriptText == segments[0].text }
        #expect(decision?.action == .reviewRequired)
        #expect(decision?.isTimelineIncluded == true)
    }
}

@Suite("QualityGateCoverage")
struct QualityGateCoverageTests {
    private func segment(_ text: String, start: Double, end: Double, confidence: Float) -> TranscriptSegment {
        TranscriptSegment(
            startTime: start,
            endTime: end,
            text: text,
            confidence: confidence,
            segmentType: .contentSentence
        )
    }

    @Test("Caption coverage below threshold fails quality")
    func captionCoverageBelowThresholdFails() {
        let segments = [
            segment("first clear sentence", start: 0, end: 3, confidence: 0.95),
            segment("mixed language broken terms", start: 3, end: 8, confidence: 0.55),
            segment("final clear sentence", start: 8, end: 10, confidence: 0.95),
        ]
        let transcription = TranscriptionResult(
            fullText: segments.map(\.text).joined(separator: " "),
            segments: segments,
            language: "tr",
            overallConfidence: 0.82
        )
        let decisions = segments.map {
            RoughCutDecision(
                startTime: $0.startTime,
                endTime: $0.endTime,
                action: .keep,
                reason: "Content",
                confidence: $0.confidence,
                linkedTranscriptText: $0.text,
                requiresReview: false
            )
        }
        let roughCut = RoughCutResult(
            decisions: decisions,
            originalDuration: 10,
            cleanDuration: 10,
            keepSegments: decisions,
            cutSegments: [],
            reviewSegments: []
        )
        let captions = [
            CaptionSegment(startTime: 0, endTime: 3, text: "first clear sentence", role: .hook, style: .premiumLowerThird),
            CaptionSegment(startTime: 8, endTime: 10, text: "final clear sentence", role: .conclusion, style: .premiumLowerThird),
        ]
        let editPlan = EditPlan(decisions: [], template: .premiumFounder, totalEffects: 0, averageIntensity: 0)

        let report = QualityGateService.evaluate(
            captions: captions,
            editPlan: editPlan,
            roughCut: roughCut,
            template: .premiumFounder,
            transcription: transcription
        )

        let coverage = report.checks.first { $0.name == "Caption coverage" }
        #expect(coverage?.passed == false)
        #expect(report.passed == false)
    }

    @Test("Caption coverage uses actual overlap duration, not whole segment")
    func captionCoverageUsesActualOverlapDuration() {
        let transcriptSegment = segment("long speech with barely captioned start", start: 0, end: 10, confidence: 0.95)
        let transcription = TranscriptionResult(
            fullText: transcriptSegment.text,
            segments: [transcriptSegment],
            language: "en",
            overallConfidence: 0.95
        )
        let decision = RoughCutDecision(
            startTime: 0,
            endTime: 10,
            action: .keep,
            reason: "Content",
            confidence: 0.95,
            linkedTranscriptText: transcriptSegment.text,
            requiresReview: false
        )
        let roughCut = RoughCutResult(
            decisions: [decision],
            originalDuration: 10,
            cleanDuration: 10,
            keepSegments: [decision],
            cutSegments: [],
            reviewSegments: []
        )
        let captions = [
            CaptionSegment(startTime: 0, endTime: 0.2, text: "long speech", role: .hook, style: .premiumLowerThird)
        ]
        let editPlan = EditPlan(decisions: [], template: .premiumFounder, totalEffects: 0, averageIntensity: 0)

        let report = QualityGateService.evaluate(
            captions: captions,
            editPlan: editPlan,
            roughCut: roughCut,
            template: .premiumFounder,
            transcription: transcription
        )

        let coverage = report.checks.first { $0.name == "Caption coverage" }
        #expect(coverage?.passed == false)
        #expect(coverage?.blocksExport == true)
        #expect(report.passed == false)
    }

    @Test("Low-confidence silence trim does not fail cut trust")
    func lowConfidenceSilenceTrimDoesNotFailCutTrust() {
        let transcriptSegment = segment("mixed language product explanation continues after pause", start: 0, end: 8, confidence: 0.68)
        let transcription = TranscriptionResult(
            fullText: transcriptSegment.text,
            segments: [transcriptSegment],
            language: "tr",
            overallConfidence: 0.82
        )
        let keepStart = RoughCutDecision(
            startTime: 0,
            endTime: 4.5,
            action: .keep,
            reason: "Content",
            confidence: 0.9,
            linkedTranscriptText: "mixed language product explanation",
            requiresReview: false
        )
        let silenceCut = RoughCutDecision(
            startTime: 4.5,
            endTime: 5.0,
            action: .cut,
            reason: "Long silence (0.5s)",
            confidence: 0.85,
            linkedTranscriptText: nil,
            requiresReview: false
        )
        let keepEnd = RoughCutDecision(
            startTime: 5.0,
            endTime: 8.0,
            action: .keep,
            reason: "Content",
            confidence: 0.9,
            linkedTranscriptText: "continues after pause",
            requiresReview: false
        )
        let roughCut = RoughCutResult(
            decisions: [keepStart, silenceCut, keepEnd],
            originalDuration: 8,
            cleanDuration: 7.5,
            keepSegments: [keepStart, keepEnd],
            cutSegments: [silenceCut],
            reviewSegments: []
        )
        let captions = [
            CaptionSegment(startTime: 0, endTime: 2, text: "mixed language", role: .hook, style: .premiumLowerThird),
            CaptionSegment(startTime: 2, endTime: 6, text: "product explanation continues", role: .regular, style: .premiumLowerThird),
            CaptionSegment(startTime: 6, endTime: 8, text: "after pause", role: .conclusion, style: .premiumLowerThird),
        ]
        let editPlan = EditPlan(decisions: [], template: .premiumFounder, totalEffects: 0, averageIntensity: 0)

        let report = QualityGateService.evaluate(
            captions: captions,
            editPlan: editPlan,
            roughCut: roughCut,
            template: .premiumFounder,
            transcription: transcription
        )

        let cutTrust = report.checks.first { $0.name == "Cut trust" }
        #expect(cutTrust?.passed == true)
        #expect(report.passed == true)
    }

    @Test("Multiple silence trims inside low-confidence speech do not fail cut trust")
    func multipleSilenceTrimsInsideLowConfidenceSpeechDoNotFailCutTrust() {
        let transcriptSegment = segment("yorumlara vibe yazıp birlikte büyüyelim", start: 31.92, end: 36.72, confidence: 0.68)
        let transcription = TranscriptionResult(
            fullText: transcriptSegment.text,
            segments: [transcriptSegment],
            language: "tr",
            overallConfidence: 0.82
        )
        let keepStart = RoughCutDecision(
            startTime: 31.92,
            endTime: 33.65,
            action: .keep,
            reason: "Content",
            confidence: 0.9,
            linkedTranscriptText: "yorumlara vibe yazıp",
            requiresReview: false
        )
        let firstSilenceCut = RoughCutDecision(
            startTime: 33.65,
            endTime: 34.7,
            action: .cut,
            reason: "Long silence (1.1s)",
            confidence: 0.85,
            linkedTranscriptText: nil,
            requiresReview: false
        )
        let keepMiddle = RoughCutDecision(
            startTime: 34.7,
            endTime: 35.15,
            action: .keep,
            reason: "Content",
            confidence: 0.9,
            linkedTranscriptText: "birlikte",
            requiresReview: false
        )
        let secondSilenceCut = RoughCutDecision(
            startTime: 35.15,
            endTime: 36.0,
            action: .cut,
            reason: "Long silence (0.9s)",
            confidence: 0.85,
            linkedTranscriptText: nil,
            requiresReview: false
        )
        let keepEnd = RoughCutDecision(
            startTime: 36.0,
            endTime: 36.72,
            action: .keep,
            reason: "Content",
            confidence: 0.9,
            linkedTranscriptText: "büyüyelim",
            requiresReview: false
        )
        let roughCut = RoughCutResult(
            decisions: [keepStart, firstSilenceCut, keepMiddle, secondSilenceCut, keepEnd],
            originalDuration: 36.72,
            cleanDuration: 2.9,
            keepSegments: [keepStart, keepMiddle, keepEnd],
            cutSegments: [firstSilenceCut, secondSilenceCut],
            reviewSegments: []
        )
        let captions = [
            CaptionSegment(startTime: 31.92, endTime: 34.7, text: "yorumlara vibe yazıp", role: .hook, style: .premiumLowerThird),
            CaptionSegment(startTime: 34.7, endTime: 36.72, text: "birlikte büyüyelim", role: .conclusion, style: .premiumLowerThird),
        ]
        let editPlan = EditPlan(decisions: [], template: .premiumFounder, totalEffects: 0, averageIntensity: 0)

        let report = QualityGateService.evaluate(
            captions: captions,
            editPlan: editPlan,
            roughCut: roughCut,
            template: .premiumFounder,
            transcription: transcription
        )

        let cutTrust = report.checks.first { $0.name == "Cut trust" }
        #expect(cutTrust?.passed == true)
        #expect(!report.failedChecks.contains { $0.name == "Cut trust" })
    }

    @Test("Destructive cuts inside low-confidence speech still fail cut trust")
    func destructiveCutsInsideLowConfidenceSpeechStillFailCutTrust() {
        let transcriptSegment = segment("important low confidence product explanation", start: 0, end: 4, confidence: 0.68)
        let transcription = TranscriptionResult(
            fullText: transcriptSegment.text,
            segments: [transcriptSegment],
            language: "tr",
            overallConfidence: 0.82
        )
        let keep = RoughCutDecision(
            startTime: 0,
            endTime: 1,
            action: .keep,
            reason: "Content",
            confidence: 0.9,
            linkedTranscriptText: "important",
            requiresReview: false
        )
        let destructiveCut = RoughCutDecision(
            startTime: 1,
            endTime: 4,
            action: .cut,
            reason: "Duplicate content",
            confidence: 0.9,
            linkedTranscriptText: "low confidence product explanation",
            requiresReview: false
        )
        let roughCut = RoughCutResult(
            decisions: [keep, destructiveCut],
            originalDuration: 4,
            cleanDuration: 1,
            keepSegments: [keep],
            cutSegments: [destructiveCut],
            reviewSegments: []
        )
        let captions = [
            CaptionSegment(startTime: 0, endTime: 1, text: "important", role: .hook, style: .premiumLowerThird)
        ]
        let editPlan = EditPlan(decisions: [], template: .premiumFounder, totalEffects: 0, averageIntensity: 0)

        let report = QualityGateService.evaluate(
            captions: captions,
            editPlan: editPlan,
            roughCut: roughCut,
            template: .premiumFounder,
            transcription: transcription
        )

        let cutTrust = report.checks.first { $0.name == "Cut trust" }
        #expect(cutTrust?.passed == false)
    }

    @Test("Review decisions fail quality gate")
    func reviewRequiredFailsQuality() {
        let transcriptSegment = segment("uncertain content", start: 0, end: 3, confidence: 0.95)
        let decision = RoughCutDecision(
            startTime: 0,
            endTime: 3,
            action: .reviewRequired,
            reason: "Review: uncertain",
            confidence: 0.6,
            linkedTranscriptText: transcriptSegment.text,
            requiresReview: true
        )
        let roughCut = RoughCutResult(
            decisions: [decision],
            originalDuration: 3,
            cleanDuration: 3,
            keepSegments: [],
            cutSegments: [],
            reviewSegments: [decision]
        )
        let transcription = TranscriptionResult(
            fullText: transcriptSegment.text,
            segments: [transcriptSegment],
            language: "tr",
            overallConfidence: 0.95
        )
        let captions = [
            CaptionSegment(startTime: 0, endTime: 3, text: transcriptSegment.text, role: .hook, style: .premiumLowerThird),
        ]
        let editPlan = EditPlan(decisions: [], template: .premiumFounder, totalEffects: 0, averageIntensity: 0)

        let report = QualityGateService.evaluate(
            captions: captions,
            editPlan: editPlan,
            roughCut: roughCut,
            template: .premiumFounder,
            transcription: transcription
        )

        let reviewCheck = report.checks.first { $0.name == "Review required" }
        #expect(reviewCheck?.passed == false)
        #expect(report.passed == false)
    }
}

@Suite("EditDecisionEngineCombos")
struct EditDecisionEngineComboTests {
    @Test("High intensity hook layers whoosh and impact SFX")
    func highIntensityHookLayersWhooshAndImpactSFX() {
        let captions = [
            CaptionSegment(
                startTime: 1.0,
                endTime: 2.0,
                text: "Bu videoda kritik nokta",
                role: .hook,
                style: .hookImpact,
                sceneBehavior: .hookImpact
            )
        ]
        let keep = RoughCutDecision(
            startTime: 0,
            endTime: 3,
            action: .keep,
            reason: "Content",
            confidence: 0.95,
            linkedTranscriptText: nil,
            requiresReview: false
        )

        let editPlan = EditDecisionEngine.generateEditPlan(
            captions: captions,
            roughCut: RoughCutResult(
                decisions: [keep],
                originalDuration: 3,
                cleanDuration: 3,
                keepSegments: [keep],
                cutSegments: [],
                reviewSegments: []
            ),
            template: .viralCaption
        )

        #expect(editPlan.decisions.contains { $0.reason == "Hook pre-whoosh" })
        #expect(editPlan.decisions.contains { $0.reason == "Hook impact SFX" })
        #expect(editPlan.decisions.filter { $0.type == .sfx }.allSatisfy { $0.time >= 0.05 })
    }

    @Test("High intensity cut transitions layer whoosh and impact SFX")
    func highIntensityCutTransitionsLayerWhooshAndImpactSFX() {
        let firstKeep = RoughCutDecision(
            startTime: 0,
            endTime: 2,
            action: .keep,
            reason: "Content",
            confidence: 0.95,
            linkedTranscriptText: nil,
            requiresReview: false
        )
        let cut = RoughCutDecision(
            startTime: 2,
            endTime: 3,
            action: .cut,
            reason: "Silence",
            confidence: 0.95,
            linkedTranscriptText: nil,
            requiresReview: false
        )
        let secondKeep = RoughCutDecision(
            startTime: 3,
            endTime: 5,
            action: .keep,
            reason: "Content",
            confidence: 0.95,
            linkedTranscriptText: nil,
            requiresReview: false
        )

        let editPlan = EditDecisionEngine.generateEditPlan(
            captions: [],
            roughCut: RoughCutResult(
                decisions: [firstKeep, cut, secondKeep],
                originalDuration: 5,
                cleanDuration: 4,
                keepSegments: [firstKeep, secondKeep],
                cutSegments: [cut],
                reviewSegments: []
            ),
            template: .viralCaption
        )

        #expect(editPlan.decisions.contains { $0.reason == "Cut whoosh" })
        #expect(editPlan.decisions.contains { $0.reason == "Cut impact SFX" })
    }
}

@Suite("SFXRouting")
struct SFXRoutingTests {
    @Test("Conclusion riser maps to riser sound")
    func conclusionRiserMapsToRiser() {
        let decision = EditDecision(
            time: 1,
            duration: 0.8,
            type: .sfx,
            reason: "Conclusion riser",
            intensity: 0.5
        )

        #expect(SFXAssetManager.sound(for: decision) == .riser)
    }

    @Test("Punch SFX maps to impact sound")
    func punchMapsToImpact() {
        let decision = EditDecision(
            time: 1,
            duration: 0.15,
            type: .sfx,
            reason: "Punch SFX",
            intensity: 0.5
        )

        #expect(SFXAssetManager.sound(for: decision) == .impact)
    }

    @Test("Transition impact maps to impact while transition whoosh stays whoosh")
    func transitionImpactRoutingUsesImpactLane() {
        let impact = EditDecision(
            time: 1,
            duration: 0.18,
            type: .sfx,
            reason: "Transition impact SFX",
            intensity: 0.5
        )
        let whoosh = EditDecision(
            time: 1,
            duration: 0.28,
            type: .sfx,
            reason: "Transition whoosh",
            intensity: 0.5
        )

        #expect(SFXAssetManager.sound(for: impact) == .impact)
        #expect(SFXAssetManager.sound(for: whoosh) == .whoosh)
    }

    @Test("Unknown SFX reason is not routed to a random impact")
    func unknownSFXReasonDoesNotDefaultToImpact() {
        let decision = EditDecision(
            time: 1,
            duration: 0.18,
            type: .sfx,
            reason: "Random viral accent",
            intensity: 0.5
        )

        #expect(SFXAssetManager.sound(for: decision) == nil)
    }

    @Test("Tech influencer SFX uses downloaded bundle assets")
    func techInfluencerSFXUsesDownloadedBundleAssets() {
        let cases: [(SFXAssetManager.SFXSound, String, String)] = [
            (.whoosh, "Topic shift whoosh", "dragon-studio-simple-whoosh-382724.mp3"),
            (.impact, "Tech reveal impact SFX", "universfield-impact-cinematic-boom-352465.mp3"),
            (.pop, "Tech UI click SFX", "dragon-studio-mouse-click-sfx-444806.mp3"),
            (.riser, "Tech reveal riser", "dragon-studio-cinematic-riser-03-414575.mp3"),
            (.glitch, "AI output digital glitch", "dragon-studio-glitch-effect-1-397982.mp3"),
            (.subHit, "Big reveal sub hit", "u_tmz2ks56ex-m3g-cinematic-bass-318310.mp3"),
            (.ping, "CTA notification ping", "universfield-new-notification-057-494255.mp3"),
            (.typing, "Code typing keyboard", "virtualzero-mechanical-keyboard-typing-hd-372290.mp3"),
            (.shutter, "Camera shutter flash", "universfield-camera-shutter-199580.mp3")
        ]

        for testCase in cases {
            let decision = EditDecision(
                time: 1,
                duration: 0.2,
                type: .sfx,
                reason: testCase.1,
                intensity: 0.4
            )
            let asset = SFXAssetManager.asset(
                for: decision,
                sound: testCase.0,
                templateId: "tech_influencer"
            )

            #expect(asset?.url.lastPathComponent == testCase.2)
        }
    }

    @Test("Asset registry routes reveal whoosh and impact to explicit lanes")
    func assetRegistryRoutesRevealCuesToExplicitLanes() {
        let selection = EditPackageSelection(
            preset: .techInfluencer,
            captionStyleAssetID: "caption_bold_tech_dynamic",
            sfxAssetIDs: [
                "mixkit_flying_fast_swoosh_1469",
                "mixkit_dramatic_metal_explosion_impact_1687",
                "mixkit_short_space_stutter_intro_riser_1144"
            ],
            visualEffectAssetIDs: [],
            musicAssetID: nil,
            transitionAssetID: "transition_zoom_cut"
        )
        let whoosh = EditDecision(
            time: 1,
            duration: 0.16,
            type: .sfx,
            reason: "Tech reveal whoosh",
            intensity: 0.4
        )
        let impact = EditDecision(
            time: 1,
            duration: 0.16,
            type: .sfx,
            reason: "Tech reveal impact SFX",
            intensity: 0.4
        )

        #expect(AssetRegistry.sfxItem(for: whoosh, selection: selection)?.category == "whoosh")
        #expect(AssetRegistry.sfxItem(for: impact, selection: selection)?.category == "impact")
    }

    @Test("Whoosh source slice skips quiet lead-in")
    func whooshSourceSliceSkipsQuietLeadIn() {
        let start = SFXAssetManager.sourceRangeStart(
            for: .whoosh,
            assetDuration: CMTime(seconds: 1.0, preferredTimescale: 600),
            clippedDuration: CMTime(seconds: 0.3, preferredTimescale: 600)
        )

        #expect(start.seconds >= 0.18)
    }

    @Test("SFX output volume boosts short impact cues above raw plan intensity")
    func sfxOutputVolumeBoostsShortImpactCues() {
        let volume = SFXAssetManager.outputVolume(
            for: .impact,
            decisionIntensity: 0.36,
            templateSFXVolume: 0.30
        )

        #expect(volume > 0.49)
        #expect(volume <= 0.95)
    }

    @Test("SFX output volume keeps template volume as floor")
    func sfxOutputVolumeKeepsTemplateVolumeFloor() {
        let volume = SFXAssetManager.outputVolume(
            for: .whoosh,
            decisionIntensity: 0.05,
            templateSFXVolume: 0.30
        )

        #expect(volume >= 0.37)
        #expect(volume <= 0.95)
    }

    @Test("Cut whoosh volume is audible enough for fast transitions")
    func cutWhooshVolumeIsAudibleEnough() {
        let volume = SFXAssetManager.outputVolume(
            for: .whoosh,
            decisionIntensity: 0.55,
            templateSFXVolume: 0.30
        )

        #expect(volume >= 0.68)
        #expect(volume <= 0.95)
    }

    @Test("Punch impact volume has an audible floor even on quiet templates")
    func punchImpactVolumeHasAudibleFloor() {
        let decision = EditDecision(
            time: 10.23,
            duration: 0.24,
            type: .sfx,
            reason: "Punch impact SFX",
            intensity: 0.096
        )

        let volume = SFXAssetManager.outputVolume(
            for: .impact,
            decision: decision,
            templateSFXVolume: 0.08
        )

        #expect(volume >= 0.60)
        #expect(volume <= 0.95)
    }

    @Test("Cut impact SFX stays in clean timeline timebase")
    func cutImpactSFXIsCleanTimelineDecision() {
        let decision = EditDecision(
            time: 2.0,
            duration: 0.22,
            type: .sfx,
            reason: "Cut impact SFX",
            intensity: 0.62
        )

        #expect(ExportService.isCleanTimelineDecision(decision))
    }

    @Test("Tech topic shift transition stays source timed for export remap")
    func techTopicShiftTransitionIsSourceTimedDecision() {
        let decision = EditDecision(
            time: 4.22,
            duration: 0.16,
            type: .cutTransition,
            reason: "Topic shift motion blur cut",
            intensity: 0.24
        )

        #expect(!ExportService.isCleanTimelineDecision(decision))
    }
}

@Suite("TemplateRecommendationEngine")
struct TemplateRecommendationEngineTests {
    @Test("Tech mixed-language script auto-selects tech influencer template")
    func techMixedLanguageScriptSelectsTechInfluencer() {
        let segment = TranscriptSegment(
            startTime: 0,
            endTime: 30,
            text: "Türkiye'de yapay zekayı anlatıp Vibe Coding ile MVP App Store web ürün çıkarabilirsin yorumlara Vibe yaz",
            confidence: 0.86,
            segmentType: .speech
        )
        let transcription = TranscriptionResult(
            fullText: segment.text,
            segments: [segment],
            language: "tr",
            overallConfidence: 0.86
        )
        let keep = RoughCutDecision(
            startTime: 0,
            endTime: 30,
            action: .keep,
            reason: "Content",
            confidence: 0.9,
            linkedTranscriptText: segment.text,
            requiresReview: false
        )
        let roughCut = RoughCutResult(
            decisions: [keep],
            originalDuration: 34,
            cleanDuration: 30,
            keepSegments: [keep],
            cutSegments: [],
            reviewSegments: []
        )
        let audio = AudioAnalysisResult(
            segments: [AudioSegment(startTime: 0, endTime: 34, type: .speech, energy: 0.12)],
            silenceIntervals: [],
            averageEnergy: 0.12,
            peakEnergy: 0.6,
            duration: 34
        )

        let recommendation = TemplateRecommendationEngine.recommend(
            transcription: transcription,
            roughCut: roughCut,
            audio: audio
        ).first

        #expect(recommendation?.template.id == "tech_influencer")
    }
}
