import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// On-device LLM-powered transcript analysis (iOS 26+).
/// Replaces heuristic substring matching with semantic understanding.
/// Falls back to existing engines on iOS < 26.
enum SmartTranscriptAnalyzer {
    enum AnalysisMode: String, Sendable {
        case foundationModels = "foundation_models"
        case heuristicFallback = "heuristic_fallback"
    }

    struct AnalysisOutput: Sendable {
        let cleanedSegments: [TranscriptSegment]
        let takeGroups: [TakeGroup]
        let fillersRemoved: Int
        let restartsDetected: Int
        let duplicatesDetected: Int
        let mode: AnalysisMode
        let fallbackReason: String?
    }

    struct ClassificationProgress: Sendable {
        let segmentIndex: Int
        let segmentText: String
        let intent: String
        let classified: Int
        let total: Int
    }

    static func analyze(
        segments: [TranscriptSegment],
        audioAnalysis: AudioAnalysisResult,
        userFeedback: [AiFeedbackRow] = [],
        onProgress: (@MainActor @Sendable (ClassificationProgress) -> Void)? = nil
    ) async -> AnalysisOutput {
        #if DEBUG
        if CutSenseDebugRuntime.forceHeuristicSmartAnalysis {
            return analyzeWithHeuristics(
                segments: segments,
                audioAnalysis: audioAnalysis,
                fallbackReason: "debug forced heuristic smart analysis"
            )
        }

        guard CutSenseDebugRuntime.enableFoundationModelsSmartAnalysis else {
            return analyzeWithHeuristics(
                segments: segments,
                audioAnalysis: audioAnalysis,
                fallbackReason: "Foundation Models smart analysis disabled by default after real-device timeout"
            )
        }
        #else
        return analyzeWithHeuristics(
            segments: segments,
            audioAnalysis: audioAnalysis,
            fallbackReason: "Foundation Models smart analysis disabled until bounded real-device runtime is proven"
        )
        #endif

        #if canImport(FoundationModels)
        if #available(iOS 26, *) {
            do {
                return try await withTimeout(
                    for: llmTimeout(forSegmentCount: segments.count)
                ) {
                    try await analyzeWithLLM(
                        segments: segments,
                        audioAnalysis: audioAnalysis,
                        userFeedback: userFeedback,
                        onProgress: onProgress
                    )
                }
            } catch {
                #if DEBUG
                print("[CutSense] LLM analysis failed, falling back to heuristics: \(error.localizedDescription)")
                #endif
                return analyzeWithHeuristics(
                    segments: segments,
                    audioAnalysis: audioAnalysis,
                    fallbackReason: error.localizedDescription
                )
            }
        }
        #endif
        return analyzeWithHeuristics(
            segments: segments,
            audioAnalysis: audioAnalysis,
            fallbackReason: nil
        )
    }

    // MARK: - Heuristic Fallback

    private static func analyzeWithHeuristics(
        segments: [TranscriptSegment],
        audioAnalysis: AudioAnalysisResult,
        fallbackReason: String?
    ) -> AnalysisOutput {
        let cleanup = TranscriptCleanupAnalyzer.analyze(segments)
        let takeGroups = TakeDetectionEngine.detectTakeGroups(segments: cleanup.segments)
        return AnalysisOutput(
            cleanedSegments: cleanup.segments,
            takeGroups: takeGroups,
            fillersRemoved: cleanup.fillersRemoved,
            restartsDetected: cleanup.restartsDetected,
            duplicatesDetected: cleanup.duplicatesDetected,
            mode: .heuristicFallback,
            fallbackReason: fallbackReason
        )
    }
}

// MARK: - Foundation Models (iOS 26+)

#if canImport(FoundationModels)
@available(iOS 26, *)
extension SmartTranscriptAnalyzer {
    private struct FoundationModelsTimeoutError: LocalizedError {
        let seconds: Int

        var errorDescription: String? {
            "Foundation Models analysis timed out after \(seconds) seconds."
        }
    }

    private final class TimeoutCoordinator<Output: Sendable>: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Output, any Error>?
        private var result: Result<Output, any Error>?
        private var didFinish = false

        func register(_ continuation: CheckedContinuation<Output, any Error>) {
            lock.lock()
            if let result {
                lock.unlock()
                continuation.resume(with: result)
                return
            }
            self.continuation = continuation
            lock.unlock()
        }

