import Foundation

enum TranscriptCleanupAnalyzer {
    // Turkish filler words
    private static let turkishFillers = [
        "şey", "yani", "hani", "ıı", "eee", "aaa", "mmm", "hmm",
        "işte", "mesela", "aslında", "bir nevi", "nasıl diyeyim",
        "şöyle ki", "ya", "evet evet"
    ]

    // English filler words
    private static let englishFillers = [
        "um", "uh", "like", "you know", "basically", "actually",
        "literally", "so", "right", "okay so", "I mean"
    ]

    private static let allFillers = turkishFillers + englishFillers

    struct CleanupResult: Sendable {
        let segments: [TranscriptSegment]
        let fillersRemoved: Int
        let restartsDetected: Int
        let duplicatesDetected: Int
    }

    static func analyze(_ segments: [TranscriptSegment]) -> CleanupResult {
        var cleaned: [TranscriptSegment] = []
        var fillersRemoved = 0
        var restartsDetected = 0
        var duplicatesDetected = 0

        for (index, segment) in segments.enumerated() {
            var modified = segment
            let lower = segment.text.lowercased().trimmingCharacters(in: .whitespaces)

            // Check pure filler
            if allFillers.contains(where: { lower == $0 }) {
                modified.segmentType = .filler
                fillersRemoved += 1
                cleaned.append(modified)
                continue
            }

            // Check for restarts (same beginning as next segment)
            if index < segments.count - 1 {
                let nextLower = segments[index + 1].text.lowercased()
                let words = lower.split(separator: " ")
                let nextWords = nextLower.split(separator: " ")

                if words.count >= 2 && nextWords.count >= 2 {
                    let overlap = commonPrefixWordCount(words, nextWords)
                    if overlap >= 2 && Double(overlap) / Double(words.count) > 0.5 {
                        modified.segmentType = .suspectedRestart
                        restartsDetected += 1
                    }
                }
            }

            // Check for duplicate content (near-identical to previous)
            if index > 0 {
                let prevLower = segments[index - 1].text.lowercased()
                let similarity = jaccardSimilarity(lower, prevLower)
                if similarity > 0.8 {
                    modified.segmentType = .suspectedDuplicate
                    duplicatesDetected += 1
                }
            }

            cleaned.append(modified)
        }

        return CleanupResult(
            segments: cleaned,
            fillersRemoved: fillersRemoved,
            restartsDetected: restartsDetected,
            duplicatesDetected: duplicatesDetected
        )
    }

    private static func commonPrefixWordCount(_ a: [Substring], _ b: [Substring]) -> Int {
        var count = 0
        for (w1, w2) in zip(a, b) {
            if w1.lowercased() == w2.lowercased() {
                count += 1
            } else {
                break
            }
        }
        return count
    }

    private static func jaccardSimilarity(_ a: String, _ b: String) -> Double {
        let setA = Set(a.split(separator: " "))
        let setB = Set(b.split(separator: " "))
        let intersection = setA.intersection(setB).count
        let union = setA.union(setB).count
        return union > 0 ? Double(intersection) / Double(union) : 0
    }
}
