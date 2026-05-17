import Foundation

enum IntensityLimiter {
    /// Max effects per 10-second window
    private static let maxEffectsPerWindow: [TemplateIntensity: Int] = [
        .low: 4,
        .medium: 6,
        .high: 10
    ]

    private static let windowDuration: Double = 10.0

    static func limit(_ decisions: [EditDecision], template: TemplateConfig) -> [EditDecision] {
        let maxPerWindow = maxEffectsPerWindow[template.intensity] ?? 4
        guard !decisions.isEmpty else { return [] }

        let sorted = decisions.sorted { $0.time < $1.time }
        var result: [EditDecision] = []

        for decision in sorted {
            let windowStart = decision.time - windowDuration / 2
            let windowEnd = decision.time + windowDuration / 2
            let countInWindow = result.filter { $0.time >= windowStart && $0.time <= windowEnd }.count

            if countInWindow < maxPerWindow {
                result.append(decision)
            }
        }

        return result
    }
}
