import SwiftUI
#if canImport(FoundationModels)
import FoundationModels
#endif

@MainActor
@Observable
final class AnalysisViewModel {
    var currentStep = 0
    var isAnalyzing = false
    var errorMessage: String?
    var audioResult: AudioAnalysisResult?
    var audioQualityReport: AudioQualityGuard.QualityReport?
    var transcriptionResult: TranscriptionResult?
    var roughCutResult: RoughCutResult?
    var cleanupResult: TranscriptCleanupAnalyzer.CleanupResult?
    var takeGroups: [TakeGroup] = []
    var continuityResult: ContinuityChecker.ContinuityResult?
    var meaningResult: MeaningPreservationEngine.PreservationResult?

    var usedSmartAnalysis = false

    // Re-analysis diff
    var previousDecisionSummary: DecisionSummary?
    var analysisDiff: AnalysisDiff?

    struct DecisionSummary: Sendable {
        let keepCount: Int
        let cutCount: Int
        let reviewCount: Int
        let totalSegments: Int
        let classificationMap: [String: String] // text -> action
    }

    struct AnalysisDiff: Sendable {
        let reclassifiedCount: Int
        let newKeepCount: Int
        let newCutCount: Int
        let previousKeepCount: Int
        let previousCutCount: Int
        let examples: [(text: String, oldAction: String, newAction: String)]
    }

    // Live classification state for streaming UI
    var liveClassifications: [(text: String, intent: String)] = []
    var classifiedCount = 0
    var totalSegmentsToClassify = 0

    let steps = [
        "Analyzing audio...",
        "Transcribing speech...",
        "Smart analysis...",
        "Detecting takes & edits...",
        "Building rough cut...",
        "Verifying coherence..."
    ]

    private let transcriptionService = SpeechTranscriptionService()

    func analyze(videoURL: URL, projectId: UUID, userId: UUID) async {
        isAnalyzing = true
        errorMessage = nil
        analysisDiff = nil
        defer { isAnalyzing = false }

        do {
            // Snapshot previous analysis for diff (if re-analyzing)
            await loadPreviousDecisions(projectId: projectId)

            // Update status to analyzing
            try? await PipelineRepository().updateProjectStatus(projectId, status: .analyzing)

            // Step 1: Audio analysis
            currentStep = 0
            audioResult = try await AudioAnalysisService.analyze(url: videoURL)

            // Run audio quality guard from analysis metadata
            if let audio = audioResult {
                // Approximate quality from analysis metadata
                let peakLinear = Float(audio.peakEnergy)
                let avgLinear = Float(audio.averageEnergy)
                let peakDB = peakLinear > 0 ? 20 * log10(peakLinear) : -Float.infinity
                let avgDB = avgLinear > 0 ? 20 * log10(avgLinear) : -Float.infinity
                let dynamicRange = peakDB - avgDB
                audioQualityReport = AudioQualityGuard.QualityReport(
                    peakDB: peakDB,
                    averageDB: avgDB,
                    isClipping: peakDB > -1.0,
                    isTooQuiet: avgDB < -30.0,
                    dynamicRange: dynamicRange,
                    passed: peakDB <= -1.0 && avgDB >= -30.0 && dynamicRange >= 6.0
                )
            }

            // Step 2: Transcription
            currentStep = 1
            transcriptionResult = try await transcriptionService.transcribe(url: videoURL)

            guard let audio = audioResult, var transcript = transcriptionResult else {
                errorMessage = "Analysis failed: missing audio or transcript data."
                return
            }

            // Step 3+4: Smart analysis (LLM on iOS 26+, heuristics fallback)
            currentStep = 2
            liveClassifications = []
            classifiedCount = 0
            totalSegmentsToClassify = transcript.segments.count

            // Fetch user's past AI feedback for few-shot learning
            let feedback = (try? await PipelineRepository().fetchRecentAiFeedback(userId: userId)) ?? []

            let smartResult = await SmartTranscriptAnalyzer.analyze(
                segments: transcript.segments,
                audioAnalysis: audio,
                userFeedback: feedback,
                onProgress: { [weak self] progress in
                    guard let self else { return }
                    self.classifiedCount = progress.classified
                    let displayText = String(progress.segmentText.prefix(40))
                    self.liveClassifications.append((text: displayText, intent: progress.intent))
                    // Keep only last 6 visible for compact UI
                    if self.liveClassifications.count > 6 {
                        self.liveClassifications.removeFirst()
                    }
                }
            )
            usedSmartAnalysis = true
            cleanupResult = TranscriptCleanupAnalyzer.CleanupResult(
                segments: smartResult.cleanedSegments,
                fillersRemoved: smartResult.fillersRemoved,
                restartsDetected: smartResult.restartsDetected,
                duplicatesDetected: smartResult.duplicatesDetected
            )
            transcript = TranscriptionResult(
                fullText: transcript.fullText,
                segments: smartResult.cleanedSegments,
                language: transcript.language,
                overallConfidence: transcript.overallConfidence
            )
            transcriptionResult = transcript

            currentStep = 3
            takeGroups = smartResult.takeGroups

            // Step 5: Rough cut decisions
            currentStep = 4
            var roughCut = RoughCutDecisionEngine.generateDecisions(
                transcription: transcript,
                audioAnalysis: audio
            )

            // Apply take group results — cut non-best takes
            if !takeGroups.isEmpty {
                roughCut = RoughCutDecisionEngine.applyTakeGroups(takeGroups, to: roughCut)
            }
            roughCutResult = roughCut

            // Step 6: Verify coherence
            currentStep = 5
            if let roughCut = roughCutResult {
                let keptTexts = roughCut.keepSegments.compactMap { decision -> TranscriptSegment? in
                    transcript.segments.first { seg in
                        abs(seg.startTime - decision.startTime) < 0.1
                    }
                }

                meaningResult = MeaningPreservationEngine.verify(
                    keptSegments: keptTexts,
                    allSegments: transcript.segments
                )

                continuityResult = ContinuityChecker.check(
                    keptDecisions: roughCut.keepSegments
                )
            }

            // Compute diff if re-analyzing
            if let prev = previousDecisionSummary, let roughCut = roughCutResult {
                analysisDiff = computeDiff(previous: prev, newDecisions: roughCut.decisions)
            }

            // Save all analysis data to DB
            await saveAnalysisData(projectId: projectId, userId: userId)
        } catch {
            errorMessage = error.localizedDescription
            try? await PipelineRepository().updateProjectStatus(projectId, status: .failed)
        }
    }

