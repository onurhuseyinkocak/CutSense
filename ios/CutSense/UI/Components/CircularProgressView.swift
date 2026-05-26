import SwiftUI

/// Circular progress ring with centered label and stats
struct CircularProgressView: View {
    let progress: Float
    let elapsedTime: TimeInterval
    let estimatedTimeRemaining: TimeInterval?
    let label: String

    private var displayedPercentage: Int {
        Int(progress * 100)
    }

    private var elapsedFormatted: String {
        formatTime(elapsedTime)
    }

    private var estimatedFormatted: String? {
        guard let estimated = estimatedTimeRemaining, estimated > 1 else { return nil }
        return formatTime(estimated)
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        if mins > 0 {
            return "\(mins)m \(secs)s"
        }
        return "\(secs)s"
    }

    var body: some View {
        VStack(spacing: 20) {
            // Circular progress ring
            ZStack {
                // Background circle
                Circle()
                    .stroke(lineWidth: 8)
                    .opacity(0.15)
                    .foregroundStyle(.white)

                // Progress ring
                Circle()
                    .trim(from: 0, to: CGFloat(progress))
                    .stroke(
                        style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            gradient: Gradient(colors: [.blue, .cyan]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.3), value: progress)

                // Center content
                VStack(spacing: 8) {
                    Text("\(displayedPercentage)%")
                        .font(.title.bold().monospacedDigit())
                        .foregroundStyle(.white)
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                        .id(displayedPercentage)  // Force re-render on percentage change

                    Text(label)
                        .font(.caption2)
                        .foregroundStyle(.gray)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(width: 140, height: 140)

            // Time info
            VStack(spacing: 8) {
                HStack(spacing: 16) {
                    HStack(spacing: 4) {
                        Image(systemName: "timer")
                            .font(.caption)
                            .foregroundStyle(.gray)
                        Text(elapsedFormatted)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(CutSenseTheme.textSecondary)
                    }

                    Divider()
                        .frame(height: 12)

                    if let estimated = estimatedFormatted {
                        HStack(spacing: 4) {
                            Image(systemName: "hourglass.end")
                                .font(.caption)
                                .foregroundStyle(.gray)
                            Text(estimated)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(CutSenseTheme.textSecondary)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Material.ultraThin)
                .cornerRadius(8)
            }
        }
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack(spacing: 40) {
            // 25% progress
            CircularProgressView(
                progress: 0.25,
                elapsedTime: 12,
                estimatedTimeRemaining: 36,
                label: "Building timeline..."
            )

            // 75% progress
            CircularProgressView(
                progress: 0.75,
                elapsedTime: 45,
                estimatedTimeRemaining: 15,
                label: "Rendering captions..."
            )
        }
        .padding(.horizontal, 40)
    }
}
