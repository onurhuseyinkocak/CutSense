import Foundation

/// Adapts a template's continuous parameters based on actual video content analysis.
/// Keeps the template's identity (theme, styles, category) but fine-tunes timing,
/// audio mix, effect intensity, and color grade to match the speaker's characteristics.
enum AdaptiveTemplateEngine {
    struct Adaptations: Sendable {
        let minCutDuration: Double
        let maxSilenceDuration: Double
        let sfxVolume: Float
        let backgroundMusicVolume: Float
        let voiceBoostDB: Float
        let colorGrade: TemplateConfig.ColorGrade
        let summary: String
    }

    /// Adapt template with both video profile AND source color analysis.
    static func adapt(
        template: TemplateConfig,
        profile: TemplateRecommendationEngine.VideoProfile,
        sliderParams: IntensityInterpolator.InterpolatedParams,
        colorProfile: VideoColorAnalyzer.ColorProfile?
    ) -> TemplateConfig {
        var adapted = adapt(template: template, profile: profile, sliderParams: sliderParams)
        if let cp = colorProfile {
            let grade = autoTuneColorGrade(base: adapted.colorGrade, source: cp)
            adapted = buildConfig(from: adapted, timing: (adapted.minCutDuration, adapted.maxSilenceDuration),
                                  audio: (adapted.sfxVolume, adapted.backgroundMusicVolume, adapted.voiceBoostDB),
                                  colorGrade: grade, intensity: adapted.intensity)
        }
        return adapted
    }

    /// Auto-tune template color grade to complement source footage characteristics.
    static func autoTuneColorGrade(
        base: TemplateConfig.ColorGrade,
        source: VideoColorAnalyzer.ColorProfile
    ) -> TemplateConfig.ColorGrade {
        var sat = base.saturation
        var brightness = base.brightness
        var contrast = base.contrast
        var warmth = base.warmth
        var fade = base.fade
        var sharpen = base.sharpen

        // Dark footage → lift brightness proportionally to darkness, reduce contrast
        if source.isDark {
            let darknessFactor = max(0.35 - source.averageBrightness, 0) / 0.35 // 0→0 at threshold, 1→1 at black
            let brightnessLift = Float(0.02 + 0.06 * darknessFactor) // 0.02..0.08 scaled
            brightness = min(brightness + brightnessLift, 0.15)
            let contrastDrop = Float(0.03 + 0.07 * darknessFactor) // 0.03..0.10
            contrast = max(contrast - contrastDrop, 0.85)
            fade = max(fade - 0.02, 0)
        }

        // Overexposed → reduce brightness proportionally, increase contrast
        if source.isOverexposed {
            let overFactor = max(source.averageBrightness - 0.75, 0) / 0.25 // 0→0 at threshold, 1→1 at white
            let brightnessDrop = Float(0.02 + 0.04 * overFactor)
            brightness = max(brightness - brightnessDrop, -0.1)
            let contrastBump = Float(0.02 + 0.04 * overFactor)
            contrast = min(contrast + contrastBump, 1.3)
        }

        // Warm source → reduce template warmth to avoid double-warming
        if source.averageWarmth > 0.1 {
            warmth = max(warmth - 0.15, -0.3)
        }
        // Cool source → let warm templates shine, add slight warmth to neutral
        else if source.averageWarmth < -0.05 && warmth < 0.05 {
            warmth = min(warmth + 0.08, 0.3)
        }

        // Saturated source → cap saturation boost to avoid oversaturation
        if source.averageSaturation > 0.45 {
            sat = min(sat, 1.2)
        }
        // Desaturated source → boost saturation more aggressively
        else if source.averageSaturation < 0.2 {
            sat = min(sat * 1.15, 1.4)
        }

        // Low contrast source → increase contrast slightly
        if source.contrastRange < 0.25 {
            contrast = min(contrast + 0.04, 1.25)
        }

        // Soft/blurry source → add sharpening
        if source.contrastRange < 0.2 && sharpen < 0.15 {
            sharpen = min(sharpen + 0.15, 0.4)
        }

        return TemplateConfig.ColorGrade(
            saturation: sat,
            brightness: brightness,
            contrast: contrast,
            warmth: warmth,
            vignetteIntensity: base.vignetteIntensity,
            fade: fade,
            highlightsTint: base.highlightsTint,
            shadowsTint: base.shadowsTint,
            sharpen: sharpen,
            grain: base.grain
        )
    }

    /// Compute adapted template from base template + video profile.
    /// Returns a new TemplateConfig with fine-tuned parameters.
    static func adapt(
        template: TemplateConfig,
        profile: TemplateRecommendationEngine.VideoProfile
    ) -> TemplateConfig {
        let a = computeAdaptations(template: template, profile: profile)
        return buildConfig(from: template, timing: (a.minCutDuration, a.maxSilenceDuration),
                          audio: (a.sfxVolume, a.backgroundMusicVolume, a.voiceBoostDB),
                          colorGrade: a.colorGrade, intensity: template.intensity)
    }

