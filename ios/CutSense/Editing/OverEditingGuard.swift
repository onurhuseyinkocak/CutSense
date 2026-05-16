import Foundation

enum OverEditingGuard {
    /// Max effects per minute of content
    private static let maxEffectsPerMinute = 8
    /// Min seconds between consecutive effects of the same type
    private static let minSameTypeGap: Double = 3.0

    static func filter(_ decisions: [EditDecision], totalDuration: Double) -> [EditDecision] {
        guard !decisions.isEmpty else { return [] }

        let maxTotal = Int(ceil(totalDuration / 60.0)) * maxEffectsPerMinute
        var sorted = decisions.sorted { $0.time < $1.time }

        // Remove same-type clusters
        var filtered: [EditDecision] = []
        var lastTimeByType: [EditType: Double] = [:]

        for decision in sorted {
            if let lastTime = lastTimeByType[decision.type],
               decision.time - lastTime < minSameTypeGap {
                continue
            }
            filtered.append(decision)
            lastTimeByType[decision.type] = decision.time
        }

        // Cap total count
        if filtered.count > maxTotal {
            // Keep highest intensity ones
            filtered.sort { $0.intensity > $1.intensity }
            filtered = Array(filtered.prefix(maxTotal))
            filtered.sort { $0.time < $1.time }
        }

        return filtered
    }
}
