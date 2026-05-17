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
    case cutTransition = "cut_transition"
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

        // Add cut transition effects at segment boundaries
        let cutTransitions = generateCutTransitions(
            roughCut: roughCut,
            template: template
        )
        decisions.append(contentsOf: cutTransitions)

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
                EditDecision(time: caption.startTime, duration: 0.4, type: .zoom, reason: "Hook emphasis", intensity: 0.85),
                EditDecision(time: caption.startTime, duration: 0.2, type: .sfx, reason: "Hook SFX", intensity: 0.7),
                EditDecision(time: caption.startTime, duration: 0.15, type: .flash, reason: "Hook flash", intensity: 0.4)
            ]

        case .focusBlur:
            return [
                EditDecision(time: caption.startTime, duration: 0.5, type: .zoom, reason: "Focus on reveal", intensity: 0.6),
                EditDecision(time: caption.startTime, duration: 0.2, type: .sfx, reason: "Focus SFX", intensity: 0.35)
            ]

        case .underlineReveal:
            return [
                EditDecision(time: caption.startTime, duration: 0.4, type: .flash, reason: "Reveal emphasis", intensity: 0.5),
                EditDecision(time: caption.startTime + 0.1, duration: 0.2, type: .sfx, reason: "Reveal SFX", intensity: 0.35)
            ]

        case .keywordLockOn:
            return [
                EditDecision(time: caption.startTime, duration: 0.3, type: .zoom, reason: "Keyword lock", intensity: 0.55),
                EditDecision(time: caption.startTime + 0.1, duration: 0.2, type: .sfx, reason: "Keyword SFX", intensity: 0.4)
            ]

        case .transitionWhoosh:
            return [
                EditDecision(time: caption.startTime, duration: 0.3, type: .sfx, reason: "Transition whoosh", intensity: 0.6),
                EditDecision(time: caption.startTime, duration: 0.25, type: .flash, reason: "Transition flash", intensity: 0.3)
            ]

        case .conclusionHold:
            return [
                EditDecision(time: caption.startTime, duration: 0.6, type: .colorShift, reason: "Conclusion mood", intensity: 0.45),
                EditDecision(time: caption.startTime, duration: 0.2, type: .sfx, reason: "Conclusion SFX", intensity: 0.3)
            ]

        case .subtleZoom:
            return [
                EditDecision(time: caption.startTime, duration: 0.35, type: .zoom, reason: "Subtle emphasis", intensity: 0.35)
            ]

        case .punchIn:
            return [
                EditDecision(time: caption.startTime, duration: 0.25, type: .zoom, reason: "Punch in", intensity: 0.55),
                EditDecision(time: caption.startTime, duration: 0.15, type: .sfx, reason: "Punch SFX", intensity: 0.3)
            ]

        case .none:
            return []
        }
    }

    /// Generate visual transition effects at cut boundaries (where segments were removed)
    private static func generateCutTransitions(
        roughCut: RoughCutResult,
        template: TemplateConfig
    ) -> [EditDecision] {
        guard template.intensity != .low else { return [] }

        let keepSegments = roughCut.decisions
            .filter { $0.action == .keep }
            .sorted { $0.startTime < $1.startTime }

        guard keepSegments.count >= 2 else { return [] }

        var transitions: [EditDecision] = []
        var cleanTime: Double = 0

        for i in 0..<(keepSegments.count - 1) {
            let current = keepSegments[i]
            let next = keepSegments[i + 1]
            let segmentDuration = current.endTime - current.startTime
            cleanTime += segmentDuration

            // Only add transition if there was actually a cut (gap between segments)
            let gap = next.startTime - current.endTime
            guard gap > 0.3 else { continue }

            // cutTransition at the boundary point in clean timeline
            let transitionDuration: Double = template.intensity == .high ? 0.2 : 0.15
            transitions.append(EditDecision(
                time: cleanTime - 0.05,
                duration: transitionDuration,
                type: .cutTransition,
                reason: "Cut boundary",
                intensity: template.intensity == .high ? 0.5 : 0.3
            ))

            // Add whoosh SFX at cut point for high intensity
            if template.intensity == .high {
                transitions.append(EditDecision(
                    time: cleanTime - 0.05,
                    duration: 0.2,
                    type: .sfx,
                    reason: "Cut whoosh",
                    intensity: 0.35
                ))
            }
        }

        return transitions
    }
}
