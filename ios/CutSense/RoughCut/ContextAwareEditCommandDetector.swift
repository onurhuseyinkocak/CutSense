import Foundation

enum EditIntent: String, Sendable {
    case editCommand = "edit_command"
    case contentSentence = "content_sentence"
    case uncertain
}

struct EditCommandAnalysis: Sendable {
    let segment: TranscriptSegment
    let intent: EditIntent
    let confidence: Float
    let reason: String
}

enum ContextAwareEditCommandDetector {
    // Turkish edit command markers
    private static let turkishEditMarkers: [(pattern: String, weight: Float)] = [
        ("baştan alıyorum", 0.95),
        ("baştan alayım", 0.95),
        ("baştan alalım", 0.90),
        ("tekrar alayım", 0.90),
        ("tekrar alalım", 0.85),
        ("bir daha alayım", 0.90),
        ("bunu kes", 0.92),
        ("şurayı kes", 0.92),
        ("burayı kes", 0.92),
        ("dur dur", 0.80),
        ("pardon baştan", 0.90),
        ("yanlış söyledim", 0.85),
        ("yeniden giriyorum", 0.85),
        ("olmadı baştan", 0.90),
    ]

    // Turkish suspicious words that MAY be edit commands or MAY be content
    private static let turkishSuspiciousWords = [
        "olmadı", "dur", "kes", "baştan", "tekrar", "yanlış", "pardon", "bir daha", "yeniden"
    ]

    // Turkish content patterns — if these surround suspicious words, it's content
    private static let turkishContentPatterns: [String] = [
        "çünkü", "dersek", "mesela", "öğrenmek", "bazen", "önemli", "aslında",
        "strateji", "kullanıcı", "sistem", "uygulama", "örneğin", "demek istiyorum"
    ]

    // Turkish filler words
    static let turkishFillers = ["ıı", "eee", "şey", "yani", "hani", "tamam mı", "işte"]

    // English equivalents
    private static let englishEditMarkers: [(pattern: String, weight: Float)] = [
        ("start over", 0.90),
        ("let me redo", 0.90),
        ("take it again", 0.85),
        ("cut that", 0.92),
        ("delete that", 0.90),
        ("sorry let me", 0.80),
        ("one more time", 0.75),
    ]

    static let englishFillers = ["um", "uh", "like", "you know", "basically", "actually"]

    static func analyze(
        segment: TranscriptSegment,
        previousSegment: TranscriptSegment?,
        nextSegment: TranscriptSegment?,
        audioResult: AudioAnalysisResult?
    ) -> EditCommandAnalysis {
        let text = segment.text.lowercased()

        // 1. Check explicit edit command patterns (high confidence)
        for marker in turkishEditMarkers + englishEditMarkers {
            if text.contains(marker.pattern) {
                // But verify it's not inside a content sentence
                if isInsideContentContext(text: text, pattern: marker.pattern, next: nextSegment) {
                    return EditCommandAnalysis(
                        segment: segment,
                        intent: .contentSentence,
                        confidence: 0.7,
                        reason: "Edit marker '\(marker.pattern)' appears inside content context"
                    )
                }
                return EditCommandAnalysis(
                    segment: segment,
                    intent: .editCommand,
                    confidence: marker.weight,
                    reason: "Explicit edit command: '\(marker.pattern)'"
                )
            }
        }

        // 2. Check suspicious words with context analysis
        for word in turkishSuspiciousWords {
            guard text.contains(word) else { continue }

            let contextScore = evaluateContext(
                text: text,
                segmentEndTime: segment.endTime,
                suspiciousWord: word,
                previous: previousSegment,
                next: nextSegment,
                audioResult: audioResult
            )

            if contextScore.isContent {
                return EditCommandAnalysis(
                    segment: segment,
                    intent: .contentSentence,
                    confidence: contextScore.confidence,
                    reason: contextScore.reason
                )
            } else if contextScore.isCommand {
                return EditCommandAnalysis(
                    segment: segment,
                    intent: .editCommand,
                    confidence: contextScore.confidence,
                    reason: contextScore.reason
                )
            } else {
                return EditCommandAnalysis(
                    segment: segment,
                    intent: .uncertain,
                    confidence: contextScore.confidence,
                    reason: contextScore.reason
                )
            }
        }

        // 3. No suspicious content found — this is normal speech
        return EditCommandAnalysis(
            segment: segment,
            intent: .contentSentence,
            confidence: 0.9,
            reason: "No edit markers detected"
        )
    }

