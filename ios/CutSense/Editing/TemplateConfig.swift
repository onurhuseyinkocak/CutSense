import Foundation

enum TemplateIntensity: String, Codable, Sendable, CaseIterable {
    case low
    case medium
    case high

    var displayName: String {
        switch self {
        case .low: "Subtle"
        case .medium: "Balanced"
        case .high: "Aggressive"
        }
    }
}

struct TemplateConfig: Sendable {
    let id: String
    let name: String
    let description: String
    let intensity: TemplateIntensity

    // Caption styles per role
    let hookStyle: CaptionStyle
    let emphasisStyle: CaptionStyle
    let keywordStyle: CaptionStyle
    let conclusionStyle: CaptionStyle
    let defaultStyle: CaptionStyle

    // Audio mix
    let backgroundMusicVolume: Float
    let sfxVolume: Float
    let voiceBoostDB: Float

    // Timing
    let minCutDuration: Double
    let maxSilenceDuration: Double
}

// MARK: - Preset Templates

extension TemplateConfig {
    static let premiumFounder = TemplateConfig(
        id: "premium_founder",
        name: "Premium Founder",
        description: "Clean, authoritative look for thought leaders and founders",
        intensity: .low,
        hookStyle: .hookImpact,
        emphasisStyle: .focusStatement,
        keywordStyle: .premiumLowerThird,
        conclusionStyle: .premiumLowerThird,
        defaultStyle: .premiumLowerThird,
        backgroundMusicVolume: 0.08,
        sfxVolume: 0.15,
        voiceBoostDB: 3.0,
        minCutDuration: 0.5,
        maxSilenceDuration: 0.6
    )

    static let viralCaption = TemplateConfig(
        id: "viral_caption",
        name: "Viral Caption",
        description: "Bold, punchy edits for maximum engagement",
        intensity: .high,
        hookStyle: .hookImpact,
        emphasisStyle: .boldCenterViral,
        keywordStyle: .boldCenterViral,
        conclusionStyle: .hookImpact,
        defaultStyle: .boldCenterViral,
        backgroundMusicVolume: 0.15,
        sfxVolume: 0.30,
        voiceBoostDB: 4.5,
        minCutDuration: 0.3,
        maxSilenceDuration: 0.35
    )

    static let cleanExpert = TemplateConfig(
        id: "clean_expert",
        name: "Clean Expert",
        description: "Minimal, polished look for educational content",
        intensity: .medium,
        hookStyle: .focusStatement,
        emphasisStyle: .minimalWellness,
        keywordStyle: .focusStatement,
        conclusionStyle: .minimalWellness,
        defaultStyle: .minimalWellness,
        backgroundMusicVolume: 0.05,
        sfxVolume: 0.10,
        voiceBoostDB: 2.0,
        minCutDuration: 0.4,
        maxSilenceDuration: 0.50
    )

    static let all: [TemplateConfig] = [.premiumFounder, .viralCaption, .cleanExpert]
}
