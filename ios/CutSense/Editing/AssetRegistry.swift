import Foundation

private final class AssetRegistryBundleAnchor {}

enum EditingAssetType: String, Codable, Sendable, CaseIterable {
    case sfx
    case music
    case visualEffect
    case captionStyle
    case transition
}

enum EditingAssetIntensity: String, Codable, Sendable, CaseIterable {
    case low
    case medium
    case high

    var displayName: String {
        switch self {
        case .low: "Clean"
        case .medium: "Punchy"
        case .high: "High Energy"
        }
    }
}

enum EditingPresetKind: String, Codable, Sendable, CaseIterable {
    case cinematic
    case techInfluencer = "tech_influencer"
    case ugc
    case influencer
    case podcast
    case productDemo = "product_demo"

    var displayName: String {
        switch self {
        case .cinematic: "Cinematic"
        case .techInfluencer: "Tech Influencer"
        case .ugc: "UGC"
        case .influencer: "Influencer"
        case .podcast: "Podcast"
        case .productDemo: "Product Demo"
        }
    }
}

struct AssetRegistryItem: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let displayName: String
    let type: EditingAssetType
    let category: String
    let localPath: String
    let sourceName: String
    let sourceURL: String
    let licenseName: String
    let commercialUseAllowed: Bool
    let attributionRequired: Bool
    let moodTags: [String]
    let intensity: EditingAssetIntensity
    let bestForPresets: [EditingPresetKind]
    let triggerKeywords: [String]
    let duration: Double?
    let bpm: Int?

    var fileName: String {
        URL(fileURLWithPath: localPath).lastPathComponent
    }
}

struct EditPackageSelection: Codable, Hashable, Sendable {
    var preset: EditingPresetKind
    var captionStyleAssetID: String
    var sfxAssetIDs: [String]
    var visualEffectAssetIDs: [String]
    var musicAssetID: String?
    var transitionAssetID: String

    static let cinematic = EditPackageSelection(
        preset: .cinematic,
        captionStyleAssetID: "caption_cinematic_lower_third",
        sfxAssetIDs: [
            "mixkit_air_woosh_1489",
            "mixkit_cinematic_whoosh_deep_impact_1143",
            "mixkit_cinematic_trailer_riser_790",
            "mixkit_cinematic_heartbeat_ambience_497"
        ],
        visualEffectAssetIDs: [
            "fx_subtle_film_grain",
            "fx_warm_light_leak",
            "fx_subtle_gold_glow",
            "fx_slow_zoom"
        ],
        musicAssetID: "mixkit_silent_descent_614",
        transitionAssetID: "transition_soft_push"
    )

    static let techInfluencer = EditPackageSelection(
        preset: .techInfluencer,
        captionStyleAssetID: "caption_bold_tech_dynamic",
        sfxAssetIDs: [
            "mixkit_flying_fast_swoosh_1469",
            "mixkit_modern_technology_select_3124",
            "mixkit_message_pop_alert_2354",
            "mixkit_small_electric_glitch_2595",
            "mixkit_short_space_stutter_intro_riser_1144",
            "mixkit_camera_shutter_click_1133"
        ],
        visualEffectAssetIDs: [
            "fx_chromatic_micro_glitch",
            "fx_blur_highlight",
            "fx_camera_snap",
            "fx_controlled_speed_ramp"
        ],
        musicAssetID: "mixkit_sci_fi_score_464",
        transitionAssetID: "transition_zoom_cut"
    )

    var template: TemplateConfig {
        switch preset {
        case .cinematic:
            return .cinematicStoryteller
        case .techInfluencer:
            return .techInfluencer
        case .ugc, .influencer:
            return .viralCaption
        case .podcast:
            return .podcastHighlights
        case .productDemo:
            return .cleanExpert
        }
    }
}

struct EditingPresetCard: Identifiable, Sendable {
    let id: EditingPresetKind
    let isLocked: Bool
    let package: EditPackageSelection?
    let subtitle: String
    let caption: String
    let sfx: String
    let visuals: String
    let music: String
    let pacing: String
}

