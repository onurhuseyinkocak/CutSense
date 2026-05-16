import Foundation

struct TimelineDebugLog: Sendable {
    let entries: [Entry]
    let summary: Summary

    struct Entry: Sendable, Identifiable {
        let id = UUID()
        let time: Double
        let endTime: Double
        let category: Category
        let label: String
        let detail: String?

        enum Category: String, Sendable {
            case keep
            case cut
            case caption
            case effect
            case warning
        }
    }

    struct Summary: Sendable {
        let originalDuration: Double
        let cleanDuration: Double
        let captionCount: Int
        let effectCount: Int
        let qualityScore: Int
        let warnings: [String]
    }
}

enum TimelineDebugLogger {
    static func generate(
        roughCut: RoughCutResult,
        captions: [CaptionSegment],
        editPlan: EditPlan?,
        qualityReport: QualityReport?
    ) -> TimelineDebugLog {
        var entries: [TimelineDebugLog.Entry] = []

        // Timeline segments
        for decision in roughCut.decisions.sorted(by: { $0.startTime < $1.startTime }) {
            let category: TimelineDebugLog.Entry.Category = decision.action == .keep ? .keep : .cut
            entries.append(TimelineDebugLog.Entry(
                time: decision.startTime,
                endTime: decision.endTime,
                category: category,
                label: "\(decision.action.rawValue): \(formatTime(decision.startTime))-\(formatTime(decision.endTime))",
                detail: decision.reason
            ))
        }

        // Captions
        for caption in captions {
            entries.append(TimelineDebugLog.Entry(
                time: caption.startTime,
                endTime: caption.endTime,
                category: .caption,
                label: "[\(caption.style.rawValue)] \(caption.text.prefix(40))",
                detail: caption.sceneBehavior != .none ? "behavior: \(caption.sceneBehavior.rawValue)" : nil
            ))
        }

        // Effects
        if let plan = editPlan {
            for decision in plan.decisions {
                entries.append(TimelineDebugLog.Entry(
                    time: decision.time,
                    endTime: decision.time + decision.duration,
                    category: .effect,
                    label: "\(decision.type.rawValue) (intensity: \(String(format: "%.0f%%", decision.intensity * 100)))",
                    detail: decision.reason
                ))
            }
        }

        // Quality warnings
        if let report = qualityReport {
            for check in report.failedChecks {
                entries.append(TimelineDebugLog.Entry(
                    time: 0,
                    endTime: 0,
                    category: .warning,
                    label: "[\(check.severity.rawValue)] \(check.name)",
                    detail: check.detail
                ))
            }
        }

        // Sort by time
        entries.sort { $0.time < $1.time }

        let warnings = qualityReport?.failedChecks.map { "[\($0.severity.rawValue)] \($0.name): \($0.detail)" } ?? []

        let summary = TimelineDebugLog.Summary(
            originalDuration: roughCut.originalDuration,
            cleanDuration: roughCut.cleanDuration,
            captionCount: captions.count,
            effectCount: editPlan?.totalEffects ?? 0,
            qualityScore: qualityReport?.score ?? -1,
            warnings: warnings
        )

        return TimelineDebugLog(entries: entries, summary: summary)
    }

    static func printLog(_ log: TimelineDebugLog) {
        #if DEBUG
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🎬 CutSense Timeline Debug Log")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("Original: \(formatTime(log.summary.originalDuration)) → Clean: \(formatTime(log.summary.cleanDuration))")
        print("Captions: \(log.summary.captionCount) | Effects: \(log.summary.effectCount) | Quality: \(log.summary.qualityScore)/100")
        print("──────────────────────────────────────────")
        for entry in log.entries {
            let icon: String = switch entry.category {
            case .keep: "✅"
            case .cut: "✂️"
            case .caption: "💬"
            case .effect: "✨"
            case .warning: "⚠️"
            }
            let line = "\(icon) \(formatTime(entry.time)) \(entry.label)"
            print(line)
            if let detail = entry.detail {
                print("   └─ \(detail)")
            }
        }
        if !log.summary.warnings.isEmpty {
            print("──────────────────────────────────────────")
            print("⚠️ Warnings:")
            for w in log.summary.warnings { print("  • \(w)") }
        }
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        #endif
    }

    private static func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        let ms = Int((seconds.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%d:%02d.%02d", mins, secs, ms)
    }
}
