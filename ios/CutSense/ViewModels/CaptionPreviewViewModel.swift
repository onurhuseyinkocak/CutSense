import SwiftUI

@MainActor
@Observable
final class CaptionPreviewViewModel {
    var captions: [CaptionSegment] = []
    var editPlan: EditPlan?
    var qualityReport: QualityReport?
    var isProcessing = false

    private static let restoreCaptionEditArtifacts = false

    func invalidate() {
        captions = []
        editPlan = nil
        qualityReport = nil
        isProcessing = false
    }

    func restoreArtifacts(projectId: UUID, template: TemplateConfig) -> Bool {
        guard Self.restoreCaptionEditArtifacts else {
            PipelineDiagnostics.record(
                projectId: projectId,
                stage: .captioned,
                status: .pending,
                source: .cache,
                message: "caption and edit artifact cache bypassed for fresh edit decisions",
                metadata: ["template": template.id]
            )
            return false
        }

        guard let snapshot = PipelineArtifactStore.load(projectId: projectId),
              let savedCaptions = snapshot.captionSegments,
              let savedPlan = snapshot.editPlanResult,
              savedPlan.template.id == template.id,
              savedPlan.template.intensity == template.intensity,
              abs(savedPlan.template.sfxVolume - template.sfxVolume) < 0.001,
              savedPlan.template.defaultStyle == template.defaultStyle else {
            return false
        }

        captions = savedCaptions
        editPlan = savedPlan
        qualityReport = nil
        PipelineDiagnostics.record(
            projectId: projectId,
            stage: .editPlanned,
            status: .completed,
            source: .cache,
            message: "caption and edit artifacts restored from cache",
            artifactCount: savedPlan.decisions.count,
            metadata: [
                "captionCount": "\(savedCaptions.count)",
                "template": template.id
            ]
        )
        return true
    }

    func evaluateQuality(
        transcription: TranscriptionResult,
        roughCut: RoughCutResult,
        template: TemplateConfig,
        audioQuality: AudioQualityGuard.QualityReport? = nil,
        projectId: UUID? = nil
    ) {
        guard let editPlan else {
            qualityReport = nil
            return
        }

        let includedDecisions = roughCut.decisions.filter { $0.isTimelineIncluded }
        let continuity = ContinuityChecker.check(
            keptDecisions: includedDecisions,
            profile: template.id == "tech_influencer" ? .shortFormSemantic : .sourceTimeline
        )
        let keptTexts = MeaningPreservationEngine.keptSpeechSegments(
            from: transcription,
            roughCut: roughCut
        )
        let coherence = MeaningPreservationEngine.verify(
            keptSegments: keptTexts,
            allSegments: transcription.segments.filter(isSpeechLike)
        )

        qualityReport = QualityGateService.evaluate(
            captions: captions,
            editPlan: editPlan,
            roughCut: roughCut,
            template: template,
            transcription: transcription,
            audioQuality: audioQuality,
            continuity: continuity,
            coherence: coherence
        )

        if let projectId, let qualityReport {
            do {
                try PipelineArtifactStore.saveQualityReport(projectId: projectId, report: qualityReport)
            } catch {
                #if DEBUG
                print("[CutSense] Quality report artifact save failed: \(error.localizedDescription)")
                #endif
            }
            PipelineDiagnostics.record(
                projectId: projectId,
                stage: .qualityChecked,
                status: qualityReport.passed ? .completed : .failed,
                source: .live,
                message: qualityReport.passed ? "caption quality gate completed" : "caption quality gate failed",
                metadata: [
                    "score": "\(qualityReport.score)",
                    "passed": "\(qualityReport.passed)",
                    "failedChecks": qualityReport.failedChecks.map(\.name).joined(separator: ", "),
                    "failedCheckDetails": qualityReport.failedChecks.map { "\($0.name): \($0.detail)" }.joined(separator: " | ")
                ]
            )
        }

        let debugLog = TimelineDebugLogger.generate(
            roughCut: roughCut,
            captions: captions,
            editPlan: editPlan,
            qualityReport: qualityReport
        )
        TimelineDebugLogger.printLog(debugLog)
    }

