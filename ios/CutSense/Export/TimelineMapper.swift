import Foundation

enum TimelineMapper {
    struct Segment: Sendable, Equatable {
        let sourceStart: Double
        let sourceEnd: Double
        let cleanStart: Double
        var duration: Double { sourceEnd - sourceStart }
    }

    /// Build source→clean time mapping from timeline-included decisions.
    static func buildMapping(from decisions: [RoughCutDecision]) -> [Segment] {
        buildMapping(from: TimelineRangeNormalizer.includedRanges(from: decisions))
    }

    /// Build source→clean time mapping from the exact ranges used by CleanTimelineBuilder.
    static func buildMapping(from ranges: [TimelineRange]) -> [Segment] {
        var mapping: [Segment] = []
        var cleanOffset: Double = 0

        for range in ranges {
            mapping.append(Segment(
                sourceStart: range.startTime,
                sourceEnd: range.endTime,
                cleanStart: cleanOffset
            ))
            cleanOffset += range.duration
        }

        return mapping
    }

    /// Map a single source time to clean timeline time. Returns nil if time falls in a cut region.
    static func mapToClean(_ sourceTime: Double, mapping: [Segment], tolerance: Double = 0.001) -> Double? {
        for seg in mapping {
            if sourceTime >= seg.sourceStart - tolerance && sourceTime <= seg.sourceEnd + tolerance {
                let clampedSourceTime = min(max(sourceTime, seg.sourceStart), seg.sourceEnd)
                return seg.cleanStart + (clampedSourceTime - seg.sourceStart)
            }
        }
        return nil
    }

    /// Remap captions from source to clean timeline coordinates.
    /// Critically also remaps wordTimings so karaoke stays aligned with audio.
    static func remapCaptions(_ captions: [CaptionSegment], mapping: [Segment]) -> [CaptionSegment] {
        // Empty mapping means no cuts were made — all captions pass through unchanged
        if mapping.isEmpty { return captions }

        return captions.flatMap { caption in
            let segments = overlappingSegments(
                sourceStart: caption.startTime,
                sourceEnd: caption.endTime,
                mapping: mapping
            )

            return segments.enumerated().compactMap { index, segment in
                remapCaption(caption, into: segment, mapping: mapping, splitIndex: index)
            }
        }
    }

    /// Remap edit decisions from source to clean timeline coordinates
    static func remapEditDecisions(_ decisions: [EditDecision], mapping: [Segment]) -> [EditDecision] {
        if mapping.isEmpty { return decisions }

        return decisions.compactMap { decision in
            remapEditDecision(decision, mapping: mapping)
        }
    }

    /// Remap transcript segments from source to clean timeline coordinates so
    /// semantic edit-plan verification uses the same coordinates as export.
    static func remapTranscription(_ transcription: TranscriptionResult, mapping: [Segment]) -> TranscriptionResult {
        guard !mapping.isEmpty else { return transcription }

        let segments = transcription.segments.flatMap { segment in
            let overlaps = overlappingSegments(
                sourceStart: segment.startTime,
                sourceEnd: segment.endTime,
                mapping: mapping
            )
            return overlaps.compactMap { overlap in
                remapTranscriptSegment(segment, into: overlap, mapping: mapping)
            }
        }

        return TranscriptionResult(
            fullText: segments.map(\.text).joined(separator: " "),
            segments: segments,
            language: transcription.language,
            overallConfidence: transcription.overallConfidence,
            rawOverallConfidence: transcription.rawOverallConfidence,
            recognitionStatus: transcription.recognitionStatus
        )
    }

    static func exportReadyCaptions(
        _ captions: [CaptionSegment],
        totalDuration: Double,
        minimumDuration: Double = 0.5
    ) -> [CaptionSegment] {
        guard !captions.isEmpty else { return [] }

        let clamped = captions.compactMap { caption -> CaptionSegment? in
            var fixed = caption
            fixed.startTime = max(0, fixed.startTime)
            if totalDuration.isFinite, totalDuration > 0 {
                fixed.endTime = min(totalDuration, fixed.endTime)
            }
            fixed = clampWordTimings(in: fixed)
            guard fixed.endTime - fixed.startTime >= minimumDuration else {
                return nil
            }
            return fixed
        }

        let resolved = resolveOverlaps(clamped)
        return resolved.compactMap { caption in
            guard caption.endTime - caption.startTime >= minimumDuration else {
                return nil
            }
            return clampWordTimings(in: caption)
        }
    }

