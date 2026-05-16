import Foundation

enum CaptionSceneEventPlanner {
    static func assignSceneBehaviors(
        to captions: [CaptionSegment],
        template: TemplateConfig
    ) -> [CaptionSegment] {
        var result = captions
        var lastBehaviorTime: Double = -10

        for i in result.indices {
            let caption = result[i]
            let timeSinceLastBehavior = caption.startTime - lastBehaviorTime

            let behavior = determineBehavior(
                role: caption.role,
                style: caption.style,
                timeSinceLastBehavior: timeSinceLastBehavior,
                intensity: template.intensity
            )

            result[i].sceneBehavior = behavior
            if behavior != .none {
                lastBehaviorTime = caption.startTime
            }
        }

        return result
    }

    private static func determineBehavior(
        role: CaptionRole,
        style: CaptionStyle,
        timeSinceLastBehavior: Double,
        intensity: TemplateIntensity
    ) -> CaptionSceneBehavior {
        // Minimum gap between behaviors to avoid over-editing
        let minGap: Double = switch intensity {
        case .low: 8.0
        case .medium: 5.0
        case .high: 3.0
        }

        guard timeSinceLastBehavior >= minGap else { return .none }

        switch role {
        case .hook:
            return .hookImpact

        case .reveal:
            return intensity == .low ? .underlineReveal : .focusBlur

        case .keyword:
            return intensity != .low ? .keywordLockOn : .none

        case .warning:
            return .underlineReveal

        case .transition:
            return intensity == .high ? .transitionWhoosh : .none

        case .conclusion:
            return .conclusionHold

        case .regular:
            return .none
        }
    }
}