        func finish(_ result: Result<Output, any Error>) {
            lock.lock()
            guard !didFinish else {
                lock.unlock()
                return
            }
            didFinish = true
            if let continuation {
                self.continuation = nil
                lock.unlock()
                continuation.resume(with: result)
            } else {
                self.result = result
                lock.unlock()
            }
        }
    }

    @Generable
    enum SegmentIntent: String, Sendable {
        case content
        case editCommand
        case filler
        case restart
        case duplicate
    }

    @Generable
    struct SegmentClassification: Sendable {
        @Guide(description: "The purpose of this transcript segment: content (real speech to keep), editCommand (speaker directing editor to cut/redo), filler (um/uh/şey/yani with no content), restart (false start that is repeated better next), duplicate (near-identical to adjacent segment)")
        var intent: SegmentIntent

        @Guide(description: "Confidence from 0.0 to 1.0")
        var confidence: Float

        @Guide(description: "One sentence reason for classification")
        var reason: String
    }

    @Generable
    struct BatchClassification: Sendable {
        @Guide(description: "Classification for each numbered segment, in order. Must have exactly the same count as input segments.")
        var results: [SegmentClassification]
    }

    private static func analyzeWithLLM(
        segments: [TranscriptSegment],
        audioAnalysis: AudioAnalysisResult,
        userFeedback: [AiFeedbackRow],
        onProgress: (@MainActor @Sendable (ClassificationProgress) -> Void)?
    ) async throws -> AnalysisOutput {
        guard !segments.isEmpty else {
            return AnalysisOutput(
                cleanedSegments: [],
                takeGroups: [],
                fillersRemoved: 0,
                restartsDetected: 0,
                duplicatesDetected: 0,
                mode: .foundationModels,
                fallbackReason: nil
            )
        }

        let fullPrompt = buildSystemPromptWithFeedback(userFeedback)
        let session = LanguageModelSession {
            Instructions(fullPrompt)
        }

        let batchSize = 15
        var allClassifications: [SegmentClassification] = []
        let totalSegments = segments.count

        for batchStart in stride(from: 0, to: segments.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, segments.count)
            let batch = Array(segments[batchStart..<batchEnd])
            let prompt = buildBatchPrompt(batch, offset: batchStart)

            if let onProgress {
                // Stream for real-time UI updates
                let stream = session.streamResponse(
                    to: prompt,
                    generating: BatchClassification.self
                )
                var lastSeenCount = 0
                var finalResults: [SegmentClassification] = []

                for try await snapshot in stream {
                    if let partialResults = snapshot.content.results {
                        let currentCount = min(partialResults.count, batch.count)
                        // Report newly completed classifications
                        while lastSeenCount < currentCount {
                            let partial = partialResults[lastSeenCount]
                            if let intent = partial.intent {
                                let segIdx = batchStart + lastSeenCount
                                let progress = ClassificationProgress(
                                    segmentIndex: segIdx,
                                    segmentText: segments[segIdx].text,
                                    intent: intent.rawValue,
                                    classified: allClassifications.count + lastSeenCount + 1,
                                    total: totalSegments
                                )
                                await onProgress(progress)
                            }
                            lastSeenCount += 1
                        }
                        // Keep updating final results from the latest complete snapshot
                        finalResults = partialResults.prefix(batch.count).compactMap { partial in
                            guard let intent = partial.intent else { return nil }
                            return SegmentClassification(
                                intent: intent,
                                confidence: partial.confidence ?? 0.5,
                                reason: partial.reason ?? ""
                            )
                        }
                    }
                }

                // Pad to match batch size
                while finalResults.count < batch.count {
                    finalResults.append(SegmentClassification(intent: .content, confidence: 0.5, reason: "Review: LLM did not classify"))
                }
                allClassifications.append(contentsOf: finalResults.prefix(batch.count))
            } else {
                // Non-streaming path
                let response = try await session.respond(
                    to: prompt,
                    generating: BatchClassification.self
                )
                var batchResults = response.content.results
                while batchResults.count < batch.count {
                    batchResults.append(SegmentClassification(intent: .content, confidence: 0.5, reason: "Review: LLM did not classify"))
                }
                allClassifications.append(contentsOf: batchResults.prefix(batch.count))
            }
        }

        return buildOutput(segments: segments, classifications: allClassifications, audioAnalysis: audioAnalysis)
    }

    private static func llmTimeout(forSegmentCount segmentCount: Int) -> Duration {
        let seconds = min(max(segmentCount * 2, 12), 45)
        return .seconds(seconds)
    }

    private static func withTimeout<Output: Sendable>(
        for duration: Duration,
        operation: @Sendable @escaping () async throws -> Output
    ) async throws -> Output {
        let coordinator = TimeoutCoordinator<Output>()
        let operationTask = Task {
            do {
                let output = try await operation()
                coordinator.finish(.success(output))
            } catch {
                coordinator.finish(.failure(error))
            }
        }

        let timeoutTask = Task {
            do {
                try await Task.sleep(for: duration)
                operationTask.cancel()
                coordinator.finish(.failure(FoundationModelsTimeoutError(seconds: durationSeconds(duration))))
            } catch {
                // Timeout task was cancelled because the operation completed first.
            }
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                coordinator.register(continuation)
            }
        } onCancel: {
            operationTask.cancel()
            timeoutTask.cancel()
            coordinator.finish(.failure(CancellationError()))
        }
    }

    private static func durationSeconds(_ duration: Duration) -> Int {
        let components = duration.components
        let seconds = components.seconds
        if components.attoseconds > 0 {
            return Int(seconds) + 1
        }
        return Int(seconds)
    }

    private static var systemPrompt: String {
        """
        You are a video editor's AI assistant analyzing transcript segments from a talking-head video recording.
        Your job is to classify each segment so the editor knows what to keep and what to cut.

        The speaker records in Turkish or English. They sometimes:
        - Give edit commands to the editor: "baştan alıyorum", "bunu kes", "tekrar alayım", "cut that", "start over", "let me redo"
        - Say filler words with no content value: "şey", "yani", "hani", "ıı", "eee", "um", "uh", "like", "you know"
        - False-start a sentence and restart it better (the first attempt should be cut)
        - Repeat themselves almost identically (the duplicate should be cut)
        - Speak actual content that must be kept

        CRITICAL RULES — READ CAREFULLY:
        1. DEFAULT IS CONTENT. Only classify as non-content when you are VERY sure.
        2. "kes" in "kese kağıdı" (paper bag) = CONTENT. Judge by MEANING, not substring.
        3. "baştan" in "baştan beri söylüyorum" = CONTENT. Context matters.
        4. Words like "yani", "aslında", "mesela", "işte", "hani" are Turkish discourse connectors. They are CONTENT, NOT fillers — people use them naturally when speaking.
        5. FILLERS are ONLY pure non-words: "ıı", "eee", "mmm", "um", "uh" — and ONLY when they appear alone, not inside a sentence.
        6. editCommand = ONLY explicit verbal commands to editor: "baştan alıyorum", "bunu kes", "cut that". Not content about editing or cutting.
        7. restart = ONLY when the speaker clearly stops mid-sentence and immediately re-says the same thing better. The first attempt must be INCOMPLETE.
        8. duplicate = ONLY near-identical repetition of the same full sentence.
        9. WHEN IN DOUBT → content. It is much worse to cut real speech than to keep a filler.
        """
    }

    private static func buildSystemPromptWithFeedback(_ feedback: [AiFeedbackRow]) -> String {
        guard !feedback.isEmpty else { return systemPrompt }

        // Group corrections where user disagreed with AI
        let corrections = feedback.filter { row in
            // AI said cut but user restored, or AI said keep but user cut
            (row.aiClassification != "keep" && row.userAction == "keep") ||
            (row.aiClassification == "keep" && row.userAction == "cut")
        }.prefix(5) // Max 5 few-shot examples

        guard !corrections.isEmpty else { return systemPrompt }

        var examples = "\n\nLEARN FROM PAST CORRECTIONS — the user previously overrode these classifications:\n"
        for (i, correction) in corrections.enumerated() {
            let aiSaid = correction.aiClassification
            let userWanted = correction.userAction == "keep" ? "content" : "filler"
            examples += "[\(i + 1)] \"\(correction.segmentText)\" — AI said \(aiSaid) but user wanted \(userWanted)"
            if let reason = correction.aiReason {
                examples += " (AI reason: \(reason))"
            }
            examples += "\n"
        }
        examples += "\nUse these corrections to avoid similar mistakes. When in doubt, lean toward what the user prefers."

        return systemPrompt + examples
    }

    private static func buildBatchPrompt(_ segments: [TranscriptSegment], offset: Int) -> String {
        var lines: [String] = ["Classify each segment:\n"]
        for (i, seg) in segments.enumerated() {
            let idx = offset + i + 1
            let start = seg.startTime.formatted(.number.precision(.fractionLength(1)))
            let end = seg.endTime.formatted(.number.precision(.fractionLength(1)))
            lines.append("[\(idx)] [\(start)s-\(end)s] \"\(seg.text)\"")
        }
        return lines.joined(separator: "\n")
    }

    private static func buildOutput(
        segments: [TranscriptSegment],
        classifications: [SegmentClassification],
        audioAnalysis: AudioAnalysisResult
    ) -> AnalysisOutput {
        var cleaned: [TranscriptSegment] = []
        var fillersRemoved = 0
        var restartsDetected = 0
        var duplicatesDetected = 0

        for (segment, classification) in zip(segments, classifications) {
            var modified = segment
            modified.aiConfidence = classification.confidence
            modified.aiReason = classification.reason

            switch classification.intent {
            case .filler:
                modified.segmentType = .filler
                fillersRemoved += 1
            case .editCommand:
                modified.segmentType = .editCommand
                fillersRemoved += 1
            case .restart:
                modified.segmentType = .suspectedRestart
                restartsDetected += 1
            case .duplicate:
                modified.segmentType = .suspectedDuplicate
                duplicatesDetected += 1
            case .content:
                modified.segmentType = .contentSentence
            }

            cleaned.append(modified)
        }

        let takeGroups = TakeDetectionEngine.detectTakeGroups(segments: cleaned)

        return AnalysisOutput(
            cleanedSegments: cleaned,
            takeGroups: takeGroups,
            fillersRemoved: fillersRemoved,
            restartsDetected: restartsDetected,
            duplicatesDetected: duplicatesDetected,
            mode: .foundationModels,
            fallbackReason: nil
        )
    }
}
#endif
