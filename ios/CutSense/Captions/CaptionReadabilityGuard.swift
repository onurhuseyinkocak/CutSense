import Foundation

enum CaptionReadabilityGuard {
    /// Max characters per caption line
    private static let maxCharsPerLine = 40
    /// Min display duration (seconds)
    private static let minDisplayDuration: Double = 0.8
    /// Max words per caption
    private static let maxWords = 10

    static func validate(_ captions: [CaptionSegment]) -> [CaptionSegment] {
        var result: [CaptionSegment] = []

        for caption in captions {
            var fixed = caption

            // Ensure minimum display duration
            if fixed.endTime - fixed.startTime < minDisplayDuration {
                fixed.endTime = fixed.startTime + minDisplayDuration
            }

            // Split overly long captions
            let words = fixed.text.split(separator: " ")
            if words.count > maxWords {
                let midpoint = words.count / 2
                let firstHalf = words[..<midpoint].joined(separator: " ")
                let secondHalf = words[midpoint...].joined(separator: " ")
                let midTime = (fixed.startTime + fixed.endTime) / 2

                var first = fixed
                first.text = firstHalf
                first.endTime = midTime

                var second = fixed
                second.text = secondHalf
                second.startTime = midTime

                result.append(first)
                result.append(second)
            } else if fixed.text.count > maxCharsPerLine {
                // Add line break at natural point
                let midChar = fixed.text.count / 2
                let searchRange = max(0, midChar - 8)...min(fixed.text.count - 1, midChar + 8)
                if let spaceIdx = fixed.text.enumerated().first(where: { searchRange.contains($0.offset) && $0.element == " " })?.offset {
                    var chars = Array(fixed.text)
                    chars[spaceIdx] = "\n"
                    fixed.text = String(chars)
                }
                result.append(fixed)
            } else {
                result.append(fixed)
            }
        }

        return result
    }
}
