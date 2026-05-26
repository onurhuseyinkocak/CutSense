import SwiftUI

/// Simple shimmer-skeleton placeholder used during async loading states.
struct SkeletonBlock: View {
    var width: CGFloat? = nil
    var height: CGFloat = 16
    var radius: CGFloat = 4

    @State private var shimmer = false

    var body: some View {
        RoundedRectangle(cornerRadius: radius)
            .fill(Color.white.opacity(0.06))
            .overlay(
                LinearGradient(
                    colors: [
                        .clear,
                        Color.white.opacity(0.08),
                        .clear
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .offset(x: shimmer ? 200 : -200)
                .blendMode(.plusLighter)
                .mask(RoundedRectangle(cornerRadius: radius))
            )
            .frame(width: width, height: height)
            .onAppear {
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    shimmer = true
                }
            }
    }
}