enum EditingPresetLibrary {
    static let cards: [EditingPresetCard] = [
        EditingPresetCard(
            id: .cinematic,
            isLocked: false,
            package: .cinematic,
            subtitle: "Black premium, emotional, controlled",
            caption: "Cinematic Lower Third",
            sfx: "Soft Whoosh + Deep Impact + Riser",
            visuals: "Film Grain + Light Leak + Slow Zoom",
            music: "Minimal Cinematic",
            pacing: "Slow Premium"
        ),
        EditingPresetCard(
            id: .techInfluencer,
            isLocked: false,
            package: .techInfluencer,
            subtitle: "Sharp product demos and AI tool clips",
            caption: "Bold Tech Dynamic",
            sfx: "Whoosh + Click + Pop + Glitch",
            visuals: "Tech Glitch + Camera Snap + Punch Zoom",
            music: "Minimal Tech",
            pacing: "Fast Controlled"
        ),
        EditingPresetCard(id: .ugc, isLocked: true, package: nil, subtitle: "Casual native creator ads", caption: "UGC captions", sfx: "Natural pops", visuals: "Handheld energy", music: "Light social", pacing: "Fast native"),
        EditingPresetCard(id: .influencer, isLocked: true, package: nil, subtitle: "Lifestyle creator polish", caption: "Influencer captions", sfx: "Soft social accents", visuals: "Glow + smooth cuts", music: "Trendy clean", pacing: "Balanced"),
        EditingPresetCard(id: .podcast, isLocked: true, package: nil, subtitle: "Interview and quote highlights", caption: "Quote captions", sfx: "Minimal", visuals: "Calm focus", music: "Low bed", pacing: "Measured"),
        EditingPresetCard(id: .productDemo, isLocked: true, package: nil, subtitle: "Product walkthrough and launches", caption: "Product labels", sfx: "Click + camera", visuals: "Screen punch", music: "Tech pulse", pacing: "Clear fast")
    ]
}

enum AssetRegistry {
    static let all: [AssetRegistryItem] = audioItems + visualItems + captionStyleItems + transitionItems

    static func item(id: String) -> AssetRegistryItem? {
        all.first { $0.id == id }
    }

    static func items(type: EditingAssetType) -> [AssetRegistryItem] {
        all.filter { $0.type == type }
    }

    static func items(type: EditingAssetType, category: String) -> [AssetRegistryItem] {
        all.filter { $0.type == type && $0.category == category }
    }

    static func bundleURL(for item: AssetRegistryItem) -> URL? {
        let url = URL(fileURLWithPath: item.localPath)
        let subdirectory = url.deletingLastPathComponent().path
        let fileName = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension

        let bundles = [Bundle.main, Bundle(for: AssetRegistryBundleAnchor.self)]
        for bundle in bundles {
            if let url = bundle.url(forResource: fileName, withExtension: ext, subdirectory: subdirectory) {
                return url
            }
            if let url = bundle.url(forResource: fileName, withExtension: ext) {
                return url
            }
        }
        return nil
    }

    static func validateBundledAssets() -> [AssetRegistryItem] {
        all.filter { bundleURL(for: $0) == nil }
    }

    static func captionStyle(for selection: EditPackageSelection) -> CaptionStyle {
        switch selection.captionStyleAssetID {
        case "caption_bold_tech_dynamic":
            return .boldCenterViral
        case "caption_minimal_clean":
            return .minimalWellness
        case "caption_cinematic_quote":
            return .focusStatement
        case "caption_bold_viral_pop":
            return .hookImpact
        default:
            return .premiumLowerThird
        }
    }

    static func transitionStyle(for selection: EditPackageSelection) -> TransitionStyle {
        switch selection.transitionAssetID {
        case "transition_fade":
            return .dip
        case "transition_swipe", "transition_zoom_cut":
            return .whipPan
        case "transition_camera_shutter":
            return .flash
        default:
            return .crossDissolve
        }
    }

    static func transitionDuration(for selection: EditPackageSelection) -> Double {
        item(id: selection.transitionAssetID)?.duration ?? selection.template.transitionDuration
    }

    static func musicItem(for selection: EditPackageSelection) -> AssetRegistryItem? {
        if let musicAssetID = selection.musicAssetID, let item = item(id: musicAssetID) {
            return item
        }
        return items(type: .music).first { $0.bestForPresets.contains(selection.preset) }
    }

    static func sfxItem(for decision: EditDecision, selection: EditPackageSelection?) -> AssetRegistryItem? {
        guard decision.type == .sfx else { return nil }

        let category = sfxCategory(for: decision, preset: selection?.preset)
        let selectedItems = (selection?.sfxAssetIDs ?? [])
            .compactMap { item(id: $0) }
            .filter { $0.type == .sfx && $0.category == category }

        let candidates = selectedItems.isEmpty ? items(type: .sfx, category: category) : selectedItems
        guard !candidates.isEmpty else { return nil }

        let index = abs(Int((decision.time * 10).rounded())) % candidates.count
        return candidates[index]
    }

