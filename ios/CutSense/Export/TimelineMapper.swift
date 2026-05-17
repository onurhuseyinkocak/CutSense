import Foundation

enum TimelineMapper {
    struct Segment {
        let sourceStart: Double
        let sourceEnd: Double
        let cleanStart: Double
        var duration: Double { sourceEnd - sourceStart }
    }

    /// Build source→clean time mapping from keep decisions
    static func buildMapping(from decisions: [RoughCutDecision]) -> [Segment] {
        let keeps = decisions
            .filter { $0.action == .keep }
            .sorted { $0.startTime < $1.startTime }

        var mapping: [Segment] = []
        var cleanOffset: Double = 0

        for keep in keeps {
            mapping.append(Segment(
                sourceStart: keep.startTime,
                sourceEnd: keep.endTime,
                cleanStart: cleanOffset
            ))
            cleanOffset += keep.endTime - keep.startTime
        }

        return mapping
    }

    /// Map a single source time to clean timeline time. Returns nil if time falls in a cut region.
    static func mapToClean(_ sourceTime: Double, mapping: [Segment]) -> Double? {
        for seg in mapping {
            if sourceTime >= seg.sourceStart && sourceTime <= seg.sourceEnd {
                return seg.cleanStart + (sourceTime - seg.sourceStart)
            }
        }
        return nil
    }

    /// Remap captions from source to clean timeline coordinates
    static func remapCaptions(_ captions: [CaptionSegment], mapping: [Segment]) -> [CaptionSegment] {
        captions.compactMap { caption in
            guard let cleanStart = mapToClean(caption.startTime, mapping: mapping) else { return nil }
            // For endTime, clamp to segment boundary if it slightly overshoots
            let cleanEnd = mapToClean(caption.endTime, mapping: mapping)
                ?? mapToClean(caption.endTime - 0.05, mapping: mapping)
                ?? (cleanStart + (caption.endTime - caption.startTime))

            var remapped = caption
            remapped.startTime = cleanStart
            remapped.endTime = max(cleanEnd, cleanStart + 0.1)
            return remapped
        }
    }

    /// Remap edit decisions from source to clean timeline coordinates
    static func remapEditDecisions(_ decisions: [EditDecision], mapping: [Segment]) -> [EditDecision] {
        decisions.compactMap { decision in
            guard let cleanTime = mapToClean(decision.time, mapping: mapping) else { return nil }
            return EditDecision(
                time: cleanTime,
                duration: decision.duration,
                type: decision.type,
                reason: decision.reason,
                intensity: decision.intensity
            )
        }
    }

    /// Resolve overlapping captions after remapping.
    /// If two captions overlap in time, the earlier one's endTime is clamped to the later one's startTime.
    static func resolveOverlaps(_ captions: [CaptionSegment]) -> [CaptionSegment] {
        guard captions.count > 1 else { return captions }

        var sorted = captions.sorted { $0.startTime < $1.startTime }

        for i in 0..<(sorted.count - 1) {
            if sorted[i].endTime > sorted[i + 1].startTime {
                // Clamp earlier caption's end to next caption's start
                sorted[i].endTime = sorted[i + 1].startTime
                // Ensure minimum duration
                if sorted[i].endTime - sorted[i].startTime < 0.1 {
                    sorted[i].endTime = sorted[i].startTime + 0.1
                }
            }
        }

        return sorted
    }
}