    private static func remapEditDecision(_ decision: EditDecision, mapping: [Segment]) -> EditDecision? {
        if let segment = segment(containing: decision.time, mapping: mapping) {
            let cleanTime = segment.cleanStart + (decision.time - segment.sourceStart)
            let sourceEnd = min(decision.time + max(0, decision.duration), segment.sourceEnd)
            let cleanEnd = segment.cleanStart + (sourceEnd - segment.sourceStart)
            return copyDecision(decision, time: cleanTime, duration: cleanEnd - cleanTime)
        }

        if let firstSegment = mapping.sorted(by: { $0.sourceStart < $1.sourceStart }).first,
           decision.time < firstSegment.sourceStart,
           shouldAnchorToCleanIntro(decision) {
            let cleanTime = decision.type == .sfx ? firstSegment.cleanStart + 0.05 : firstSegment.cleanStart
            return copyDecision(decision, time: cleanTime, duration: decision.duration)
        }

        // Some effects intentionally start slightly before the caption they introduce
        // (e.g. transition whoosh / whip zoom). If that pre-roll lands in a removed
        // silence gap, keep the cue by anchoring it just before the next clean segment.
        guard decision.duration.isFinite, decision.duration > 0 else { return nil }

        for segment in mapping.sorted(by: { $0.sourceStart < $1.sourceStart }) {
            let startsInCutBeforeSegment = decision.time < segment.sourceStart
            let overlapsSegmentStart = decision.time + decision.duration > segment.sourceStart
            guard startsInCutBeforeSegment && overlapsSegmentStart else { continue }

            let leadIn = segment.sourceStart - decision.time
            let cleanTime = max(0, segment.cleanStart - leadIn)
            let sourceEnd = min(decision.time + max(0, decision.duration), segment.sourceEnd)
            let cleanEnd = segment.cleanStart + max(0, sourceEnd - segment.sourceStart)
            return copyDecision(decision, time: cleanTime, duration: cleanEnd - cleanTime)
        }

        return nil
    }

    private static func segment(containing sourceTime: Double, mapping: [Segment]) -> Segment? {
        mapping.first { segment in
            sourceTime >= segment.sourceStart && sourceTime <= segment.sourceEnd
        }
    }

    private static func copyDecision(
        _ decision: EditDecision,
        time: Double,
        duration: Double
    ) -> EditDecision? {
        let clippedDuration = min(decision.duration, duration)
        guard clippedDuration.isFinite, clippedDuration >= 0.05 else {
            return nil
        }

        return EditDecision(
            time: max(0, time),
            duration: clippedDuration,
            type: decision.type,
            reason: decision.reason,
            intensity: decision.intensity
        )
    }

    private static func shouldAnchorToCleanIntro(_ decision: EditDecision) -> Bool {
        let reason = decision.reason.lowercased()
        return reason.contains("hook") || reason.contains("intro")
    }

    /// Resolve overlapping captions after remapping.
    /// If two captions overlap in time, the earlier one's endTime is clamped to the later one's startTime.
    static func resolveOverlaps(_ captions: [CaptionSegment]) -> [CaptionSegment] {
        guard captions.count > 1 else { return captions }

        var sorted = captions.sorted { $0.startTime < $1.startTime }
        let minimumDuration = 0.1

        for i in 0..<(sorted.count - 1) {
            if sorted[i].endTime > sorted[i + 1].startTime {
                let minimumEnd = sorted[i].startTime + minimumDuration
                if sorted[i + 1].startTime < minimumEnd {
                    sorted[i + 1].startTime = minimumEnd
                    if sorted[i + 1].endTime < sorted[i + 1].startTime + minimumDuration {
                        sorted[i + 1].endTime = sorted[i + 1].startTime + minimumDuration
                    }
                }
                sorted[i].endTime = min(sorted[i].endTime, sorted[i + 1].startTime)
                sorted[i] = clampWordTimings(in: sorted[i])
                sorted[i + 1] = clampWordTimings(in: sorted[i + 1])
            }
        }

        return sorted
    }

    private static func overlappingSegments(
        sourceStart: Double,
        sourceEnd: Double,
        mapping: [Segment]
    ) -> [Segment] {
        mapping.filter { segment in
            min(sourceEnd, segment.sourceEnd) > max(sourceStart, segment.sourceStart)
        }
    }

