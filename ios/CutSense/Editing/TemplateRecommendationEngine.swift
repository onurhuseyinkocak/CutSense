import Foundation

struct TemplateRecommendation: Sendable {
    let template: TemplateConfig
    let score: Float       // 0-100
    let confidence: Float  // 0-1
    let reason: String
}

struct AutonomousTemplateSelection: Sendable {
    let template: TemplateConfig
    let recommendation: TemplateRecommendation
    let profile: TemplateRecommendationEngine.VideoProfile
    let intensityLevel: Float
}

enum TemplateRecommendationEngine {
    struct VideoProfile: Sendable {
        let wordsPerMinute: Float
        let averageEnergy: Float
        let silenceRatio: Float
        let retentionPercent: Float
        let segmentCount: Int
        let averageSegmentDuration: Double
        let fillerRatio: Float
        let duration: Double
        let techKeywordRatio: Float
        let brandKeywordCount: Int
        let callToActionCount: Int
        let mixedLanguageSignal: Float
    }

    static func recommend(
        transcription: TranscriptionResult,
        roughCut: RoughCutResult,
        audio: AudioAnalysisResult
    ) -> [TemplateRecommendation] {
        let profile = buildProfile(
            transcription: transcription,
            roughCut: roughCut,
            audio: audio
        )

        return TemplateConfig.all
            .map { score(template: $0, profile: profile) }
            .sorted { $0.score > $1.score }
    }

    static func selectAutonomousTemplate(
        transcription: TranscriptionResult,
        roughCut: RoughCutResult,
        audio: AudioAnalysisResult,
        sourceURL: URL
    ) async -> AutonomousTemplateSelection? {
        let recommendations = recommend(
            transcription: transcription,
            roughCut: roughCut,
            audio: audio
        )
        guard let topRecommendation = recommendations.first else { return nil }

        let profile = buildProfile(
            transcription: transcription,
            roughCut: roughCut,
            audio: audio
        )
        let level = autonomousIntensityLevel(
            profile: profile,
            recommendation: topRecommendation
        )
        let sliderParams = IntensityInterpolator.interpolate(
            template: topRecommendation.template,
            level: level
        )
        let colorProfile = try? await VideoColorAnalyzer.analyze(url: sourceURL)
        let resolvedTemplate = AdaptiveTemplateEngine.adapt(
            template: topRecommendation.template,
            profile: profile,
            sliderParams: sliderParams,
            colorProfile: colorProfile
        )

        return AutonomousTemplateSelection(
            template: resolvedTemplate,
            recommendation: topRecommendation,
            profile: profile,
            intensityLevel: level
        )
    }

    // MARK: - Profile

