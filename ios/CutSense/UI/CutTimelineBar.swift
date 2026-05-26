import SwiftUI

/// Interactive timeline showing source video with cut regions, keep regions,
/// and tap-to-jump markers at each edit boundary.
struct CutTimelineBar: View {
    let decisions: [RoughCutDecision]
    let sourceDuration: Double
    @Binding var currentTime: Double

    @State private var expandedCutIndex: Int?

    private var sortedDecisions: [RoughCutDecision] {
        decisions.sorted { $0.startTime < $1.startTime }
    }

    /// Edit boundaries — positions where a cut meets a keep segment.
    private var cutBoundaries: [CutBoundary] {
        let sorted = sortedDecisions
        var boundaries: [CutBoundary] = []
        for i in 0..<sorted.count {
            let d = sorted[i]
            guard d.action == .cut else { continue }
            // Find adjacent keep segments
            let prevKeep = i > 0 && sorted[i - 1].action == .keep ? sorted[i - 1] : nil
            let nextKeep = i < sorted.count - 1 && sorted[i + 1].action == .keep ? sorted[i + 1] : nil
            boundaries.append(CutBoundary(
                index: i,
                cutDecision: d,
                sourceTime: d.startTime,
                prevKeepEnd: prevKeep?.endTime,
                nextKeepStart: nextKeep?.startTime
            ))
        }
        return boundaries
    }

    var body: some View {
        VStack(spacing: 6) {
            // Timeline bar
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    // Background track
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.06))
                        .frame(height: 28)

                    // Decision regions
                    ForEach(Array(sortedDecisions.enumerated()), id: \.element.id) { idx, decision in
                        let startFrac = decision.startTime / max(sourceDuration, 0.01)
                        let endFrac = decision.endTime / max(sourceDuration, 0.01)
                        let xPos = startFrac * w
                        let regionW = max((endFrac - startFrac) * w, 1)

                        RoundedRectangle(cornerRadius: 2)
                            .fill(regionColor(decision))
                            .frame(width: regionW, height: 20)
                            .offset(x: xPos)
                            .onTapGesture {
                                // Jump to start of this segment
                                currentTime = cleanTimeForSource(decision.startTime)
                                HapticEngine.tap()
                            }
                    }

                    // Cut boundary markers
                    ForEach(Array(cutBoundaries.enumerated()), id: \.element.cutDecision.id) { idx, boundary in
                        let frac = boundary.sourceTime / max(sourceDuration, 0.01)
                        let xPos = frac * w

                        Circle()
                            .fill(Color.white)
                            .frame(width: 8, height: 8)
                            .shadow(color: .black.opacity(0.5), radius: 2)
                            .frame(width: 44, height: 44)
                            .contentShape(Circle().size(width: 44, height: 44))
                            .offset(x: xPos - 22)
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    expandedCutIndex = expandedCutIndex == idx ? nil : idx
                                }
                                currentTime = cleanTimeForSource(boundary.sourceTime)
                                HapticEngine.impact()
                            }
                            .accessibilityLabel("Cut point at \(formatTime(boundary.sourceTime))")
                            .accessibilityHint("Tap to show cut details")
                    }

                    // Playhead
                    let playheadSource = sourceTimeForClean(currentTime)
                    let playFrac = playheadSource / max(sourceDuration, 0.01)
                    RoundedRectangle(cornerRadius: 1)
                        .fill(.white)
                        .frame(width: 2, height: 32)
                        .offset(x: min(max(playFrac * w - 1, 0), w - 2))
                        .animation(.easeOut(duration: 0.1), value: currentTime)
                }
                .frame(height: 44)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let frac = min(max(value.location.x / w, 0), 1)
                            let sourceTime = frac * sourceDuration
                            currentTime = cleanTimeForSource(sourceTime)
                        }
                )
            }
            .frame(height: 44)

            // Legend
            HStack(spacing: 12) {
                legendDot(color: .green.opacity(0.6), label: "Keep")
                legendDot(color: .red.opacity(0.5), label: "Cut")
                legendDot(color: .yellow.opacity(0.5), label: "Review")

                Spacer()

                Text("\(cutBoundaries.count) cuts")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.gray)
            }

            // Expanded cut detail
            if let idx = expandedCutIndex, idx < cutBoundaries.count {
                cutDetailCard(cutBoundaries[idx])
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .opacity
                    ))
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Cut Detail Card

    private func cutDetailCard(_ boundary: CutBoundary) -> some View {
        let cut = boundary.cutDecision
        let duration = cut.endTime - cut.startTime

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "scissors")
                    .font(.caption)
                    .foregroundStyle(.red.opacity(0.8))
                Text("Cut: \(formatTime(cut.startTime)) – \(formatTime(cut.endTime))")
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(.white)
                Spacer()
                Text(String(format: "%.1fs", duration))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.gray)
            }

            if let text = cut.linkedTranscriptText, !text.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "text.quote")
                        .font(.caption2)
                        .foregroundStyle(.gray)
                    Text("\"\(text)\"")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(2)
                }
            }

            HStack(spacing: 8) {
                // Reason
                Text(cut.reason)
                    .font(.caption2)
                    .foregroundStyle(.orange.opacity(0.8))
                    .lineLimit(1)

                Spacer()

                // Confidence
                Text("\(Int(cut.confidence * 100))% conf")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.gray)
            }
        }
        .padding(10)
        .background(Color.red.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.red.opacity(0.2), lineWidth: 0.5)
        )
    }

    // MARK: - Helpers

    private func regionColor(_ decision: RoughCutDecision) -> Color {
        switch decision.action {
        case .keep: .green.opacity(0.5)
        case .cut: .red.opacity(0.35)
        case .trimStart, .trimEnd: .yellow.opacity(0.4)
        case .reviewRequired: .yellow.opacity(0.4)
        case .replaceWithBetterTake, .mergeWithNext, .addAudioFade: .orange.opacity(0.35)
        }
    }

    /// Map source time → clean timeline time (what the player uses).
    private func cleanTimeForSource(_ sourceTime: Double) -> Double {
        let keepSegments = decisions
            .filter { $0.action == .keep }
            .sorted { $0.startTime < $1.startTime }

        var cleanOffset: Double = 0
        for seg in keepSegments {
            if sourceTime >= seg.startTime && sourceTime < seg.endTime {
                return cleanOffset + (sourceTime - seg.startTime)
            }
            if sourceTime >= seg.endTime {
                cleanOffset += seg.endTime - seg.startTime
            }
        }
        return cleanOffset
    }

    /// Map clean timeline time → source time (inverse of above).
    private func sourceTimeForClean(_ cleanTime: Double) -> Double {
        let keepSegments = decisions
            .filter { $0.action == .keep }
            .sorted { $0.startTime < $1.startTime }

        var cleanOffset: Double = 0
        for seg in keepSegments {
            let segDur = seg.endTime - seg.startTime
            if cleanTime >= cleanOffset && cleanTime < cleanOffset + segDur {
                return seg.startTime + (cleanTime - cleanOffset)
            }
            cleanOffset += segDur
        }
        // Past end — return last keep end
        return keepSegments.last?.endTime ?? 0
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.gray)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) region")
    }

    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        let ms = Int((seconds.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%d:%02d.%d", mins, secs, ms)
    }
}

// MARK: - Cut Boundary Model

private struct CutBoundary {
    let index: Int
    let cutDecision: RoughCutDecision
    let sourceTime: Double
    let prevKeepEnd: Double?
    let nextKeepStart: Double?
}