    private static func remapCaption(
        _ caption: CaptionSegment,
        into segment: Segment,
        mapping: [Segment],
        splitIndex: Int
    ) -> CaptionSegment? {
        let clippedSourceStart = max(caption.startTime, segment.sourceStart)
        let clippedSourceEnd = min(caption.endTime, segment.sourceEnd)
        guard clippedSourceEnd > clippedSourceStart,
              let cleanStart = mapToClean(clippedSourceStart, mapping: mapping),
              let cleanEnd = mapToClean(clippedSourceEnd, mapping: mapping) else {
            return nil
        }

        let wordTimings = remapWordTimings(
            caption.wordTimings,
            sourceStart: clippedSourceStart,
            sourceEnd: clippedSourceEnd,
            mapping: mapping
        )

        let text = remappedText(
            for: caption,
            wordTimings: wordTimings,
            sourceStart: clippedSourceStart,
            sourceEnd: clippedSourceEnd
        )
        let repairedWordTimings = repairedWordTimings(
            for: text,
            originalHadTimings: !caption.wordTimings.isEmpty,
            remappedWordTimings: wordTimings,
            cleanStart: cleanStart,
            cleanEnd: cleanEnd
        )

        return CaptionSegment(
            startTime: cleanStart,
            endTime: max(cleanEnd, cleanStart + 0.1),
            text: text,
            role: caption.role,
            style: caption.style,
            sceneBehavior: splitIndex == 0 ? caption.sceneBehavior : .none,
            wordTimings: repairedWordTimings
        )
    }

    private static func remapTranscriptSegment(
        _ transcriptSegment: TranscriptSegment,
        into segment: Segment,
        mapping: [Segment]
    ) -> TranscriptSegment? {
        let clippedSourceStart = max(transcriptSegment.startTime, segment.sourceStart)
        let clippedSourceEnd = min(transcriptSegment.endTime, segment.sourceEnd)
        guard clippedSourceEnd > clippedSourceStart,
              let cleanStart = mapToClean(clippedSourceStart, mapping: mapping),
              let cleanEnd = mapToClean(clippedSourceEnd, mapping: mapping) else {
            return nil
        }

        let wordTimings = remapWordTimings(
            transcriptSegment.wordTimings,
            sourceStart: clippedSourceStart,
            sourceEnd: clippedSourceEnd,
            mapping: mapping
        )
        let text = remappedText(
            text: transcriptSegment.text,
            originalStart: transcriptSegment.startTime,
            originalEnd: transcriptSegment.endTime,
            originalWordTimings: transcriptSegment.wordTimings,
            remappedWordTimings: wordTimings,
            sourceStart: clippedSourceStart,
            sourceEnd: clippedSourceEnd
        )

        var remapped = TranscriptSegment(
            startTime: cleanStart,
            endTime: max(cleanEnd, cleanStart + 0.1),
            text: text,
            confidence: transcriptSegment.confidence,
            segmentType: transcriptSegment.segmentType
        )
        remapped.aiConfidence = transcriptSegment.aiConfidence
        remapped.aiReason = transcriptSegment.aiReason
        remapped.rawConfidence = transcriptSegment.rawConfidence
        remapped.wordTimings = repairedWordTimings(
            for: text,
            originalHadTimings: !transcriptSegment.wordTimings.isEmpty,
            remappedWordTimings: wordTimings,
            cleanStart: cleanStart,
            cleanEnd: cleanEnd
        )
        return remapped
    }

    private static func remapWordTimings(
        _ wordTimings: [(word: String, start: Double, duration: Double)],
        sourceStart: Double,
        sourceEnd: Double,
        mapping: [Segment]
    ) -> [(word: String, start: Double, duration: Double)] {
        wordTimings.compactMap { timing in
            let wordSourceStart = max(timing.start, sourceStart)
            let wordSourceEnd = min(timing.start + timing.duration, sourceEnd)
            guard wordSourceEnd > wordSourceStart,
                  let wordStart = mapToClean(wordSourceStart, mapping: mapping),
                  let wordEnd = mapToClean(wordSourceEnd, mapping: mapping) else {
                return nil
            }

            return (
                word: timing.word,
                start: wordStart,
                duration: max(0.01, wordEnd - wordStart)
            )
        }
    }

