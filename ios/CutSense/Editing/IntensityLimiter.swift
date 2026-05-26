import Foundation

enum IntensityLimiter {
    private static let windowDuration: Double = 10.0
    private static let comboClusterGap: Double = 1.2

    static func limit(_ decisions: [EditDecision], template: TemplateConfig) -> [EditDecision] {
        let maxPerWindow = template.editGrammar.maxEffectsPerTenSeconds
        guard !decisions.isEmpty else { return [] }

        let clusters = semanticClusters(from: decisions)
        let sorted = clusters.sorted { left, right in
            let leftPriority = left.priority
            let rightPriority = right.priority
            if leftPriority != rightPriority { return leftPriority > rightPriority }
            if left.intensity != right.intensity { return left.intensity > right.intensity }
            return left.time < right.time
        }
        var result: [DecisionCluster] = []

        for cluster in sorted {
            let windowStart = cluster.time - windowDuration / 2
            let windowEnd = cluster.time + windowDuration / 2
            let countInWindow = result.filter { $0.time >= windowStart && $0.time <= windowEnd }.count

            if countInWindow < maxPerWindow {
                result.append(cluster)
            }
        }

        let limited = result
            .flatMap(\.decisions)
        return enforceTypeCaps(limited, template: template)
            .sorted { $0.time < $1.time }
    }

    private struct DecisionCluster {
        let key: String?
        var decisions: [EditDecision]

        var time: Double {
            decisions.map(\.time).max() ?? 0
        }

        var priority: Int {
            decisions.map { IntensityLimiter.priority($0) }.max() ?? 0
        }

        var intensity: Float {
            decisions.map(\.intensity).max() ?? 0
        }
    }

    private struct TypeCapCluster {
        var decisions: [EditDecision]

        var time: Double {
            decisions.map(\.time).max() ?? 0
        }

        var priority: Int {
            decisions.map { IntensityLimiter.priority($0) }.max() ?? 0
        }

        var intensity: Float {
            decisions.map(\.intensity).max() ?? 0
        }
    }

    private static func semanticClusters(from decisions: [EditDecision]) -> [DecisionCluster] {
        var clusters: [DecisionCluster] = []
        let sorted = decisions.sorted { $0.time < $1.time }

        for decision in sorted {
            guard let key = semanticComboKey(for: decision) else {
                clusters.append(DecisionCluster(key: nil, decisions: [decision]))
                continue
            }

            if let index = clusters.indices.last(where: { clusterIndex in
                let cluster = clusters[clusterIndex]
                guard cluster.key == key else { return false }
                let latestTime = cluster.decisions.map(\.time).max() ?? decision.time
                return decision.time - latestTime <= comboClusterGap
            }) {
                clusters[index].decisions.append(decision)
            } else {
                clusters.append(DecisionCluster(key: key, decisions: [decision]))
            }
        }

        return clusters
    }

    private static func semanticComboKey(for decision: EditDecision) -> String? {
        if let cue = TechInfluencerEffectCue(reason: decision.reason) {
            return "tech_\(cue.eventKind.rawValue)"
        }

        let reason = decision.reason.lowercased()
        if reason.contains("hook") { return "hook" }
        if reason.contains("reveal") { return "reveal" }
        if reason.contains("cta") || reason.contains("conclusion") { return "cta" }
        if reason.contains("topic shift") { return "topic_shift" }
        if reason.contains("transition") || reason.contains("cut") { return "transition" }
        if reason.contains("keyword") { return "keyword" }
        if reason.contains("focus") || reason.contains("ui") { return "focus" }
        return nil
    }

    private static func enforceTypeCaps(_ decisions: [EditDecision], template: TemplateConfig) -> [EditDecision] {
        var limited = decisions
        limited = limitType(.zoom, in: limited, maxPerWindow: maxZoomsPerWindow(for: template))
        limited = limitType(.flash, in: limited, maxPerWindow: maxFlashesPerWindow(for: template))
        limited = limitType(.sfx, in: limited, maxPerWindow: maxSFXPerWindow(for: template))
        return limited
    }

    private static func limitType(
        _ type: EditType,
        in decisions: [EditDecision],
        maxPerWindow: Int
    ) -> [EditDecision] {
        let unaffected = decisions.filter { $0.type != type }
        let candidates = decisions.filter { $0.type == type }
        guard candidates.count > maxPerWindow else { return decisions }

        let clusters = typeCapClusters(from: candidates)
        let sorted = clusters.sorted { left, right in
            let leftPriority = left.priority
            let rightPriority = right.priority
            if leftPriority != rightPriority { return leftPriority > rightPriority }
            if left.intensity != right.intensity { return left.intensity > right.intensity }
            return left.time < right.time
        }
        var kept: [TypeCapCluster] = []

        for cluster in sorted {
            let countInWindow = kept.filter { abs($0.time - cluster.time) <= windowDuration }.count
            if countInWindow < maxPerWindow {
                kept.append(cluster)
            }
        }

        return unaffected + kept.flatMap(\.decisions)
    }

    private static func typeCapClusters(from candidates: [EditDecision]) -> [TypeCapCluster] {
        var clusters: [TypeCapCluster] = []
        let sorted = candidates.sorted { $0.time < $1.time }

        for decision in sorted {
            guard let key = semanticComboKey(for: decision) else {
                clusters.append(TypeCapCluster(decisions: [decision]))
                continue
            }

            if let index = clusters.indices.last(where: { clusterIndex in
                let cluster = clusters[clusterIndex]
                let clusterKeys = Set(cluster.decisions.compactMap { semanticComboKey(for: $0) })
                let latestTime = cluster.decisions.map(\.time).max() ?? decision.time
                return clusterKeys == [key] && decision.time - latestTime <= comboClusterGap
            }) {
                clusters[index].decisions.append(decision)
            } else {
                clusters.append(TypeCapCluster(decisions: [decision]))
            }
        }

        return clusters
    }

    private static func maxZoomsPerWindow(for template: TemplateConfig) -> Int {
        if template.id == "tech_influencer" { return 3 }
        return switch template.intensity {
        case .high: 8
        case .medium: 5
        case .low: 4
        }
    }

    private static func maxFlashesPerWindow(for template: TemplateConfig) -> Int {
        switch template.intensity {
        case .high: 5
        case .medium: 3
        case .low: 2
        }
    }

    private static func maxSFXPerWindow(for template: TemplateConfig) -> Int {
        switch template.intensity {
        case .high: 8
        case .medium: 6
        case .low: 4
        }
    }

    private static func priority(_ decision: EditDecision) -> Int {
        if let cue = TechInfluencerEffectCue(reason: decision.reason) {
            switch cue.eventKind {
            case .hook: return 100
            case .reveal: return 95
            case .topicShift, .uiAction: return 90
            case .cta: return 85
            case .warning: return 80
            case .keyword: return 70
            }
        }

        let reason = decision.reason.lowercased()
        if reason.contains("hook") { return 100 }
        if reason.contains("transition") || reason.contains("cut") { return 90 }
        if reason.contains("conclusion") || reason.contains("cta") || reason.contains("riser") { return 85 }
        if reason.contains("punch") || reason.contains("impact") { return 80 }
        if reason.contains("keyword") { return 70 }
        if reason.contains("focus") || reason.contains("reveal") { return 65 }
        if decision.type == .sfx { return 60 }
        if decision.type == .shake || decision.type == .flash { return 55 }
        return 40
    }
}