    private static func sfxCategory(for decision: EditDecision, preset: EditingPresetKind?) -> String {
        let reason = decision.reason.lowercased()
        if reason.localizedStandardContains("riser") {
            return "riser"
        }
        if reason.localizedStandardContains("camera") || reason.localizedStandardContains("snap") || reason.localizedStandardContains("shutter") {
            return "camera_transition"
        }
        if preset == .techInfluencer,
           reason.localizedStandardContains("glitch") {
            return "glitch"
        }
        if reason.localizedStandardContains("impact") || reason.localizedStandardContains("punch") || reason.localizedStandardContains("hook") {
            return "impact"
        }
        if reason.localizedStandardContains("whoosh") || reason.localizedStandardContains("transition") || reason.localizedStandardContains("cut") {
            return "whoosh"
        }
        if reason.localizedStandardContains("reveal") {
            return "impact"
        }
        if reason.localizedStandardContains("pop") || reason.localizedStandardContains("click") || reason.localizedStandardContains("keyword") || reason.localizedStandardContains("focus") || reason.localizedStandardContains("product") || reason.localizedStandardContains("ui") {
            return "pop_click"
        }
        if reason.localizedStandardContains("ambient") {
            return "ambient"
        }
        return "impact"
    }
}

private extension AssetRegistry {
    static func mixkit(
        id: String,
        name: String,
        type: EditingAssetType,
        category: String,
        path: String,
        sourceURL: String,
        license: String,
        tags: [String],
        intensity: EditingAssetIntensity,
        bestFor: [EditingPresetKind],
        keywords: [String],
        duration: Double?,
        bpm: Int? = nil
    ) -> AssetRegistryItem {
        AssetRegistryItem(
            id: id,
            displayName: name,
            type: type,
            category: category,
            localPath: path,
            sourceName: "Mixkit",
            sourceURL: sourceURL,
            licenseName: license,
            commercialUseAllowed: true,
            attributionRequired: false,
            moodTags: tags,
            intensity: intensity,
            bestForPresets: bestFor,
            triggerKeywords: keywords,
            duration: duration,
            bpm: bpm
        )
    }

    static func localDefinition(
        id: String,
        name: String,
        type: EditingAssetType,
        category: String,
        path: String,
        tags: [String],
        intensity: EditingAssetIntensity,
        bestFor: [EditingPresetKind],
        keywords: [String],
        duration: Double? = nil
    ) -> AssetRegistryItem {
        AssetRegistryItem(
            id: id,
            displayName: name,
            type: type,
            category: category,
            localPath: path,
            sourceName: "CutSense",
            sourceURL: "local://\(path)",
            licenseName: "CutSense internal app metadata",
            commercialUseAllowed: true,
            attributionRequired: false,
            moodTags: tags,
            intensity: intensity,
            bestForPresets: bestFor,
            triggerKeywords: keywords,
            duration: duration,
            bpm: nil
        )
    }
}