    private struct ContextScore {
        let isContent: Bool
        let isCommand: Bool
        let confidence: Float
        let reason: String
    }

    private static func evaluateContext(
        text: String,
        segmentEndTime: Double,
        suspiciousWord: String,
        previous: TranscriptSegment?,
        next: TranscriptSegment?,
        audioResult: AudioAnalysisResult?
    ) -> ContextScore {
        var contentSignals = 0
        var commandSignals = 0

        // Check if content patterns are nearby
        let combinedText = [previous?.text, text, next?.text]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")

        for pattern in turkishContentPatterns {
            if combinedText.contains(pattern) {
                contentSignals += 1
            }
        }

        // If the sentence is long and grammatically complete, it's likely content
        let wordCount = text.split(separator: " ").count
        if wordCount >= 8 {
            contentSignals += 2
        } else if wordCount <= 3 {
            commandSignals += 1
        }

        // If a cleaner repeated take follows (next segment exists and is similar topic), it's likely a restart
        if let next, isSimilarTopic(text, next.text) {
            commandSignals += 2
        }

        // If followed by silence, more likely a command/restart
        if let audio = audioResult {
            let gapStart = segmentEndTime
            let hasSilenceAfter = audio.silenceIntervals.contains { $0.contains(gapStart + 0.1) }
            if hasSilenceAfter {
                commandSignals += 1
            }
        }

        // Check if suspicious word is at the beginning (more likely command)
        if text.hasPrefix(suspiciousWord) {
            commandSignals += 1
        }

        // Decision
        let total = contentSignals + commandSignals
        if contentSignals > commandSignals {
            return ContextScore(
                isContent: true, isCommand: false,
                confidence: Float(contentSignals) / Float(max(total, 1)),
                reason: "'\(suspiciousWord)' is part of content (content signals: \(contentSignals), command signals: \(commandSignals))"
            )
        } else if commandSignals > contentSignals + 1 {
            return ContextScore(
                isContent: false, isCommand: true,
                confidence: Float(commandSignals) / Float(max(total, 1)),
                reason: "'\(suspiciousWord)' appears to be edit command (command signals: \(commandSignals), content signals: \(contentSignals))"
            )
        } else {
            return ContextScore(
                isContent: false, isCommand: false,
                confidence: 0.4,
                reason: "'\(suspiciousWord)' is ambiguous — requires review (content: \(contentSignals), command: \(commandSignals))"
            )
        }
    }

    private static func isInsideContentContext(text: String, pattern: String, next: TranscriptSegment?) -> Bool {
        // If the sentence continues naturally after the pattern, it's content
        guard let range = text.range(of: pattern) else { return false }
        let afterPattern = text[range.upperBound...].trimmingCharacters(in: .whitespaces)

        // If there's substantial text after the pattern, it's likely content
        if afterPattern.split(separator: " ").count >= 3 {
            return true
        }

        // Check content patterns in surrounding text
        for contentPattern in turkishContentPatterns {
            if text.contains(contentPattern) { return true }
        }

        return false
    }

    private static func isSimilarTopic(_ text1: String, _ text2: String) -> Bool {
        let words1 = Set(text1.lowercased().split(separator: " ").map(String.init))
        let words2 = Set(text2.lowercased().split(separator: " ").map(String.init))
        let intersection = words1.intersection(words2)
        let minCount = max(min(words1.count, words2.count), 1)
        return Float(intersection.count) / Float(minCount) > 0.4
    }
}