    func generate(
        transcription: TranscriptionResult,
        roughCut: RoughCutResult,
        template: TemplateConfig,
        audioQuality: AudioQualityGuard.QualityReport? = nil,
        projectId: UUID? = nil
    ) async {
        isProcessing = true
        defer { isProcessing = false }

        // Yield to let SwiftUI render the loading state
        await Task.yield()

        let captionStart = Date()
        if let projectId {
            PipelineDiagnostics.record(
                projectId: projectId,
                stage: .captioned,
                status: .running,
                source: .live,
                message: "caption generation started",
                metadata: ["template": template.id]
            )
        }

        captions = CaptionEngine.generateCaptions(
            from: transcription,
            roughCut: roughCut,
            template: template
        )
        if let projectId {
            PipelineDiagnostics.record(
                projectId: projectId,
                stage: .captioned,
                status: captions.isEmpty ? .failed : .completed,
                source: .live,
                message: captions.isEmpty ? "caption generation produced no captions" : "caption generation completed",
                artifactCount: captions.count,
                durationSeconds: Date().timeIntervalSince(captionStart)
            )
        }

        let timelinePlan = template.id == "tech_influencer"
            ? TechInfluencerTimelineAnalyzer.analyze(
                transcription: transcription,
                audioAnalysis: AudioAnalysisResult(
                    segments: [],
                    silenceIntervals: [],
                    averageEnergy: 0,
                    peakEnergy: 0,
                    duration: roughCut.originalDuration
                )
            )
            : nil
        let editStart = Date()
        let plan = EditDecisionEngine.generateEditPlan(
            captions: captions,
            roughCut: roughCut,
            template: template,
            timelinePlan: timelinePlan
        )
        editPlan = plan
        if let projectId {
            PipelineDiagnostics.record(
                projectId: projectId,
                stage: .editPlanned,
                status: plan.decisions.isEmpty ? .failed : .completed,
                source: .live,
                message: plan.decisions.isEmpty ? "edit plan generated no decisions" : "edit plan generated",
                artifactCount: plan.decisions.count,
                durationSeconds: Date().timeIntervalSince(editStart),
                metadata: ["averageIntensity": "\(plan.averageIntensity)"]
            )
            do {
                try PipelineArtifactStore.saveCaptioning(
                    projectId: projectId,
                    template: template,
                    captions: captions,
                    editPlan: plan
                )
            } catch {
                #if DEBUG
                print("[CutSense] Caption/edit artifact save failed before quality gate: \(error.localizedDescription)")
                #endif
            }
        }

        evaluateQuality(
            transcription: transcription,
            roughCut: roughCut,
            template: template,
            audioQuality: audioQuality,
            projectId: projectId
        )
    }

    func saveCaptionData(projectId: UUID, userId: UUID, template: TemplateConfig) async {
        guard !captions.isEmpty else { return }
        let pipeline = PipelineRepository()

        do {
            try PipelineArtifactStore.saveCaptioning(
                projectId: projectId,
                template: template,
                captions: captions,
                editPlan: editPlan
            )
        } catch {
            #if DEBUG
            print("[CutSense] Local caption artifact save failed: \(error.localizedDescription)")
            #endif
        }

        do {
            try await pipeline.updateProjectTemplate(projectId: projectId, templateName: template.name)
            try await pipeline.updateProjectStatus(projectId, status: .styling)

            // Delete old caption/edit data to prevent duplicates on re-generation
            try await pipeline.deleteCaptionData(projectId: projectId)

            try await pipeline.saveCaptionSegments(
                projectId: projectId,
                userId: userId,
                captions: captions
            )

            if let plan = editPlan {
                try await pipeline.saveEditDecisions(
                    projectId: projectId,
                    userId: userId,
                    decisions: plan.decisions
                )
            }
        } catch {
            #if DEBUG
            print("[CutSense] DB save after captioning failed: \(error.localizedDescription)")
            #endif
        }
    }

    private func isSpeechLike(_ segment: TranscriptSegment) -> Bool {
        switch segment.segmentType {
        case .speech, .contentSentence, .suspectedRestart, .suspectedDuplicate:
            return true
        case .silence, .filler, .editCommand:
            return false
        }
    }
}
