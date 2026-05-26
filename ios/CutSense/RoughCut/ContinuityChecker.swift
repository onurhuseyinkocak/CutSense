import Foundation

enum ContinuityChecker {
    enum Profile: Sendable {
        case sourceTimeline
        case shortFormSemantic
    }

    struct ContinuityResult: Sendable {
        let transitions: [TransitionCheck]
        let smoothTransitions: Int
        let roughTransitions: Int
        let overallScore: Float // 0-100
    }

    struct TransitionCheck: Sendable, Identifiable {
        let id = UUID()
        let fromIndex: Int
        let toIndex: Int
        let gapDuration: Double
        let isSmooth: Bool
        let suggestion: String?
    }

    /// Max gap between kept segments that still feels natural
    private static let naturalGapThreshold: Double = 0.5
    /// Gap that definitely needs a transition effect
    private static let roughGapThreshold: Double = 2.0
    /// Source gaps are expected in shorts when both sides are intentional semantic keep ranges.
    private static let shortFormSemanticJumpThreshold: Double = 8.0

    static func check(
        keptDecisions: [RoughCutDecision],
        profile: Profile = .sourceTimeline
    ) -> ContinuityResult {
        guard keptDecisions.count > 1 else {
            return ContinuityResult(
                transitions: [],
                smoothTransitions: 0,
                roughTransitions: 0,
                overallScore: 100
            )
        }

        let sorted = keptDecisions.sorted { $0.startTime < $1.startTime }
        var transitions: [TransitionCheck] = []
        var smooth = 0
        var rough = 0

        for i in 1..<sorted.count {
            let prev = sorted[i - 1]
            let curr = sorted[i]
            let gap = curr.startTime - prev.endTime

            let isSmooth: Bool
            let suggestion: String?

            if gap <= naturalGapThreshold {
                isSmooth = true
                suggestion = nil
                smooth += 1
            } else if gap <= roughGapThreshold {
                isSmooth = true
                suggestion = "Consider audio crossfade (\(String(format: "%.1f", gap))s gap)"
                smooth += 1
            } else if profile == .shortFormSemantic,
                      isIntentionalShortFormJump(from: prev, to: curr, gap: gap) {
                isSmooth = true
                suggestion = "Intentional short-form semantic jump cut"
                smooth += 1
            } else {
                isSmooth = false
                suggestion = "Large gap (\(String(format: "%.1f", gap))s) — add transition or J-cut"
                rough += 1
            }

            transitions.append(TransitionCheck(
                fromIndex: i - 1,
                toIndex: i,
                gapDuration: gap,
                isSmooth: isSmooth,
                suggestion: suggestion
            ))
        }

        let total = smooth + rough
        let score: Float = total > 0 ? Float(smooth) / Float(total) * 100 : 100

        return ContinuityResult(
            transitions: transitions,
            smoothTransitions: smooth,
            roughTransitions: rough,
            overallScore: score
        )
    }

    private static func isIntentionalShortFormJump(
        from previous: RoughCutDecision,
        to current: RoughCutDecision,
        gap: Double
    ) -> Bool {
        gap <= shortFormSemanticJumpThreshold
            && !previous.requiresReview
            && !current.requiresReview
            && isTechSemanticKeep(previous)
            && isTechSemanticKeep(current)
    }

    private static func isTechSemanticKeep(_ decision: RoughCutDecision) -> Bool {
        decision.action == .keep
            && decision.reason.localizedStandardContains("Tech semantic keep")
    }
}
