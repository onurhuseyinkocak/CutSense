import SwiftUI

@MainActor
@Observable
final class CaptionPreviewViewModel {
    var captions: [CaptionSegment] = []
    var editPlan: EditPlan?
    var qualityReport: QualityReport?
    var isProcessing = false

    func generate(
        transcription: TranscriptionResult,
        roughCut: RoughCutResult,
        template: TemplateConfig
    ) async {
        isProcessing = true
        defer { isProcessing = false }

        // Yield to let SwiftUI render the loading state
        await Task.yield()

        captions = CaptionEngine.generateCaptions(
            from: transcription,
            roughCut: roughCut,
            template: template
        )

        let plan = EditDecisionEngine.generateEditPlan(
            captions: captions,
            roughCut: roughCut,
            template: template
        )
        editPlan = plan

        // Compute continuity and coherence for quality gate
        let continuity = ContinuityChecker.check(keptDecisions: roughCut.keepSegments)
        let keptTexts = roughCut.keepSegments.compactMap { decision -> TranscriptSegment? in
            transcription.segments.first { seg in
                abs(seg.startTime - decision.startTime) < 0.1
            }
        }
        let coherence = MeaningPreservationEngine.verify(
            keptSegments: keptTexts,
            allSegments: transcription.segments.filter { $0.segmentType == .speech }
        )

        qualityReport = QualityGateService.evaluate(
            captions: captions,
            editPlan: plan,
            roughCut: roughCut,
            template: template,
            continuity: continuity,
            coherence: coherence
        )

        // Debug log entire timeline state
        let debugLog = TimelineDebugLogger.generate(
            roughCut: roughCut,
            captions: captions,
            editPlan: plan,
            qualityReport: qualityReport
        )
        TimelineDebugLogger.printLog(debugLog)
    }

    func saveCaptionData(projectId: UUID, userId: UUID, templateName: String) async {
        guard !captions.isEmpty else { return }
        let pipeline = PipelineRepository()
        do {
            try await pipeline.updateProjectTemplate(projectId: projectId, templateName: templateName)
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
}
