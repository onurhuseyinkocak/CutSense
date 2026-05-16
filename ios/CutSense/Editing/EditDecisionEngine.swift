import Foundation

struct EditDecision: Sendable, Identifiable {
    let id = UUID()
    let time: Double
    let duration: Double
    let type: EditType
    let reason: String
    let intensity: Float // 0.0-1.0
}

enum EditType: String, Sendable, CaseIterable {
    case sfx
    case zoom
    case shake
    case flash
    case colorShift = "color_shift"
    case speedRamp = "speed_ramp"
    case textPopup = "text_popup"
}

struct EditPlan: Sendable {
    let decisions: [EditDecision]
    let template: TemplateConfig
    let totalEffects: Int
    let averageIntensity: Float
}

enum EditDecisionEngine {
    static func generateEditPlan(
        captions: [CaptionSegment],
        roughCut: RoughCutResult,
        template: TemplateConfig
    ) -> EditPlan {
        var decisions: [EditDecision] = []

        for caption in captions {
            let edits = editsForCaption(caption, template: template)
            decisions.append(contentsOf: edits)
        }

        // Apply intensity limits
        decisions = IntensityLimiter.limit(decisions, template: template)

        // Guard against over-editing
        decisions = OverEditingGuard.filter(decisions, totalDuration: roughCut.cleanDuration)

        let avgIntensity = decisions.isEmpty ? 0 : decisions.reduce(Float(0)) { $0 + $1.intensity } / Float(decisions.count)

        return EditPlan(
            decisions: decisions,
            template: template,
            totalEffects: decisions.count,
            averageIntensity: avgIntensity
        )
    }

    private static func editsForCaption(_ caption: CaptionSegment, template: TemplateConfig) -> [EditDecision] {
        switch caption.sceneBehavior {
        case .hookImpact:
            return [
                EditDecision(time: caption.startTime, duration: 0.3, type: .zoom, reason: "Hook emphasis", intensity: 0.8),
                EditDecision(time: caption.startTime, duration: 0.2, type: .sfx, reason: "Hook SFX", intensity: 0.7)
            ]

        case .focusBlur:
            return [
                EditDecision(time: caption.startTime, duration: 0.5, type: .zoom, reason: "Focus on reveal", intensity: 0.6)
            ]

        case .underlineReveal:
            return [
                EditDecision(time: caption.startTime, duration: 0.4, type: .flash, reason: "Reveal emphasis", intensity: 0.5)
            ]

        case .keywordLockOn:
            return [
                EditDecision(time: caption.startTime, duration: 0.3, type: .zoom, reason: "Keyword lock", intensity: 0.5),
                EditDecision(time: caption.startTime + 0.1, duration: 0.2, type: .sfx, reason: "Keyword SFX", intensity: 0.4)
            ]

        case .transitionWhoosh:
            return [
                EditDecision(time: caption.startTime, duration: 0.3, type: .sfx, reason: "Transition whoosh", intensity: 0.6)
            ]

        case .conclusionHold:
            return [
                EditDecision(time: caption.startTime, duration: 0.5, type: .colorShift, reason: "Conclusion mood", intensity: 0.4)
            ]

        case .none:
            return []
        }
    }
}
