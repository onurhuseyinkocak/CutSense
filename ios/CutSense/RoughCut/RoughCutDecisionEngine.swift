import Foundation

struct RoughCutDecision: Sendable, Identifiable {
    let id = UUID()
    let startTime: Double
    let endTime: Double
    let action: CutAction
    let reason: String
    let confidence: Float
    let linkedTranscriptText: String?
    let requiresReview: Bool
}

enum CutAction: String, Sendable {
    case keep
    case cut
    case trimStart = "trim_start"
    case trimEnd = "trim_end"
    case replaceWithBetterTake = "replace_with_better_take"
    case mergeWithNext = "merge_with_next"
    case addAudioFade = "add_audio_fade"
    case reviewRequired = "review_required"
}

struct RoughCutResult: Sendable {
    let decisions: [RoughCutDecision]
    let originalDuration: Double
    let cleanDuration: Double
    let keepSegments: [RoughCutDecision]
    let cutSegments: [RoughCutDecision]
    let reviewSegments: [RoughCutDecision]
}

enum RoughCutDecisionEngine {
    /// Silence thresholds (seconds)
    private static let maxIntraSpeechSilence: Double = 0.35
    private static let maxInterIdeaSilence: Double = 0.55
    /// Breathing room to keep around speech (seconds)
    private static let breathingRoom: Double = 0.10

    static func generateDecisions(
        transcription: TranscriptionResult,
        audioAnalysis: AudioAnalysisResult
    ) -> RoughCutResult {
        var decisions: [RoughCutDecision] = []

        // Analyze each transcript segment
        for (index, segment) in transcription.segments.enumerated() {
            let prev = index > 0 ? transcription.segments[index - 1] : nil
            let next = index < transcription.segments.count - 1 ? transcription.segments[index + 1] : nil

            // Run edit command detection
            let analysis = ContextAwareEditCommandDetector.analyze(
                segment: segment,
                previousSegment: prev,
                nextSegment: next,
                audioResult: audioAnalysis
            )

            switch analysis.intent {
            case .editCommand:
                decisions.append(RoughCutDecision(
                    startTime: segment.startTime,
                    endTime: segment.endTime,
                    action: .cut,
                    reason: analysis.reason,
                    confidence: analysis.confidence,
                    linkedTranscriptText: segment.text,
                    requiresReview: false
                ))

            case .uncertain:
                decisions.append(RoughCutDecision(
                    startTime: segment.startTime,
                    endTime: segment.endTime,
                    action: .reviewRequired,
                    reason: analysis.reason,
                    confidence: analysis.confidence,
                    linkedTranscriptText: segment.text,
                    requiresReview: true
                ))

            case .contentSentence:
                decisions.append(RoughCutDecision(
                    startTime: segment.startTime,
                    endTime: segment.endTime,
                    action: .keep,
                    reason: analysis.reason,
                    confidence: analysis.confidence,
                    linkedTranscriptText: segment.text,
                    requiresReview: false
                ))
            }
        }

        // Process silence intervals
        for silence in audioAnalysis.silenceIntervals {
            let duration = silence.upperBound - silence.lowerBound

            if duration > maxInterIdeaSilence {
                // Long silence between ideas — trim but keep breathing room
                let trimmedStart = silence.lowerBound + breathingRoom
                let trimmedEnd = silence.upperBound - breathingRoom

                if trimmedEnd > trimmedStart {
                    decisions.append(RoughCutDecision(
                        startTime: trimmedStart,
                        endTime: trimmedEnd,
                        action: .cut,
                        reason: "Silence exceeds \(String(format: "%.1f", maxInterIdeaSilence))s threshold (\(String(format: "%.1f", duration))s)",
                        confidence: 0.85,
                        linkedTranscriptText: nil,
                        requiresReview: false
                    ))
                }
            } else if duration > maxIntraSpeechSilence {
                // Medium silence inside speech — trim gently
                let trimmedStart = silence.lowerBound + breathingRoom
                let trimmedEnd = silence.upperBound - breathingRoom

                if trimmedEnd > trimmedStart {
                    decisions.append(RoughCutDecision(
                        startTime: trimmedStart,
                        endTime: trimmedEnd,
                        action: .trimStart,
                        reason: "Intra-speech silence (\(String(format: "%.1f", duration))s) — trimming gently",
                        confidence: 0.70,
                        linkedTranscriptText: nil,
                        requiresReview: false
                    ))
                }
            }
        }

        // Split keep segments that overlap with silence cuts
        decisions = subtractCutsFromKeeps(decisions)

        // Sort by start time
        decisions.sort { $0.startTime < $1.startTime }

        return buildResult(decisions: decisions, originalDuration: audioAnalysis.duration)
    }