    /// Adapt template using both video profile AND slider-interpolated params.
    /// Slider provides base overrides, profile provides content-aware fine-tuning on top.
    static func adapt(
        template: TemplateConfig,
        profile: TemplateRecommendationEngine.VideoProfile,
        sliderParams: IntensityInterpolator.InterpolatedParams
    ) -> TemplateConfig {
        // Create a temporary config with slider params to feed into content adaptation
        let sliderConfig = buildConfig(
            from: template,
            timing: (sliderParams.minCutDuration, sliderParams.maxSilenceDuration),
            audio: (sliderParams.sfxVolume, sliderParams.backgroundMusicVolume, sliderParams.voiceBoostDB),
            colorGrade: template.colorGrade,
            intensity: sliderParams.resolvedIntensity
        )
        // Now apply content-aware adaptations on top of slider base
        let a = computeAdaptations(template: sliderConfig, profile: profile)
        return buildConfig(from: template, timing: (a.minCutDuration, a.maxSilenceDuration),
                          audio: (a.sfxVolume, a.backgroundMusicVolume, a.voiceBoostDB),
                          colorGrade: a.colorGrade, intensity: sliderParams.resolvedIntensity)
    }

    private static func buildConfig(
        from template: TemplateConfig,
        timing: (Double, Double),
        audio: (Float, Float, Float),
        colorGrade: TemplateConfig.ColorGrade,
        intensity: TemplateIntensity
    ) -> TemplateConfig {
        TemplateConfig(
            id: template.id,
            name: template.name,
            description: template.description,
            intensity: intensity,
            hookStyle: template.hookStyle,
            emphasisStyle: template.emphasisStyle,
            keywordStyle: template.keywordStyle,
            conclusionStyle: template.conclusionStyle,
            defaultStyle: template.defaultStyle,
            backgroundMusicVolume: audio.1,
            sfxVolume: audio.0,
            voiceBoostDB: audio.2,
            minCutDuration: timing.0,
            maxSilenceDuration: timing.1,
            colorGrade: colorGrade,
            transitionStyle: template.transitionStyle,
            transitionDuration: template.transitionDuration,
            category: template.category,
            captionMinGap: template.captionMinGap,
            themeId: template.themeId
        )
    }

    static func computeAdaptations(
        template: TemplateConfig,
        profile: TemplateRecommendationEngine.VideoProfile
    ) -> Adaptations {
        var reasons: [String] = []

        // --- Timing: adapt cut/silence thresholds to speech pace ---
        var minCut = template.minCutDuration
        var maxSilence = template.maxSilenceDuration

        let wpm = profile.wordsPerMinute
        if wpm > 180 {
            // Very fast speaker → tighter cuts, less silence tolerance
            minCut *= 0.75
            maxSilence *= 0.7
            reasons.append("tighter cuts for fast speech")
        } else if wpm > 150 {
            minCut *= 0.88
            maxSilence *= 0.85
        } else if wpm < 100 {
            // Very slow/deliberate → preserve breathing room
            minCut *= 1.25
            maxSilence *= 1.3
            reasons.append("wider cuts for deliberate pace")
        } else if wpm < 120 {
            minCut *= 1.1
            maxSilence *= 1.15
        }

        // High silence ratio → the speaker uses pauses intentionally
        if profile.silenceRatio > 0.25 {
            maxSilence *= 1.2
            reasons.append("preserved intentional pauses")
        }

        // Clamp timing to sane bounds
        minCut = min(max(minCut, 0.15), 1.2)
        maxSilence = min(max(maxSilence, 0.2), 1.5)

        // --- Audio mix: adapt volumes to energy level ---
        var sfxVol = template.sfxVolume
        var bgmVol = template.backgroundMusicVolume
        var voiceBoost = template.voiceBoostDB

        let energyDB = profile.averageEnergy > 0 ? 20 * log10(profile.averageEnergy) : -60
        if energyDB < -30 {
            // Quiet audio → boost voice more, reduce SFX/BGM to avoid masking
            voiceBoost = min(voiceBoost + 2.0, 8.0)
            sfxVol *= 0.7
            bgmVol *= 0.6
            reasons.append("boosted quiet voice")
        } else if energyDB > -15 {
            // Loud/energetic → can use more SFX, less voice boost needed
            voiceBoost = max(voiceBoost - 1.0, 0.0)
            sfxVol = min(sfxVol * 1.15, 0.5)
            reasons.append("matched high energy audio")
        }

        // High filler ratio → slightly louder SFX to mask edit points
        if profile.fillerRatio > 0.12 {
            sfxVol = min(sfxVol * 1.1, 0.5)
        }

        // --- Color grade: subtle adaptation ---
        var sat = template.colorGrade.saturation
        var brightness = template.colorGrade.brightness
        let contrast = template.colorGrade.contrast
        let warmth = template.colorGrade.warmth
        let vignette = template.colorGrade.vignetteIntensity

        // Short-form social content → slightly more saturation for pop
        if profile.duration < 30 && template.category == .social {
            sat = min(sat * 1.05, 1.3)
            brightness = min(brightness + 0.01, 0.1)
            reasons.append("boosted color for short-form")
        }

        // Long content → reduce saturation slightly to avoid fatigue
        if profile.duration > 180 {
            sat = max(sat * 0.97, 0.75)
        }

        let adaptedGrade = TemplateConfig.ColorGrade(
            saturation: sat,
            brightness: brightness,
            contrast: contrast,
            warmth: warmth,
            vignetteIntensity: vignette,
            fade: template.colorGrade.fade,
            highlightsTint: template.colorGrade.highlightsTint,
            shadowsTint: template.colorGrade.shadowsTint,
            sharpen: template.colorGrade.sharpen,
            grain: template.colorGrade.grain
        )

        let summary = reasons.isEmpty ? "Standard parameters" : reasons.joined(separator: ", ")

        return Adaptations(
            minCutDuration: minCut,
            maxSilenceDuration: maxSilence,
            sfxVolume: sfxVol,
            backgroundMusicVolume: bgmVol,
            voiceBoostDB: voiceBoost,
            colorGrade: adaptedGrade,
            summary: summary
        )
    }
}
