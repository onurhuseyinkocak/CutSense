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

        for segment in segments {
            // Skip non-speech segments
            guard segment.segmentType == .speech ||
                    segment.segmentType == .contentSentence ||
                    segment.segmentType == .suspectedRestart else {
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

            if isSameTakeCandidate(lastInGroup, segment) && timeDiff < maxTakeGap {
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

    private static func isSameTakeCandidate(_ previous: TranscriptSegment, _ current: TranscriptSegment) -> Bool {
        let previousWords = normalizedWords(previous.text)
        let currentWords = normalizedWords(current.text)
        let similarity = wordOverlap(previousWords, currentWords)
        guard similarity >= overlapThreshold else { return false }

        // Generic overlap is not enough: adjacent story fragments often repeat brand/product
        // terms while continuing the thought. Require actual restart evidence.
        let hasClassifierEvidence = previous.segmentType == .suspectedRestart ||
            previous.segmentType == .suspectedDuplicate ||
            current.segmentType == .suspectedRestart ||
            current.segmentType == .suspectedDuplicate
        let hasSharedOpening = commonPrefixWordCount(previousWords, currentWords) >= 3

        return hasClassifierEvidence || hasSharedOpening
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

    private static func normalizedWords(_ text: String) -> [String] {
        text
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
    }

    private static func commonPrefixWordCount(_ left: [String], _ right: [String]) -> Int {
        var count = 0
        for (leftWord, rightWord) in zip(left, right) {
            guard leftWord == rightWord else { break }
            count += 1
        }
        return count
    }

    private static func wordOverlap(_ wordsA: [String], _ wordsB: [String]) -> Double {
        let wordsA = Set(wordsA)
        let wordsB = Set(wordsB)
        let intersection = wordsA.intersection(wordsB).count
        let minCount = min(wordsA.count, wordsB.count)
        return minCount > 0 ? Double(intersection) / Double(minCount) : 0
    }
}
