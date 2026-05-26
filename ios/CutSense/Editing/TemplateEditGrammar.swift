import Foundation

struct TemplateEditGrammar: Sendable {
    let id: String
    let minimumBehaviorGap: Double
    let roleBehaviors: [CaptionRole: CaptionSceneBehavior]
    let regularBehavior: CaptionSceneBehavior
    let cueRecipes: [CaptionSceneBehavior: [EditCue]]
    let cutTransition: CutTransitionRecipe?
    let maxEffectsPerTenSeconds: Int
    var anchorPhrases: [CaptionSceneBehavior: [EditAnchorPhrase]] = [:]
}

struct EditCue: Sendable {
    let type: EditType
    let offset: Double
    let duration: Double
    let intensity: Float
    let reason: String

    init(
        type: EditType,
        offset: Double = 0,
        duration: Double,
        intensity: Float,
        reason: String
    ) {
        self.type = type
        self.offset = offset
        self.duration = duration
        self.intensity = intensity
        self.reason = reason
    }
}

struct CutTransitionRecipe: Sendable {
    let minimumGap: Double
    let transitionDuration: Double
    let transitionIntensity: Float
    let cues: [EditCue]
}

struct EditAnchorPhrase: Sendable {
    let text: String

    init(_ text: String) {
        self.text = text
    }
}

enum TemplateGrammarLibrary {
    static func grammar(for template: TemplateConfig) -> TemplateEditGrammar {
        switch template.id {
        case "tech_influencer":
            techInfluencer
        case "viral_caption":
            viralCaption
        case "premium_founder":
            premiumFounder
        case "clean_expert":
            cleanExpert
        case "cinematic_storyteller":
            cinematicStoryteller
        case "podcast_highlights":
            podcastHighlights
        default:
            cleanExpert
        }
    }

    private static let techAnchorPhrases: [EditAnchorPhrase] = [
        EditAnchorPhrase("yapay zeka"),
        EditAnchorPhrase("artificial intelligence"),
        EditAnchorPhrase("vibe coding"),
        EditAnchorPhrase("app store"),
        EditAnchorPhrase("mvp"),
        EditAnchorPhrase("web"),
        EditAnchorPhrase("uygulama"),
        EditAnchorPhrase("ürün"),
        EditAnchorPhrase("urun"),
        EditAnchorPhrase("product"),
        EditAnchorPhrase("startup"),
        EditAnchorPhrase("kod"),
        EditAnchorPhrase("code"),
        EditAnchorPhrase("coding"),
        EditAnchorPhrase("ai")
    ]

    private static let techInfluencer = TemplateEditGrammar(
        id: "tech_influencer",
        minimumBehaviorGap: 2.35,
        roleBehaviors: [
            .hook: .hookImpact,
            .warning: .underlineReveal,
            .reveal: .punchIn,
            .keyword: .keywordLockOn,
            .transition: .transitionWhoosh,
            .conclusion: .conclusionHold
        ],
        regularBehavior: .none,
        cueRecipes: [
            .hookImpact: [
                EditCue(type: .sfx, offset: -0.70, duration: 0.70, intensity: 0.26, reason: "Hook short riser"),
                EditCue(type: .zoom, duration: 0.80, intensity: 0.18, reason: "Hook slow push-in zoom"),
                EditCue(type: .zoom, offset: 0.80, duration: 0.80, intensity: 0.18, reason: "Hook sentence back zoom"),
                EditCue(type: .sfx, duration: 0.16, intensity: 0.38, reason: "Hook keyword impact SFX")
            ],
            .focusBlur: [
                EditCue(type: .zoom, offset: -0.06, duration: 0.76, intensity: 0.30, reason: "Tech UI focus zoom"),
                EditCue(type: .colorShift, duration: 0.34, intensity: 0.14, reason: "Tech UI highlight pulse")
            ],
            .keywordLockOn: [
                EditCue(type: .zoom, offset: -0.04, duration: 0.64, intensity: 0.18, reason: "Tech keyword controlled zoom")
            ],
            .transitionWhoosh: [
                EditCue(type: .cutTransition, offset: -0.02, duration: 0.16, intensity: 0.22, reason: "Topic shift motion blur cut")
            ],
            .conclusionHold: [
                EditCue(type: .zoom, duration: 1.40, intensity: 0.24, reason: "CTA slow push"),
                EditCue(type: .sfx, duration: 0.14, intensity: 0.34, reason: "CTA notification ping")
            ],
            .subtleZoom: [
                EditCue(type: .zoom, duration: 0.46, intensity: 0.20, reason: "Tech subtle emphasis zoom")
            ],
            .punchIn: [
                EditCue(type: .zoom, offset: -0.04, duration: 0.72, intensity: 0.34, reason: "Tech reveal zoom"),
                EditCue(type: .sfx, duration: 0.16, intensity: 0.46, reason: "Tech reveal impact SFX")
            ]
        ],
        cutTransition: nil,
        maxEffectsPerTenSeconds: 7,
        anchorPhrases: [
            .keywordLockOn: techAnchorPhrases,
            .punchIn: techAnchorPhrases,
            .focusBlur: techAnchorPhrases
        ]
    )

