import Foundation
import SwiftUI

struct CaptionSegment: Sendable, Identifiable {
    let id: UUID
    var startTime: Double
    var endTime: Double
    var text: String
    var role: CaptionRole
    var style: CaptionStyle
    var sceneBehavior: CaptionSceneBehavior

    init(
        id: UUID = UUID(),
        startTime: Double,
        endTime: Double,
        text: String,
        role: CaptionRole,
        style: CaptionStyle,
        sceneBehavior: CaptionSceneBehavior = .none
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.text = text
        self.role = role
        self.style = style
        self.sceneBehavior = sceneBehavior
    }
}

enum CaptionRole: String, Codable, Sendable, CaseIterable {
    case hook
    case regular
    case warning
    case reveal
    case keyword
    case transition
    case conclusion
}

enum CaptionStyle: String, Codable, Sendable, CaseIterable {
    case hookImpact = "hook_impact"
    case boldCenterViral = "bold_center_viral"
    case premiumLowerThird = "premium_lower_third"
    case focusStatement = "focus_statement"
    case minimalWellness = "minimal_wellness"

    var displayName: String {
        switch self {
        case .hookImpact: "Hook Impact"
        case .boldCenterViral: "Bold Center"
        case .premiumLowerThird: "Lower Third"
        case .focusStatement: "Focus"
        case .minimalWellness: "Minimal"
        }
    }
}

enum CaptionSceneBehavior: String, Codable, Sendable, CaseIterable {
    case none
    case hookImpact
    case focusBlur
    case underlineReveal
    case keywordLockOn
    case transitionWhoosh
    case conclusionHold

    var displayName: String {
        switch self {
        case .none: "None"
        case .hookImpact: "Hook Impact"
        case .focusBlur: "Focus Blur"
        case .underlineReveal: "Underline Reveal"
        case .keywordLockOn: "Keyword Lock"
        case .transitionWhoosh: "Whoosh"
        case .conclusionHold: "Hold"
        }
    }
}

// MARK: - Safe Areas for 1080x1920

enum CaptionSafeArea {
    static let topInset: CGFloat = 90
    static let bottomInset: CGFloat = 180
    static let horizontalInset: CGFloat = 80
    static let maxWidthRatio: CGFloat = 0.80
    static let canvasWidth: CGFloat = 1080
    static let canvasHeight: CGFloat = 1920
}
