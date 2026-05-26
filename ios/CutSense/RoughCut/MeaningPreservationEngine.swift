import Foundation

enum MeaningPreservationEngine {
    struct PreservationResult: Sendable {
        let isCoherent: Bool
        let issues: [CoherenceIssue]
        let overallScore: Float // 0-100
    }

    struct CoherenceIssue: Sendable {
        let segmentIndex: Int
        let description: String
        let severity: IssueSeverity
    }

    enum IssueSeverity: String, Sendable {
        case low
        case medium
        case high
    }

    static func keptSpeechSegments(
        from transcription: TranscriptionResult,
        roughCut: RoughCutResult
    ) -> [TranscriptSegment] {
        let includedRanges = TimelineRangeNormalizer.includedRanges(
            from: roughCut.decisions,
            assetDuration: roughCut.originalDuration
        )
        let ranges = includedRanges.isEmpty && roughCut.decisions.isEmpty
            ? [TimelineRange(startTime: 0, endTime: roughCut.originalDuration)]
            : includedRanges

        return transcription.segments.filter { segment in
            guard isSpeechLike(segment), segment.endTime > segment.startTime else {
                return false
            }

            let duration = segment.endTime - segment.startTime
            let overlap = ranges.reduce(0.0) { total, range in
                total + max(0, min(segment.endTime, range.endTime) - max(segment.startTime, range.startTime))
            }
            return overlap >= min(0.12, duration * 0.50) || overlap / duration >= 0.45
        }
    }

    /// Verify that kept segments form a coherent narrative
    static func verify(
        keptSegments: [TranscriptSegment],
        allSegments: [TranscriptSegment]
    ) -> PreservationResult {
        var issues: [CoherenceIssue] = []

        // 1. Check for dangling references
        for (index, segment) in keptSegments.enumerated() {
            let lower = segment.text.lowercased()

            // Turkish dangling references
            let danglingRefs = ["bu", "şu", "o", "bunun", "bunu", "şunu", "onu",
                               "this", "that", "these", "those", "it"]

            let words = lower.split(separator: " ")
            if let firstWord = words.first,
               danglingRefs.contains(String(firstWord)),
               index == 0 {
                issues.append(CoherenceIssue(
                    segmentIndex: index,
                    description: "Starts with pronoun '\(firstWord)' — reference may be cut",
                    severity: .medium
                ))
            }
        }

        // 2. Check for incomplete sentences at boundaries
        for (index, segment) in keptSegments.enumerated() {
            let text = segment.text.trimmingCharacters(in: .whitespaces)

            // Sentence ends mid-thought (no punctuation at end)
            if index < keptSegments.count - 1 {
                let lastChar = text.last
                if lastChar != "." && lastChar != "!" && lastChar != "?" && lastChar != "," {
                    // Check if next kept segment continues naturally
                    let next = keptSegments[index + 1]
                    let gap = next.startTime - segment.endTime
                    if gap > 2.0 {
                        issues.append(CoherenceIssue(
                            segmentIndex: index,
                            description: "Possible sentence break with \(String(format: "%.1f", gap))s gap",
                            severity: .low
                        ))
                    }
                }
            }
        }

        // 3. Check topic continuity (simple word overlap between consecutive)
        for i in 1..<keptSegments.count {
            let prevWords = Set(keptSegments[i - 1].text.lowercased().split(separator: " "))
            let currWords = Set(keptSegments[i].text.lowercased().split(separator: " "))
            let overlap = prevWords.intersection(currWords).count
            let totalUnique = prevWords.union(currWords).count

            let continuity = totalUnique > 0 ? Float(overlap) / Float(totalUnique) : 0

            if continuity < 0.05 && keptSegments.count > 3 {
                issues.append(CoherenceIssue(
                    segmentIndex: i,
                    description: "Low topic continuity with previous segment",
                    severity: .low
                ))
            }
        }

        // 4. Coverage check — how much of original meaning is retained
        let keptWordCount = keptSegments.reduce(0) { $0 + $1.text.split(separator: " ").count }
        let totalWordCount = allSegments.reduce(0) { $0 + $1.text.split(separator: " ").count }
        let coverage = totalWordCount > 0 ? Float(keptWordCount) / Float(totalWordCount) : 1.0

        if coverage < 0.3 {
            issues.append(CoherenceIssue(
                segmentIndex: -1,
                description: "Only \(Int(coverage * 100))% of content retained — may lose key points",
                severity: .high
            ))
        }

        // Score
        let highIssues = issues.filter { $0.severity == .high }.count
        let mediumIssues = issues.filter { $0.severity == .medium }.count
        let score = max(0, 100 - Float(highIssues * 25) - Float(mediumIssues * 10) - Float(issues.count * 2))

        return PreservationResult(
            isCoherent: highIssues == 0,
            issues: issues,
            overallScore: min(score, 100)
        )
    }

    private static func isSpeechLike(_ segment: TranscriptSegment) -> Bool {
        switch segment.segmentType {
        case .speech, .contentSentence, .suspectedRestart, .suspectedDuplicate:
            return true
        case .silence, .filler, .editCommand:
            return false
        }
    }
}