private extension AssetRegistry {
    static let audioItems: [AssetRegistryItem] = [
        mixkit(id: "mixkit_air_woosh_1489", name: "Air Woosh", type: .sfx, category: "whoosh", path: "EditingAssets/sfx/whoosh/mixkit_air_woosh_1489.wav", sourceURL: "https://mixkit.co/free-sound-effects/discover/air-woosh-1489/", license: "Mixkit Sound Effects Free License", tags: ["soft", "transition"], intensity: .low, bestFor: [.cinematic], keywords: ["whoosh", "soft", "transition"], duration: 2),
        mixkit(id: "mixkit_arrow_whoosh_1714", name: "Arrow Whoosh", type: .sfx, category: "whoosh", path: "EditingAssets/sfx/whoosh/mixkit_arrow_whoosh_1714.wav", sourceURL: "https://mixkit.co/free-sound-effects/discover/arrow-whoosh-1714/", license: "Mixkit Sound Effects Free License", tags: ["fast", "transition"], intensity: .medium, bestFor: [.techInfluencer, .ugc], keywords: ["whoosh", "fast"], duration: 1),
        mixkit(id: "mixkit_cinematic_whoosh_fast_transition_1492", name: "Cinematic Fast Whoosh", type: .sfx, category: "whoosh", path: "EditingAssets/sfx/whoosh/mixkit_cinematic_whoosh_fast_transition_1492.wav", sourceURL: "https://mixkit.co/free-sound-effects/discover/cinematic-whoosh-fast-transition-1492/", license: "Mixkit Sound Effects Free License", tags: ["cinematic", "fast"], intensity: .medium, bestFor: [.cinematic, .techInfluencer], keywords: ["whoosh", "cut"], duration: 1),
        mixkit(id: "mixkit_cinematic_tunnel_reverb_woosh_1486", name: "Tunnel Reverb Woosh", type: .sfx, category: "whoosh", path: "EditingAssets/sfx/whoosh/mixkit_cinematic_tunnel_reverb_woosh_1486.wav", sourceURL: "https://mixkit.co/free-sound-effects/discover/cinematic-tunnel-reverb-woosh-1486/", license: "Mixkit Sound Effects Free License", tags: ["deep", "cinematic"], intensity: .medium, bestFor: [.cinematic], keywords: ["whoosh", "deep"], duration: 6),
        mixkit(id: "mixkit_flying_fast_swoosh_1469", name: "Flying Fast Swoosh", type: .sfx, category: "whoosh", path: "EditingAssets/sfx/whoosh/mixkit_flying_fast_swoosh_1469.wav", sourceURL: "https://mixkit.co/free-sound-effects/discover/flying-fast-swoosh-1469/", license: "Mixkit Sound Effects Free License", tags: ["fast", "tech"], intensity: .medium, bestFor: [.techInfluencer], keywords: ["whoosh", "fast"], duration: 1),
        mixkit(id: "mixkit_cinematic_whoosh_deep_impact_1143", name: "Deep Impact", type: .sfx, category: "impact", path: "EditingAssets/sfx/impact/mixkit_cinematic_whoosh_deep_impact_1143.mp3", sourceURL: "https://mixkit.co/free-sound-effects/discover/cinematic-whoosh-deep-impact-1143/", license: "Mixkit Sound Effects Free License", tags: ["deep", "impact"], intensity: .medium, bestFor: [.cinematic], keywords: ["impact", "hook", "claim"], duration: 4),
        mixkit(id: "mixkit_big_cinematic_impact_788", name: "Big Cinematic Impact", type: .sfx, category: "impact", path: "EditingAssets/sfx/impact/mixkit_big_cinematic_impact_788.mp3", sourceURL: "https://mixkit.co/free-sound-effects/discover/big-cinematic-impact-788/", license: "Mixkit Sound Effects Free License", tags: ["big", "cinematic"], intensity: .high, bestFor: [.cinematic], keywords: ["impact", "reveal"], duration: 7),
        mixkit(id: "mixkit_dramatic_metal_explosion_impact_1687", name: "Metal Impact", type: .sfx, category: "impact", path: "EditingAssets/sfx/impact/mixkit_dramatic_metal_explosion_impact_1687.wav", sourceURL: "https://mixkit.co/free-sound-effects/discover/dramatic-metal-explosion-impact-1687/", license: "Mixkit Sound Effects Free License", tags: ["heavy", "strong"], intensity: .high, bestFor: [.techInfluencer, .cinematic], keywords: ["impact", "strong"], duration: 4),
        mixkit(id: "mixkit_movie_logo_intro_impact_2900", name: "Movie Logo Impact", type: .sfx, category: "impact", path: "EditingAssets/sfx/impact/mixkit_movie_logo_intro_impact_2900.wav", sourceURL: "https://mixkit.co/free-sound-effects/discover/movie-logo-intro-impact-2900/", license: "Mixkit Sound Effects Free License", tags: ["intro", "cinematic"], intensity: .medium, bestFor: [.cinematic], keywords: ["impact", "intro"], duration: 8),
        mixkit(id: "mixkit_reverse_cinematic_impact_trailer_784", name: "Reverse Impact", type: .sfx, category: "impact", path: "EditingAssets/sfx/impact/mixkit_reverse_cinematic_impact_trailer_784.wav", sourceURL: "https://mixkit.co/free-sound-effects/discover/reverse-cinematic-impact-trailer-784/", license: "Mixkit Sound Effects Free License", tags: ["reverse", "tension"], intensity: .medium, bestFor: [.cinematic], keywords: ["impact", "tension"], duration: 10),
        mixkit(id: "mixkit_cinematic_trailer_riser_790", name: "Cinematic Riser", type: .sfx, category: "riser", path: "EditingAssets/sfx/riser/mixkit_cinematic_trailer_riser_790.wav", sourceURL: "https://mixkit.co/free-sound-effects/discover/cinematic-trailer-riser-790/", license: "Mixkit Sound Effects Free License", tags: ["riser", "reveal"], intensity: .medium, bestFor: [.cinematic], keywords: ["riser", "reveal"], duration: 2),
        mixkit(id: "mixkit_short_space_stutter_intro_riser_1144", name: "Space Stutter Riser", type: .sfx, category: "riser", path: "EditingAssets/sfx/riser/mixkit_short_space_stutter_intro_riser_1144.mp3", sourceURL: "https://mixkit.co/free-sound-effects/discover/short-space-stutter-intro-riser-1144/", license: "Mixkit Sound Effects Free License", tags: ["tech", "stutter"], intensity: .medium, bestFor: [.techInfluencer], keywords: ["riser", "tech"], duration: 6),
        mixkit(id: "mixkit_cinematic_suspense_swell_786", name: "Suspense Swell", type: .sfx, category: "riser", path: "EditingAssets/sfx/riser/mixkit_cinematic_suspense_swell_786.wav", sourceURL: "https://mixkit.co/free-sound-effects/discover/cinematic-suspense-swell-786/", license: "Mixkit Sound Effects Free License", tags: ["suspense", "cinematic"], intensity: .medium, bestFor: [.cinematic], keywords: ["riser", "swell"], duration: 11),
        mixkit(id: "mixkit_terror_sweep_of_darkness_2630", name: "Dark Sweep", type: .sfx, category: "riser", path: "EditingAssets/sfx/riser/mixkit_terror_sweep_of_darkness_2630.wav", sourceURL: "https://mixkit.co/free-sound-effects/discover/terror-sweep-of-darkness-2630/", license: "Mixkit Sound Effects Free License", tags: ["dark", "sweep"], intensity: .medium, bestFor: [.cinematic], keywords: ["riser", "dark"], duration: 7),
        mixkit(id: "mixkit_cinematic_horror_trailer_long_sweep_561", name: "Long Sweep", type: .sfx, category: "riser", path: "EditingAssets/sfx/riser/mixkit_cinematic_horror_trailer_long_sweep_561.wav", sourceURL: "https://mixkit.co/free-sound-effects/discover/cinematic-horror-trailer-long-sweep-561/", license: "Mixkit Sound Effects Free License", tags: ["long", "cinematic"], intensity: .medium, bestFor: [.cinematic], keywords: ["riser", "long"], duration: 8),
        mixkit(id: "mixkit_hard_pop_click_2364", name: "Hard Pop Click", type: .sfx, category: "pop_click", path: "EditingAssets/sfx/pop_click/mixkit_hard_pop_click_2364.wav", sourceURL: "https://mixkit.co/free-sound-effects/discover/hard-pop-click-2364/", license: "Mixkit Sound Effects Free License", tags: ["click", "pop"], intensity: .medium, bestFor: [.techInfluencer, .ugc], keywords: ["click", "pop"], duration: 1),
        mixkit(id: "mixkit_message_pop_alert_2354", name: "Message Pop", type: .sfx, category: "pop_click", path: "EditingAssets/sfx/pop_click/mixkit_message_pop_alert_2354.mp3", sourceURL: "https://mixkit.co/free-sound-effects/discover/message-pop-alert-2354/", license: "Mixkit Sound Effects Free License", tags: ["pop", "caption"], intensity: .low, bestFor: [.techInfluencer, .ugc], keywords: ["pop", "keyword"], duration: 1),
        mixkit(id: "mixkit_bubble_pop_up_alert_notification_2357", name: "Bubble Pop", type: .sfx, category: "pop_click", path: "EditingAssets/sfx/pop_click/mixkit_bubble_pop_up_alert_notification_2357.wav", sourceURL: "https://mixkit.co/free-sound-effects/discover/bubble-pop-up-alert-notification-2357/", license: "Mixkit Sound Effects Free License", tags: ["soft", "pop"], intensity: .low, bestFor: [.ugc, .influencer], keywords: ["pop", "soft"], duration: 1),
        mixkit(id: "mixkit_modern_technology_select_3124", name: "Modern Tech Select", type: .sfx, category: "pop_click", path: "EditingAssets/sfx/pop_click/mixkit_modern_technology_select_3124.wav", sourceURL: "https://mixkit.co/free-sound-effects/discover/modern-technology-select-3124/", license: "Mixkit Sound Effects Free License", tags: ["tech", "ui"], intensity: .low, bestFor: [.techInfluencer], keywords: ["ui", "product", "select"], duration: 1),
        mixkit(id: "mixkit_select_click_1109", name: "Select Click", type: .sfx, category: "pop_click", path: "EditingAssets/sfx/pop_click/mixkit_select_click_1109.wav", sourceURL: "https://mixkit.co/free-sound-effects/discover/select-click-1109/", license: "Mixkit Sound Effects Free License", tags: ["click", "ui"], intensity: .low, bestFor: [.techInfluencer], keywords: ["click", "ui"], duration: 1),
        mixkit(id: "mixkit_small_electric_glitch_2595", name: "Small Electric Glitch", type: .sfx, category: "glitch", path: "EditingAssets/sfx/glitch/mixkit_small_electric_glitch_2595.wav", sourceURL: "https://mixkit.co/free-sound-effects/discover/small-electric-glitch-2595/", license: "Mixkit Sound Effects Free License", tags: ["glitch", "tech"], intensity: .medium, bestFor: [.techInfluencer], keywords: ["glitch", "tech"], duration: 1),
        mixkit(id: "mixkit_glitch_static_1457", name: "Glitch Static", type: .sfx, category: "glitch", path: "EditingAssets/sfx/glitch/mixkit_glitch_static_1457.wav", sourceURL: "https://mixkit.co/free-sound-effects/discover/glitch-static-1457/", license: "Mixkit Sound Effects Free License", tags: ["static", "glitch"], intensity: .medium, bestFor: [.techInfluencer], keywords: ["glitch", "static"], duration: 1),
        mixkit(id: "mixkit_electric_buzz_glitch_2594", name: "Electric Buzz Glitch", type: .sfx, category: "glitch", path: "EditingAssets/sfx/glitch/mixkit_electric_buzz_glitch_2594.wav", sourceURL: "https://mixkit.co/free-sound-effects/discover/electric-buzz-glitch-2594/", license: "Mixkit Sound Effects Free License", tags: ["buzz", "glitch"], intensity: .medium, bestFor: [.techInfluencer], keywords: ["glitch", "buzz"], duration: 1),
        mixkit(id: "mixkit_camera_shutter_click_1133", name: "Camera Shutter", type: .sfx, category: "camera_transition", path: "EditingAssets/sfx/camera_transition/mixkit_camera_shutter_click_1133.wav", sourceURL: "https://mixkit.co/free-sound-effects/discover/camera-shutter-click-1133/", license: "Mixkit Sound Effects Free License", tags: ["camera", "snap"], intensity: .medium, bestFor: [.techInfluencer, .influencer], keywords: ["camera", "snap"], duration: 1),
        mixkit(id: "mixkit_camera_shutter_hard_click_1430", name: "Hard Camera Shutter", type: .sfx, category: "camera_transition", path: "EditingAssets/sfx/camera_transition/mixkit_camera_shutter_hard_click_1430.wav", sourceURL: "https://mixkit.co/free-sound-effects/discover/camera-shutter-hard-click-1430/", license: "Mixkit Sound Effects Free License", tags: ["camera", "sharp"], intensity: .medium, bestFor: [.techInfluencer], keywords: ["camera", "shutter"], duration: 1),
        mixkit(id: "mixkit_vintage_camera_shutter_1438", name: "Vintage Camera Shutter", type: .sfx, category: "camera_transition", path: "EditingAssets/sfx/camera_transition/mixkit_vintage_camera_shutter_1438.wav", sourceURL: "https://mixkit.co/free-sound-effects/discover/vintage-camera-shutter-1438/", license: "Mixkit Sound Effects Free License", tags: ["retro", "camera"], intensity: .low, bestFor: [.influencer, .techInfluencer], keywords: ["camera", "retro"], duration: 1),
        mixkit(id: "mixkit_cinematic_heartbeat_ambience_497", name: "Heartbeat Ambience", type: .sfx, category: "ambient", path: "EditingAssets/sfx/ambient/mixkit_cinematic_heartbeat_ambience_497.wav", sourceURL: "https://mixkit.co/free-sound-effects/discover/cinematic-heartbeat-ambience-497/", license: "Mixkit Sound Effects Free License", tags: ["ambient", "cinematic"], intensity: .low, bestFor: [.cinematic], keywords: ["ambient", "texture"], duration: 5),
        mixkit(id: "mixkit_silent_descent_614", name: "Silent Descent", type: .music, category: "cinematic", path: "EditingAssets/music/cinematic/mixkit_silent_descent_614.mp3", sourceURL: "https://mixkit.co/free-stock-music/discover/silent-descent-614/", license: "Mixkit Stock Music Free License", tags: ["cinematic", "emotional", "minimal"], intensity: .low, bestFor: [.cinematic], keywords: ["cinematic", "emotional"], duration: 160),
        mixkit(id: "mixkit_valley_sunset_127", name: "Valley Sunset", type: .music, category: "cinematic", path: "EditingAssets/music/cinematic/mixkit_valley_sunset_127.mp3", sourceURL: "https://mixkit.co/free-stock-music/discover/valley-sunset-127/", license: "Mixkit Stock Music Free License", tags: ["ambient", "minimal"], intensity: .low, bestFor: [.cinematic], keywords: ["minimal", "ambient"], duration: 134),
        mixkit(id: "mixkit_sci_fi_score_464", name: "Sci-Fi Score", type: .music, category: "tech", path: "EditingAssets/music/tech/mixkit_sci_fi_score_464.mp3", sourceURL: "https://mixkit.co/free-stock-music/discover/sci-fi-score-464/", license: "Mixkit Stock Music Free License", tags: ["tech", "futuristic"], intensity: .medium, bestFor: [.techInfluencer], keywords: ["tech", "future"], duration: 97),
        mixkit(id: "mixkit_cyberpunk_city_140", name: "Cyberpunk City", type: .music, category: "tech", path: "EditingAssets/music/tech/mixkit_cyberpunk_city_140.mp3", sourceURL: "https://mixkit.co/free-stock-music/discover/cyberpunk-city-140/", license: "Mixkit Stock Music Free License", tags: ["tech", "energetic"], intensity: .medium, bestFor: [.techInfluencer], keywords: ["cyberpunk", "tech"], duration: 100),
        mixkit(id: "mixkit_meditation_441", name: "Meditation", type: .music, category: "minimal", path: "EditingAssets/music/minimal/mixkit_meditation_441.mp3", sourceURL: "https://mixkit.co/free-stock-music/discover/meditation-441/", license: "Mixkit Stock Music Free License", tags: ["minimal", "clean"], intensity: .low, bestFor: [.podcast, .productDemo], keywords: ["minimal", "clean"], duration: 118)
    ]

