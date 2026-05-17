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
        // Reduced gaps for Prequel-level editing density
        let minGap: Double = switch intensity {
        case .low: 5.0
        case .medium: 3.0
        case .high: 2.0
        }

        guard timeSinceLastBehavior >= minGap else { return .none }

        switch role {
        case .hook:
            return .hookImpact

        case .reveal:
            return intensity == .low ? .underlineReveal : .focusBlur

        case .keyword:
            return .keywordLockOn

        case .warning:
            return .underlineReveal

        case .transition:
            return intensity == .low ? .none : .transitionWhoosh

        case .conclusion:
            return .conclusionHold

        case .regular:
            // Regular captions now get subtle effects instead of nothing
            switch intensity {
            case .low:
                return .none
            case .medium:
                return .subtleZoom
            case .high:
                return .punchIn
            }
        }
    }
}
