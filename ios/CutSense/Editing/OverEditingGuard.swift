import Foundation

enum OverEditingGuard {
    /// Max effects per minute of content (aligned with IntensityLimiter high-tier)
    private static let maxEffectsPerMinute = 40
    /// Min seconds between consecutive effects of the same type
    private static let minSameTypeGap: Double = 1.5

    static func filter(_ decisions: [EditDecision], totalDuration: Double) -> [EditDecision] {
        guard !decisions.isEmpty else { return [] }

        let maxTotal = Int(ceil(totalDuration / 60.0)) * maxEffectsPerMinute
        let sorted = decisions.sorted { $0.time < $1.time }

        // Remove repeated clusters, but keep combined SFX lanes such as whoosh + impact
        // at the same edit point.
        var filtered: [EditDecision] = []
        var lastTimeByGuardKey: [String: Double] = [:]

        for decision in sorted {
            let key = guardKey(for: decision)
            if let lastTime = lastTimeByGuardKey[key],
               decision.time - lastTime < minimumSameTypeGap(for: decision) {
                continue
            }
            filtered.append(decision)
            lastTimeByGuardKey[key] = decision.time
        }

        // Cap total count
        if filtered.count > maxTotal {
            // Keep the semantic accents first, then highest intensity ones.
            filtered.sort { left, right in
                let leftPriority = priority(left)
                let rightPriority = priority(right)
                if leftPriority != rightPriority { return leftPriority > rightPriority }
                return left.intensity > right.intensity
            }
            filtered = Array(filtered.prefix(maxTotal))
            filtered.sort { $0.time < $1.time }
        }

        return filtered
    }

    private static func minimumSameTypeGap(for decision: EditDecision) -> Double {
        let reason = decision.reason.lowercased()
        if decision.type == .sfx {
            switch SFXAssetManager.sound(for: decision) {
            case .riser:
                return 1.4
            case .whoosh:
                return 0.45
            case .impact:
                return 0.30
            case .pop:
                return 0.20
            case .confirm:
                return 0.55
            case .glitch, .subHit, .sweep, .ping, .typing, .shutter:
                return 0.60
            case nil:
                return 0.55
            }
        }
        if reason.contains("hook") || reason.contains("transition") || reason.contains("conclusion") {
            return 0.55
        }
        if reason.contains("punch") || reason.contains("impact") || reason.contains("keyword") {
            return 0.75
        }
        return minSameTypeGap
    }

    private static func guardKey(for decision: EditDecision) -> String {
        guard decision.type == .sfx else {
            return decision.type.rawValue
        }

        guard let sound = SFXAssetManager.sound(for: decision) else {
            return "sfx:impact"
        }
        return "sfx:\(sound.rawValue)"
    }

    private static func priority(_ decision: EditDecision) -> Int {
        let reason = decision.reason.lowercased()
        if reason.contains("hook") { return 100 }
        if reason.contains("transition") || reason.contains("cut") { return 90 }
        if reason.contains("conclusion") || reason.contains("riser") { return 85 }
        if reason.contains("punch") || reason.contains("impact") { return 80 }
        if reason.contains("keyword") { return 70 }
        if reason.contains("focus") || reason.contains("reveal") { return 65 }
        if decision.type == .sfx { return 60 }
        if decision.type == .shake || decision.type == .flash { return 55 }
        return 40
    }
}