    static let visualItems: [AssetRegistryItem] = [
        localDefinition(id: "fx_subtle_film_grain", name: "Subtle Film Grain", type: .visualEffect, category: "film_grain", path: "EditingAssets/visual_effects/film_grain/subtle_film_grain.json", tags: ["cinematic", "premium"], intensity: .low, bestFor: [.cinematic], keywords: ["film", "grain"]),
        localDefinition(id: "fx_warm_light_leak", name: "Warm Light Leak", type: .visualEffect, category: "light_leak", path: "EditingAssets/visual_effects/light_leak/warm_light_leak.json", tags: ["warm", "cinematic"], intensity: .medium, bestFor: [.cinematic], keywords: ["light", "leak"]),
        localDefinition(id: "fx_subtle_gold_glow", name: "Subtle Gold Glow", type: .visualEffect, category: "glow", path: "EditingAssets/visual_effects/glow/subtle_gold_glow.json", tags: ["premium", "soft"], intensity: .low, bestFor: [.cinematic], keywords: ["glow", "gold"]),
        localDefinition(id: "fx_blur_highlight", name: "Blur Highlight", type: .visualEffect, category: "blur", path: "EditingAssets/visual_effects/blur/blur_highlight.json", tags: ["focus", "product"], intensity: .medium, bestFor: [.techInfluencer], keywords: ["blur", "focus"]),
        localDefinition(id: "fx_chromatic_micro_glitch", name: "Tech Glitch", type: .visualEffect, category: "chromatic_aberration", path: "EditingAssets/visual_effects/chromatic_aberration/chromatic_micro_glitch.json", tags: ["tech", "glitch"], intensity: .medium, bestFor: [.techInfluencer], keywords: ["glitch", "chromatic"]),
        localDefinition(id: "fx_slow_zoom", name: "Slow Zoom", type: .visualEffect, category: "camera_motion", path: "EditingAssets/visual_effects/camera_motion/slow_zoom.json", tags: ["camera", "smooth"], intensity: .low, bestFor: [.cinematic], keywords: ["zoom", "push"]),
        localDefinition(id: "fx_camera_snap", name: "Camera Snap", type: .visualEffect, category: "retro_camera", path: "EditingAssets/visual_effects/retro_camera/camera_snap.json", tags: ["camera", "creator"], intensity: .medium, bestFor: [.techInfluencer], keywords: ["camera", "snap"]),
        localDefinition(id: "fx_controlled_speed_ramp", name: "Controlled Speed Ramp", type: .visualEffect, category: "speed_ramp", path: "EditingAssets/visual_effects/speed_ramp/controlled_speed_ramp.json", tags: ["fast", "dynamic"], intensity: .medium, bestFor: [.techInfluencer], keywords: ["speed", "ramp"])
    ]