    /// Apply take group results: mark non-best takes as cut
    static func applyTakeGroups(
        _ takeGroups: [TakeGroup],
        to result: RoughCutResult
    ) -> RoughCutResult {
        guard !takeGroups.isEmpty else { return result }

        var decisions = result.decisions

        for group in takeGroups {
            for (takeIndex, take) in group.takes.enumerated() {
                guard takeIndex != group.bestTakeIndex else { continue }

                // Find the decision that covers this non-best take and mark it as cut
                if let decisionIndex = decisions.firstIndex(where: { decision in
                    decision.action == .keep &&
                    abs(decision.startTime - take.startTime) < 0.2
                }) {
                    let old = decisions[decisionIndex]
                    decisions[decisionIndex] = RoughCutDecision(
                        startTime: old.startTime,
                        endTime: old.endTime,
                        action: .cut,
                        reason: "Non-best take (group has \(group.takes.count) takes, best is #\(group.bestTakeIndex + 1))",
                        confidence: 0.85,
                        linkedTranscriptText: old.linkedTranscriptText,
                        requiresReview: false
                    )
                }
            }
        }

        return buildResult(decisions: decisions, originalDuration: result.originalDuration)
    }

    /// Splits keep segments around overlapping cut/trim segments so timeline builder
    /// actually removes silences from within speech segments.
    private static func subtractCutsFromKeeps(_ decisions: [RoughCutDecision]) -> [RoughCutDecision] {
        let cuts = decisions.filter { $0.action == .cut || $0.action == .trimStart || $0.action == .trimEnd }
        let keeps = decisions.filter { $0.action == .keep }
        var nonKeeps = decisions.filter { $0.action != .keep }

        for keep in keeps {
            // Find cuts that overlap this keep segment
            let overlapping = cuts.filter { cut in
                cut.startTime < keep.endTime && cut.endTime > keep.startTime
            }.sorted { $0.startTime < $1.startTime }

            guard !overlapping.isEmpty else {
                nonKeeps.append(keep)
                continue
            }

            // Split the keep segment around each cut
            var cursor = keep.startTime
            for cut in overlapping {
                let cutStart = max(cut.startTime, keep.startTime)
                let cutEnd = min(cut.endTime, keep.endTime)

                // Keep region before this cut
                if cursor < cutStart && cutStart - cursor > 0.05 {
                    nonKeeps.append(RoughCutDecision(
                        startTime: cursor,
                        endTime: cutStart,
                        action: .keep,
                        reason: keep.reason,
                        confidence: keep.confidence,
                        linkedTranscriptText: keep.linkedTranscriptText,
                        requiresReview: false
                    ))
                }
                cursor = cutEnd
            }

            // Keep region after last cut
            if cursor < keep.endTime && keep.endTime - cursor > 0.05 {
                nonKeeps.append(RoughCutDecision(
                    startTime: cursor,
                    endTime: keep.endTime,
                    action: .keep,
                    reason: keep.reason,
                    confidence: keep.confidence,
                    linkedTranscriptText: keep.linkedTranscriptText,
                    requiresReview: false
                ))
            }
        }

        return nonKeeps
    }

    private static func buildResult(
        decisions: [RoughCutDecision],
        originalDuration: Double
    ) -> RoughCutResult {
        let cutDuration = decisions
            .filter { $0.action == .cut || $0.action == .trimStart || $0.action == .trimEnd }
            .reduce(0.0) { $0 + ($1.endTime - $1.startTime) }
        let cleanDuration = max(originalDuration - cutDuration, 0)

        return RoughCutResult(
            decisions: decisions,
            originalDuration: originalDuration,
            cleanDuration: cleanDuration,
            keepSegments: decisions.filter { $0.action == .keep },
            cutSegments: decisions.filter { $0.action == .cut || $0.action == .trimStart || $0.action == .trimEnd },
            reviewSegments: decisions.filter { $0.requiresReview }
        )
    }
}
