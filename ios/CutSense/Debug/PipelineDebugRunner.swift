#if DEBUG
import AVFoundation
import Foundation

@MainActor
enum PipelineDebugRunner {
    static func runFromLaunchEnvironment() async {
        let inputURL = URL.documentsDirectory
            .appending(path: CutSenseDebugRuntime.debugInputFileName)
        await run(sourceURL: inputURL)
    }

    static func run(sourceURL: URL, projectId: UUID = UUID()) async {
        PipelineDiagnostics.record(
            projectId: projectId,
            stage: .imported,
            status: .running,
            source: .synthetic,
            message: "debug pipeline autorun started",
            metadata: ["sourcePath": sourceURL.path]
        )

        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            PipelineDiagnostics.record(
                projectId: projectId,
                stage: .imported,
                status: .failed,
                source: .synthetic,
                message: "debug input file not found",
                metadata: ["sourcePath": sourceURL.path]
            )
            return
        }

        var currentFailureStage = PipelineStage.imported

        do {
            let sourceStart = Date()
            let asset = AVURLAsset(url: sourceURL)
            let duration = try await asset.load(.duration).seconds
            PipelineDiagnostics.record(
                projectId: projectId,
                stage: .imported,
                status: .completed,
                source: .live,
                message: "debug input loaded",
                artifactCount: 1,
                durationSeconds: Date().timeIntervalSince(sourceStart),
                metadata: ["duration": "\(duration)"]
            )

            currentFailureStage = .audioAnalyzed
            let audioStart = Date()
            PipelineDiagnostics.record(
                projectId: projectId,
                stage: .audioAnalyzed,
                status: .running,
                source: .live,
                message: "audio analysis started"
            )
            let audioResult = try await AudioAnalysisService.analyze(url: sourceURL)
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

            currentFailureStage = .transcribed
            let transcription = try await transcribeForDebugRun(
                sourceURL: sourceURL,
                duration: max(duration, audioResult.duration),
                projectId: projectId
            )
            let feedback: [AiFeedbackRow] = []
            currentFailureStage = .smartAnalyzed
            let smartStart = Date()
            PipelineDiagnostics.record(
                projectId: projectId,
                stage: .smartAnalyzed,
                status: .running,
                source: .live,
                message: "debug smart transcript analysis started",
                artifactCount: transcription.segments.count
            )
            let smartResult = await SmartTranscriptAnalyzer.analyze(
                segments: transcription.segments,
                audioAnalysis: audioResult,
                userFeedback: feedback
            )
            let cleanedTranscription = try TranscriptionValidator.validated(
                TranscriptPostProcessor.corrected(TranscriptionResult(
                    fullText: transcription.fullText,
                    segments: smartResult.cleanedSegments,
                    language: transcription.language,
                    overallConfidence: transcription.overallConfidence,
                    rawOverallConfidence: transcription.rawOverallConfidence,
                    recognitionStatus: transcription.recognitionStatus
                ))
            )
            PipelineDiagnostics.record(
                projectId: projectId,
                stage: .smartAnalyzed,
                status: .completed,
                source: .live,
                message: "debug smart transcript analysis completed",
                artifactCount: cleanedTranscription.segments.count,
                durationSeconds: Date().timeIntervalSince(smartStart),
                metadata: [
                    "takeGroups": "\(smartResult.takeGroups.count)",
                    "fillersRemoved": "\(smartResult.fillersRemoved)",
                    "analysisMode": smartResult.mode.rawValue,
                    "fallbackReason": smartResult.fallbackReason ?? ""
                ]
            )

            let timelinePlan = TechInfluencerTimelineAnalyzer.analyze(
                transcription: cleanedTranscription,
                audioAnalysis: audioResult
            )
            PipelineDiagnostics.record(
                projectId: projectId,
                stage: .timelineAnalyzed,
                status: .completed,
                source: .live,
                message: "tech timeline analysis completed before edits",
                artifactCount: timelinePlan.events.count,
                metadata: [
                    "events": timelinePlan.events.map(\.kind.rawValue).joined(separator: ","),
                    "anchors": timelinePlan.events.map { event in
                        event.anchorTime.formatted(.number.precision(.fractionLength(2)))
                    }.joined(separator: ","),
                    "reasons": timelinePlan.events.map(\.reason).joined(separator: " | ")
                ]
            )

            currentFailureStage = .roughCut
            let roughStart = Date()
            PipelineDiagnostics.record(
                projectId: projectId,
                stage: .roughCut,
                status: .running,
                source: .live,
                message: "rough cut started"
            )
            let roughCut = RoughCutDecisionEngine.generateTechInfluencerDecisions(
                transcription: cleanedTranscription,
                audioAnalysis: audioResult,
                takeGroups: smartResult.takeGroups,
                timelinePlan: timelinePlan
            )
            try PipelineArtifactStore.saveAnalysis(
                projectId: projectId,
                sourceVideoURL: sourceURL,
                transcription: cleanedTranscription,
                roughCut: roughCut,
                audioAnalysis: audioResult
            )
            PipelineDiagnostics.record(
                projectId: projectId,
                stage: .roughCut,
                status: .completed,
                source: .live,
                message: "rough cut completed",
                artifactCount: roughCut.decisions.count,
                durationSeconds: Date().timeIntervalSince(roughStart),
                metadata: [
                    "cleanDuration": "\(roughCut.cleanDuration)",
                    "cutCount": "\(roughCut.cutSegments.count)",
                    "takeGroupsApplied": "\(smartResult.takeGroups.count)"
                ]
            )

            let selection = await TemplateRecommendationEngine.selectAutonomousTemplate(
                transcription: cleanedTranscription,
                roughCut: roughCut,
                audio: audioResult,
                sourceURL: sourceURL
            )
            let template = selection?.template ?? TemplateConfig.techInfluencer
            PipelineDiagnostics.record(
                projectId: projectId,
                stage: .templateSelected,
                status: .completed,
                source: .live,
                message: "debug autonomous template selected",
                metadata: [
                    "template": template.id,
                    "reason": selection?.recommendation.reason ?? "fallback",
                    "score": selection?.recommendation.score.formatted(.number.precision(.fractionLength(1))) ?? "",
                    "confidence": selection?.recommendation.confidence.formatted(.number.precision(.fractionLength(2))) ?? "",
                    "intensityLevel": selection?.intensityLevel.formatted(.number.precision(.fractionLength(2))) ?? ""
                ]
            )
            currentFailureStage = .captioned
            let captionStart = Date()
            PipelineDiagnostics.record(
                projectId: projectId,
                stage: .captioned,
                status: .running,
                source: .live,
                message: "caption generation started",
                metadata: ["template": template.id]
            )
            let captions = CaptionEngine.generateCaptions(
                from: cleanedTranscription,
                roughCut: roughCut,
                template: template
            )
            PipelineDiagnostics.record(
                projectId: projectId,
                stage: .captioned,
                status: captions.isEmpty ? .failed : .completed,
                source: .live,
                message: captions.isEmpty ? "caption generation produced no captions" : "caption generation completed",
                artifactCount: captions.count,
                durationSeconds: Date().timeIntervalSince(captionStart)
            )

            currentFailureStage = .editPlanned
            let editStart = Date()
            let editPlan = EditDecisionEngine.generateEditPlan(
                captions: captions,
                roughCut: roughCut,
                template: template,
                timelinePlan: timelinePlan
            )
            try PipelineArtifactStore.saveCaptioning(
                projectId: projectId,
                template: template,
                captions: captions,
                editPlan: editPlan
            )
            PipelineDiagnostics.record(
                projectId: projectId,
                stage: .editPlanned,
                status: editPlan.decisions.isEmpty ? .failed : .completed,
                source: .live,
                message: editPlan.decisions.isEmpty ? "edit plan generated no decisions" : "edit plan completed",
                artifactCount: editPlan.decisions.count,
                durationSeconds: Date().timeIntervalSince(editStart),
                metadata: ["averageIntensity": "\(editPlan.averageIntensity)"]
            )

            currentFailureStage = .qualityChecked
            let includedDecisions = roughCut.decisions.filter(\.isTimelineIncluded)
            let keptSegments = MeaningPreservationEngine.keptSpeechSegments(
                from: cleanedTranscription,
                roughCut: roughCut
            )
            let audioQuality = AudioQualityGuard.analyze(audioAnalysis: audioResult)
            let continuity = ContinuityChecker.check(
                keptDecisions: includedDecisions,
                profile: template.id == "tech_influencer" ? .shortFormSemantic : .sourceTimeline
            )
            let coherence = MeaningPreservationEngine.verify(
                keptSegments: keptSegments,
                allSegments: cleanedTranscription.segments.filter { isSpeechLike($0) }
            )
            let quality = QualityGateService.evaluate(
                captions: captions,
                editPlan: editPlan,
                roughCut: roughCut,
                template: template,
                transcription: cleanedTranscription,
                audioQuality: audioQuality,
                continuity: continuity,
                coherence: coherence
            )
            try PipelineArtifactStore.saveQualityReport(projectId: projectId, report: quality)
            PipelineDiagnostics.record(
                projectId: projectId,
                stage: .qualityChecked,
                status: quality.passed ? .completed : .failed,
                source: .live,
                message: quality.passed ? "quality gate completed" : "quality gate failed",
                metadata: [
                    "score": "\(quality.score)",
                    "passed": "\(quality.passed)",
                    "failedChecks": quality.failedChecks.map(\.name).joined(separator: ", "),
                    "failedCheckDetails": quality.failedChecks.map { "\($0.name): \($0.detail)" }.joined(separator: " | "),
                    "audioPeakDB": audioQuality.peakDB.formatted(.number.precision(.fractionLength(1))),
                    "audioAverageDB": audioQuality.averageDB.formatted(.number.precision(.fractionLength(1))),
                    "continuityScore": continuity.overallScore.formatted(.number.precision(.fractionLength(1))),
                    "coherenceScore": coherence.overallScore.formatted(.number.precision(.fractionLength(1)))
                ]
            )
            if !quality.passed && !CutSenseDebugRuntime.exportEvenWhenQualityFails {
                PipelineDiagnostics.record(
                    projectId: projectId,
                    stage: .exported,
                    status: .failed,
                    source: .export,
                    message: "debug export blocked by quality gate",
                    metadata: [
                        "score": "\(quality.score)",
                        "failedChecks": quality.failedChecks.map(\.name).joined(separator: ", "),
                        "failedCheckDetails": quality.failedChecks.map { "\($0.name): \($0.detail)" }.joined(separator: " | ")
                    ]
                )
                return
            }

            currentFailureStage = .exported
            let exportStart = Date()
            let exportService = ExportService()
            PipelineDiagnostics.record(
                projectId: projectId,
                stage: .exported,
                status: .running,
                source: .export,
                message: "export started"
            )

            guard let outputURL = await exportService.exportWithPipeline(
                sourceURL: sourceURL,
                decisions: roughCut.decisions,
                captions: captions,
                template: template,
                editPlan: editPlan,
                isProEntitled: SubscriptionManager.shared.isPro
            ) else {
                PipelineDiagnostics.record(
                    projectId: projectId,
                    stage: .exported,
                    status: .failed,
                    source: .export,
                    message: exportService.errorMessage ?? "export failed"
                )
                return
            }

            let fileSize = try? FileManager.default
                .attributesOfItem(atPath: outputURL.path)[.size] as? Int64
            let exportResolution = await exportResolutionString(for: outputURL)
            let verification = exportService.lastVerificationReport
            try PipelineArtifactStore.saveExport(
                projectId: projectId,
                fileURL: outputURL,
                duration: verification?.duration ?? roughCut.cleanDuration,
                resolution: verification?.resolution ?? exportResolution,
                templateName: template.name,
                fileSizeBytes: fileSize,
                qualityReport: quality,
                verificationReport: verification
            )
            PipelineDiagnostics.record(
                projectId: projectId,
                stage: .exported,
                status: .completed,
                source: .export,
                message: "export completed",
                artifactCount: 1,
                durationSeconds: Date().timeIntervalSince(exportStart),
                metadata: [
                    "outputPath": outputURL.path,
                    "fileSizeBytes": "\(fileSize ?? 0)",
                    "resolution": verification?.resolution ?? exportResolution,
                    "postExportVerified": "\(verification?.passed ?? false)",
                    "postExportFailures": verification?.failureSummary ?? ""
                ]
            )
        } catch {
            PipelineDiagnostics.record(
                projectId: projectId,
                stage: currentFailureStage,
                status: .failed,
                source: .live,
                message: error.localizedDescription
            )
        }
    }

    private static func exportResolutionString(for url: URL) async -> String {
        let asset = AVURLAsset(url: url)
        let tracks = (try? await asset.loadTracks(withMediaType: .video)) ?? []
        guard let track = tracks.first,
              let naturalSize = try? await track.load(.naturalSize),
              let transform = try? await track.load(.preferredTransform) else {
            return "unknown"
        }

        let transformed = naturalSize.applying(transform)
        let width = Int(abs(transformed.width).rounded())
        let height = Int(abs(transformed.height).rounded())
        return "\(width)x\(height)"
    }

    private static func transcribeForDebugRun(
        sourceURL: URL,
        duration: Double,
        projectId: UUID
    ) async throws -> TranscriptionResult {
        if CutSenseDebugRuntime.useSyntheticTranscript {
            let transcription = syntheticTranscription(duration: duration)
            PipelineDiagnostics.record(
                projectId: projectId,
                stage: .transcribed,
                status: .completed,
                source: .synthetic,
                message: "synthetic transcript explicitly requested for debug run",
                artifactCount: transcription.segments.count,
                metadata: ["language": transcription.language]
            )
            return transcription
        }

        let transcriptionStart = Date()
        PipelineDiagnostics.record(
            projectId: projectId,
            stage: .transcribed,
            status: .running,
            source: .live,
            message: "real speech transcription started"
        )

        do {
            let transcription = try await SpeechTranscriptionService().transcribe(url: sourceURL)
            let validated = try TranscriptionValidator.validated(transcription)
            let partialRecognition = validated.recognitionStatus.isPartial
            PipelineDiagnostics.record(
                projectId: projectId,
                stage: .transcribed,
                status: partialRecognition ? .failed : .completed,
                source: .live,
                message: partialRecognition
                    ? "real speech transcription returned \(validated.recognitionStatus.rawValue)"
                    : "real speech transcription completed",
                artifactCount: validated.segments.count,
                durationSeconds: Date().timeIntervalSince(transcriptionStart),
                metadata: [
                    "language": validated.language,
                    "overallConfidence": "\(validated.overallConfidence)",
                    "rawOverallConfidence": "\(validated.qualityConfidence)",
                    "recognitionStatus": validated.recognitionStatus.rawValue
                ]
            )
            return validated
        } catch {
            PipelineDiagnostics.record(
                projectId: projectId,
                stage: .transcribed,
                status: .failed,
                source: .live,
                message: error.localizedDescription,
                durationSeconds: Date().timeIntervalSince(transcriptionStart)
            )
            throw error
        }
    }

    private static func syntheticTranscription(duration: Double) -> TranscriptionResult {
        let safeDuration = max(duration, 8.0)

        func segment(start: Double, end: Double, text: String, confidence: Float = 0.94) -> TranscriptSegment {
            let clampedStart = min(max(0, start), max(0, safeDuration - 0.25))
            let clampedEnd = min(max(clampedStart + 0.25, end), safeDuration)
            var segment = TranscriptSegment(
                startTime: clampedStart,
                endTime: clampedEnd,
                text: text,
                confidence: confidence,
                segmentType: .contentSentence
            )
            segment.wordTimings = proportionalWordTimings(
                words: text.split(whereSeparator: \.isWhitespace).map(String.init),
                start: clampedStart,
                end: clampedEnd
            )
            return segment
        }

        let segments = [
            segment(
                start: 0.0,
                end: min(2.2, safeDuration * 0.12),
                text: "This AI tool builds apps in minutes",
                confidence: 0.96
            ),
            segment(
                start: max(2.8, safeDuration * 0.16),
                end: max(4.8, safeDuration * 0.28),
                text: "Most people waste weeks coding the wrong thing"
            ),
            segment(
                start: max(7.0, safeDuration * 0.36),
                end: max(9.4, safeDuration * 0.48),
                text: "click generate and the result appears"
            ),
            segment(
                start: max(12.0, safeDuration * 0.56),
                end: max(14.6, safeDuration * 0.66),
                text: "Vibe Coding Turkey launches the MVP faster"
            ),
            segment(
                start: max(16.0, safeDuration * 0.82),
                end: safeDuration,
                text: "follow for more and comment Vibe"
            )
        ].filter { $0.endTime > $0.startTime }

        return TranscriptionResult(
            fullText: segments.map(\.text).joined(separator: " "),
            segments: segments,
            language: "en-US",
            overallConfidence: 0.92
        )
    }

    private static func proportionalWordTimings(
        words: [String],
        start: Double,
        end: Double
    ) -> [(word: String, start: Double, duration: Double)] {
        guard !words.isEmpty else { return [] }
        let span = max(0.01, end - start)
        let weights = words.map { max(1, $0.count) }
        let totalWeight = max(1, weights.reduce(0, +))
        var cursor = start

        return words.enumerated().map { index, word in
            let duration = index == words.indices.last
                ? max(0.01, end - cursor)
                : max(0.01, span * Double(weights[index]) / Double(totalWeight))
            defer { cursor += duration }
            return (word: word, start: cursor, duration: duration)
        }
    }

    private static func isSpeechLike(_ segment: TranscriptSegment) -> Bool {
        switch segment.segmentType {
        case .speech, .contentSentence, .suspectedRestart, .suspectedDuplicate:
            return true
        case .silence, .filler, .editCommand:
            return false
        }
    }
}
#endif