    static func buildProfile(
        transcription: TranscriptionResult,
        roughCut: RoughCutResult,
        audio: AudioAnalysisResult
    ) -> VideoProfile {
        let speechSegments = transcription.segments.filter { $0.segmentType == .speech || $0.segmentType == .contentSentence }
        let totalWords = speechSegments.reduce(0) { $0 + $1.text.split(separator: " ").count }
        let speechDuration = speechSegments.reduce(0.0) { $0 + ($1.endTime - $1.startTime) }
        let wpm: Float = speechDuration > 0 ? Float(totalWords) / Float(speechDuration / 60.0) : 0

        let silenceSegs = audio.segments.filter { $0.type == .silence }
        let silenceDur = silenceSegs.reduce(0.0) { $0 + ($1.endTime - $1.startTime) }
        let silenceRatio = audio.duration > 0 ? Float(silenceDur / audio.duration) : 0

        let retention = roughCut.originalDuration > 0
            ? Float(roughCut.cleanDuration / roughCut.originalDuration)
            : 1.0

        let fillerCount = transcription.segments.filter { $0.segmentType == .filler }.count
        let totalCount = max(transcription.segments.count, 1)
        let fillerRatio = Float(fillerCount) / Float(totalCount)
        let fullText = transcription.fullText.lowercased()
        let words = fullText.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        let totalTextWords = max(words.count, 1)
        let techKeywords = [
            "ai", "yapay", "zeka", "mvp", "app", "store", "web", "android",
            "ios", "swiftui", "kod", "code", "coding", "vibe", "startup",
            "uygulama", "ürün", "product", "founder", "launch"
        ]
        let techKeywordHits = words.filter { word in
            techKeywords.contains { keyword in
                word.localizedStandardContains(keyword)
            }
        }.count
        let brandKeywords = [
            "vibe coding",
            "vibe coding turkey",
            "mvp",
            "app store",
            "android",
            "swiftui"
        ]
        let brandKeywordCount = brandKeywords.filter { fullText.localizedStandardContains($0) }.count
        let callToActionPatterns = [
            "yorumlara",
            "comment",
            "follow",
            "takip",
            "katıl",
            "join",
            "büyüyelim",
            "download",
            "indir"
        ]
        let callToActionCount = callToActionPatterns.filter { fullText.localizedStandardContains($0) }.count
        let hasTurkishSignals = ["ı", "ğ", "ş", "ç", "ö", "ü", "yapay", "zeka", "uygulama", "yorumlara"]
            .contains { fullText.localizedStandardContains($0) }
        let hasEnglishSignals = ["ai", "app", "store", "web", "code", "coding", "mvp", "android", "startup"]
            .contains { fullText.localizedStandardContains($0) }

        let includedRanges = TimelineRangeNormalizer.includedRanges(
            from: roughCut.decisions,
            assetDuration: roughCut.originalDuration
        )
        let avgSegDur = includedRanges.isEmpty
            ? 0
            : includedRanges.reduce(0.0) { $0 + $1.duration } / Double(includedRanges.count)

        return VideoProfile(
            wordsPerMinute: wpm,
            averageEnergy: audio.averageEnergy,
            silenceRatio: silenceRatio,
            retentionPercent: retention * 100,
            segmentCount: includedRanges.count,
            averageSegmentDuration: avgSegDur,
            fillerRatio: fillerRatio,
            duration: audio.duration,
            techKeywordRatio: Float(techKeywordHits) / Float(totalTextWords),
            brandKeywordCount: brandKeywordCount,
            callToActionCount: callToActionCount,
            mixedLanguageSignal: hasTurkishSignals && hasEnglishSignals ? 1.0 : 0.0
        )
    }

    // MARK: - Scoring

