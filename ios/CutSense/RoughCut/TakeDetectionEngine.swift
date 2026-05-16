import Foundation

struct TakeGroup: Sendable, Identifiable {
    let id = UUID()
    let takes: [TranscriptSegment]
    let startTime: Double
    let endTime: Double
    let bestTakeIndex: Int
}

enum TakeDetectionEngine {
    /// Min word overlap ratio to consider segments as same take
    private static let overlapThreshold: Double = 0.4
    /// Max time gap between takes in same group (seconds)
    private static let maxTakeGap: Double = 5.0

    static func detectTakeGroups(segments: [TranscriptSegment]) -> [TakeGroup] {
        guard segments.count > 1 else { return [] }

        var groups: [TakeGroup] = []
        var currentGroup: [TranscriptSegment] = []
        var groupStartTime: Double?

        for (index, segment) in segments.enumerated() {
            // Skip non-speech segments
            guard segment.segmentType == .speech || segment.segmentType == .suspectedRestart else {
                if !currentGroup.isEmpty {
                    finalizeGroup(&currentGroup, startTime: &groupStartTime, into: &groups)
                }
                continue
            }

            if currentGroup.isEmpty {
                currentGroup.append(segment)
                groupStartTime = segment.startTime
                continue
            }

            let lastInGroup = currentGroup.last!
            let timeDiff = segment.startTime - lastInGroup.endTime
            let similarity = wordOverlap(lastInGroup.text, segment.text)

            if similarity >= overlapThreshold && timeDiff < maxTakeGap {
                // Same take group — speaker restarted
                currentGroup.append(segment)
            } else {
                // Different content — finalize current group
                if currentGroup.count > 1 {
                    finalizeGroup(&currentGroup, startTime: &groupStartTime, into: &groups)
                } else {
                    currentGroup.removeAll()
                    groupStartTime = nil
                }
                currentGroup.append(segment)
                groupStartTime = segment.startTime
            }
        }

        if currentGroup.count > 1 {
            finalizeGroup(&currentGroup, startTime: &groupStartTime, into: &groups)
        }

        return groups
    }

    private static func finalizeGroup(
        _ group: inout [TranscriptSegment],
        startTime: inout Double?,
        into groups: inout [TakeGroup]
    ) {
        guard group.count > 1, let start = startTime else {
            group.removeAll()
            startTime = nil
            return
        }

        let bestIndex = BestTakeSelector.selectBest(from: group)
        groups.append(TakeGroup(
            takes: group,
            startTime: start,
            endTime: group.last!.endTime,
            bestTakeIndex: bestIndex
        ))

        group.removeAll()
        startTime = nil
    }

    private static func wordOverlap(_ a: String, _ b: String) -> Double {
        let wordsA = Set(a.lowercased().split(separator: " "))
        let wordsB = Set(b.lowercased().split(separator: " "))
        let intersection = wordsA.intersection(wordsB).count
        let minCount = min(wordsA.count, wordsB.count)
        return minCount > 0 ? Double(intersection) / Double(minCount) : 0
    }
}