    private static let viralCaption = TemplateEditGrammar(
        id: "viral_caption",
        minimumBehaviorGap: 1.0,
        roleBehaviors: [
            .hook: .hookImpact,
            .warning: .underlineReveal,
            .reveal: .focusBlur,
            .keyword: .keywordLockOn,
            .transition: .transitionWhoosh,
            .conclusion: .conclusionHold
        ],
        regularBehavior: .punchIn,
        cueRecipes: [
            .hookImpact: [
                EditCue(type: .sfx, offset: -0.10, duration: 0.28, intensity: 0.64, reason: "Hook pre-whoosh"),
                EditCue(type: .zoom, duration: 0.80, intensity: 0.95, reason: "Hook push-pull zoom"),
                EditCue(type: .sfx, duration: 0.24, intensity: 0.86, reason: "Hook impact SFX"),
                EditCue(type: .flash, duration: 0.18, intensity: 0.48, reason: "Hook flash"),
                EditCue(type: .shake, duration: 0.16, intensity: 0.50, reason: "Hook micro shake")
            ],
            .focusBlur: [
                EditCue(type: .zoom, duration: 0.65, intensity: 0.68, reason: "Focus push-pull zoom"),
                EditCue(type: .sfx, duration: 0.18, intensity: 0.42, reason: "Focus pop SFX")
            ],
            .underlineReveal: [
                EditCue(type: .flash, duration: 0.26, intensity: 0.42, reason: "Reveal flash"),
                EditCue(type: .sfx, offset: 0.06, duration: 0.18, intensity: 0.44, reason: "Reveal pop SFX")
            ],
            .keywordLockOn: [
                EditCue(type: .zoom, duration: 0.42, intensity: 0.64, reason: "Keyword snap zoom"),
                EditCue(type: .sfx, offset: 0.04, duration: 0.18, intensity: 0.58, reason: "Keyword impact SFX"),
                EditCue(type: .shake, duration: 0.10, intensity: 0.26, reason: "Keyword micro shake")
            ],
            .transitionWhoosh: [
                EditCue(type: .sfx, offset: -0.12, duration: 0.32, intensity: 0.65, reason: "Transition whoosh"),
                EditCue(type: .zoom, offset: -0.08, duration: 0.40, intensity: 0.62, reason: "Transition whip zoom"),
                EditCue(type: .flash, duration: 0.18, intensity: 0.30, reason: "Transition flash")
            ],
            .conclusionHold: [
                EditCue(type: .sfx, offset: -0.55, duration: 0.75, intensity: 0.34, reason: "Conclusion riser"),
                EditCue(type: .zoom, duration: 1.10, intensity: 0.50, reason: "Conclusion slow push"),
                EditCue(type: .colorShift, duration: 0.45, intensity: 0.42, reason: "Conclusion mood"),
                EditCue(type: .sfx, duration: 0.18, intensity: 0.50, reason: "Conclusion impact SFX")
            ],
            .punchIn: [
                EditCue(type: .zoom, duration: 0.38, intensity: 0.70, reason: "Punch camera punch"),
                EditCue(type: .sfx, duration: 0.16, intensity: 0.48, reason: "Punch impact SFX"),
                EditCue(type: .shake, duration: 0.10, intensity: 0.26, reason: "Punch micro shake")
            ],
            .subtleZoom: [
                EditCue(type: .zoom, duration: 0.48, intensity: 0.35, reason: "Subtle push zoom")
            ]
        ],
        cutTransition: CutTransitionRecipe(
            minimumGap: 0.30,
            transitionDuration: 0.20,
            transitionIntensity: 0.50,
            cues: [
                EditCue(type: .sfx, offset: -0.05, duration: 0.28, intensity: 0.68, reason: "Cut whoosh"),
                EditCue(type: .sfx, offset: -0.01, duration: 0.20, intensity: 0.62, reason: "Cut impact SFX")
            ]
        ),
        maxEffectsPerTenSeconds: 10
    )

