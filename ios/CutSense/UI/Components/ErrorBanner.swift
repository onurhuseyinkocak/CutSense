import SwiftUI

/// Reusable inline error banner for displaying error messages with optional retry action.
struct ErrorBanner: View {
    let message: String
    var retryAction: (() -> Void)?

    var body: some View {
        HStack(spacing: CutSenseTheme.spacingMD) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(CutSenseTheme.warning)
                .font(.system(size: 16, weight: .semibold))

            VStack(alignment: .leading, spacing: 2) {
                Text("Error")
                    .font(.caption.bold())
                    .foregroundStyle(CutSenseTheme.warning)

                Text(message)
                    .font(.caption)
                    .foregroundStyle(CutSenseTheme.textPrimary)
                    .lineLimit(3)
            }

            Spacer()

            if let retryAction {
                Button(action: retryAction) {
                    Text("Retry")
                        .font(.caption.bold())
                        .foregroundStyle(CutSenseTheme.textPrimary)
                        .padding(.horizontal, CutSenseTheme.spacingSM)
                        .padding(.vertical, 4)
                        .background(CutSenseTheme.warning.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: CutSenseTheme.radiusSM))
                }
            }
        }
        .padding(CutSenseTheme.spacingMD)
        .background(CutSenseTheme.warning.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: CutSenseTheme.radiusMD))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error: \(message)")
    }
}

/// Reusable error state view for displaying full-screen or large-area error messages.
struct ErrorStateView: View {
    let title: String
    let message: String
    var icon: String = "exclamationmark.triangle.fill"
    var retryTitle: String = "Retry"
    var retryAction: (() -> Void)?
    var secondaryAction: (() -> Void)?
    var secondaryTitle: String = "Go Back"

    var body: some View {
        VStack(spacing: CutSenseTheme.spacingLG) {
            Spacer()

            Image(systemName: icon)
                .font(.system(size: 52, weight: .semibold))
                .foregroundStyle(CutSenseTheme.error)

            VStack(spacing: CutSenseTheme.spacingMD) {
                Text(title)
                    .font(.title3.bold())
                    .foregroundStyle(CutSenseTheme.textPrimary)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(CutSenseTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(5)
            }

            Spacer()

            VStack(spacing: CutSenseTheme.spacingMD) {
                if let retryAction {
                    Button(action: retryAction) {
                        Text(retryTitle)
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, CutSenseTheme.spacingMD)
                            .background(CutSenseTheme.error.opacity(0.15))
                            .foregroundStyle(CutSenseTheme.error)
                            .clipShape(RoundedRectangle(cornerRadius: CutSenseTheme.radiusMD))
                    }
                }

                if let secondaryAction {
                    Button(action: secondaryAction) {
                        Text(secondaryTitle)
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, CutSenseTheme.spacingMD)
                            .background(CutSenseTheme.surface)
                            .foregroundStyle(CutSenseTheme.textSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: CutSenseTheme.radiusMD))
                    }
                }
            }

            Spacer()
        }
        .padding(CutSenseTheme.spacingLG)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error: \(title)")
    }
}

#Preview("ErrorBanner with Retry") {
    ZStack {
        Color.black.ignoresSafeArea()
        VStack(spacing: 20) {
            ErrorBanner(
                message: "Failed to export video. Check your storage space.",
                retryAction: {}
            )
            ErrorBanner(
                message: "Network connection lost"
            )
            Spacer()
        }
        .padding()
    }
}

#Preview("ErrorStateView") {
    ZStack {
        Color.black.ignoresSafeArea()
        ErrorStateView(
            title: "Export Failed",
            message: "There wasn't enough storage space to complete the export. Free up space and try again.",
            retryAction: {},
            secondaryAction: {},
            secondaryTitle: "Go Back"
        )
    }
    .preferredColorScheme(.dark)
}
