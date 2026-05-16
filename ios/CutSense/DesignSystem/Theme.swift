import SwiftUI

enum CutSenseTheme {
    // MARK: - Colors
    static let background = Color.black
    static let surface = Color.white.opacity(0.05)
    static let surfaceElevated = Color.white.opacity(0.08)
    static let border = Color.white.opacity(0.12)

    static let textPrimary = Color.white
    static let textSecondary = Color.gray
    static let textTertiary = Color.gray.opacity(0.5)

    static let accent = Color.white
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
}
