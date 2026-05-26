import Foundation

/// Maps a continuous 0.0–1.0 intensity value to interpolated template parameters.
/// Enables smooth intensity control instead of discrete low/medium/high steps.
enum IntensityInterpolator {

    struct InterpolatedParams: Sendable {
        let minCutDuration: Double
        let maxSilenceDuration: Double
        let sfxVolume: Float
        let backgroundMusicVolume: Float
        let voiceBoostDB: Float
        let effectIntensityScale: Float   // multiplier for effect intensity values
        let minBehaviorGap: Double        // min seconds between scene behaviors
        let resolvedIntensity: TemplateIntensity // nearest enum for scene planner
        let effectsPerMinuteEstimate: Int

        var label: String {
            switch resolvedIntensity {
            case .low: "Subtle"
            case .medium: "Balanced"
            case .high: "Aggressive"
            }
        }
    }

    /// Interpolate between template's base parameters using a continuous 0.0–1.0 level.
    /// 0.0 = most subtle, 1.0 = most aggressive.
    static func interpolate(
        template: TemplateConfig,
        level: Float
    ) -> InterpolatedParams {
        let t = min(max(level, 0), 1)

        // Define extreme ranges based on template category
        let isSocial = template.category == .social

        // Timing: low level → longer cuts, high level → shorter
        let minCutRange: (Double, Double) = isSocial ? (0.6, 0.2) : (0.8, 0.3)
        let maxSilRange: (Double, Double) = isSocial ? (0.8, 0.25) : (1.0, 0.35)

        let minCut = lerp(minCutRange.0, minCutRange.1, Double(t))
        let maxSil = lerp(maxSilRange.0, maxSilRange.1, Double(t))

        // Audio: higher level → more SFX, slightly more BGM
        let sfxScale = lerp(0.4, 1.4, Double(t))
        let bgmScale = lerp(0.6, 1.3, Double(t))
        let voiceBoostOffset = lerp(2.0, -1.0, Double(t))

        let sfxVol = min(Float(sfxScale) * template.sfxVolume, 0.5)
        let bgmVol = min(Float(bgmScale) * template.backgroundMusicVolume, 0.3)
        let voiceBoost = max(template.voiceBoostDB + Float(voiceBoostOffset), 0)

        // Effect intensity: scales all effect intensity values
        let effectScale = lerp(0.5, 1.3, Double(t))

        // Scene behavior gap: how close effects can be
        let gapRange: (Double, Double) = (6.0, 1.5)
        let gap = lerp(gapRange.0, gapRange.1, Double(t))

        // Resolve to nearest enum
        let resolved: TemplateIntensity
        if t < 0.33 { resolved = .low }
        else if t < 0.67 { resolved = .medium }
        else { resolved = .high }

        // Estimate effects per minute based on gap and typical caption density
        let avgCaptionsPerMin = 12.0
        let behaviorHitRate: Double = switch resolved {
        case .low: 0.25
        case .medium: 0.5
        case .high: 0.75
        }
        let effectsPerCaptionAvg = 1.5
        let epm = Int(avgCaptionsPerMin * behaviorHitRate * effectsPerCaptionAvg)

        return InterpolatedParams(
            minCutDuration: minCut,
            maxSilenceDuration: maxSil,
            sfxVolume: sfxVol,
            backgroundMusicVolume: bgmVol,
            voiceBoostDB: voiceBoost,
            effectIntensityScale: Float(effectScale),
            minBehaviorGap: gap,
            resolvedIntensity: resolved,
            effectsPerMinuteEstimate: epm
        )
    }

    /// Map template intensity enum to initial slider position.
    static func defaultLevel(for intensity: TemplateIntensity) -> Float {
        switch intensity {
        case .low: 0.2
        case .medium: 0.5
        case .high: 0.8
        }
    }

    private static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * t
    }
}