    private static func clampWordTimings(in caption: CaptionSegment) -> CaptionSegment {
        guard !caption.wordTimings.isEmpty else { return caption }

        let clamped: [(word: String, start: Double, duration: Double)] = caption.wordTimings.compactMap { timing in
            let start = max(timing.start, caption.startTime)
            let end = min(timing.start + timing.duration, caption.endTime)
            guard end > start else { return nil }
            return (word: timing.word, start: start, duration: max(0.01, end - start))
        }

        var caption = caption
        let canDeriveTextFromTimings = captionTextMatchesWordTimings(
            caption.text,
            wordTimings: caption.wordTimings
        )
        caption.wordTimings = clamped
        if canDeriveTextFromTimings && !clamped.isEmpty {
            caption.text = clamped.map { $0.word }.joined(separator: " ")
        }
        return caption
    }

    private static func repairedWordTimings(
        for text: String,
        originalHadTimings: Bool,
        remappedWordTimings: [(word: String, start: Double, duration: Double)],
        cleanStart: Double,
        cleanEnd: Double
    ) -> [(word: String, start: Double, duration: Double)] {
        guard originalHadTimings else { return [] }

        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return [] }

        if remappedWordTimings.count == words.count {
            return zip(words, remappedWordTimings).map { pair in
                let (word, timing) = pair
                return (word: word, start: timing.start, duration: timing.duration)
            }
        }

        return proportionalWordTimings(
            words: words,
            start: cleanStart,
            end: max(cleanEnd, cleanStart + 0.01)
        )
    }

    private static func remappedText(
        for caption: CaptionSegment,
        wordTimings: [(word: String, start: Double, duration: Double)],
        sourceStart: Double,
        sourceEnd: Double
    ) -> String {
        remappedText(
            text: caption.text,
            originalStart: caption.startTime,
            originalEnd: caption.endTime,
            originalWordTimings: caption.wordTimings,
            remappedWordTimings: wordTimings,
            sourceStart: sourceStart,
            sourceEnd: sourceEnd
        )
    }

    private static func remappedText(
        text: String,
        originalStart: Double,
        originalEnd: Double,
        originalWordTimings: [(word: String, start: Double, duration: Double)],
        remappedWordTimings: [(word: String, start: Double, duration: Double)],
        sourceStart: Double,
        sourceEnd: Double
    ) -> String {
        guard !remappedWordTimings.isEmpty else { return text }

        if captionTextMatchesWordTimings(text, wordTimings: originalWordTimings) {
            return remappedWordTimings.map { $0.word }.joined(separator: " ")
        }

        if sourceStart <= originalStart + 0.001 && sourceEnd >= originalEnd - 0.001 {
            return text
        }

        return proportionalTextSlice(
            text,
            captionStart: originalStart,
            captionEnd: originalEnd,
            sourceStart: sourceStart,
            sourceEnd: sourceEnd
        )
    }

    private static func captionTextMatchesWordTimings(
        _ text: String,
        wordTimings: [(word: String, start: Double, duration: Double)]
    ) -> Bool {
        guard !wordTimings.isEmpty else { return false }
        let timingText = wordTimings.map { $0.word }.joined(separator: " ")
        return normalizedText(text) == normalizedText(timingText)
    }

    private static func normalizedText(_ text: String) -> String {
        text
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .lowercased()
    }

    private static func proportionalTextSlice(
        _ text: String,
        captionStart: Double,
        captionEnd: Double,
        sourceStart: Double,
        sourceEnd: Double
    ) -> String {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return text }

        let duration = max(0.001, captionEnd - captionStart)
        let startRatio = min(max((sourceStart - captionStart) / duration, 0), 1)
        let endRatio = min(max((sourceEnd - captionStart) / duration, 0), 1)

        let startIndex = min(words.count - 1, max(0, Int((startRatio * Double(words.count)).rounded(.down))))
        let rawEndIndex = Int((endRatio * Double(words.count)).rounded(.up))
        let endIndex = min(words.count, max(startIndex + 1, rawEndIndex))

        return words[startIndex..<endIndex].joined(separator: " ")
    }

    private static func proportionalWordTimings(
        words: [String],
        start: Double,
        end: Double
    ) -> [(word: String, start: Double, duration: Double)] {
        guard !words.isEmpty else { return [] }

        let span = max(0.01, end - start)
        let weights = words.map { word in
            max(1, word.filter { !$0.isWhitespace }.count)
        }
        let totalWeight = max(1, weights.reduce(0, +))
        var cursor = start

        return words.enumerated().map { index, word in
            let isLast = index == words.indices.last
            let duration = isLast
                ? max(0.01, end - cursor)
                : max(0.01, span * Double(weights[index]) / Double(totalWeight))
            defer { cursor += duration }
            return (word: word, start: cursor, duration: duration)
        }
    }
}
