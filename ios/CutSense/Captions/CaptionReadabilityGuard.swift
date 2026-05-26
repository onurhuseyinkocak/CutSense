import Foundation

enum CaptionReadabilityGuard {
    /// Max characters per displayed line before line-break is inserted
    private static let maxCharsPerLine = 40
    /// Min display duration (seconds) — captions held briefly look glitchy
    private static let minDisplayDuration: Double = 0.8
    /// Max words per caption before splitting.
    private static let maxWords = 10

    static func validate(_ captions: [CaptionSegment], template: TemplateConfig? = nil) -> [CaptionSegment] {
        var result: [CaptionSegment] = []
        let maxWordsForCaption = template?.id == "tech_influencer" ? 6 : maxWords
        let maxCharsForCaption = template?.id == "tech_influencer" ? 34 : maxCharsPerLine

        for caption in captions {
            var fixed = caption

            // Ensure minimum display duration
            if fixed.endTime - fixed.startTime < minDisplayDuration {
                fixed.endTime = fixed.startTime + minDisplayDuration
            }

            let words = fixed.text.split(separator: " ").map(String.init)
            if words.count > maxWordsForCaption {
                // Split at word boundary — closer to middle but never inside a word
                let midpoint = words.count / 2
                let firstHalf = words[..<midpoint].joined(separator: " ")
                let secondHalf = words[midpoint...].joined(separator: " ")

                // Derive a natural split TIME from wordTimings if we have them;
                // otherwise fall back to a duration-proportional midTime.
                let splitTime: Double = {
                    if fixed.wordTimings.count == words.count {
                        // Last word of the first half — split after its end
                        let lastFirst = fixed.wordTimings[midpoint - 1]
                        return lastFirst.start + lastFirst.duration
                    } else {
                        return (fixed.startTime + fixed.endTime) / 2
                    }
                }()

                let firstTimings = Array(fixed.wordTimings.prefix(midpoint))
                let secondTimings = Array(fixed.wordTimings.dropFirst(midpoint))

                let first = CaptionSegment(
                    startTime: fixed.startTime,
                    endTime: max(splitTime, fixed.startTime + minDisplayDuration),
                    text: firstHalf,
                    role: fixed.role,
                    style: fixed.style,
                    sceneBehavior: fixed.sceneBehavior,
                    wordTimings: firstTimings
                )
                // Avoid duplicate hook/keyword effects on the second half
                var second = CaptionSegment(
                    startTime: first.endTime,
                    endTime: max(fixed.endTime, first.endTime + minDisplayDuration),
                    text: secondHalf,
                    role: fixed.role,
                    style: fixed.style,
                    sceneBehavior: .none,
                    wordTimings: secondTimings
                )

                // If splitting pushed past the original end (because we forced minDuration),
                // gently extend the second half rather than overlapping the next caption.
                if second.endTime - second.startTime < minDisplayDuration {
                    second.endTime = second.startTime + minDisplayDuration
                }
                result.append(first)
                result.append(second)
            } else if fixed.text.count > maxCharsForCaption {
                // Long but ≤ maxWords — keep as one caption, insert a line break at the
                // word boundary closest to the middle so we never split mid-character.
                if words.count > 1 {
                    let midpoint = words.count / 2
                    let firstHalf = words[..<midpoint].joined(separator: " ")
                    let secondHalf = words[midpoint...].joined(separator: " ")
                    fixed.text = firstHalf + "\n" + secondHalf
                }
                result.append(fixed)
            } else {
                result.append(fixed)
            }
        }

        // Defensive: clamp any overlap that arose from the minDuration enforcement
        return clampOverlaps(result)
    }

    /// If a caption's endTime now overlaps the next one's startTime, shrink the earlier
    /// caption so both stay visible-but-not-stacked.
    private static func clampOverlaps(_ captions: [CaptionSegment]) -> [CaptionSegment] {
        guard captions.count > 1 else { return captions }
        var sorted = captions.sorted { $0.startTime < $1.startTime }
        for i in 0..<(sorted.count - 1) {
            if sorted[i].endTime > sorted[i + 1].startTime {
                sorted[i].endTime = sorted[i + 1].startTime
                // If shrinking violates min duration, push the next one's start forward
                if sorted[i].endTime - sorted[i].startTime < 0.2 {
                    sorted[i].endTime = sorted[i].startTime + 0.2
                    if sorted[i + 1].startTime < sorted[i].endTime {
                        sorted[i + 1].startTime = sorted[i].endTime
                    }
                }
            }
        }
        return sorted
    }
}
