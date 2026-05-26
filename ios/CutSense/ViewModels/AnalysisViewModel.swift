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

    func restoreArtifacts(projectId: UUID, expectedVideoURL: URL) -> Bool {
        guard let snapshot = PipelineArtifactStore.load(projectId: projectId) else {
            return false
        }

        if !snapshot.matchesSourceVideo(expectedVideoURL) {
            return false
        }

        guard let cachedTranscript = snapshot.transcriptionResult,
              let roughCut = snapshot.roughCutResult else {
            return false
        }
        let restoredAudio = snapshot.audioAnalysis?.domainValue
        let transcript = (try? TranscriptionValidator.validated(
            TranscriptPostProcessor.corrected(cachedTranscript)
        )) ?? cachedTranscript
        let didRepairCachedTranscript = transcript.fullText != cachedTranscript.fullText

        PipelineDiagnostics.record(
            projectId: projectId,
            stage: .roughCut,
            status: .completed,
            source: .cache,
            message: "analysis restored from local artifact cache",
            artifactCount: roughCut.decisions.count,
            metadata: [
                "transcriptSegments": "\(transcript.segments.count)",
                "sourceVideoPath": snapshot.sourceVideoPath ?? "",
                "audioSegments": "\(snapshot.audioAnalysis?.segments.count ?? 0)",
                "transcriptRepaired": "\(didRepairCachedTranscript)"
            ]
        )

        transcriptionResult = transcript
        roughCutResult = roughCut
        audioResult = restoredAudio
        audioQualityReport = restoredAudio.map { Self.audioQualityReport(for: $0) }
        usedSmartAnalysis = true
        currentStep = max(0, steps.count - 1)
        errorMessage = nil
        if didRepairCachedTranscript {
            try? PipelineArtifactStore.saveAnalysis(
                projectId: projectId,
                sourceVideoURL: expectedVideoURL,
                transcription: transcript,
                roughCut: roughCut,
                audioAnalysis: restoredAudio
            )
        }
        return true
    }

    func analyze(videoURL: URL, projectId: UUID, userId: UUID) async {
        isAnalyzing = true
        errorMessage = nil
        analysisDiff = nil
        var currentFailureStage = PipelineStage.audioAnalyzed
        defer { isAnalyzing = false }

        do {
            // Snapshot previous analysis for diff (if re-analyzing)
            await loadPreviousDecisions(projectId: projectId)

            // Update status to analyzing
            try? await PipelineRepository().updateProjectStatus(projectId, status: .analyzing)

            // Step 1: Audio analysis
            currentStep = 0
            currentFailureStage = .audioAnalyzed
            let audioStart = Date()
            PipelineDiagnostics.record(
                projectId: projectId,
                stage: .audioAnalyzed,
                status: .running,
                source: .live,
                message: "audio analysis started"
            )
            #if DEBUG
            print("[Analyze] >> AudioAnalysisService.analyze CALL")
            #endif
            audioResult = try await AudioAnalysisService.analyze(url: videoURL)
            if let audioResult {
                PipelineDiagnostics.record(
                    projectId: projectId,
                    stage: .audioAnalyzed,
                    status: .completed,
                    source: .live,
                    message: "audio analysis completed",
                    artifactCount: audioResult.segments.count,
                    durationSeconds: Date().timeIntervalSince(audioStart),
                    metadata: [
                        "duration": "\(audioResult.duration)",
                        "silenceCount": "\(audioResult.silenceIntervals.count)"
                    ]
                )
            }
            #if DEBUG
            print("[Analyze] << AudioAnalysisService.analyze RETURN segments=\(audioResult?.segments.count ?? -1) silences=\(audioResult?.silenceIntervals.count ?? -1) duration=\(audioResult?.duration ?? -1)")
            #endif

            // Run audio quality guard from analysis metadata
            if let audio = audioResult {
                #if DEBUG
                print("[Analyze] >> quality guard peak=\(audio.peakEnergy) avg=\(audio.averageEnergy)")
                #endif
                audioQualityReport = Self.audioQualityReport(for: audio)
                #if DEBUG
                print("[Analyze] << quality guard DONE")
                #endif
            }

            // Step 2: Transcription
            #if DEBUG
            print("[Analyze] >> step=1 setting")
            #endif
            currentStep = 1
            currentFailureStage = .transcribed
            let transcriptionStart = Date()
            PipelineDiagnostics.record(
                projectId: projectId,
                stage: .transcribed,
                status: .running,
                source: .live,
                message: "speech transcription started"
            )
            #if DEBUG
            print("[Analyze] >> Transcribe CALL")
            #endif
            transcriptionResult = try await transcriptionService.transcribe(url: videoURL)
            if let transcriptionResult {
                let partialRecognition = transcriptionResult.recognitionStatus.isPartial
                PipelineDiagnostics.record(
                    projectId: projectId,
                    stage: .transcribed,
                    status: partialRecognition ? .failed : .completed,
                    source: .live,
                    message: partialRecognition
                        ? "speech transcription returned \(transcriptionResult.recognitionStatus.rawValue)"
                        : "speech transcription completed",
                    artifactCount: transcriptionResult.segments.count,
                    durationSeconds: Date().timeIntervalSince(transcriptionStart),
                    metadata: [
                        "language": transcriptionResult.language,
                        "overallConfidence": "\(transcriptionResult.overallConfidence)",
                        "rawOverallConfidence": "\(transcriptionResult.qualityConfidence)",
                        "recognitionStatus": transcriptionResult.recognitionStatus.rawValue
                    ]
                )
            }
            #if DEBUG
            print("[Analyze] << Transcribe RETURN segments=\(transcriptionResult?.segments.count ?? -1)")
            #endif

            guard let audio = audioResult, var transcript = transcriptionResult else {
                errorMessage = "Analysis failed: missing audio or transcript data."
                return
            }

            // Step 3+4: Smart analysis (LLM on iOS 26+, heuristics fallback)
            currentStep = 2
            currentFailureStage = .smartAnalyzed
            liveClassifications = []
            classifiedCount = 0
            totalSegmentsToClassify = transcript.segments.count
            let smartStart = Date()
            PipelineDiagnostics.record(
                projectId: projectId,
                stage: .smartAnalyzed,
                status: .running,
                source: .live,
                message: "smart transcript analysis started",
                artifactCount: transcript.segments.count
            )

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
                overallConfidence: transcript.overallConfidence,
                rawOverallConfidence: transcript.rawOverallConfidence,
                recognitionStatus: transcript.recognitionStatus
            )
            transcript = TranscriptPostProcessor.corrected(transcript)
            transcript = try TranscriptionValidator.validated(transcript)
            transcriptionResult = transcript
            PipelineDiagnostics.record(
                projectId: projectId,
                stage: .smartAnalyzed,
                status: .completed,
                source: .live,
                message: "smart transcript analysis completed",
                artifactCount: transcript.segments.count,
                durationSeconds: Date().timeIntervalSince(smartStart),
                metadata: [
                    "takeGroups": "\(smartResult.takeGroups.count)",
                    "fillersRemoved": "\(smartResult.fillersRemoved)",
                    "analysisMode": smartResult.mode.rawValue,
                    "fallbackReason": smartResult.fallbackReason ?? ""
                ]
            )

            currentStep = 3
            currentFailureStage = .roughCut
            takeGroups = TakeDetectionEngine.detectTakeGroups(segments: transcript.segments)
            let timelinePlan = TechInfluencerTimelineAnalyzer.analyze(
                transcription: transcript,
                audioAnalysis: audio
            )
            PipelineDiagnostics.record(
                projectId: projectId,
                stage: .timelineAnalyzed,
                status: .completed,
                source: .live,
                message: "tech timeline analysis completed before rough cut",
                artifactCount: timelinePlan.events.count,
                metadata: [
                    "events": timelinePlan.events.map(\.kind.rawValue).joined(separator: ","),
                    "anchors": timelinePlan.events.map { event in
                        event.anchorTime.formatted(.number.precision(.fractionLength(2)))
                    }.joined(separator: ","),
                    "reasons": timelinePlan.events.map(\.reason).joined(separator: " | ")
                ]
            )

            // Step 5: Rough cut decisions
            currentStep = 4
            let roughCutStart = Date()
            PipelineDiagnostics.record(
                projectId: projectId,
                stage: .roughCut,
                status: .running,
                source: .live,
                message: "rough cut generation started"
            )
            let roughCut = RoughCutDecisionEngine.generateTechInfluencerDecisions(
                transcription: transcript,
                audioAnalysis: audio,
                takeGroups: takeGroups,
                timelinePlan: timelinePlan
            )
            roughCutResult = roughCut
            PipelineDiagnostics.record(
                projectId: projectId,
                stage: .roughCut,
                status: .completed,
                source: .live,
                message: "rough cut generation completed",
                artifactCount: roughCut.decisions.count,
                durationSeconds: Date().timeIntervalSince(roughCutStart),
                metadata: [
                    "cleanDuration": "\(roughCut.cleanDuration)",
                    "cutCount": "\(roughCut.cutSegments.count)",
                    "reviewCount": "\(roughCut.reviewSegments.count)"
                ]
            )

            // Step 6: Verify coherence
            currentStep = 5
            let qualityStart = Date()
            if let roughCut = roughCutResult {
                let includedDecisions = roughCut.decisions.filter { $0.isTimelineIncluded }
                let keptTexts = MeaningPreservationEngine.keptSpeechSegments(
                    from: transcript,
                    roughCut: roughCut
                )

                meaningResult = MeaningPreservationEngine.verify(
                    keptSegments: keptTexts,
                    allSegments: transcript.segments.filter(Self.isSpeechLike)
                )

                continuityResult = ContinuityChecker.check(
                    keptDecisions: includedDecisions
                )
                PipelineDiagnostics.record(
                    projectId: projectId,
                    stage: .roughCut,
                    status: .completed,
                    source: .live,
                    message: "rough cut continuity/meaning preflight completed",
                    artifactCount: includedDecisions.count,
                    durationSeconds: Date().timeIntervalSince(qualityStart),
                    metadata: [
                        "continuityScore": "\(continuityResult?.overallScore ?? 0)",
                        "meaningScore": "\(meaningResult?.overallScore ?? 0)",
                        "meaningCoherent": "\(meaningResult?.isCoherent ?? false)"
                    ]
                )
            }

            // Compute diff if re-analyzing
            if let prev = previousDecisionSummary, let roughCut = roughCutResult {
                analysisDiff = computeDiff(previous: prev, newDecisions: roughCut.decisions)
            }

            do {
                try PipelineArtifactStore.saveAnalysis(
                    projectId: projectId,
                    sourceVideoURL: videoURL,
                    transcription: transcript,
                    roughCut: roughCut,
                    audioAnalysis: audioResult
                )
            } catch {
                #if DEBUG
                print("[CutSense] Local pipeline artifact save failed: \(error.localizedDescription)")
                #endif
            }

            // Save all analysis data to DB (cloud-only; local mode short-circuits)
            await saveAnalysisData(projectId: projectId, userId: userId)
        } catch {
            #if DEBUG
            print("[Analyze] FAILED: \(error)")
            #endif
            PipelineDiagnostics.record(
                projectId: projectId,
                stage: currentFailureStage,
                status: .failed,
                source: .live,
                message: error.localizedDescription,
                metadata: ["currentStep": "\(currentStep)"]
            )
            if let localized = (error as? LocalizedError)?.errorDescription {
                errorMessage = localized
            } else {
                errorMessage = "Analiz başarısız oldu. Lütfen tekrar deneyin."
            }
            try? await PipelineRepository().updateProjectStatus(projectId, status: .failed)
        }
    }

    private static func audioQualityReport(for audio: AudioAnalysisResult) -> AudioQualityGuard.QualityReport {
        AudioQualityGuard.analyze(audioAnalysis: audio)
    }

    private static func isSpeechLike(_ segment: TranscriptSegment) -> Bool {
        switch segment.segmentType {
        case .speech, .contentSentence, .suspectedRestart, .suspectedDuplicate:
            return true
        case .silence, .filler, .editCommand:
            return false
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
        if let localResult = PipelineArtifactStore.load(projectId: projectId)?.roughCutResult {
            var classMap: [String: String] = [:]
            for decision in localResult.decisions {
                if let text = decision.linkedTranscriptText {
                    classMap[text] = decision.action.rawValue
                }
            }
            previousDecisionSummary = DecisionSummary(
                keepCount: localResult.keepSegments.count,
                cutCount: localResult.cutSegments.count,
                reviewCount: localResult.reviewSegments.count,
                totalSegments: localResult.decisions.count,
                classificationMap: classMap
            )
            return
        }

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
