import SwiftUI

/// Reusable empty state view for displaying when no content is available.
struct EmptyStateView: View {
    let icon: String
    let title: String
    let subtitle: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: CutSenseTheme.spacingLG) {
            Spacer()

            Image(systemName: icon)
                .font(.system(size: 52, weight: .semibold))
                .foregroundStyle(CutSenseTheme.textSecondary)

            VStack(spacing: CutSenseTheme.spacingMD) {
                Text(title)
                    .font(.title3.bold())
                    .foregroundStyle(CutSenseTheme.textPrimary)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(CutSenseTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }

            Spacer()

            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, CutSenseTheme.spacingMD)
                        .background(CutSenseTheme.accent)
                        .foregroundStyle(CutSenseTheme.background)
                        .clipShape(RoundedRectangle(cornerRadius: CutSenseTheme.radiusMD))
                }
            }

            Spacer()
        }
        .padding(CutSenseTheme.spacingLG)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(subtitle)")
    }
}

/// Loading state view displayed while content is being fetched.
struct LoadingStateView: View {
    let title: String
    let subtitle: String?

    var body: some View {
        VStack(spacing: CutSenseTheme.spacingMD) {
            Spacer()

            ProgressView()
                .tint(CutSenseTheme.accent)
                .scaleEffect(1.2)

            VStack(spacing: CutSenseTheme.spacingSM) {
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundStyle(CutSenseTheme.textPrimary)

                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(CutSenseTheme.textSecondary)
                }
            }

            Spacer()
        }
        .padding(CutSenseTheme.spacingLG)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) \(subtitle ?? "")")
    }
}

#Preview("EmptyStateView") {
    ZStack {
        Color.black.ignoresSafeArea()
        EmptyStateView(
            icon: "film.stack",
            title: "No Projects Yet",
            subtitle: "Import a video to get started with editing",
            actionTitle: "Import Video",
            action: {}
        )
    }
    .preferredColorScheme(.dark)
}

#Preview("LoadingStateView") {
    ZStack {
        Color.black.ignoresSafeArea()
        LoadingStateView(
            title: "Analyzing Video",
            subtitle: "This may take a moment..."
        )
    }
    .preferredColorScheme(.dark)
}
