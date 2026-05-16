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
    private static let maxIntraSpeechSilence: Double = 0.45
    private static let maxInterIdeaSilence: Double = 0.70
    /// Breathing room to keep around speech (seconds)
    private static let breathingRoom: Double = 0.15

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

        // Sort by start time
        decisions.sort { $0.startTime < $1.startTime }

        // Compute durations
        let originalDuration = audioAnalysis.duration
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
