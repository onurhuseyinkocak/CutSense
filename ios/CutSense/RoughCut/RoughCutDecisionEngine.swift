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
    /// Silence thresholds (seconds) — tuned for social media pacing
    private static let maxIntraSpeechSilence: Double = 0.40
    private static let maxInterIdeaSilence: Double = 0.7
    /// Breathing room to keep around speech (seconds)
    private static let breathingRoom: Double = 0.10

    static func generateDecisions(
        transcription: TranscriptionResult,
        audioAnalysis: AudioAnalysisResult
    ) -> RoughCutResult {
        var decisions: [RoughCutDecision] = []

        // Analyze each transcript segment
        for (index, segment) in transcription.segments.enumerated() {
            // Handle segments classified by SmartTranscriptAnalyzer / heuristics
            let aiConf = segment.aiConfidence
            let lowConfidence = aiConf != nil && aiConf! < 0.7

            switch segment.segmentType {
            case .filler:
                let reason = segment.aiReason ?? "Filler word detected"
                let fillerDuration = segment.endTime - segment.startTime
                // Only cut fillers if they're pure short fillers (< 1s) and high confidence
                // Longer "fillers" are often misclassified content
                if fillerDuration > 1.0 || lowConfidence {
                    decisions.append(RoughCutDecision(
                        startTime: segment.startTime,
                        endTime: segment.endTime,
                        action: .reviewRequired,
                        reason: fillerDuration > 1.0 ? "Long filler — likely content: \(reason)" : "AI uncertain: \(reason)",
                        confidence: aiConf ?? 0.50,
                        linkedTranscriptText: segment.text,
                        requiresReview: true
                    ))
                } else {
                    decisions.append(RoughCutDecision(
                        startTime: segment.startTime,
                        endTime: segment.endTime,
                        action: .cut,
                        reason: reason,
                        confidence: aiConf ?? 0.90,
                        linkedTranscriptText: segment.text,
                        requiresReview: false
                    ))
                }
                continue
            case .suspectedRestart:
                let reason = segment.aiReason ?? "Suspected restart — cleaner take follows"
                // Restarts should always go to review unless AI is very confident (>= 0.85)
                let highConfRestart = aiConf != nil && aiConf! >= 0.85
                decisions.append(RoughCutDecision(
                    startTime: segment.startTime,
                    endTime: segment.endTime,
                    action: highConfRestart ? .cut : .reviewRequired,
                    reason: highConfRestart ? reason : "Review: \(reason)",
                    confidence: aiConf ?? 0.60,
                    linkedTranscriptText: segment.text,
                    requiresReview: !highConfRestart
                ))
                continue
            case .suspectedDuplicate:
                let reason = segment.aiReason ?? "Duplicate content detected"
                decisions.append(RoughCutDecision(
                    startTime: segment.startTime,
                    endTime: segment.endTime,
                    action: lowConfidence ? .reviewRequired : .cut,
                    reason: lowConfidence ? "AI uncertain: \(reason)" : reason,
                    confidence: aiConf ?? 0.75,
                    linkedTranscriptText: segment.text,
                    requiresReview: lowConfidence || aiConf == nil
                ))
                continue
            case .contentSentence where lowConfidence:
                let reason = segment.aiReason ?? "Content (low confidence)"
                decisions.append(RoughCutDecision(
                    startTime: segment.startTime,
                    endTime: segment.endTime,
                    action: .keep,
                    reason: "AI uncertain: \(reason)",
                    confidence: aiConf ?? 0.50,
                    linkedTranscriptText: segment.text,
                    requiresReview: true
                ))
                continue
            case .speech, .silence, .contentSentence:
                break // Fall through to edit command detection
            }

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

        // Process silence intervals — only cut clearly excessive silences
        for silence in audioAnalysis.silenceIntervals {
            let duration = silence.upperBound - silence.lowerBound

            if duration > maxInterIdeaSilence {
                // Long silence between ideas — trim but keep generous breathing room
                let trimmedStart = silence.lowerBound + breathingRoom
                // Keep a natural pause at the end (0.3s feels organic)
                let trimmedEnd = silence.upperBound - max(breathingRoom, 0.3)

                if trimmedEnd > trimmedStart + 0.1 {
                    decisions.append(RoughCutDecision(
                        startTime: trimmedStart,
                        endTime: trimmedEnd,
                        action: .cut,
                        reason: "Long silence (\(String(format: "%.1f", duration))s)",
                        confidence: 0.85,
                        linkedTranscriptText: nil,
                        requiresReview: false
                    ))
                }
            }
            // Medium silences (0.4-0.7s) are natural pauses — DON'T trim them
            // They give the video breathing room and feel natural
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
        let keepSegments = decisions.filter { $0.action == .keep }
        let cleanDuration = keepSegments.reduce(0.0) { $0 + ($1.endTime - $1.startTime) }

        return RoughCutResult(
            decisions: decisions,
            originalDuration: originalDuration,
            cleanDuration: cleanDuration,
            keepSegments: keepSegments,
            cutSegments: decisions.filter { $0.action == .cut || $0.action == .trimStart || $0.action == .trimEnd },
            reviewSegments: decisions.filter { $0.requiresReview }
        )
    }
}