    private func saveAnalysisData(projectId: UUID, userId: UUID) async {
        let pipeline = PipelineRepository()

        do {
            guard let transcript = transcriptionResult else { return }

            // Delete old analysis data to prevent duplicates on re-analysis
            try await pipeline.deleteAnalysisData(projectId: projectId)

            // Save transcript
            let transcriptId = try await pipeline.saveTranscript(
                projectId: projectId,
                userId: userId,
                transcription: transcript
            )

            // Save transcript segments
            try await pipeline.saveTranscriptSegments(
                transcriptId: transcriptId,
                projectId: projectId,
                userId: userId,
                segments: transcript.segments
            )

            // Save rough cut decisions
            if let roughCut = roughCutResult {
                try await pipeline.saveRoughCutDecisions(
                    projectId: projectId,
                    userId: userId,
                    decisions: roughCut.decisions
                )

                // Update project durations
                try await pipeline.updateProjectDurations(
                    projectId: projectId,
                    originalDuration: roughCut.originalDuration,
                    finalDuration: roughCut.cleanDuration
                )
            }

            // Save take groups
            if !takeGroups.isEmpty {
                try await pipeline.saveTakeGroups(
                    projectId: projectId,
                    userId: userId,
                    takeGroups: takeGroups
                )
            }

            // Update project status
            try await pipeline.updateProjectStatus(projectId, status: .roughCutReady)
        } catch {
            #if DEBUG
            print("[CutSense] DB save after analysis failed: \(error.localizedDescription)")
            #endif
        }
    }

    // MARK: - Re-analysis Diff

    private func loadPreviousDecisions(projectId: UUID) async {
        do {
            guard let oldResult = try await PipelineRepository().fetchRoughCutDecisions(projectId: projectId) else {
                previousDecisionSummary = nil
                return
            }
            var classMap: [String: String] = [:]
            for d in oldResult.decisions {
                if let text = d.linkedTranscriptText {
                    classMap[text] = d.action.rawValue
                }
            }
            previousDecisionSummary = DecisionSummary(
                keepCount: oldResult.keepSegments.count,
                cutCount: oldResult.cutSegments.count,
                reviewCount: oldResult.reviewSegments.count,
                totalSegments: oldResult.decisions.count,
                classificationMap: classMap
            )
        } catch {
            previousDecisionSummary = nil
        }
    }

    private func computeDiff(previous: DecisionSummary, newDecisions: [RoughCutDecision]) -> AnalysisDiff {
        var reclassified = 0
        var examples: [(text: String, oldAction: String, newAction: String)] = []

        for decision in newDecisions {
            guard let text = decision.linkedTranscriptText,
                  let oldAction = previous.classificationMap[text] else { continue }
            let newAction = decision.action.rawValue
            if oldAction != newAction {
                reclassified += 1
                if examples.count < 3 {
                    examples.append((text: String(text.prefix(50)), oldAction: oldAction, newAction: newAction))
                }
            }
        }

        let newKeep = newDecisions.filter { $0.action == .keep }.count
        let newCut = newDecisions.filter { $0.action == .cut || $0.action == .trimStart || $0.action == .trimEnd }.count

        return AnalysisDiff(
            reclassifiedCount: reclassified,
            newKeepCount: newKeep,
            newCutCount: newCut,
            previousKeepCount: previous.keepCount,
            previousCutCount: previous.cutCount,
            examples: examples
        )
    }
}