    private static let premiumFounder = TemplateEditGrammar(
        id: "premium_founder",
        minimumBehaviorGap: 4.0,
        roleBehaviors: [
            .hook: .hookImpact,
            .reveal: .focusBlur,
            .keyword: .keywordLockOn,
            .conclusion: .conclusionHold
        ],
        regularBehavior: .none,
        cueRecipes: [
            .hookImpact: [
                EditCue(type: .zoom, duration: 0.90, intensity: 0.38, reason: "Founder hook push"),
                EditCue(type: .sfx, duration: 0.18, intensity: 0.22, reason: "Founder soft impact SFX")
            ],
            .focusBlur: [
                EditCue(type: .zoom, duration: 0.75, intensity: 0.28, reason: "Founder focus push")
            ],
            .keywordLockOn: [
                EditCue(type: .zoom, duration: 0.42, intensity: 0.26, reason: "Founder keyword push")
            ],
            .conclusionHold: [
                EditCue(type: .zoom, duration: 1.4, intensity: 0.28, reason: "Founder conclusion hold")
            ]
        ],
        cutTransition: nil,
        maxEffectsPerTenSeconds: 4
    )

    private static let cleanExpert = TemplateEditGrammar(
        id: "clean_expert",
        minimumBehaviorGap: 3.0,
        roleBehaviors: [
            .hook: .focusBlur,
            .reveal: .underlineReveal,
            .keyword: .keywordLockOn,
            .conclusion: .conclusionHold
        ],
        regularBehavior: .none,
        cueRecipes: [
            .focusBlur: [
                EditCue(type: .zoom, duration: 0.70, intensity: 0.30, reason: "Clean focus push")
            ],
            .underlineReveal: [
                EditCue(type: .flash, duration: 0.20, intensity: 0.20, reason: "Clean reveal emphasis")
            ],
            .keywordLockOn: [
                EditCue(type: .sfx, duration: 0.14, intensity: 0.20, reason: "Clean keyword click SFX")
            ],
            .conclusionHold: [
                EditCue(type: .zoom, duration: 1.0, intensity: 0.22, reason: "Clean conclusion hold")
            ]
        ],
        cutTransition: nil,
        maxEffectsPerTenSeconds: 5
    )

    private static let cinematicStoryteller = TemplateEditGrammar(
        id: "cinematic_storyteller",
        minimumBehaviorGap: 3.0,
        roleBehaviors: [
            .hook: .hookImpact,
            .reveal: .focusBlur,
            .keyword: .focusBlur,
            .conclusion: .conclusionHold
        ],
        regularBehavior: .subtleZoom,
        cueRecipes: [
            .hookImpact: [
                EditCue(type: .zoom, duration: 1.2, intensity: 0.36, reason: "Cinematic hook slow push"),
                EditCue(type: .colorShift, duration: 0.7, intensity: 0.28, reason: "Cinematic hook mood")
            ],
            .focusBlur: [
                EditCue(type: .zoom, duration: 0.90, intensity: 0.30, reason: "Cinematic focus push")
            ],
            .subtleZoom: [
                EditCue(type: .zoom, duration: 1.1, intensity: 0.18, reason: "Cinematic breathing push")
            ],
            .conclusionHold: [
                EditCue(type: .sfx, offset: -0.7, duration: 0.9, intensity: 0.26, reason: "Conclusion riser"),
                EditCue(type: .zoom, duration: 1.7, intensity: 0.30, reason: "Cinematic conclusion slow push"),
                EditCue(type: .colorShift, duration: 0.9, intensity: 0.30, reason: "Conclusion mood")
            ]
        ],
        cutTransition: CutTransitionRecipe(
            minimumGap: 0.55,
            transitionDuration: 0.24,
            transitionIntensity: 0.22,
            cues: []
        ),
        maxEffectsPerTenSeconds: 5
    )

    private static let podcastHighlights = TemplateEditGrammar(
        id: "podcast_highlights",
        minimumBehaviorGap: 5.0,
        roleBehaviors: [
            .hook: .focusBlur,
            .keyword: .keywordLockOn,
            .conclusion: .conclusionHold
        ],
        regularBehavior: .none,
        cueRecipes: [
            .focusBlur: [
                EditCue(type: .zoom, duration: 0.80, intensity: 0.20, reason: "Podcast quote focus")
            ],
            .keywordLockOn: [
                EditCue(type: .sfx, duration: 0.12, intensity: 0.14, reason: "Podcast keyword tap SFX")
            ],
            .conclusionHold: [
                EditCue(type: .zoom, duration: 1.1, intensity: 0.18, reason: "Podcast conclusion hold")
            ]
        ],
        cutTransition: nil,
        maxEffectsPerTenSeconds: 3
    )
}

extension TemplateConfig {
    var editGrammar: TemplateEditGrammar {
        TemplateGrammarLibrary.grammar(for: self)
    }
}
