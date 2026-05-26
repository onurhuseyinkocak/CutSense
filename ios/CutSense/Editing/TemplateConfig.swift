import Foundation
import UIKit

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

/// Cross-segment visual transition style applied at cut boundaries.
enum TransitionStyle: String, Codable, Sendable, CaseIterable {
    case crossDissolve
    case dip       // black-dip transition
    case whipPan
    case flash

    var displayName: String {
        switch self {
        case .crossDissolve: "Cross Dissolve"
        case .dip: "Black Dip"
        case .whipPan: "Whip Pan"
        case .flash: "Flash"
        }
    }
}

/// Top-level category for grouping templates in the picker / hub.
enum TemplateCategory: String, Codable, Sendable, CaseIterable {
    case professional
    case social
    case creative
    case lifestyle

    var displayName: String {
        switch self {
        case .professional: "Professional"
        case .social: "Social"
        case .creative: "Creative"
        case .lifestyle: "Lifestyle"
        }
    }

    var icon: String {
        switch self {
        case .professional: "briefcase.fill"
        case .social: "bolt.fill"
        case .creative: "paintbrush.fill"
        case .lifestyle: "sun.max.fill"
        }
    }
}

struct TemplateConfig: Sendable, Codable {
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

    // Color grading
    let colorGrade: ColorGrade

    // Visual transition between segments at cut boundaries
    var transitionStyle: TransitionStyle = .crossDissolve
    var transitionDuration: Double = 0.18

    // Grouping for picker UI
    var category: TemplateCategory = .creative

    // Caption pacing (min gap between consecutive caption reveals, seconds)
    var captionMinGap: Double = 1.2

    // Theme override for custom templates (maps to a preset theme by id)
    var themeId: String? = nil

    struct TintColor: Sendable, Codable {
        var r: Float
        var g: Float
        var b: Float
        static let zero = TintColor(r: 0, g: 0, b: 0)
    }

    struct ColorGrade: Sendable, Codable {
        let saturation: Float    // 1.0 = neutral
        let brightness: Float    // 0.0 = neutral
        let contrast: Float      // 1.0 = neutral
        let warmth: Float        // 0.0 = neutral, >0 warm, <0 cool
        let vignetteIntensity: Float // 0.0 = off
        var fade: Float = 0.0                  // black-point lift; 0 = off
        var highlightsTint: TintColor = .zero  // RGB tint of highlights
        var shadowsTint: TintColor = .zero     // RGB tint of shadows
        var sharpen: Float = 0.0               // 0 = off; up to ~0.5
        var grain: Float = 0.0                 // film-grain intensity, 0 = off

        static let none = ColorGrade(saturation: 1.0, brightness: 0.0, contrast: 1.0, warmth: 0.0, vignetteIntensity: 0.0)
    }

    /// Per-template caption color theme for karaoke reveal + text styling
    struct CaptionTheme: Sendable {
        let karaokeHighlight: CaptionColor   // Active word color
        let karaokeDim: CaptionColor         // Unrevealed word color
        let wordHighlightBg: CaptionColor    // Background behind active word
        let hookTextColor: CaptionColor      // Hook caption text
        let hookBgColor: CaptionColor        // Hook caption background
        let defaultTextColor: CaptionColor   // Regular caption text
        let shadowColor: CaptionColor        // Text shadow
        let glowEnabled: Bool                // Neon glow effect on active word

        struct CaptionColor: Sendable {
            let r: Float, g: Float, b: Float, a: Float

            static let white = CaptionColor(r: 1, g: 1, b: 1, a: 1)
            static let clear = CaptionColor(r: 0, g: 0, b: 0, a: 0)

            var uiColor: UIColor {
                UIColor(red: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: CGFloat(a))
            }
        }

        static let premiumGold = CaptionTheme(
            karaokeHighlight: CaptionColor(r: 1.0, g: 0.84, b: 0.0, a: 1.0),     // Gold
            karaokeDim: CaptionColor(r: 0.7, g: 0.7, b: 0.7, a: 0.7),
            wordHighlightBg: CaptionColor(r: 1.0, g: 0.84, b: 0.0, a: 0.2),
            hookTextColor: .white,
            hookBgColor: CaptionColor(r: 0.15, g: 0.15, b: 0.15, a: 0.85),        // Dark charcoal
            defaultTextColor: .white,
            shadowColor: CaptionColor(r: 0, g: 0, b: 0, a: 0.7),
            glowEnabled: false
        )

        static let neonViral = CaptionTheme(
            karaokeHighlight: CaptionColor(r: 0.0, g: 1.0, b: 0.8, a: 1.0),      // Neon cyan-green
            karaokeDim: CaptionColor(r: 0.82, g: 0.82, b: 0.82, a: 0.86),
            wordHighlightBg: CaptionColor(r: 0.0, g: 1.0, b: 0.8, a: 0.25),
            hookTextColor: .white,
            hookBgColor: CaptionColor(r: 0.03, g: 0.035, b: 0.04, a: 0.68),
            defaultTextColor: .white,
            shadowColor: CaptionColor(r: 0, g: 0, b: 0, a: 0.8),
            glowEnabled: true
        )

        static let monoClean = CaptionTheme(
            karaokeHighlight: .white,
            karaokeDim: CaptionColor(r: 0.5, g: 0.5, b: 0.5, a: 0.65),
            wordHighlightBg: CaptionColor(r: 1.0, g: 1.0, b: 1.0, a: 0.12),
            hookTextColor: .white,
            hookBgColor: CaptionColor(r: 0.1, g: 0.1, b: 0.1, a: 0.7),
            defaultTextColor: CaptionColor(r: 0.95, g: 0.95, b: 0.95, a: 0.9),
            shadowColor: CaptionColor(r: 0, g: 0, b: 0, a: 0.5),
            glowEnabled: false
        )

