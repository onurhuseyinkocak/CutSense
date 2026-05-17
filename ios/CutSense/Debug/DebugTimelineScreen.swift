import SwiftUI

/// Debug screen showing per-segment pipeline decisions.
/// Access: shake gesture or debug menu in dev builds.
struct DebugTimelineScreen: View {
    let segments: [DebugSegmentRow]
    let qualityReport: QualityReport?
    let reportJSON: String?

    var body: some View {
        NavigationStack {
            List {
                if let report = qualityReport {
                    Section("Quality Gate") {
                        HStack {
                            Text("Score")
                            Spacer()
                            Text("\(report.score)/100")
                                .foregroundStyle(report.passed ? .green : .red)
                                .bold()
                        }
                        ForEach(report.checks) { check in
                            HStack {
                                Image(systemName: check.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundStyle(check.passed ? .green : (check.severity == .critical ? .red : .orange))
                                VStack(alignment: .leading) {
                                    Text(check.name)
                                        .font(.subheadline.bold())
                                    Text(check.detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                Section("Timeline (\(segments.count) segments)") {
                    ForEach(segments) { row in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(String(format: "%.1f-%.1fs", row.startTime, row.endTime))
                                    .font(.caption.monospaced())
                                Spacer()
                                Text(row.action)
                                    .font(.caption.bold())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(row.actionColor.opacity(0.2))
                                    .clipShape(Capsule())
                            }

                            Text(row.text)
                                .font(.subheadline)
                                .lineLimit(2)

                            HStack(spacing: 12) {
                                Label(row.reason, systemImage: "info.circle")
                                Label(String(format: "%.0f%%", row.confidence * 100), systemImage: "gauge")
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                            if let captionRole = row.captionRole {
                                HStack(spacing: 8) {
                                    Label(captionRole, systemImage: "text.bubble")
                                    if let style = row.captionStyle {
                                        Text(style).foregroundStyle(.blue)
                                    }
                                    if let behavior = row.sceneBehavior, behavior != "none" {
                                        Text(behavior).foregroundStyle(.purple)
                                    }
                                }
                                .font(.caption2)
                            }

                            if !row.effects.isEmpty {
                                HStack(spacing: 4) {
                                    ForEach(row.effects, id: \.self) { effect in
                                        Text(effect)
                                            .font(.caption2.bold())
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .background(.orange.opacity(0.15))
                                            .clipShape(Capsule())
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .navigationTitle("Debug Timeline")
            .toolbar {
                if let json = reportJSON {
                    ShareLink(item: json, preview: SharePreview("Debug Report"))
                }
            }
        }
    }
}

// MARK: - Row model

struct DebugSegmentRow: Identifiable, Sendable {
    let id = UUID()
    let startTime: Double
    let endTime: Double
    let text: String
    let action: String
    let reason: String
    let confidence: Float
    let captionRole: String?
    let captionStyle: String?
    let sceneBehavior: String?
    let effects: [String]

    var actionColor: Color {
        switch action.lowercased() {
        case "keep": .green
        case "cut": .red
        case "review": .orange
        default: .gray
        }
    }
}

// MARK: - Builder

extension DebugTimelineScreen {
    static func build(
        roughCut: RoughCutResult,
        captions: [CaptionSegment],
        editPlan: EditPlan,
        qualityReport: QualityReport?
    ) -> DebugTimelineScreen {
        var rows: [DebugSegmentRow] = []

        for decision in roughCut.decisions.sorted(by: { $0.startTime < $1.startTime }) {
            let caption = captions.first { c in
                c.startTime >= decision.startTime - 0.1 && c.startTime <= decision.endTime + 0.1
            }
            let effects = editPlan.decisions
                .filter { $0.time >= decision.startTime && $0.time <= decision.endTime }
                .map { "\($0.type.rawValue) (\(String(format: "%.0f%%", $0.intensity * 100)))" }

            rows.append(DebugSegmentRow(
                startTime: decision.startTime,
                endTime: decision.endTime,
                text: decision.linkedTranscriptText ?? "[silence/gap]",
                action: decision.action.rawValue,
                reason: decision.reason,
                confidence: decision.confidence,
                captionRole: caption?.role.rawValue,
                captionStyle: caption?.style.rawValue,
                sceneBehavior: caption?.sceneBehavior.rawValue,
                effects: effects
            ))
        }

        var reportJSON: String?
        if let report = qualityReport {
            let lines = report.checks.map { "\($0.passed ? "PASS" : "FAIL") \($0.name): \($0.detail)" }
            reportJSON = "Score: \(report.score)/100\n" + lines.joined(separator: "\n")
        }

        return DebugTimelineScreen(
            segments: rows,
            qualityReport: qualityReport,
            reportJSON: reportJSON
        )
    }
}
