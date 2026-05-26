import Foundation

struct TimelineRange: Sendable, Equatable {
    let startTime: Double
    let endTime: Double

    var duration: Double {
        endTime - startTime
    }
}

enum TimelineRangeNormalizer {
    static let defaultMaxGap: Double = 0.05
    static let defaultMinimumDuration: Double = 0.05

    static func includedRanges(
        from decisions: [RoughCutDecision],
        assetDuration: Double? = nil,
        maxGap: Double = defaultMaxGap,
        minimumDuration: Double = defaultMinimumDuration
    ) -> [TimelineRange] {
        let upperBound = assetDuration.flatMap { duration in
            duration.isFinite && duration > 0 ? duration : nil
        }
        let ranges = decisions
            .filter { $0.isTimelineIncluded }
            .compactMap { range(for: $0, upperBound: upperBound, minimumDuration: minimumDuration) }

        return coalesce(ranges, maxGap: maxGap)
    }

    static func coalesce(_ ranges: [TimelineRange], maxGap: Double = defaultMaxGap) -> [TimelineRange] {
        let sorted = ranges
            .filter { $0.startTime.isFinite && $0.endTime.isFinite && $0.endTime > $0.startTime }
            .sorted { $0.startTime < $1.startTime }

        guard let first = sorted.first else { return [] }

        var result: [TimelineRange] = []
        var currentStart = first.startTime
        var currentEnd = first.endTime

        for range in sorted.dropFirst() {
            if range.startTime <= currentEnd + maxGap {
                currentEnd = max(currentEnd, range.endTime)
            } else {
                result.append(TimelineRange(startTime: currentStart, endTime: currentEnd))
                currentStart = range.startTime
                currentEnd = range.endTime
            }
        }

        result.append(TimelineRange(startTime: currentStart, endTime: currentEnd))
        return result
    }

    private static func range(
        for decision: RoughCutDecision,
        upperBound: Double?,
        minimumDuration: Double
    ) -> TimelineRange? {
        guard decision.startTime.isFinite, decision.endTime.isFinite else {
            return nil
        }

        let start = max(0, decision.startTime)
        let end = min(upperBound ?? decision.endTime, decision.endTime)

        guard end - start >= minimumDuration else {
            return nil
        }

        return TimelineRange(startTime: start, endTime: end)
    }
}
