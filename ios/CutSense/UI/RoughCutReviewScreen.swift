import SwiftUI

struct RoughCutReviewScreen: View {
    @State var roughCut: RoughCutResult
    let transcription: TranscriptionResult
    let videoURL: URL
    let projectId: UUID
    @State private var showTemplateSelection = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    // Video preview
                    RoughCutPreviewPlayer(
                        videoURL: videoURL,
                        decisions: roughCut.decisions
                    )
                    .padding(.top, 8)

                    // Summary header
                    summaryCard

                    // Decision list
                    VStack(spacing: 1) {
                        ForEach(Array(roughCut.decisions.enumerated()), id: \.element.id) { index, decision in
                            DecisionRow(
                                decision: decision,
                                onRestore: {
                                    restoreSegment(at: index)
                                },
                                onCut: {
                                    cutSegment(at: index)
                                }
                            )
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)

                    // Actions
                    VStack(spacing: 12) {
                        Button {
                            showTemplateSelection = true
                        } label: {
                            Text("Choose Template")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(.white)
                                .foregroundStyle(.black)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
                }
            }
        }
        .navigationTitle("Rough Cut Review")
        .toolbarColorScheme(.dark, for: .navigationBar)
        .navigationDestination(isPresented: $showTemplateSelection) {
            TemplateSelectionScreen(
                roughCut: roughCut,
                transcription: transcription,
                videoURL: videoURL,
                projectId: projectId
            )
        }
    }

    private var summaryCard: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Original")
                        .font(.caption)
                        .foregroundStyle(.gray)
                    Text(formatDuration(roughCut.originalDuration))
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                }
                Spacer()
                Image(systemName: "arrow.right")
                    .foregroundStyle(.gray)
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Clean")
                        .font(.caption)
                        .foregroundStyle(.gray)
                    Text(formatDuration(roughCut.cleanDuration))
                        .font(.title2.bold())
                        .foregroundStyle(.green)
                }
            }

            HStack(spacing: 16) {
                badge("\(roughCut.keepSegments.count) kept", color: .green)
                badge("\(roughCut.cutSegments.count) cut", color: .red)
                if !roughCut.reviewSegments.isEmpty {
                    badge("\(roughCut.reviewSegments.count) review", color: .yellow)
                }
            }
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private func restoreSegment(at index: Int) {
        guard index < roughCut.decisions.count else { return }
        let old = roughCut.decisions[index]
        let restored = RoughCutDecision(
            startTime: old.startTime,
            endTime: old.endTime,
            action: .keep,
            reason: "Restored by user",
            confidence: 1.0,
            linkedTranscriptText: old.linkedTranscriptText,
            requiresReview: false
        )
        var updated = roughCut.decisions
        updated[index] = restored
        roughCut = recalculate(updated)
    }

    private func cutSegment(at index: Int) {
        guard index < roughCut.decisions.count else { return }
        let old = roughCut.decisions[index]
        let cut = RoughCutDecision(
            startTime: old.startTime,
            endTime: old.endTime,
            action: .cut,
            reason: "Cut by user",
            confidence: 1.0,
            linkedTranscriptText: old.linkedTranscriptText,
            requiresReview: false
        )
        var updated = roughCut.decisions
        updated[index] = cut
        roughCut = recalculate(updated)
    }

    private func recalculate(_ decisions: [RoughCutDecision]) -> RoughCutResult {
        let cutDuration = decisions
            .filter { $0.action == .cut || $0.action == .trimStart || $0.action == .trimEnd }
            .reduce(0.0) { $0 + ($1.endTime - $1.startTime) }

        return RoughCutResult(
            decisions: decisions,
            originalDuration: roughCut.originalDuration,
            cleanDuration: max(roughCut.originalDuration - cutDuration, 0),
            keepSegments: decisions.filter { $0.action == .keep },
            cutSegments: decisions.filter { $0.action == .cut || $0.action == .trimStart || $0.action == .trimEnd },
            reviewSegments: decisions.filter { $0.requiresReview }
        )
    }

    private func formatDuration(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

private struct DecisionRow: View {
    let decision: RoughCutDecision
    let onRestore: () -> Void
    let onCut: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                actionBadge
                Spacer()
                Text("\(formatTime(decision.startTime)) - \(formatTime(decision.endTime))")
                    .font(.caption.monospaced())
                    .foregroundStyle(.gray)
            }

            if let text = decision.linkedTranscriptText {
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(decision.action == .cut ? .gray : .white)
                    .strikethrough(decision.action == .cut)
            }

            Text(decision.reason)
                .font(.caption2)
                .foregroundStyle(.gray.opacity(0.7))

            if decision.action != .keep {
                HStack {
                    Button("Restore", action: onRestore)
                        .font(.caption.bold())
                        .foregroundStyle(.green)
                }
            }
            if decision.action == .keep || decision.action == .reviewRequired {
                HStack {
                    Button("Cut", action: onCut)
                        .font(.caption.bold())
                        .foregroundStyle(.red)
                }
            }
        }
        .padding()
        .background(backgroundColor)
    }

    private var actionBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: actionIcon)
            Text(decision.action.rawValue.replacingOccurrences(of: "_", with: " ").uppercased())
                .font(.caption2.bold())
        }
        .foregroundStyle(actionColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(actionColor.opacity(0.12))
        .clipShape(Capsule())
    }

    private var actionIcon: String {
        switch decision.action {
        case .keep: "checkmark"
        case .cut, .trimStart, .trimEnd: "scissors"
        case .reviewRequired: "eye"
        default: "questionmark"
        }
    }

    private var actionColor: Color {
        switch decision.action {
        case .keep: .green
        case .cut, .trimStart, .trimEnd: .red
        case .reviewRequired: .yellow
        default: .gray
        }
    }

    private var backgroundColor: Color {
        switch decision.action {
        case .keep: Color.white.opacity(0.03)
        case .cut, .trimStart, .trimEnd: Color.red.opacity(0.03)
        case .reviewRequired: Color.yellow.opacity(0.05)
        default: Color.white.opacity(0.03)
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        let ms = Int((seconds.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%d:%02d.%d", mins, secs, ms)
    }
}