        static let warmCinematic = CaptionTheme(
            karaokeHighlight: CaptionColor(r: 1.0, g: 0.72, b: 0.3, a: 1.0),   // Warm amber
            karaokeDim: CaptionColor(r: 0.6, g: 0.55, b: 0.45, a: 0.65),
            wordHighlightBg: CaptionColor(r: 1.0, g: 0.72, b: 0.3, a: 0.18),
            hookTextColor: CaptionColor(r: 1.0, g: 0.95, b: 0.85, a: 1.0),     // Warm white
            hookBgColor: CaptionColor(r: 0.12, g: 0.08, b: 0.04, a: 0.85),     // Dark sepia
            defaultTextColor: CaptionColor(r: 1.0, g: 0.95, b: 0.85, a: 0.95), // Warm cream
            shadowColor: CaptionColor(r: 0.05, g: 0.03, b: 0.0, a: 0.75),
            glowEnabled: false
        )

        static let podcastQuote = CaptionTheme(
            karaokeHighlight: CaptionColor(r: 0.4, g: 0.75, b: 1.0, a: 1.0),   // Soft blue
            karaokeDim: CaptionColor(r: 0.55, g: 0.55, b: 0.55, a: 0.65),
            wordHighlightBg: CaptionColor(r: 0.4, g: 0.75, b: 1.0, a: 0.15),
            hookTextColor: .white,
            hookBgColor: CaptionColor(r: 0.08, g: 0.08, b: 0.12, a: 0.9),      // Deep navy
            defaultTextColor: CaptionColor(r: 0.92, g: 0.92, b: 0.95, a: 0.9),
            shadowColor: CaptionColor(r: 0, g: 0, b: 0.05, a: 0.6),
            glowEnabled: false
        )
    }

    var captionTheme: CaptionTheme {
        let lookupId = themeId ?? id
        switch lookupId {
        case "premium_founder": return .premiumGold
        case "viral_caption": return .neonViral
        case "tech_influencer": return .neonViral
        case "clean_expert": return .monoClean
        case "cinematic_storyteller": return .warmCinematic
        case "podcast_highlights": return .podcastQuote
        default: return .premiumGold
        }
    }
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
        maxSilenceDuration: 0.6,
        colorGrade: ColorGrade(saturation: 0.95, brightness: 0.02, contrast: 1.05, warmth: 0.08, vignetteIntensity: 0.3)
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
        maxSilenceDuration: 0.35,
        colorGrade: ColorGrade(saturation: 1.15, brightness: 0.04, contrast: 1.12, warmth: 0.0, vignetteIntensity: 0.0)
    )

    static let techInfluencer = TemplateConfig(
        id: "tech_influencer",
        name: "Tech Influencer",
        description: "Sharp creator pacing for startup, AI, product, and app clips",
        intensity: .high,
        hookStyle: .hookImpact,
        emphasisStyle: .neonGlow,
        keywordStyle: .neonGlow,
        conclusionStyle: .hookImpact,
        defaultStyle: .focusStatement,
        backgroundMusicVolume: 0.08,
        sfxVolume: 0.22,
        voiceBoostDB: 4.5,
        minCutDuration: 0.28,
        maxSilenceDuration: 0.32,
        colorGrade: ColorGrade(
            saturation: 1.08,
            brightness: 0.03,
            contrast: 1.15,
            warmth: -0.03,
            vignetteIntensity: 0.08,
            sharpen: 0.16
        ),
        transitionStyle: .whipPan,
        transitionDuration: 0.16,
        category: .social,
        captionMinGap: 0.75
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
        maxSilenceDuration: 0.50,
        colorGrade: ColorGrade(saturation: 0.90, brightness: 0.0, contrast: 1.02, warmth: -0.05, vignetteIntensity: 0.15)
    )

    static let cinematicStoryteller = TemplateConfig(
        id: "cinematic_storyteller",
        name: "Cinematic Storyteller",
        description: "Warm, filmic look with amber tones for narrative content",
        intensity: .medium,
        hookStyle: .hookImpact,
        emphasisStyle: .focusStatement,
        keywordStyle: .focusStatement,
        conclusionStyle: .premiumLowerThird,
        defaultStyle: .premiumLowerThird,
        backgroundMusicVolume: 0.10,
        sfxVolume: 0.12,
        voiceBoostDB: 2.5,
        minCutDuration: 0.5,
        maxSilenceDuration: 0.55,
        colorGrade: ColorGrade(saturation: 0.92, brightness: 0.01, contrast: 1.08, warmth: 0.15, vignetteIntensity: 0.45)
    )

    static let podcastHighlights = TemplateConfig(
        id: "podcast_highlights",
        name: "Podcast Highlights",
        description: "Quote-style captions for interview and podcast clips",
        intensity: .low,
        hookStyle: .focusStatement,
        emphasisStyle: .focusStatement,
        keywordStyle: .minimalWellness,
        conclusionStyle: .minimalWellness,
        defaultStyle: .minimalWellness,
        backgroundMusicVolume: 0.03,
        sfxVolume: 0.08,
        voiceBoostDB: 4.0,
        minCutDuration: 0.6,
        maxSilenceDuration: 0.7,
        colorGrade: ColorGrade(saturation: 0.85, brightness: -0.02, contrast: 1.04, warmth: -0.03, vignetteIntensity: 0.2)
    )

    static let all: [TemplateConfig] = [
        .techInfluencer
    ]
}