    static let captionStyleItems: [AssetRegistryItem] = [
        localDefinition(id: "caption_cinematic_lower_third", name: "Cinematic Lower Third", type: .captionStyle, category: "cinematic", path: "EditingAssets/caption_styles/cinematic/cinematic_lower_third.json", tags: ["lower third", "cinematic"], intensity: .low, bestFor: [.cinematic], keywords: ["caption", "cinematic"]),
        localDefinition(id: "caption_cinematic_quote", name: "Cinematic Quote", type: .captionStyle, category: "cinematic", path: "EditingAssets/caption_styles/cinematic/cinematic_quote.json", tags: ["quote", "focus"], intensity: .low, bestFor: [.cinematic, .podcast], keywords: ["quote", "caption"]),
        localDefinition(id: "caption_bold_tech_dynamic", name: "Bold Tech Dynamic", type: .captionStyle, category: "tech_influencer", path: "EditingAssets/caption_styles/tech_influencer/bold_tech_dynamic.json", tags: ["tech", "bold"], intensity: .medium, bestFor: [.techInfluencer], keywords: ["tech", "caption"]),
        localDefinition(id: "caption_minimal_clean", name: "Minimal Clean", type: .captionStyle, category: "minimal", path: "EditingAssets/caption_styles/minimal/minimal_clean.json", tags: ["minimal", "clean"], intensity: .low, bestFor: [.productDemo, .podcast], keywords: ["minimal", "caption"]),
        localDefinition(id: "caption_bold_viral_pop", name: "Bold Viral Pop", type: .captionStyle, category: "bold_viral", path: "EditingAssets/caption_styles/bold_viral/bold_viral_pop.json", tags: ["viral", "bold"], intensity: .high, bestFor: [.ugc, .influencer], keywords: ["viral", "caption"])
    ]

