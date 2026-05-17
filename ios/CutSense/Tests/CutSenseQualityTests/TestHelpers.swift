import Foundation
@testable import CutSense

// MARK: - Factory helpers for building test fixtures without boilerplate

enum TestFixture {
    static func segment(
        start: Double,
        end: Double,
        text: String,
        confidence: Float = 0.95,
        type: TranscriptSegment.SegmentType = .speech,
        aiConfidence: Float? = nil,
        aiReason: String? = nil
    ) -> TranscriptSegment {
        var seg = TranscriptSegment(
            startTime: start,
            endTime: end,
            text: text,
            confidence: confidence,
            segmentType: type
        )
        seg.aiConfidence = aiConfidence
        seg.aiReason = aiReason
        return seg
    }

    static func transcription(
        segments: [TranscriptSegment],
        language: String = "tr-TR"
    ) -> TranscriptionResult {
        let fullText = segments.map(\.text).joined(separator: " ")
        let avgConf = segments.isEmpty ? 0 : segments.map(\.confidence).reduce(0, +) / Float(segments.count)
        return TranscriptionResult(
            fullText: fullText,
            segments: segments,
            language: language,
            overallConfidence: avgConf
        )
    }

    static func audioResult(
        duration: Double,
        silenceIntervals: [ClosedRange<Double>] = []
    ) -> AudioAnalysisResult {
        AudioAnalysisResult(
            segments: [],
            silenceIntervals: silenceIntervals,
            averageEnergy: 0.1,
            peakEnergy: 0.5,
            duration: duration
        )
    }

    static func caption(
        start: Double,
        end: Double,
        text: String,
        role: CaptionRole = .regular,
        style: CaptionStyle = .premiumLowerThird,
        behavior: CaptionSceneBehavior = .none
    ) -> CaptionSegment {
        CaptionSegment(
            startTime: start,
            endTime: end,
            text: text,
            role: role,
            style: style,
            sceneBehavior: behavior
        )
    }

    static func editDecision(
        time: Double,
        duration: Double = 0.5,
        type: EditType = .zoom,
        reason: String = "Test",
        intensity: Float = 0.5
    ) -> EditDecision {
        EditDecision(
            time: time,
            duration: duration,
            type: type,
            reason: reason,
            intensity: intensity
        )
    }

    static func roughCutResult(
        decisions: [RoughCutDecision],
        originalDuration: Double,
        cleanDuration: Double
    ) -> RoughCutResult {
        let keeps = decisions.filter { $0.action == .keep }
        let cuts = decisions.filter { $0.action == .cut }
        let reviews = decisions.filter { $0.action == .reviewRequired }
        return RoughCutResult(
            decisions: decisions,
            originalDuration: originalDuration,
            cleanDuration: cleanDuration,
            keepSegments: keeps,
            cutSegments: cuts,
            reviewSegments: reviews
        )
    }

    /// Build a simple RoughCutResult where all segments are kept
    static func roughCutAllKept(
        segments: [TranscriptSegment],
        originalDuration: Double
    ) -> RoughCutResult {
        let decisions = segments.map {
            RoughCutDecision(
                startTime: $0.startTime,
                endTime: $0.endTime,
                action: .keep,
                reason: "Content",
                confidence: 0.95,
                linkedTranscriptText: $0.text,
                requiresReview: false
            )
        }
        let cleanDuration = segments.reduce(0.0) { $0 + ($1.endTime - $1.startTime) }
        return roughCutResult(
            decisions: decisions,
            originalDuration: originalDuration,
            cleanDuration: cleanDuration
        )
    }
}
