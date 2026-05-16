import Foundation

enum CaptionEngine {
    static func generateCaptions(
        from transcription: TranscriptionResult,
        roughCut: RoughCutResult,
        template: TemplateConfig
    ) -> [CaptionSegment] {
        // Only use kept segments
        let keptDecisions = roughCut.keepSegments
        let keptTimeRanges = keptDecisions.map { $0.startTime...$0.endTime }

        // Filter transcript segments that fall within kept ranges
        let keptTranscriptSegments = transcription.segments.filter { segment in
            keptTimeRanges.contains { range in
                range.contains(segment.startTime) || range.contains(segment.endTime)
            }
        }

        guard !keptTranscriptSegments.isEmpty else { return [] }

        // Classify roles
        var captions: [CaptionSegment] = []
        var previousRole: CaptionRole?

        for (index, segment) in keptTranscriptSegments.enumerated() {
            let role = CaptionRoleClassifier.classify(
                text: segment.text,
                index: index,
                totalSegments: keptTranscriptSegments.count,
                previousRole: previousRole
            )

            let style = styleForRole(role, template: template)

            captions.append(CaptionSegment(
                startTime: segment.startTime,
                endTime: segment.endTime,
                text: segment.text,
                role: role,
                style: style
            ))

            previousRole = role
        }

        // Assign scene behaviors
        captions = CaptionSceneEventPlanner.assignSceneBehaviors(
            to: captions,
            template: template
        )

        // Validate readability
        captions = CaptionReadabilityGuard.validate(captions)

        return captions
    }

    private static func styleForRole(_ role: CaptionRole, template: TemplateConfig) -> CaptionStyle {
        switch role {
        case .hook:
            return template.hookStyle
        case .reveal, .warning:
            return template.emphasisStyle
        case .keyword:
            return template.keywordStyle
        case .conclusion:
            return template.conclusionStyle
        default:
            return template.defaultStyle
        }
    }
}