    static let transitionItems: [AssetRegistryItem] = [
        localDefinition(id: "transition_fade", name: "Fade", type: .transition, category: "fade", path: "EditingAssets/transitions/fade.json", tags: ["cinematic", "soft"], intensity: .low, bestFor: [.cinematic], keywords: ["fade"], duration: 0.28),
        localDefinition(id: "transition_cross_dissolve", name: "Cross Dissolve", type: .transition, category: "cross_dissolve", path: "EditingAssets/transitions/cross_dissolve.json", tags: ["clean", "smooth"], intensity: .low, bestFor: [.cinematic, .podcast], keywords: ["dissolve"], duration: 0.24),
        localDefinition(id: "transition_soft_push", name: "Soft Push", type: .transition, category: "soft_push", path: "EditingAssets/transitions/soft_push.json", tags: ["premium", "motion"], intensity: .medium, bestFor: [.cinematic], keywords: ["push"], duration: 0.30),
        localDefinition(id: "transition_swipe", name: "Swipe", type: .transition, category: "swipe", path: "EditingAssets/transitions/swipe.json", tags: ["tech", "fast"], intensity: .medium, bestFor: [.techInfluencer], keywords: ["swipe"], duration: 0.20),
        localDefinition(id: "transition_zoom_cut", name: "Zoom Cut", type: .transition, category: "zoom_cut", path: "EditingAssets/transitions/zoom_cut.json", tags: ["tech", "punch"], intensity: .high, bestFor: [.techInfluencer], keywords: ["zoom", "cut"], duration: 0.18),
        localDefinition(id: "transition_camera_shutter", name: "Camera Shutter", type: .transition, category: "camera_shutter", path: "EditingAssets/transitions/camera_shutter.json", tags: ["camera", "snap"], intensity: .medium, bestFor: [.techInfluencer], keywords: ["camera", "shutter"], duration: 0.16)
    ]
}