    private static func score(template: TemplateConfig, profile: VideoProfile) -> TemplateRecommendation {
        var points: Float = 50 // base
        var reasons: [String] = []
        let hasTechScript = profile.techKeywordRatio > 0.08 || profile.brandKeywordCount > 0

        // Speech pace matching
        switch template.intensity {
        case .high:
            // High intensity templates suit fast speakers (>160 wpm)
            if profile.wordsPerMinute > 160 {
                points += 15
                reasons.append("fast pace")
            } else if profile.wordsPerMinute < 120 {
                if template.id == "tech_influencer", hasTechScript {
                    points += 4
                    reasons.append("domain fit")
                } else {
                    points -= 15
                }
            }
        case .medium:
            // Medium suits moderate speakers (120-160 wpm)
            if profile.wordsPerMinute >= 120 && profile.wordsPerMinute <= 160 {
                points += 10
                reasons.append("balanced pace")
            }
        case .low:
            // Low intensity suits slower, deliberate speakers (<130 wpm)
            if profile.wordsPerMinute < 130 {
                points += 12
                reasons.append("deliberate pace")
            } else if profile.wordsPerMinute > 170 {
                points -= 12
            }
        }

        // Energy matching — all templates scored by energy fit
        let energyDB = profile.averageEnergy > 0 ? 20 * log10(profile.averageEnergy) : -60
        let isHighEnergy = energyDB > -20
        let isMidEnergy = energyDB >= -30 && energyDB <= -20
        let isLowEnergy = energyDB < -25
        let isVeryLow = energyDB < -35

        switch template.id {
        case "tech_influencer":
            if profile.techKeywordRatio > 0.08 {
                points += 24
                reasons.append("tech script")
            }
            if profile.brandKeywordCount > 0 {
                points += 14
                reasons.append("product terms")
            }
            if profile.mixedLanguageSignal > 0 {
                points += 10
                reasons.append("mixed TR/EN")
            }
            if profile.duration < 60 {
                points += 6
            }
            if isVeryLow { points -= 6 }
        case "motivation_fire", "street_vlog", "viral_caption", "gaming_highlights":
            if isHighEnergy { points += 12; reasons.append("high energy") }
            else if isVeryLow { points -= 12 }
            else if isLowEnergy { points -= 6 }
        case "asmr_relaxing", "beauty_lifestyle", "wedding_event":
            if isLowEnergy { points += 10; reasons.append("soft audio") }
            else if isHighEnergy { points -= 10 }
        case "podcast_highlights", "clean_expert":
            if isMidEnergy { points += 8; reasons.append("voice-focused") }
            else if isHighEnergy { points -= 4 }
        case "premium_founder", "news_commentary", "tutorial_teacher":
            if isMidEnergy { points += 6; reasons.append("balanced energy") }
            else if isVeryLow { points -= 4 }
        case "cinematic_storyteller", "dark_moody":
            if isMidEnergy || isLowEnergy { points += 6; reasons.append("atmospheric") }
            else if isHighEnergy { points -= 3 }
        case "tech_review":
            if isMidEnergy { points += 6; reasons.append("focused audio") }
        default:
            break
        }

        // Retention matching — high retention = less editing needed
        if profile.retentionPercent > 85 {
            // Very little cut → low intensity templates work better
            if template.intensity == .low { points += 8 }
            else if template.intensity == .high { points -= 5 }
        } else if profile.retentionPercent < 60 {
            // Heavy cutting → high intensity makes sense
            if template.intensity == .high { points += 8; reasons.append("heavy edits") }
            else if template.intensity == .low { points -= 5 }
        }

        // Segment count — many short segments = fast content
        if profile.segmentCount > 15 && profile.averageSegmentDuration < 3.0 {
            if template.intensity == .high { points += 8 }
            else if template.intensity == .low { points -= 5 }
        }

        // Duration matching
        if profile.duration < 30 {
            // Short videos → social templates
            if template.category == .social { points += 8; reasons.append("short-form") }
        } else if profile.duration > 120 {
            // Longer videos → professional or creative
            if template.category == .professional { points += 6 }
            else if template.category == .creative { points += 4 }
        }

        // Filler ratio — high fillers = casual content
        if profile.fillerRatio > 0.15 {
            // Lots of fillers = casual/vlog style
            if template.id == "street_vlog" || template.id == "viral_caption" {
                points += 6
                reasons.append("casual style")
            }
        } else if profile.fillerRatio < 0.05 {
            // Very polished speech
            if template.category == .professional { points += 6; reasons.append("polished speech") }
        }

        if profile.callToActionCount > 0 {
            if template.id == "tech_influencer" || template.id == "viral_caption" {
                points += 7
                reasons.append("CTA")
            }
        }

        if hasTechScript, template.category == .professional, template.id != "tech_influencer" {
            points -= 8
        }

        // Silence ratio — high silence = contemplative
        if profile.silenceRatio > 0.3 {
            if template.id == "cinematic_storyteller" || template.id == "asmr_relaxing" {
                points += 6
            }
        }

        let clamped = min(max(points, 0), 100)
        let confidence = min(max((clamped - 40) / 40, 0), 1) // 40→0.0, 80→1.0
        let reason = reasons.isEmpty ? "general fit" : reasons.prefix(2).joined(separator: ", ")

        return TemplateRecommendation(
            template: template,
            score: clamped,
            confidence: confidence,
            reason: reason.prefix(1).uppercased() + reason.dropFirst()
        )
    }

    private static func autonomousIntensityLevel(
        profile: VideoProfile,
        recommendation: TemplateRecommendation
    ) -> Float {
        var level = IntensityInterpolator.defaultLevel(for: recommendation.template.intensity)
        if profile.duration < 60 {
            level = max(level, 0.72)
        }
        if profile.techKeywordRatio > 0.08 || profile.brandKeywordCount > 0 {
            level = max(level, 0.82)
        }
        if profile.callToActionCount > 0 {
            level = max(level, 0.78)
        }
        if profile.wordsPerMinute > 165 {
            level = min(level + 0.08, 0.95)
        }
        if profile.averageSegmentDuration > 4.0 {
            level = min(level, 0.70)
        }
        return min(max(level, 0.2), 0.95)
    }
}
