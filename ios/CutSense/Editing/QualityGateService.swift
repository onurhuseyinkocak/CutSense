import Foundation

struct QualityReport: Sendable {
    let checks: [QualityCheck]
    let passed: Bool
    let score: Int // 0-100

    var failedChecks: [QualityCheck] {
        checks.filter { !$0.passed }
    }
}

struct QualityCheck: Sendable, Identifiable {
    let id = UUID()
    let name: String
    let passed: Bool
    let detail: String
    let severity: Severity

    enum Severity: String, Sendable {
        case critical
        case warning
        case info
    }
}

enum QualityGateService {
    static func evaluate(
        captions: [CaptionSegment],
        editPlan: EditPlan,
        roughCut: RoughCutResult,
        template: TemplateConfig,
        audioQuality: AudioQualityGuard.QualityReport? = nil,
        continuity: ContinuityChecker.ContinuityResult? = nil,
        coherence: MeaningPreservationEngine.PreservationResult? = nil
    ) -> QualityReport {
        var checks: [QualityCheck] = []

        // 1. Caption count check
        let captionCount = captions.count
        checks.append(QualityCheck(
            name: "Caption count",
            passed: captionCount > 0,
            detail: captionCount > 0 ? "\(captionCount) captions generated" : "No captions generated",
            severity: captionCount > 0 ? .info : .critical
        ))

        // 2. Caption readability (none too long)
        let overLong = captions.filter { $0.text.count > 80 }
        checks.append(QualityCheck(
            name: "Caption readability",
            passed: overLong.isEmpty,
            detail: overLong.isEmpty ? "All captions readable" : "\(overLong.count) captions exceed 80 chars",
            severity: overLong.isEmpty ? .info : .warning
        ))

        // 3. Caption timing (min display duration)
        let tooShort = captions.filter { $0.endTime - $0.startTime < 0.5 }
        checks.append(QualityCheck(
            name: "Caption timing",
            passed: tooShort.isEmpty,
            detail: tooShort.isEmpty ? "All captions have adequate display time" : "\(tooShort.count) captions under 0.5s",
            severity: tooShort.isEmpty ? .info : .warning
        ))

        // 4. Effect density
        let effectsPerMinute = roughCut.cleanDuration > 0
            ? Double(editPlan.totalEffects) / (roughCut.cleanDuration / 60.0)
            : 0
        let maxPerMinute: Double = 35
        checks.append(QualityCheck(
            name: "Effect density",
            passed: effectsPerMinute <= maxPerMinute,
            detail: String(format: "%.1f effects/min (max %.0f)", effectsPerMinute, maxPerMinute),
            severity: effectsPerMinute <= maxPerMinute ? .info : .warning
        ))

        // 5. Clean duration sanity
        let retentionRatio = roughCut.originalDuration > 0
            ? roughCut.cleanDuration / roughCut.originalDuration
            : 0
        let tooMuchCut = retentionRatio < 0.3
        let tooLittleCut = retentionRatio > 0.95
        checks.append(QualityCheck(
            name: "Content retention",
            passed: !tooMuchCut && !tooLittleCut,
            detail: String(format: "%.0f%% retained", retentionRatio * 100),
            severity: tooMuchCut ? .critical : (tooLittleCut ? .warning : .info)
        ))

        // 6. Hook presence
        let hasHook = captions.contains { $0.role == .hook }
        checks.append(QualityCheck(
            name: "Hook presence",
            passed: hasHook,
            detail: hasHook ? "Hook caption found" : "No hook caption — first impression weak",
            severity: hasHook ? .info : .warning
        ))

        // 7. Conclusion presence
        let hasConclusion = captions.contains { $0.role == .conclusion }
        checks.append(QualityCheck(
            name: "Conclusion presence",
            passed: hasConclusion,
            detail: hasConclusion ? "Conclusion caption found" : "No conclusion — ending may feel abrupt",
            severity: hasConclusion ? .info : .warning
        ))

        // 8. Audio quality (if available)
        if let aq = audioQuality {
            let passed = aq.passed
            var detail = String(format: "Peak: %.1fdB, Avg: %.1fdB", aq.peakDB, aq.averageDB)
            if aq.isClipping { detail += " [CLIPPING]" }
            if aq.isTooQuiet { detail += " [TOO QUIET]" }
            checks.append(QualityCheck(
                name: "Audio quality",
                passed: passed,
                detail: detail,
                severity: aq.isClipping ? .critical : (passed ? .info : .warning)
            ))
        }

        // 9. Continuity (if available)
        if let cont = continuity {
            let hasBadTransitions = cont.roughTransitions > 0
            let passed = cont.overallScore >= 60
            checks.append(QualityCheck(
                name: "Continuity",
                passed: passed,
                detail: String(format: "%.0f%% smooth (%d rough transitions)", cont.overallScore, cont.roughTransitions),
                severity: hasBadTransitions && !passed ? .warning : .info
            ))
        }

        // 10. Coherence (if available)
        if let coh = coherence {
            let passed = coh.isCoherent
            let highIssues = coh.issues.filter { $0.severity == .high }.count
            checks.append(QualityCheck(
                name: "Coherence",
                passed: passed,
                detail: passed
                    ? String(format: "Score: %.0f/100", coh.overallScore)
                    : "\(highIssues) critical coherence issue(s) — meaning may be lost",
                severity: passed ? .info : .warning
            ))
        }

        // Score
        let criticalFails = checks.filter { !$0.passed && $0.severity == .critical }.count
        let warningFails = checks.filter { !$0.passed && $0.severity == .warning }.count
        let score = max(0, 100 - criticalFails * 30 - warningFails * 10)
        let passed = criticalFails == 0

        return QualityReport(checks: checks, passed: passed, score: score)
    }
}
