import SwiftUI

enum CutSenseTheme {
    // MARK: - Colors
    static let background = Color.black
    static let canvas = Color.black
    static let surface = Color.white.opacity(0.05)
    static let surfaceElevated = Color.white.opacity(0.08)
    static let surfaceHigh = Color.white.opacity(0.12)
    static let border = Color.white.opacity(0.12)
    static let borderStrong = Color.white.opacity(0.25)
    static let springSnappy = Animation.spring(response: 0.35, dampingFraction: 0.85)

    static let textPrimary = Color.white
    static let textSecondary = Color.gray
    static let textTertiary = Color.gray.opacity(0.5)
    static let textMuted = Color.gray.opacity(0.4)

    static let accent = Color.white
    static let accentWarm = Color.orange
    static let success = Color.green
    static let warning = Color.yellow
    static let error = Color.red

    // MARK: - Spacing
    static let spacingXS: CGFloat = 4
    static let spacingSM: CGFloat = 8
    static let spacingMD: CGFloat = 16
    static let spacingLG: CGFloat = 24
    static let spacingXL: CGFloat = 32

    // MARK: - Corner Radius
    static let radiusSM: CGFloat = 6
    static let radiusMD: CGFloat = 12
    static let radiusLG: CGFloat = 16
    static let radiusFull: CGFloat = 999

    // MARK: - Typography
    static let titleXL: Font = .system(size: 34, weight: .bold, design: .rounded)
    static let titleL: Font = .system(size: 28, weight: .bold, design: .rounded)
    static let titleM: Font = .system(size: 22, weight: .semibold, design: .rounded)
    static let titleHero: Font = .system(size: 40, weight: .bold, design: .rounded)
    static let bodyEmph: Font = .system(size: 17, weight: .semibold, design: .rounded)
    static let bodyReg: Font = .system(size: 17, weight: .regular, design: .rounded)
    static let label: Font = .system(size: 15, weight: .medium, design: .rounded)
    static let labelSmall: Font = .system(size: 12, weight: .medium, design: .rounded)

    // MARK: - Gradients
    static let heroGradient = LinearGradient(
        colors: [Color.white, Color.white.opacity(0.6)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let canvasGradient = LinearGradient(
        colors: [Color.black, Color(white: 0.05)],
        startPoint: .top,
        endPoint: .bottom
    )
    static let accentSecondary = Color.blue
}

extension View {
    func glassSurface(corner: CGFloat = CutSenseTheme.radiusLG, tint: Color = .white.opacity(0.04)) -> some View {
        background(tint)
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
            )
    }

    func pressableScale(_ scale: CGFloat = 0.97) -> some View {
        self.scaleEffect(1.0)
            .onLongPressGesture(minimumDuration: 0, pressing: { pressing in
                withAnimation(.easeInOut(duration: 0.1)) {
                    // scale effect handled below
                }
            }, perform: {})
    }
}
