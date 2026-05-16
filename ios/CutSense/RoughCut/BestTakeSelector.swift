import Foundation

enum BestTakeSelector {
    struct TakeScore: Sendable {
        let index: Int
        let score: Float // 0-100
        let confidenceScore: Float
        let completenessScore: Float
        let durationScore: Float
    }

    /// Select best take index from a group of similar segments
    static func selectBest(from takes: [TranscriptSegment]) -> Int {
        guard takes.count > 1 else { return 0 }

        let scores = takes.enumerated().map { index, take in
            scoreTake(take, index: index, totalTakes: takes.count)
        }

        return scores.max(by: { $0.score < $1.score })?.index ?? takes.count - 1
    }

    /// Score individual takes
    static func scoreTakes(from takes: [TranscriptSegment]) -> [TakeScore] {
        takes.enumerated().map { index, take in
            scoreTake(take, index: index, totalTakes: takes.count)
        }
    }

    private static func scoreTake(_ take: TranscriptSegment, index: Int, totalTakes: Int) -> TakeScore {
        // 1. Confidence from speech recognition (0-40 points)
        let confidenceScore = take.confidence * 40

        // 2. Completeness — longer is usually more complete (0-30 points)
        let wordCount = take.text.split(separator: " ").count
        let completenessScore = min(Float(wordCount) / 10.0, 1.0) * 30

        // 3. Duration — prefer natural pace, not too short or too long (0-20 points)
        let duration = take.endTime - take.startTime
        let idealPace = Double(wordCount) * 0.4 // ~0.4s per word
        let durationDiff = abs(duration - idealPace)
        let durationScore = max(0, 20 - Float(durationDiff) * 5)

        // 4. Recency bonus — later takes tend to be better (0-10 points)
        let recencyScore = totalTakes > 1
            ? Float(index) / Float(totalTakes - 1) * 10
            : 5.0

        let total = confidenceScore + completenessScore + durationScore + recencyScore

        return TakeScore(
            index: index,
            score: min(total, 100),
            confidenceScore: confidenceScore,
            completenessScore: completenessScore,
            durationScore: durationScore
        )
    }
}
