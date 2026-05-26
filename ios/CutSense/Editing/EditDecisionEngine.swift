import Foundation

struct EditDecision: Sendable, Identifiable {
    let id = UUID()
    let time: Double
    let duration: Double
    let type: EditType
    let reason: String
    let intensity: Float // 0.0-1.0
}

enum EditType: String, Codable, Sendable, CaseIterable {
    case sfx
    case zoom
    case shake
    case flash
    case colorShift = "color_shift"
    case cutTransition = "cut_transition"
}

enum TechInfluencerEffectEventKind: String, CaseIterable, Sendable {
    case hook
    case topicShift
    case reveal
    case uiAction
    case keyword
    case warning
    case cta
}

enum TechInfluencerCueAnchorMode: Sendable, Equatable {
    case anchor(offset: Double, tolerance: Double)
    case start(tolerance: Double)
}

enum TechInfluencerEffectCue: String, CaseIterable, Sendable {
    case hookShortRiser = "Hook short riser"
    case hookKeywordImpactSFX = "Hook keyword impact SFX"
    case hookSlowPushInZoom = "Hook slow push-in zoom"
    case hookSentenceBackZoom = "Hook sentence back zoom"
    case legacyHookSlowPushBackZoom = "Hook slow push-back zoom"
    case topicShiftWhoosh = "Topic shift whoosh"
    case topicShiftMotionBlurCut = "Topic shift motion blur cut"
    case topicShiftSoftImpactSFX = "Topic shift soft impact SFX"
    case techRevealRiser = "Tech reveal riser"
    case techRevealWhoosh = "Tech reveal whoosh"
    case techRevealZoom = "Tech reveal zoom"
    case techRevealImpactSFX = "Tech reveal impact SFX"
    case techUIFocusZoom = "Tech UI focus zoom"
    case techUIHighlightPulse = "Tech UI highlight pulse"
    case techUIClickSFX = "Tech UI click SFX"
    case techKeywordControlledZoom = "Tech keyword controlled zoom"
    case techKeywordClickSFX = "Tech keyword click SFX"
    case techWarningAmberAccent = "Tech warning amber accent"
    case techWarningLowImpactSFX = "Tech warning low impact SFX"
    case ctaMusicLiftRiser = "CTA music lift riser"
    case ctaSlowPush = "CTA slow push"
    case ctaNotificationPing = "CTA notification ping"

    init?(reason: String) {
        self.init(rawValue: reason)
    }

    var reason: String { rawValue }

    var eventKind: TechInfluencerEffectEventKind {
        switch self {
        case .hookShortRiser,
             .hookKeywordImpactSFX,
             .hookSlowPushInZoom,
             .hookSentenceBackZoom,
             .legacyHookSlowPushBackZoom:
            .hook
        case .topicShiftWhoosh,
             .topicShiftMotionBlurCut,
             .topicShiftSoftImpactSFX:
            .topicShift
        case .techRevealRiser,
             .techRevealWhoosh,
             .techRevealZoom,
             .techRevealImpactSFX:
            .reveal
        case .techUIFocusZoom,
             .techUIHighlightPulse,
             .techUIClickSFX:
            .uiAction
        case .techKeywordControlledZoom,
             .techKeywordClickSFX:
            .keyword
        case .techWarningAmberAccent,
             .techWarningLowImpactSFX:
            .warning
        case .ctaMusicLiftRiser,
             .ctaSlowPush,
             .ctaNotificationPing:
            .cta
        }
    }

    var editType: EditType {
        switch self {
        case .hookShortRiser,
             .hookKeywordImpactSFX,
             .topicShiftWhoosh,
             .topicShiftSoftImpactSFX,
             .techRevealRiser,
             .techRevealWhoosh,
             .techRevealImpactSFX,
             .techUIClickSFX,
             .techKeywordClickSFX,
             .techWarningLowImpactSFX,
             .ctaMusicLiftRiser,
             .ctaNotificationPing:
            .sfx
        case .hookSlowPushInZoom,
             .hookSentenceBackZoom,
             .legacyHookSlowPushBackZoom,
             .techRevealZoom,
             .techUIFocusZoom,
             .techKeywordControlledZoom,
             .ctaSlowPush:
            .zoom
        case .techUIHighlightPulse,
             .techWarningAmberAccent:
            .colorShift
        case .topicShiftMotionBlurCut:
            .cutTransition
        }
    }

    var routeMode: TechInfluencerCueAnchorMode {
        switch self {
        case .hookShortRiser:
            .anchor(offset: -0.70, tolerance: 0.45)
        case .hookKeywordImpactSFX:
            .anchor(offset: 0, tolerance: 0.35)
        case .hookSlowPushInZoom,
             .legacyHookSlowPushBackZoom:
            .start(tolerance: 0.45)
        case .hookSentenceBackZoom:
            .anchor(offset: 0.70, tolerance: 0.90)
        case .topicShiftWhoosh:
            .anchor(offset: -0.12, tolerance: 0.35)
        case .topicShiftMotionBlurCut:
            .anchor(offset: -0.02, tolerance: 0.35)
        case .topicShiftSoftImpactSFX:
            .anchor(offset: 0, tolerance: 0.35)
        case .techRevealRiser:
            .anchor(offset: -0.70, tolerance: 0.50)
        case .techRevealWhoosh:
            .anchor(offset: -0.10, tolerance: 0.40)
        case .techRevealZoom:
            .anchor(offset: Self.techRevealZoomAnchorOffset, tolerance: 0.45)
        case .techRevealImpactSFX:
            .anchor(offset: 0, tolerance: 0.40)
        case .techUIFocusZoom:
            .anchor(offset: -0.38, tolerance: 0.45)
        case .techUIHighlightPulse:
            .anchor(offset: 0, tolerance: 0.35)
        case .techUIClickSFX:
            .anchor(offset: 0.04, tolerance: 0.35)
        case .techKeywordControlledZoom:
            .anchor(offset: -0.32, tolerance: 0.50)
        case .techKeywordClickSFX:
            .anchor(offset: 0, tolerance: 0.45)
        case .techWarningAmberAccent:
            .anchor(offset: -0.02, tolerance: 0.45)
        case .techWarningLowImpactSFX:
            .anchor(offset: 0, tolerance: 0.40)
        case .ctaMusicLiftRiser:
            .anchor(offset: -0.85, tolerance: 0.50)
        case .ctaSlowPush:
            .anchor(offset: -1.20, tolerance: 1.35)
        case .ctaNotificationPing:
            .anchor(offset: 0, tolerance: 0.40)
        }
    }

    var requiredPeakScale: Double? {
        switch self {
        case .techRevealZoom:
            1.08
        case .techUIFocusZoom:
            1.06
        case .hookSlowPushInZoom,
             .hookSentenceBackZoom,
             .legacyHookSlowPushBackZoom,
             .ctaSlowPush:
            1.035
        case .techKeywordControlledZoom:
            1.025
        case .hookShortRiser,
             .hookKeywordImpactSFX,
             .topicShiftWhoosh,
             .topicShiftMotionBlurCut,
             .topicShiftSoftImpactSFX,
             .techRevealRiser,
             .techRevealWhoosh,
             .techRevealImpactSFX,
             .techUIHighlightPulse,
             .techUIClickSFX,
             .techKeywordClickSFX,
             .techWarningAmberAccent,
             .techWarningLowImpactSFX,
             .ctaMusicLiftRiser,
             .ctaNotificationPing:
            nil
        }
    }

    var isRequiredComboCue: Bool {
        switch self {
        case .hookShortRiser,
             .legacyHookSlowPushBackZoom,
             .topicShiftWhoosh,
             .topicShiftSoftImpactSFX,
             .techRevealRiser,
             .techRevealWhoosh,
             .techUIClickSFX,
             .techKeywordControlledZoom,
             .techKeywordClickSFX,
             .techWarningAmberAccent,
             .techWarningLowImpactSFX,
             .ctaMusicLiftRiser:
            false
        case .hookKeywordImpactSFX,
             .hookSlowPushInZoom,
             .hookSentenceBackZoom,
             .topicShiftMotionBlurCut,
             .techRevealZoom,
             .techRevealImpactSFX,
             .techUIFocusZoom,
             .techUIHighlightPulse,
             .ctaSlowPush,
             .ctaNotificationPing:
            true
        }
    }

    var isOptionalSFX: Bool {
        switch self {
        case .hookShortRiser,
             .topicShiftWhoosh,
             .techRevealRiser,
             .techRevealWhoosh,
             .topicShiftSoftImpactSFX,
             .techUIClickSFX,
             .techKeywordClickSFX,
             .techWarningLowImpactSFX,
             .ctaMusicLiftRiser:
            true
        case .hookKeywordImpactSFX,
             .techRevealImpactSFX,
             .ctaNotificationPing,
             .hookSlowPushInZoom,
             .hookSentenceBackZoom,
             .legacyHookSlowPushBackZoom,
             .topicShiftMotionBlurCut,
             .techRevealZoom,
             .techUIFocusZoom,
             .techUIHighlightPulse,
             .techKeywordControlledZoom,
             .techWarningAmberAccent,
             .ctaSlowPush:
            false
        }
    }

    var isRevealComboCue: Bool {
        eventKind == .reveal
    }

    var revealComboAnchorOffset: Double? {
        switch self {
        case .techRevealRiser:
            return -0.60
        case .techRevealWhoosh:
            return -0.10
        case .techRevealZoom:
            return Self.techRevealZoomAnchorOffset
        case .techRevealImpactSFX:
            return 0
        case .hookShortRiser,
             .hookKeywordImpactSFX,
             .hookSlowPushInZoom,
             .hookSentenceBackZoom,
             .legacyHookSlowPushBackZoom,
             .topicShiftWhoosh,
             .topicShiftMotionBlurCut,
             .topicShiftSoftImpactSFX,
             .techUIFocusZoom,
             .techUIHighlightPulse,
             .techUIClickSFX,
             .techKeywordControlledZoom,
             .techKeywordClickSFX,
             .techWarningAmberAccent,
             .techWarningLowImpactSFX,
             .ctaMusicLiftRiser,
             .ctaSlowPush,
             .ctaNotificationPing:
            return nil
        }
    }

    static func requiredReasons(for eventKind: TechInfluencerEffectEventKind) -> [String] {
        allCases
            .filter { $0.eventKind == eventKind && $0.isRequiredComboCue }
            .map(\.reason)
    }

    static var semanticReasons: Set<String> {
        Set(allCases.map(\.reason))
    }

    private static let techRevealZoomAnchorOffset = -0.72 * 0.34
}

struct EditPlan: Sendable {
    let decisions: [EditDecision]
    let template: TemplateConfig
    let totalEffects: Int
    let averageIntensity: Float
}

enum EditDecisionEngine {
    static func generateEditPlan(
        captions: [CaptionSegment],
        roughCut: RoughCutResult,
        template: TemplateConfig,
        timelinePlan: TechInfluencerTimelinePlan? = nil
    ) -> EditPlan {
        var captionDecisions = if template.id == "tech_influencer" {
            TechInfluencerTimelineDirector.generateDecisions(
                captions: captions,
                roughCut: roughCut,
                timelinePlan: timelinePlan
            )
        } else {
            captions.flatMap { caption in
                editsForCaption(caption, template: template)
            }
        }

        // Caption decisions are source-timed and get remapped during export. Cut transitions below are
        // already clean-timeline decisions, so density limiting them together would mix timebases.
        captionDecisions = IntensityLimiter.limit(captionDecisions, template: template)
        captionDecisions = OverEditingGuard.filter(captionDecisions, totalDuration: roughCut.originalDuration)
        captionDecisions = clampIntensities(captionDecisions)

        let cutTransitions = generateCutTransitions(
            roughCut: roughCut,
            template: template
        )
        let decisions = (captionDecisions + clampIntensities(cutTransitions))
            .sorted { $0.time < $1.time }

        let avgIntensity = decisions.isEmpty ? 0 : decisions.reduce(Float(0)) { $0 + $1.intensity } / Float(decisions.count)

        return EditPlan(
            decisions: decisions,
            template: template,
            totalEffects: decisions.count,
            averageIntensity: avgIntensity
        )
    }

    /// Per-template visual intensity multiplier (scales zoom + flash + colorShift strength).
    /// Low-intensity templates (premiumFounder, podcastHighlights, cleanExpert) get softer effects;
    /// high-intensity templates (viralCaption) get punchier ones.
    private static func visualScale(_ template: TemplateConfig) -> Float {
        switch template.intensity {
        case .low: return 0.55
        case .medium: return 1.0
        case .high: return 1.35
        }
    }

    /// SFX intensity is gated by the template's sfxVolume so quiet templates don't get loud SFX
    /// just because the scene behavior says "hook".
    private static func sfxScale(_ template: TemplateConfig, base: Float) -> Float {
        let v = min(max(template.sfxVolume, 0), 1)
        // Map sfxVolume 0..0.3 -> 0.0..1.0 multiplier so even quiet templates keep their relative
        // accents, but never exceed `base`.
        let mapped = min(1.0, v / 0.3)
        return base * mapped
    }

    private static func layeredSFXEnabled(_ template: TemplateConfig) -> Bool {
        template.intensity == .high
    }

    private static func audibleSFXTime(_ time: Double) -> Double {
        max(0.05, time)
    }

    private static func clampIntensities(_ decisions: [EditDecision]) -> [EditDecision] {
        decisions.map { decision in
            let clamped = min(max(decision.intensity, 0), 1)
            guard clamped != decision.intensity else { return decision }
            return EditDecision(
                time: decision.time,
                duration: decision.duration,
                type: decision.type,
                reason: decision.reason,
                intensity: clamped
            )
        }
    }

    private static func editsForCaption(_ caption: CaptionSegment, template: TemplateConfig) -> [EditDecision] {
        let recipes = template.editGrammar.cueRecipes[caption.sceneBehavior] ?? []
        let anchorTime = anchorTime(for: caption, template: template)
        return recipes.map { decision(from: $0, anchorTime: anchorTime, template: template) }
    }

    /// Generate visual transition effects at cut boundaries (where segments were removed)
    private static func generateCutTransitions(
        roughCut: RoughCutResult,
        template: TemplateConfig
    ) -> [EditDecision] {
        // Tech Influencer uses semantic topic/reveal/UI transitions from
        // TechInfluencerTimelineDirector. Normal silence trims stay hard cuts.
        guard template.id != "tech_influencer" else { return [] }
        guard let recipe = template.editGrammar.cutTransition else { return [] }

        let includedRanges = TimelineRangeNormalizer.includedRanges(
            from: roughCut.decisions,
            assetDuration: roughCut.originalDuration
        )

        guard includedRanges.count >= 2 else { return [] }

        var transitions: [EditDecision] = []
        var cleanTime: Double = 0

        for i in 0..<(includedRanges.count - 1) {
            let current = includedRanges[i]
            let next = includedRanges[i + 1]
            let segmentDuration = current.duration
            cleanTime += segmentDuration

            // Only add transition if there was actually a cut (gap between segments)
            let gap = next.startTime - current.endTime
            guard gap > recipe.minimumGap else { continue }

            // cutTransition at the boundary point in clean timeline
            transitions.append(EditDecision(
                time: cleanTime - 0.05,
                duration: recipe.transitionDuration,
                type: .cutTransition,
                reason: "Cut boundary",
                intensity: recipe.transitionIntensity
            ))

            let cutCues = recipe.cues.map { cue in
                decision(from: cue, anchorTime: cleanTime, template: template)
            }
            transitions.append(contentsOf: cutCues)
        }

        return transitions
    }

    private static func decision(from cue: EditCue, anchorTime: Double, template: TemplateConfig) -> EditDecision {
        let rawTime = anchorTime + cue.offset
        let time = cue.type == .sfx ? audibleSFXTime(rawTime) : max(0, rawTime)
        let intensity = switch cue.type {
        case .sfx:
            sfxScale(template, base: cue.intensity)
        case .zoom, .shake, .flash, .colorShift, .cutTransition:
            cue.intensity * visualScale(template)
        }
        return EditDecision(
            time: time,
            duration: cue.duration,
            type: cue.type,
            reason: cue.reason,
            intensity: intensity
        )
    }

    private static func anchorTime(for caption: CaptionSegment, template: TemplateConfig) -> Double {
        let phrases = template.editGrammar.anchorPhrases[caption.sceneBehavior] ?? []
        guard !phrases.isEmpty,
              let wordStart = matchingAnchorTime(in: caption, phrases: phrases) else {
            return caption.startTime
        }

        let latestUsefulAnchor = max(caption.startTime, caption.endTime - 0.05)
        return min(max(wordStart, caption.startTime), latestUsefulAnchor)
    }

    private static func matchingAnchorTime(
        in caption: CaptionSegment,
        phrases: [EditAnchorPhrase]
    ) -> Double? {
        let timings = caption.wordTimings
        guard !timings.isEmpty else { return nil }

        let timingTokens = timings.map { normalizedToken($0.word) }
        let phraseTokens = phrases
            .map { phrase in phrase.text.split(whereSeparator: \.isWhitespace).map { normalizedToken(String($0)) } }
            .filter { !$0.isEmpty }

        var earliestMatch: Double?
        for phrase in phraseTokens {
            guard phrase.count <= timingTokens.count else { continue }

            let lastStartIndex = timingTokens.count - phrase.count
            for startIndex in 0...lastStartIndex where phraseMatches(
                phrase,
                timingTokens: timingTokens,
                at: startIndex
            ) {
                let start = timings[startIndex].start
                earliestMatch = min(earliestMatch ?? start, start)
            }
        }

        return earliestMatch
    }

    private static func phraseMatches(
        _ phrase: [String],
        timingTokens: [String],
        at startIndex: Int
    ) -> Bool {
        for (offset, phraseToken) in phrase.enumerated() {
            let timingToken = timingTokens[startIndex + offset]
            guard tokenMatches(timingToken, phraseToken: phraseToken) else {
                return false
            }
        }
        return true
    }

    private static func tokenMatches(_ timingToken: String, phraseToken: String) -> Bool {
        guard !timingToken.isEmpty, !phraseToken.isEmpty else { return false }
        if timingToken == phraseToken { return true }
        return phraseToken.count >= 4 && timingToken.hasPrefix(phraseToken)
    }

    private static func normalizedToken(_ token: String) -> String {
        token
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }
}

private extension TechInfluencerTimelinePlan.Event.Kind {
    var captionRole: CaptionRole {
        switch self {
        case .hook: .hook
        case .topicShift: .transition
        case .reveal: .reveal
        case .uiAction, .keyword: .keyword
        case .warning: .warning
        case .cta: .conclusion
        }
    }

    var captionStyle: CaptionStyle {
        switch self {
        case .hook, .cta: .hookImpact
        case .topicShift: .typewriterClean
        case .reveal, .uiAction, .keyword, .warning: .neonGlow
        }
    }

    var sceneBehavior: CaptionSceneBehavior {
        switch self {
        case .hook: .hookImpact
        case .topicShift: .transitionWhoosh
        case .reveal: .punchIn
        case .uiAction: .focusBlur
        case .keyword: .keywordLockOn
        case .warning: .underlineReveal
        case .cta: .conclusionHold
        }
    }
}

private enum TechInfluencerTimelineDirector {
    private typealias Cue = TechInfluencerEffectCue

    private enum EventKind: Equatable {
        case hook
        case topicShift
        case reveal
        case uiAction
        case keyword
        case warning
        case cta

        init(_ kind: TechInfluencerTimelinePlan.Event.Kind) {
            switch kind {
            case .hook: self = .hook
            case .topicShift: self = .topicShift
            case .reveal: self = .reveal
            case .uiAction: self = .uiAction
            case .keyword: self = .keyword
            case .warning: self = .warning
            case .cta: self = .cta
            }
        }
    }

    private struct TimelineEvent {
        let kind: EventKind
        let caption: CaptionSegment
        let anchorTime: Double
        let confidence: Float
        let sourceReason: String

        init(
            kind: EventKind,
            caption: CaptionSegment,
            anchorTime: Double,
            confidence: Float = 1,
            sourceReason: String = ""
        ) {
            self.kind = kind
            self.caption = caption
            self.anchorTime = anchorTime
            self.confidence = confidence
            self.sourceReason = sourceReason
        }

        init(event: TechInfluencerTimelinePlan.Event) {
            self.kind = EventKind(event.kind)
            self.caption = CaptionSegment(
                startTime: event.sourceStart,
                endTime: event.sourceEnd,
                text: event.text,
                role: event.kind.captionRole,
                style: event.kind.captionStyle,
                sceneBehavior: event.kind.sceneBehavior
            )
            self.anchorTime = event.anchorTime
            self.confidence = event.confidence
            self.sourceReason = event.reason
        }
    }

    private static let revealComboMinimumSpacing: Double = 5.0
    private static let uiRevealCouplingWindow: Double = 3.05
    private static let hookMinimumPushDuration: Double = 0.75
    private static let hookMinimumBackDuration: Double = 0.55
    private static let minimumDecisionGap: Double = 1.35

    static func generateDecisions(
        captions: [CaptionSegment],
        roughCut: RoughCutResult,
        timelinePlan: TechInfluencerTimelinePlan? = nil
    ) -> [EditDecision] {
        let budgetDuration = effectiveBudgetDuration(for: roughCut)
        if let timelinePlan, !timelinePlan.events.isEmpty {
            let plannedEvents = coalescedPlannedEvents(timelinePlan.events.map(TimelineEvent.init(event:)))
            let supplementalEvents = supplementalCaptionEvents(
                from: captions,
                plannedEvents: plannedEvents,
                totalDuration: roughCut.originalDuration
            )
            let semanticEvents = prunedSemanticEvents(
                plannedEvents + supplementalEvents,
                totalDuration: budgetDuration
            )
            let generatedDecisions = semanticEvents.flatMap { event in
                decisions(for: event, events: semanticEvents)
            }
            let rangeClamped = clampVisualLeadInsToKeptRanges(generatedDecisions, roughCut: roughCut)
            return finalizedDecisions(rangeClamped, totalDuration: budgetDuration)
        }

        let sortedCaptions = captions.sorted { $0.startTime < $1.startTime }
        guard !sortedCaptions.isEmpty else { return [] }

        let events = prunedSemanticEvents(
            buildEvents(from: sortedCaptions, totalDuration: roughCut.originalDuration),
            totalDuration: budgetDuration
        )
        let generatedDecisions = events.flatMap { decisions(for: $0, events: events) }
        return finalizedDecisions(
            clampVisualLeadInsToKeptRanges(generatedDecisions, roughCut: roughCut),
            totalDuration: budgetDuration
        )
    }

    private static func effectiveBudgetDuration(for roughCut: RoughCutResult) -> Double {
        if roughCut.cleanDuration.isFinite, roughCut.cleanDuration > 0 {
            return roughCut.cleanDuration
        }
        return max(roughCut.originalDuration, 0)
    }

    private static func clampVisualLeadInsToKeptRanges(
        _ decisions: [EditDecision],
        roughCut: RoughCutResult
    ) -> [EditDecision] {
        let ranges = TimelineRangeNormalizer.includedRanges(
            from: roughCut.decisions,
            assetDuration: roughCut.originalDuration
        )
        guard !ranges.isEmpty else { return decisions }

        return decisions.compactMap { decision in
            guard decision.type != .sfx else { return decision }
            if ranges.contains(where: { decision.time >= $0.startTime && decision.time <= $0.endTime }) {
                return decision
            }

            let decisionEnd = decision.time + max(0, decision.duration)
            guard let nextRange = ranges.first(where: { range in
                decision.time < range.startTime && decisionEnd > range.startTime
            }) else {
                return decision
            }

            let clampedEnd = min(decisionEnd, nextRange.endTime)
            let clampedDuration = max(0.12, clampedEnd - nextRange.startTime)
            return EditDecision(
                time: nextRange.startTime,
                duration: clampedDuration,
                type: decision.type,
                reason: decision.reason,
                intensity: decision.intensity
            )
        }
    }

    private static func coalescedPlannedEvents(_ events: [TimelineEvent]) -> [TimelineEvent] {
        var coalesced: [TimelineEvent] = []
        var lastHookIndex: Int?
        var lastHookAnchorTime: Double = -10
        var lastRevealIndex: Int?
        var lastRevealAnchorTime: Double = -10
        var lastCTAIndex: Int?
        var lastCTAAnchorTime: Double = -10

        for event in events.sorted(by: { $0.caption.startTime < $1.caption.startTime }) {
            if event.kind == .hook,
               let lastHookIndex,
               event.anchorTime - lastHookAnchorTime < 3.0 {
                if event.anchorTime < coalesced[lastHookIndex].anchorTime {
                    coalesced[lastHookIndex] = event
                    lastHookAnchorTime = event.anchorTime
                }
                continue
            }

            if event.kind == EventKind.reveal,
               let lastRevealIndex,
               event.anchorTime - lastRevealAnchorTime < revealComboMinimumSpacing {
                let currentPriority = revealPriority(event.caption.text)
                let existingPriority = revealPriority(coalesced[lastRevealIndex].caption.text)
                if currentPriority > existingPriority {
                    coalesced[lastRevealIndex] = event
                    lastRevealAnchorTime = event.anchorTime
                }
                continue
            }

            if event.kind == .cta,
               let lastCTAIndex,
               event.anchorTime - lastCTAAnchorTime < 4.0 {
                if ctaPriority(event.caption.text) >= ctaPriority(coalesced[lastCTAIndex].caption.text) {
                    coalesced[lastCTAIndex] = event
                    lastCTAAnchorTime = event.anchorTime
                }
                continue
            }

            coalesced.append(event)
            if event.kind == .hook {
                lastHookIndex = coalesced.count - 1
                lastHookAnchorTime = event.anchorTime
            }
            if event.kind == EventKind.reveal {
                lastRevealIndex = coalesced.count - 1
                lastRevealAnchorTime = event.anchorTime
            }
            if event.kind == .cta {
                lastCTAIndex = coalesced.count - 1
                lastCTAAnchorTime = event.anchorTime
            }
        }

        return coalesced
    }

    private static func prunedSemanticEvents(
        _ events: [TimelineEvent],
        totalDuration: Double
    ) -> [TimelineEvent] {
        let spaced = events
            .sorted { $0.anchorTime < $1.anchorTime }
            .reduce(into: [TimelineEvent]()) { kept, event in
                if let conflictIndex = kept.lastIndex(where: { keptEvent in
                    abs(keptEvent.anchorTime - event.anchorTime) < minimumDecisionGap
                }) {
                    let keptEvent = kept[conflictIndex]
                    if isOrderedUIRevealPair(keptEvent, event),
                       event.anchorTime - keptEvent.anchorTime >= 0.65,
                       sameSpokenWindow(keptEvent, event),
                       !hasDelayedUIRevealBridge(keptEvent.caption.text) {
                        kept.append(event)
                        return
                    }
                    if eventScore(event) > eventScore(kept[conflictIndex]) {
                        kept[conflictIndex] = event
                    }
                    return
                }
                kept.append(event)
            }

        let singleIntent = resolveSameSpokenWindowEventConflicts(spaced)
        let kindBudgeted = enforceKindBudgets(singleIntent, totalDuration: totalDuration)
        let storyBudgeted = suppressSupportEventsForCompleteShortDemo(kindBudgeted, totalDuration: totalDuration)
        let limit = semanticEventLimit(for: totalDuration)
        guard storyBudgeted.count > limit else { return storyBudgeted }

        let selected = storyBudgeted
            .sorted { lhs, rhs in
                let lhsScore = eventScore(lhs)
                let rhsScore = eventScore(rhs)
                if lhsScore != rhsScore { return lhsScore > rhsScore }
                return lhs.anchorTime < rhs.anchorTime
            }
            .prefix(limit)

        return selected.sorted { $0.anchorTime < $1.anchorTime }
    }

    private static func resolveSameSpokenWindowEventConflicts(_ events: [TimelineEvent]) -> [TimelineEvent] {
        var resolved: [TimelineEvent] = []
        var consumed = Set<Int>()

        for index in events.indices {
            guard !consumed.contains(index) else { continue }

            let groupIndices = events.indices.filter { candidateIndex in
                !consumed.contains(candidateIndex)
                    && sameSpokenWindow(events[index], events[candidateIndex])
            }
            consumed.formUnion(groupIndices)

            let group = groupIndices.map { events[$0] }
            resolved.append(contentsOf: preferredEventsForSingleSpokenWindow(group))
        }

        return resolved.sorted { $0.anchorTime < $1.anchorTime }
    }

    private static func preferredEventsForSingleSpokenWindow(_ events: [TimelineEvent]) -> [TimelineEvent] {
        guard events.count > 1 else { return events }

        if let uiRevealPair = preferredUIRevealPair(in: events) {
            return uiRevealPair.sorted { $0.anchorTime < $1.anchorTime }
        }

        guard let strongest = events.sorted(by: dominantEventSort).first else {
            return []
        }
        return [strongest]
    }

    private static func preferredUIRevealPair(in events: [TimelineEvent]) -> [TimelineEvent]? {
        let uiActions = events.filter { $0.kind == .uiAction }
        let reveals = events.filter { $0.kind == .reveal }

        var bestPair: (ui: TimelineEvent, reveal: TimelineEvent, score: Int)?
        for ui in uiActions {
            for reveal in reveals {
                let gap = reveal.anchorTime - ui.anchorTime
                guard gap >= 0.65, gap <= uiRevealCouplingWindow else { continue }
                guard !hasDelayedUIRevealBridge(ui.caption.text) else { continue }
                let score = eventScore(ui) + eventScore(reveal)
                if bestPair == nil || score > bestPair!.score {
                    bestPair = (ui, reveal, score)
                }
            }
        }

        guard let bestPair else { return nil }
        return [bestPair.ui, bestPair.reveal]
    }

    private static func isOrderedUIRevealPair(_ lhs: TimelineEvent, _ rhs: TimelineEvent) -> Bool {
        lhs.kind == .uiAction
            && rhs.kind == .reveal
            && rhs.anchorTime > lhs.anchorTime
            && rhs.anchorTime - lhs.anchorTime <= uiRevealCouplingWindow
    }

    private static func dominantEventSort(_ lhs: TimelineEvent, _ rhs: TimelineEvent) -> Bool {
        let lhsScore = eventScore(lhs)
        let rhsScore = eventScore(rhs)
        if lhsScore != rhsScore { return lhsScore > rhsScore }

        let lhsPriority = dominantIntentPriority(lhs.kind)
        let rhsPriority = dominantIntentPriority(rhs.kind)
        if lhsPriority != rhsPriority { return lhsPriority > rhsPriority }

        return lhs.anchorTime < rhs.anchorTime
    }

    private static func dominantIntentPriority(_ kind: EventKind) -> Int {
        switch kind {
        case .hook: return 100
        case .cta: return 96
        case .reveal: return 92
        case .warning: return 86
        case .uiAction: return 82
        case .topicShift: return 58
        case .keyword: return 42
        }
    }

    private static func semanticEventLimit(for duration: Double) -> Int {
        if duration <= 12 { return 3 }
        if duration <= 40 { return 5 }
        return min(10, max(6, Int(ceil(duration / 9.0))))
    }

    private static func enforceKindBudgets(_ events: [TimelineEvent], totalDuration: Double) -> [TimelineEvent] {
        let maxRevealCount = totalDuration <= 40 ? 1 : min(3, max(1, Int(ceil(totalDuration / 35.0))))
        let maxUICount = totalDuration <= 40 ? 1 : min(3, max(1, Int(ceil(totalDuration / 35.0))))
        let maxWarningCount = totalDuration <= 60 ? 1 : 2
        let maxTopicShiftCount = totalDuration <= 40 ? 1 : min(3, max(1, Int(ceil(totalDuration / 35.0))))
        let maxKeywordCount = totalDuration <= 40 ? 1 : min(3, max(1, Int(ceil(totalDuration / 45.0))))

        var budgeted = capped(events, kind: .hook, maxCount: 1)
        budgeted = capped(budgeted, kind: .cta, maxCount: 1)
        budgeted = capped(budgeted, kind: .reveal, maxCount: maxRevealCount)
        budgeted = capped(budgeted, kind: .uiAction, maxCount: maxUICount)
        budgeted = capped(budgeted, kind: .warning, maxCount: maxWarningCount)
        budgeted = capped(budgeted, kind: .topicShift, maxCount: maxTopicShiftCount)
        budgeted = capped(budgeted, kind: .keyword, maxCount: maxKeywordCount)
        return budgeted
    }

    private static func suppressSupportEventsForCompleteShortDemo(
        _ events: [TimelineEvent],
        totalDuration: Double
    ) -> [TimelineEvent] {
        guard totalDuration <= 40,
              events.contains(where: { $0.kind == .hook }),
              events.contains(where: { $0.kind == .reveal }),
              events.contains(where: { $0.kind == .cta }),
              events.contains(where: { $0.kind == .uiAction && isUIActionCoupledToReveal($0, events: events) }) else {
            return events
        }

        return events.filter { event in
            switch event.kind {
            case .warning, .topicShift, .keyword:
                false
            case .hook, .reveal, .uiAction, .cta:
                true
            }
        }
    }

    private static func capped(_ events: [TimelineEvent], kind: EventKind, maxCount: Int) -> [TimelineEvent] {
        let matching = events.filter { $0.kind == kind }
        guard matching.count > maxCount else { return events }
        let keepAnchors = Set(
            matching
                .sorted { lhs, rhs in
                    let lhsScore = eventScore(lhs)
                    let rhsScore = eventScore(rhs)
                    if lhsScore != rhsScore { return lhsScore > rhsScore }
                    return lhs.anchorTime > rhs.anchorTime
                }
                .prefix(maxCount)
                .map(\.anchorTime)
        )
        return events.filter { event in
            event.kind != kind || keepAnchors.contains(event.anchorTime)
        }
    }

    private static func eventScore(_ event: TimelineEvent) -> Int {
        let confidenceBonus = Int((event.confidence * 10).rounded())
        switch event.kind {
        case .hook:
            return 120 + confidenceBonus
        case .cta:
            return 104 + ctaPriority(event.caption.text) * 3 + confidenceBonus
        case .reveal:
            return 88 + revealPriority(event.caption.text) * 4 + confidenceBonus
        case .uiAction:
            return 82 + (hasDirectUIAction(event.caption.text) ? 8 : 0) + confidenceBonus
        case .warning:
            return 70 + (isStrongWarning(event.caption.text) ? 10 : 0) + confidenceBonus
        case .topicShift:
            return 56 + confidenceBonus
        case .keyword:
            return 42 + keywordImportance(event.caption.text) * 5 + confidenceBonus
        }
    }

    private static func supplementalCaptionEvents(
        from captions: [CaptionSegment],
        plannedEvents: [TimelineEvent],
        totalDuration: Double
    ) -> [TimelineEvent] {
        let captionEvents = buildEvents(
            from: captions.sorted { $0.startTime < $1.startTime },
            totalDuration: totalDuration
        )

        return captionEvents.filter { candidate in
            guard candidate.kind == .reveal
                || candidate.kind == .uiAction
                || candidate.kind == .topicShift
                || candidate.kind == .warning else {
                return false
            }

            if candidate.kind == .topicShift,
               plannedEvents.contains(where: { planned in
                   isPrimarySemanticEvent(planned.kind)
                       && abs(planned.anchorTime - candidate.anchorTime) < 1.8
               }) {
                return false
            }

            if candidate.kind == .reveal,
               plannedEvents.contains(where: { planned in
                   planned.kind == .reveal
                       && abs(planned.anchorTime - candidate.anchorTime) < revealComboMinimumSpacing
               }) {
                return false
            }

            return !plannedEvents.contains { planned in
                planned.kind == candidate.kind
                    && abs(planned.anchorTime - candidate.anchorTime) < 0.80
            }
        }
    }

    private static func isPrimarySemanticEvent(_ kind: EventKind) -> Bool {
        switch kind {
        case .hook, .reveal, .uiAction, .warning, .cta:
            true
        case .topicShift, .keyword:
            false
        }
    }

    private static func buildEvents(
        from captions: [CaptionSegment],
        totalDuration: Double
    ) -> [TimelineEvent] {
        var events: [TimelineEvent] = []
        var lastNoticeableEventTime: Double = -10
        var lastHookAnchorTime: Double = -10
        var lastKeywordTime: Double = -10
        var lastTopicShiftTime: Double = -10
        var lastRevealAnchorTime: Double = -10
        var lastRevealIndex: Int?
        var lastCTAAnchorTime: Double = -10
        var lastCTAIndex: Int?
        var revealCount = 0
        let maxRevealCount = max(1, Int(ceil(totalDuration / 30.0)) * 2)

        for (index, caption) in captions.enumerated() {
            guard let kind = classify(caption, index: index, totalCount: captions.count) else {
                continue
            }
            let anchor = anchorTime(for: kind, caption: caption)

            switch kind {
            case .hook:
                guard anchor - lastHookAnchorTime >= 3.0 else { continue }
                events.append(TimelineEvent(kind: kind, caption: caption, anchorTime: anchor))
                lastHookAnchorTime = anchor
                lastNoticeableEventTime = caption.startTime
            case .cta:
                if let lastCTAIndex,
                   anchor - lastCTAAnchorTime < 4.0 {
                    if ctaPriority(caption.text) >= ctaPriority(events[lastCTAIndex].caption.text) {
                        events[lastCTAIndex] = TimelineEvent(kind: kind, caption: caption, anchorTime: anchor)
                        lastCTAAnchorTime = anchor
                        lastNoticeableEventTime = caption.startTime
                    }
                    continue
                }
                guard caption.startTime - lastNoticeableEventTime >= 1.2 else { continue }
                events.append(TimelineEvent(kind: kind, caption: caption, anchorTime: anchor))
                lastCTAIndex = events.count - 1
                lastCTAAnchorTime = anchor
                lastNoticeableEventTime = caption.startTime
            case .reveal:
                if let lastRevealIndex,
                   anchor - lastRevealAnchorTime < revealComboMinimumSpacing {
                    let currentPriority = revealPriority(caption.text)
                    let existingPriority = revealPriority(events[lastRevealIndex].caption.text)
                    if currentPriority > existingPriority {
                        events[lastRevealIndex] = TimelineEvent(kind: kind, caption: caption, anchorTime: anchor)
                        lastRevealAnchorTime = anchor
                        lastNoticeableEventTime = caption.startTime
                    }
                    continue
                }

                guard revealCount < maxRevealCount,
                      caption.startTime - lastNoticeableEventTime >= 2.8,
                      anchor - lastRevealAnchorTime >= revealComboMinimumSpacing else { continue }
                events.append(TimelineEvent(kind: kind, caption: caption, anchorTime: anchor))
                lastRevealIndex = events.count - 1
                revealCount += 1
                lastRevealAnchorTime = anchor
                lastNoticeableEventTime = caption.startTime
            case .topicShift:
                guard caption.startTime - lastTopicShiftTime >= 4.0,
                      caption.startTime - lastNoticeableEventTime >= 2.0 else { continue }
                events.append(TimelineEvent(kind: kind, caption: caption, anchorTime: anchor))
                lastTopicShiftTime = caption.startTime
                lastNoticeableEventTime = caption.startTime
            case .uiAction:
                guard caption.startTime - lastNoticeableEventTime >= 2.3 else { continue }
                events.append(TimelineEvent(kind: kind, caption: caption, anchorTime: anchor))
                lastNoticeableEventTime = caption.startTime
            case .warning:
                guard caption.startTime - lastNoticeableEventTime >= 2.0 else { continue }
                events.append(TimelineEvent(kind: kind, caption: caption, anchorTime: anchor))
                lastNoticeableEventTime = caption.startTime
            case .keyword:
                guard caption.startTime - lastKeywordTime >= 2.5,
                      caption.startTime - lastNoticeableEventTime >= 1.6 else { continue }
                events.append(TimelineEvent(kind: kind, caption: caption, anchorTime: anchor))
                lastKeywordTime = caption.startTime
                lastNoticeableEventTime = caption.startTime
            }
        }

        return events
    }

    private static func classify(
        _ caption: CaptionSegment,
        index: Int,
        totalCount: Int
    ) -> EventKind? {
        switch caption.sceneBehavior {
        case .hookImpact:
            if isOpeningHookCandidate(caption, index: index) { return .hook }
        case .punchIn:
            if isMeaningfulReveal(caption.text) { return .reveal }
        case .transitionWhoosh:
            if startsTopicShift(caption.text) { return .topicShift }
        case .focusBlur:
            if canPromoteCaptionToUIAction(caption),
               hasDirectUIAction(caption.text) {
                return .uiAction
            }
        case .keywordLockOn:
            if caption.role == .warning || isStrongWarning(caption.text) {
                return .warning
            }
            return keywordImportance(caption.text) >= 2 ? .keyword : nil
        case .conclusionHold:
            return containsCTAPhrase(in: caption.text) ? .cta : nil
        case .underlineReveal:
            return caption.role == .warning || isStrongWarning(caption.text) ? .warning : nil
        case .subtleZoom, .none:
            break
        }

        if isOpeningHookCandidate(caption, index: index) { return .hook }
        let isClosingSection = index >= max(1, Int(Double(totalCount) * 0.72))
        if containsCTAPhrase(in: caption.text)
            && (caption.role == .conclusion || isClosingSection) {
            return .cta
        }
        if isMeaningfulReveal(caption.text) {
            return .reveal
        }
        if caption.role == .warning || isStrongWarning(caption.text) {
            return .warning
        }
        if caption.role == .transition || startsTopicShift(caption.text) {
            return .topicShift
        }
        if hasDirectUIAction(caption.text) {
            return .uiAction
        }
        if caption.role == .keyword || keywordImportance(caption.text) >= 3 {
            return .keyword
        }
        return nil
    }

    private static func canPromoteCaptionToUIAction(_ caption: CaptionSegment) -> Bool {
        guard caption.role != .warning,
              !isStrongWarning(caption.text) else {
            return false
        }

        switch caption.role {
        case .regular, .transition, .keyword:
            return true
        case .hook, .warning, .reveal, .conclusion:
            return false
        }
    }

    private static func isOpeningHookCandidate(_ caption: CaptionSegment, index: Int) -> Bool {
        (caption.role == .hook || (index == 0 && caption.startTime < 2.5))
            && isHookWorthy(caption.text)
    }

    private static func decisions(for event: TimelineEvent, events: [TimelineEvent]) -> [EditDecision] {
        switch event.kind {
        case .hook:
            var decisions = [
                hookSlowPushIn(for: event),
                hookSentenceBackZoom(for: event),
                sfx(event.anchorTime, duration: 0.16, intensity: 0.38, reason: Cue.hookKeywordImpactSFX.reason)
            ]
            if shouldUseHookLeadIn(for: event) {
                decisions.insert(
                    sfx(event.anchorTime - 0.70, duration: 0.70, intensity: 0.22, reason: Cue.hookShortRiser.reason),
                    at: 0
                )
            }
            return decisions
        case .topicShift:
            var decisions = [
                cutTransition(event.anchorTime - 0.02, duration: 0.16, intensity: 0.22, reason: Cue.topicShiftMotionBlurCut.reason)
            ]
            if shouldUseTopicShiftWhoosh(for: event) {
                decisions.insert(
                    sfx(event.anchorTime - 0.12, duration: 0.20, intensity: 0.24, reason: Cue.topicShiftWhoosh.reason),
                    at: 0
                )
            }
            return decisions
        case .reveal:
            let zoomDuration = 0.72
            var decisions = [
                zoom(event.anchorTime - zoomDuration * 0.34, duration: zoomDuration, intensity: 0.26, reason: Cue.techRevealZoom.reason),
                sfx(event.anchorTime, duration: 0.16, intensity: 0.40, reason: Cue.techRevealImpactSFX.reason)
            ]
            if shouldUseRevealLeadIn(for: event, events: events) {
                decisions.insert(
                    sfx(event.anchorTime - 0.60, duration: 0.55, intensity: 0.18, reason: Cue.techRevealRiser.reason),
                    at: 0
                )
            }
            return decisions
        case .uiAction:
            if isUIActionCoupledToReveal(event, events: events) {
                return [
                    colorShift(event.anchorTime, duration: 0.28, intensity: 0.12, reason: Cue.techUIHighlightPulse.reason)
                ]
            }
            let zoomDuration = 0.76
            var decisions = [
                zoom(event.anchorTime - zoomDuration * 0.50, duration: zoomDuration, intensity: 0.24, reason: Cue.techUIFocusZoom.reason),
                colorShift(event.anchorTime, duration: 0.34, intensity: 0.14, reason: Cue.techUIHighlightPulse.reason)
            ]
            if hasDiscreteUIAction(event.caption.text) {
                decisions.append(sfx(event.anchorTime + 0.04, duration: 0.12, intensity: 0.28, reason: Cue.techUIClickSFX.reason))
            }
            return decisions
        case .keyword:
            guard keywordImportance(event.caption.text) >= 2 else { return [] }
            let zoomDuration = 0.64
            return [
                zoom(event.anchorTime - zoomDuration * 0.50, duration: zoomDuration, intensity: 0.16, reason: Cue.techKeywordControlledZoom.reason)
            ]
        case .warning:
            return [
                colorShift(event.anchorTime - 0.02, duration: 0.30, intensity: 0.16, reason: Cue.techWarningAmberAccent.reason)
            ]
        case .cta:
            let pushDuration = clampedSpokenDuration(for: event, minimum: 1.20, maximum: 2.40)
            let pushStart = max(event.caption.startTime, event.anchorTime - pushDuration)
            return [
                zoom(
                    pushStart,
                    duration: pushDuration,
                    intensity: 0.18,
                    reason: Cue.ctaSlowPush.reason
                ),
                sfx(event.anchorTime, duration: 0.14, intensity: 0.28, reason: Cue.ctaNotificationPing.reason)
            ]
        }
    }

    private static func clampedSpokenDuration(
        for event: TimelineEvent,
        minimum: Double,
        maximum: Double
    ) -> Double {
        let duration = event.caption.endTime - event.caption.startTime
        guard duration.isFinite, duration > 0 else { return minimum }
        return min(max(duration, minimum), maximum)
    }

    private static func enforceZoomSpacing(_ decisions: [EditDecision]) -> [EditDecision] {
        var kept: [EditDecision] = []
        for decision in decisions.sorted(by: { $0.time < $1.time }) {
            guard decision.type == .zoom else {
                kept.append(decision)
                continue
            }

            if let conflictIndex = kept.lastIndex(where: { keptDecision in
                keptDecision.type == .zoom && zoomsConflict(keptDecision, decision)
            }) {
                if isAllowedHookZoomPair(kept[conflictIndex], decision) {
                    kept.append(decision)
                    continue
                }
                if isProtectedAfterHookZoomPair(kept: kept, conflictIndex: conflictIndex, nextZoom: decision) {
                    kept.append(decision)
                    continue
                }
                guard zoomPriority(decision) > zoomPriority(kept[conflictIndex]) else { continue }
                kept.remove(at: conflictIndex)
            }
            kept.append(decision)
        }
        return kept.sorted { $0.time < $1.time }
    }

    private static func isAllowedHookZoomPair(_ first: EditDecision, _ second: EditDecision) -> Bool {
        let reasons = Set([first.reason, second.reason])
        return first.type == .zoom
            && second.type == .zoom
            && reasons == [Cue.hookSlowPushInZoom.reason, Cue.hookSentenceBackZoom.reason]
    }

    private static func isProtectedAfterHookZoomPair(
        kept: [EditDecision],
        conflictIndex: Int,
        nextZoom: EditDecision
    ) -> Bool {
        let conflict = kept[conflictIndex]
        guard conflict.reason == Cue.hookSentenceBackZoom.reason,
              kept[..<conflictIndex].contains(where: { isAllowedHookZoomPair($0, conflict) }) else {
            return false
        }

        return nextZoom.time - (conflict.time + conflict.duration) >= 0.90
    }

    private static func zoomsConflict(_ lhs: EditDecision, _ rhs: EditDecision) -> Bool {
        let lhsEnd = lhs.time + max(0, lhs.duration)
        let rhsEnd = rhs.time + max(0, rhs.duration)
        let overlap = min(lhsEnd, rhsEnd) - max(lhs.time, rhs.time)
        if overlap > 0 { return true }
        let visualGap = max(rhs.time, lhs.time) - min(lhsEnd, rhsEnd)
        return visualGap < 0.85
    }

    private static func finalizedDecisions(_ decisions: [EditDecision], totalDuration: Double) -> [EditDecision] {
        let spaced = enforceZoomSpacing(decisions)
        let coherent = removeOrphanedDependentCues(spaced)
        let sfxBudgeted = enforceSFXBudget(coherent, totalDuration: totalDuration)
        let decisionBudgeted = enforceDecisionBudget(sfxBudgeted, totalDuration: totalDuration)
        return removeOrphanedDependentCues(decisionBudgeted)
    }

    private static func enforceDecisionBudget(_ decisions: [EditDecision], totalDuration: Double) -> [EditDecision] {
        let limit = decisionLimit(for: totalDuration)
        var kept = decisions.sorted { $0.time < $1.time }

        while kept.count > limit {
            guard let dropIndex = kept
                .enumerated()
                .min(by: { lhs, rhs in
                    let lhsPriority = decisionKeepPriority(lhs.element)
                    let rhsPriority = decisionKeepPriority(rhs.element)
                    if lhsPriority != rhsPriority { return lhsPriority < rhsPriority }
                    return lhs.element.time < rhs.element.time
                })?
                .offset,
                decisionKeepPriority(kept[dropIndex]) < 80 else {
                break
            }
            kept.remove(at: dropIndex)
            kept = removeOrphanedDependentCues(kept).sorted { $0.time < $1.time }
        }

        return kept.sorted { $0.time < $1.time }
    }

    private static func decisionLimit(for duration: Double) -> Int {
        if duration <= 12 { return 7 }
        if duration <= 40 { return 9 }
        return min(18, max(11, Int(ceil(duration / 5.5))))
    }

    private static func decisionKeepPriority(_ decision: EditDecision) -> Int {
        guard let cue = TechInfluencerEffectCue(reason: decision.reason) else { return 0 }
        switch cue {
        case .techKeywordClickSFX,
             .techWarningLowImpactSFX,
             .ctaMusicLiftRiser,
             .techRevealWhoosh,
             .topicShiftSoftImpactSFX:
            return 10
        case .techRevealRiser,
             .topicShiftWhoosh:
            return 20
        case .techUIClickSFX:
            return 35
        case .techKeywordControlledZoom:
            return 45
        case .topicShiftMotionBlurCut:
            return 62
        case .techWarningAmberAccent:
            return 70
        case .hookShortRiser:
            return 74
        case .techUIFocusZoom,
             .techUIHighlightPulse:
            return 84
        case .ctaSlowPush,
             .ctaNotificationPing:
            return 88
        case .techRevealZoom,
             .techRevealImpactSFX:
            return 92
        case .hookSlowPushInZoom,
             .hookSentenceBackZoom,
             .hookKeywordImpactSFX,
             .legacyHookSlowPushBackZoom:
            return 96
        }
    }

    private static func enforceSFXBudget(_ decisions: [EditDecision], totalDuration: Double) -> [EditDecision] {
        let limit = sfxLimit(for: totalDuration)
        var kept = decisions.sorted { $0.time < $1.time }

        while kept.filter({ $0.type == .sfx }).count > limit {
            guard let optionalIndex = kept
                .enumerated()
                .filter({ isOptionalSFX($0.element) })
                .min(by: { lhs, rhs in
                    let lhsPriority = sfxKeepPriority(lhs.element)
                    let rhsPriority = sfxKeepPriority(rhs.element)
                    if lhsPriority != rhsPriority { return lhsPriority < rhsPriority }
                    return lhs.element.time < rhs.element.time
                })?
                .offset else { break }
            kept.remove(at: optionalIndex)
        }

        while kept.filter({ $0.type == .sfx }).count > limit {
            guard let lowestValueIndex = kept
                .enumerated()
                .filter({ $0.element.type == .sfx })
                .min(by: { lhs, rhs in
                    sfxKeepPriority(lhs.element) < sfxKeepPriority(rhs.element)
                })?
                .offset else { break }
            kept.remove(at: lowestValueIndex)
        }

        return kept.sorted { $0.time < $1.time }
    }

    private static func sfxLimit(for duration: Double) -> Int {
        if duration <= 12 { return 3 }
        if duration <= 40 { return 5 }
        return min(12, max(6, Int(ceil(duration / 7.5))))
    }

    private static func isOptionalSFX(_ decision: EditDecision) -> Bool {
        decision.type == .sfx && TechInfluencerEffectCue(reason: decision.reason)?.isOptionalSFX == true
    }

    private static func sfxKeepPriority(_ decision: EditDecision) -> Int {
        guard let cue = TechInfluencerEffectCue(reason: decision.reason) else { return 0 }
        switch cue {
        case .hookKeywordImpactSFX:
            return 100
        case .hookShortRiser:
            return 92
        case .techRevealImpactSFX:
            return 88
        case .ctaNotificationPing:
            return 82
        case .techUIClickSFX:
            return 78
        case .topicShiftWhoosh:
            return 62
        case .topicShiftSoftImpactSFX:
            return 42
        case .techRevealRiser,
             .techRevealWhoosh,
             .techWarningLowImpactSFX,
             .ctaMusicLiftRiser,
             .techKeywordClickSFX:
            return 25
        case .hookSlowPushInZoom,
             .hookSentenceBackZoom,
             .legacyHookSlowPushBackZoom,
             .topicShiftMotionBlurCut,
             .techRevealZoom,
             .techUIFocusZoom,
             .techUIHighlightPulse,
             .techKeywordControlledZoom,
             .techWarningAmberAccent,
             .ctaSlowPush:
            return 0
        }
    }

    private static func removeOrphanedDependentCues(_ decisions: [EditDecision]) -> [EditDecision] {
        decisions.filter { decision in
            guard let cue = TechInfluencerEffectCue(reason: decision.reason) else { return true }
            switch cue {
            case .techUIHighlightPulse,
                 .techUIClickSFX:
                if cue == .techUIHighlightPulse,
                   isUIHighlightLeadingRevealCombo(decision, in: decisions) {
                    return true
                }
                return hasCompanionCue(.techUIFocusZoom, for: decision, childCue: cue, in: decisions)
            case .techRevealRiser,
                 .techRevealWhoosh,
                 .techRevealImpactSFX:
                return hasCompanionCue(.techRevealZoom, for: decision, childCue: cue, in: decisions)
            case .ctaNotificationPing:
                return hasCompanionCue(.ctaSlowPush, for: decision, childCue: cue, in: decisions)
            case .hookShortRiser,
                 .hookKeywordImpactSFX:
                return hasNearbyHookZoom(for: decision, in: decisions)
            case .topicShiftWhoosh:
                return hasCompanionCue(.topicShiftMotionBlurCut, for: decision, childCue: cue, in: decisions)
            case .topicShiftSoftImpactSFX:
                return hasCompanionCue(.topicShiftMotionBlurCut, for: decision, childCue: cue, in: decisions)
            case .techKeywordClickSFX:
                return hasCompanionCue(.techKeywordControlledZoom, for: decision, childCue: cue, in: decisions)
            case .techWarningLowImpactSFX:
                return hasCompanionCue(.techWarningAmberAccent, for: decision, childCue: cue, in: decisions)
            case .ctaMusicLiftRiser:
                return hasCompanionCue(.ctaSlowPush, for: decision, childCue: cue, in: decisions)
            case .hookSlowPushInZoom,
                 .hookSentenceBackZoom,
                 .legacyHookSlowPushBackZoom,
                 .topicShiftMotionBlurCut,
                 .techRevealZoom,
                 .techUIFocusZoom,
                 .techKeywordControlledZoom,
                 .techWarningAmberAccent,
                 .ctaSlowPush:
                return true
            }
        }
    }

    private static func isUIActionCoupledToReveal(_ event: TimelineEvent, events: [TimelineEvent]) -> Bool {
        guard event.kind == .uiAction else { return false }
        return events.contains { candidate in
            guard candidate.kind == .reveal else { return false }
            let anchorGap = candidate.anchorTime - event.anchorTime
            guard anchorGap >= 0, anchorGap <= uiRevealCouplingWindow else { return false }
            guard !sameSpokenWindow(event, candidate) || !hasDelayedUIRevealBridge(event.caption.text) else { return false }
            return sameSpokenWindow(event, candidate)
                || candidate.caption.startTime - event.caption.endTime <= 0.35
                || event.caption.endTime - event.caption.startTime >= anchorGap
        }
    }

    private static func sameSpokenWindow(_ lhs: TimelineEvent, _ rhs: TimelineEvent) -> Bool {
        abs(lhs.caption.startTime - rhs.caption.startTime) < 0.05
            && abs(lhs.caption.endTime - rhs.caption.endTime) < 0.05
    }

    private static func isUIHighlightLeadingRevealCombo(
        _ decision: EditDecision,
        in decisions: [EditDecision]
    ) -> Bool {
        guard decision.reason == Cue.techUIHighlightPulse.reason else { return false }
        return decisions.contains { impact in
            guard impact.reason == Cue.techRevealImpactSFX.reason else { return false }
            let gap = impact.time - decision.time
            guard gap >= 0.20, gap <= uiRevealCouplingWindow else { return false }
            return decisions.contains { revealZoom in
                revealZoom.reason == Cue.techRevealZoom.reason
                    && abs(revealZoom.time - (impact.time + (Cue.techRevealZoom.revealComboAnchorOffset ?? 0))) <= 0.75
            }
        }
    }

    private static func hasCompanionCue(
        _ companionCue: TechInfluencerEffectCue,
        for decision: EditDecision,
        childCue: TechInfluencerEffectCue,
        in decisions: [EditDecision]
    ) -> Bool {
        guard let anchor = inferredAnchorTime(for: decision, cue: childCue) else { return true }
        return decisions.contains { candidate in
            guard candidate.reason == companionCue.reason else { return false }
            return cue(companionCue, at: candidate.time, matchesAnchor: anchor)
        }
    }

    private static func inferredAnchorTime(for decision: EditDecision, cue: TechInfluencerEffectCue) -> Double? {
        switch cue.routeMode {
        case .anchor(let offset, _):
            return decision.time - offset
        case .start:
            return nil
        }
    }

    private static func cue(
        _ cue: TechInfluencerEffectCue,
        at time: Double,
        matchesAnchor anchor: Double
    ) -> Bool {
        switch cue.routeMode {
        case .anchor(let offset, let tolerance):
            return abs(time - (anchor + offset)) <= tolerance
        case .start:
            return abs(time - anchor) <= 0.80
        }
    }

    private static func hasNearbyHookZoom(for decision: EditDecision, in decisions: [EditDecision]) -> Bool {
        decisions.contains { candidate in
            candidate.type == .zoom
                && (candidate.reason == Cue.hookSlowPushInZoom.reason || candidate.reason == Cue.hookSentenceBackZoom.reason)
                && abs(candidate.time - decision.time) <= 1.60
        }
    }


    private static func zoomPriority(_ decision: EditDecision) -> Int {
        if let cue = TechInfluencerEffectCue(reason: decision.reason) {
            switch cue.eventKind {
            case .reveal: return 95
            case .uiAction: return 90
            case .hook: return 85
            case .cta: return 80
            case .keyword: return 70
            case .topicShift, .warning: return 60
            }
        }

        let reason = decision.reason.lowercased()
        if reason.contains("reveal") { return 95 }
        if reason.contains("ui") { return 90 }
        if reason.contains("hook") { return 85 }
        if reason.contains("cta") { return 80 }
        if reason.contains("keyword") { return 70 }
        return 50
    }

    private static func hookSlowPushIn(for event: TimelineEvent) -> EditDecision {
        let split = hookZoomSplitTime(for: event.caption)
        return zoom(
            event.caption.startTime,
            duration: max(0.36, split - event.caption.startTime),
            intensity: 0.18,
            reason: Cue.hookSlowPushInZoom.reason
        )
    }

    private static func hookSentenceBackZoom(for event: TimelineEvent) -> EditDecision {
        let split = hookZoomSplitTime(for: event.caption)
        let remaining = max(0.36, event.caption.endTime - split)
        return zoom(
            split,
            duration: min(remaining, 1.20),
            intensity: 0.18,
            reason: Cue.hookSentenceBackZoom.reason
        )
    }

    private static func hookZoomSplitTime(for caption: CaptionSegment) -> Double {
        let start = caption.startTime
        let end = max(caption.endTime, start + 0.01)
        let fallback = start + (end - start) * 0.5
        let captionDuration = end - start
        let minimumPush = min(hookMinimumPushDuration, max(0.36, captionDuration * 0.45))
        let minimumBack = min(hookMinimumBackDuration, max(0.30, captionDuration * 0.30))
        let earliestSplit = start + minimumPush
        let latestSplit = max(earliestSplit, end - minimumBack)

        if let sentenceBoundary = caption.wordTimings.first(where: { timing in
            let wordEnd = timing.start + timing.duration
            return wordEnd >= earliestSplit
                && wordEnd <= latestSplit
                && isTerminalWord(timing.word)
        }) {
            return sentenceBoundary.start + sentenceBoundary.duration
        }

        return min(max(fallback, earliestSplit), latestSplit)
    }

    private static func isTerminalWord(_ word: String) -> Bool {
        guard let last = word.trimmingCharacters(in: .whitespacesAndNewlines).last else {
            return false
        }
        return ".!?".contains(last)
    }

    private static func anchorTime(for kind: EventKind, caption: CaptionSegment) -> Double {
        switch kind {
        case .hook:
            return preferredHookAnchorTime(in: caption)
                ?? firstWordTime(in: caption)
        case .reveal:
            return preferredRevealAnchorTime(in: caption)
                ?? firstWordTime(in: caption)
        case .uiAction:
            return matchingAnchorTime(in: caption, phrases: uiActionAnchorTriggers)
                ?? matchingAnchorTime(in: caption, phrases: techKeywordTriggers)
                ?? firstWordTime(in: caption)
        case .keyword:
            return matchingAnchorTime(in: caption, phrases: techKeywordTriggers)
                ?? firstWordTime(in: caption)
        case .warning:
            return matchingAnchorTime(in: caption, phrases: warningTriggers)
                ?? firstWordTime(in: caption)
        case .topicShift:
            return caption.startTime
        case .cta:
            if let ctaAnchor = preferredCTAAnchorTime(in: caption) {
                return ctaAnchor
            }
            if isLongCTAWindow(caption) {
                return max(caption.startTime, caption.endTime - 0.20)
            }
            return matchingAnchorTime(in: caption, phrases: ctaTriggers + techKeywordTriggers)
                ?? estimatedPhraseAnchorTime(in: caption, phrases: ctaTriggers + techKeywordTriggers)
                ?? max(caption.startTime, caption.endTime - 0.20)
        }
    }

    private static func isLongCTAWindow(_ caption: CaptionSegment) -> Bool {
        caption.endTime - caption.startTime > 5.0
    }

    private static func firstWordTime(in caption: CaptionSegment) -> Double {
        caption.wordTimings.first?.start ?? caption.startTime
    }

    private static func preferredHookAnchorTime(in caption: CaptionSegment) -> Double? {
        matchingAnchorTime(in: caption, phrases: hookPayoffAnchorTriggers)
            ?? estimatedPhraseAnchorTime(in: caption, phrases: hookPayoffAnchorTriggers)
            ?? matchingAnchorTime(in: caption, phrases: hookAnchorTriggers)
            ?? estimatedPhraseAnchorTime(in: caption, phrases: hookAnchorTriggers)
    }

    private static func zoom(
        _ time: Double,
        duration: Double,
        intensity: Float,
        reason: String
    ) -> EditDecision {
        EditDecision(time: max(0, time), duration: duration, type: .zoom, reason: reason, intensity: intensity)
    }

    private static func sfx(
        _ time: Double,
        duration: Double,
        intensity: Float,
        reason: String
    ) -> EditDecision {
        EditDecision(time: max(0.05, time), duration: duration, type: .sfx, reason: reason, intensity: intensity)
    }

    private static func colorShift(
        _ time: Double,
        duration: Double,
        intensity: Float,
        reason: String
    ) -> EditDecision {
        EditDecision(time: max(0, time), duration: duration, type: .colorShift, reason: reason, intensity: intensity)
    }

    private static func cutTransition(
        _ time: Double,
        duration: Double,
        intensity: Float,
        reason: String
    ) -> EditDecision {
        EditDecision(time: max(0, time), duration: duration, type: .cutTransition, reason: reason, intensity: intensity)
    }

    private static func matchingAnchorTime(
        in caption: CaptionSegment,
        phrases: [String]
    ) -> Double? {
        matchingAnchorTimes(in: caption, phrases: phrases).min()
    }

    private static func matchingAnchorTimes(
        in caption: CaptionSegment,
        phrases: [String]
    ) -> [Double] {
        let timings = caption.wordTimings
        guard !timings.isEmpty else { return [] }

        let timingTokens = timings.map { normalizedToken($0.word) }
        let phraseTokens = phrases
            .map { phrase in phrase.split(whereSeparator: \.isWhitespace).map { normalizedToken(String($0)) } }
            .filter { !$0.isEmpty }

        var matches: [Double] = []
        for phrase in phraseTokens {
            guard phrase.count <= timingTokens.count else { continue }

            let lastStartIndex = timingTokens.count - phrase.count
            for startIndex in 0...lastStartIndex where phraseMatches(
                phrase,
                timingTokens: timingTokens,
                at: startIndex
            ) {
                matches.append(timings[startIndex].start)
            }
        }

        return matches
    }

    private static func estimatedPhraseAnchorTime(
        in caption: CaptionSegment,
        phrases: [String]
    ) -> Double? {
        estimatedPhraseAnchorTimes(in: caption, phrases: phrases).min()
    }

    private static func estimatedPhraseAnchorTimes(
        in caption: CaptionSegment,
        phrases: [String]
    ) -> [Double] {
        let words = normalizedWords(in: caption.text)
        guard !words.isEmpty, caption.endTime > caption.startTime else { return [] }

        var matchIndexes: [Int] = []
        for phrase in phrases {
            let phraseWords = normalizedWords(in: phrase)
            guard !phraseWords.isEmpty, phraseWords.count <= words.count else { continue }

            let lastStartIndex = words.count - phraseWords.count
            for startIndex in 0...lastStartIndex where phraseWordsMatch(phraseWords, words: words, at: startIndex) {
                matchIndexes.append(startIndex)
            }
        }

        guard !matchIndexes.isEmpty else { return [] }
        let estimatedWordDuration = (caption.endTime - caption.startTime) / Double(words.count)
        return matchIndexes.map { caption.startTime + estimatedWordDuration * Double($0) }
    }

    private static func preferredCTAAnchorTime(in caption: CaptionSegment) -> Double? {
        let duration = caption.endTime - caption.startTime
        let matches = matchingAnchorTimes(in: caption, phrases: ctaTriggers)
        if let latest = matches.max() {
            return latest
        }

        guard duration <= 5.0 else { return nil }
        return estimatedPhraseAnchorTimes(in: caption, phrases: ctaTriggers).max()
    }

    private static func preferredRevealAnchorTime(in caption: CaptionSegment) -> Double? {
        if let payoff = matchingAnchorTime(in: caption, phrases: coreRevealPayoffTriggers)
            ?? estimatedPhraseAnchorTime(in: caption, phrases: coreRevealPayoffTriggers) {
            return payoff
        }
        if containsPhrase(in: caption.text, phrases: generatedCreatedRevealTriggers),
           let generatedVerb = matchingAnchorTime(in: caption, phrases: generatedCreatedRevealVerbAnchorTriggers)
            ?? estimatedPhraseAnchorTime(in: caption, phrases: generatedCreatedRevealVerbAnchorTriggers) {
            return generatedVerb
        }
        if let generated = matchingAnchorTime(in: caption, phrases: generatedCreatedRevealTriggers)
            ?? estimatedPhraseAnchorTime(in: caption, phrases: generatedCreatedRevealTriggers) {
            return generated
        }
        if isBigRevealLeadInCandidate(caption.text),
           let product = matchingAnchorTime(in: caption, phrases: productRevealAnchorTriggers)
            ?? estimatedPhraseAnchorTime(in: caption, phrases: productRevealAnchorTriggers) {
            return product
        }
        if let bigReveal = matchingAnchorTime(in: caption, phrases: bigRevealAnchorTriggers)
            ?? estimatedPhraseAnchorTime(in: caption, phrases: bigRevealAnchorTriggers) {
            return bigReveal
        }
        return matchingAnchorTime(in: caption, phrases: productRevealAnchorTriggers)
            ?? estimatedPhraseAnchorTime(in: caption, phrases: productRevealAnchorTriggers)
    }

    private static func phraseWordsMatch(
        _ phraseWords: [String],
        words: [String],
        at startIndex: Int
    ) -> Bool {
        for (offset, phraseWord) in phraseWords.enumerated() {
            let word = words[startIndex + offset]
            guard tokenMatches(word, phraseToken: phraseWord) else { return false }
        }
        return true
    }

    private static func phraseMatches(
        _ phrase: [String],
        timingTokens: [String],
        at startIndex: Int
    ) -> Bool {
        for (offset, phraseToken) in phrase.enumerated() {
            let timingToken = timingTokens[startIndex + offset]
            guard tokenMatches(timingToken, phraseToken: phraseToken) else {
                return false
            }
        }
        return true
    }

    private static func tokenMatches(_ timingToken: String, phraseToken: String) -> Bool {
        guard !timingToken.isEmpty, !phraseToken.isEmpty else { return false }
        if timingToken == phraseToken { return true }
        return phraseToken.count >= 3 && timingToken.hasPrefix(phraseToken)
    }

    private static func startsTopicShift(_ text: String) -> Bool {
        let words = normalizedWords(in: text)
        guard !words.isEmpty else { return false }
        let phrases = [
            "now",
            "next",
            "then",
            "first step",
            "second step",
            "third step",
            "şimdi",
            "sonra",
            "ilk olarak",
            "ikinci adım",
            "ucuncu adim",
            "üçüncü adım",
            "ama şimdi",
            "burada ise"
        ]
            .map { normalizedWords(in: $0) }
            .filter { !$0.isEmpty }

        return phrases.contains { phrase in
            guard phrase.count <= words.count else { return false }
            return zip(words.prefix(phrase.count), phrase).allSatisfy { pair in
                pair.0 == pair.1
            }
        }
    }

    private static func containsPhrase(in text: String, phrases: [String]) -> Bool {
        let words = normalizedWords(in: text)
        guard !words.isEmpty else { return false }
        return phrases.contains { phrase in
            let phraseWords = normalizedWords(in: phrase)
            guard !phraseWords.isEmpty, phraseWords.count <= words.count else { return false }
            return words.indices.contains { startIndex in
                let endIndex = startIndex + phraseWords.count
                guard endIndex <= words.count else { return false }
                return zip(words[startIndex..<endIndex], phraseWords).allSatisfy { pair in
                    pair.0 == pair.1 || (pair.1.count >= 4 && pair.0.hasPrefix(pair.1))
                }
            }
        }
    }

    private static func containsCTAPhrase(in text: String) -> Bool {
        let words = normalizedWords(in: text)
        guard !words.isEmpty else { return false }
        return ctaTriggers.contains { phrase in
            let phraseWords = normalizedWords(in: phrase)
            guard !phraseWords.isEmpty, phraseWords.count <= words.count else { return false }
            return words.indices.contains { startIndex in
                let endIndex = startIndex + phraseWords.count
                guard endIndex <= words.count else { return false }
                return zip(words[startIndex..<endIndex], phraseWords).allSatisfy { pair in
                    pair.0 == pair.1
                }
            }
        }
    }

    private static func revealPriority(_ text: String) -> Int {
        let lower = text.lowercased()
        var score = 0
        if containsPhrase(in: text, phrases: coreRevealPayoffTriggers)
            || containsPhrase(in: text, phrases: generatedCreatedRevealTriggers) {
            score += 8
        }
        if lower.localizedStandardContains("işte tam") || lower.localizedStandardContains("tam da bu yüzden") { score += 6 }
        if lower.localizedStandardContains("ilk vibe") { score += 5 }
        if lower.localizedStandardContains("vibe coding") { score += 4 }
        if lower.localizedStandardContains("kurdum") || lower.localizedStandardContains("kurduk") { score += 4 }
        return score
    }

    private static func ctaPriority(_ text: String) -> Int {
        let lower = text.lowercased()
        var score = 0
        if lower.localizedStandardContains("yorumlara") || lower.localizedStandardContains("comment") { score += 4 }
        if lower.localizedStandardContains("vibe") { score += 4 }
        if lower.localizedStandardContains("büyüyelim") || lower.localizedStandardContains("buyuyelim") { score += 3 }
        if lower.localizedStandardContains("follow") || lower.localizedStandardContains("save") { score += 3 }
        return score
    }

    private static func shouldUseRevealLeadIn(for event: TimelineEvent, events: [TimelineEvent]) -> Bool {
        guard event.kind == .reveal,
              event.anchorTime >= 3.0,
              isBigRevealLeadInCandidate(event.caption.text),
              eventScore(event) >= 112 else {
            return false
        }

        let revealEvents = events.filter { $0.kind == .reveal }
        guard revealEvents.count > 1 else { return true }
        let bestRevealScore = revealEvents.map(eventScore).max() ?? eventScore(event)
        return eventScore(event) >= bestRevealScore
    }

    private static func isBigRevealLeadInCandidate(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.localizedStandardContains("tam da bu yüzden")
            || lower.localizedStandardContains("işte tam")
            || lower.localizedStandardContains("türkiye'nin ilk")
            || lower.localizedStandardContains("turkiyenin ilk")
            || lower.localizedStandardContains("ilk vibe")
            || lower.localizedStandardContains("kurdum")
            || lower.localizedStandardContains("kurduk")
    }

    private static func shouldUseHookLeadIn(for event: TimelineEvent) -> Bool {
        !event.sourceReason.isEmpty
            && event.caption.startTime <= 0.40
            && event.anchorTime >= 0.85
            && containsPhrase(in: event.caption.text, phrases: strongHookTriggers)
            && eventScore(event) >= 126
    }

    private static func shouldUseTopicShiftWhoosh(for event: TimelineEvent) -> Bool {
        event.confidence >= 0.90
            && startsTopicShift(event.caption.text)
            && event.caption.text.split(separator: " ").count <= 5
    }

    private static func hasDirectUIAction(_ text: String) -> Bool {
        let words = normalizedWords(in: text)
        guard !words.isEmpty else { return false }
        guard !hasNegatedUIAction(words) else { return false }
        guard !hasMetaphoricalUIActionPhrase(text) else { return false }

        return words.indices.contains { index in
            let word = words[index]
            if isHardDiscreteUIActionWord(word) { return true }
            if isAmbiguousDiscreteUIActionWord(word)
                || isEnglishDiscreteUIActionInflection(word)
                || isTurkishProgressivePressActionWord(word)
                || isTurkishCopyPasteActionWord(word)
                || isSelectActionWord(word) {
                return hasUIActionContext(words, near: index)
                    || hasExecutableActionTarget(words, near: index)
            }
            if isOpenActionWord(word),
               !containsPhrase(in: text, phrases: ["open source"]) {
                return hasUIActionContext(words, near: index)
                    || hasOpenActionTarget(words, near: index)
            }
            if isWorkflowActionWord(word) {
                return hasWorkflowExecutionContext(words) || hasExecutionAuxiliary(words)
            }
            return false
        }
    }

    private static func hasNegatedUIAction(_ words: [String]) -> Bool {
        for index in words.indices where isUIActionCandidateWord(words[index]) {
            if isNegativeImperativeUIAction(words[index]) { return true }

            let lowerBound = max(words.startIndex, index - 3)
            let leadIn = Array(words[lowerBound..<index])
            if leadIn.contains(where: isUIActionNegator) { return true }
            if leadIn.count >= 2,
               leadIn[leadIn.count - 2] == "don",
               leadIn[leadIn.count - 1] == "t" {
                return true
            }
        }
        return false
    }

    private static func isUIActionCandidateWord(_ word: String) -> Bool {
        isDiscreteUIActionWord(word)
            || word.hasPrefix("tikla")
            || isTurkishPastPressActionWord(word)
            || isTurkishProgressivePressActionWord(word)
            || isEnglishDiscreteUIActionInflection(word)
            || isSelectActionWord(word)
            || isTurkishCopyPasteActionWord(word)
            || isOpenActionWord(word)
            || isWorkflowActionWord(word)
    }

    private static func isUIActionNegator(_ word: String) -> Bool {
        Set(["dont", "avoid", "not", "never", "sakin", "sakın", "asla", "yapma", "yapmayin", "yapmayın"]).contains(word)
    }

    private static func isNegativeImperativeUIAction(_ word: String) -> Bool {
        Set([
            "tiklama", "tiklamayin", "tiklamayın",
            "basma", "basmayin", "basmayın",
            "secme", "secmeyin", "seçme", "seçmeyin",
            "acma", "acmayin", "açma", "açmayın",
            "calistirma", "calistirmayin", "çalıştırma", "çalıştırmayın",
            "kopyalama", "yapistirma", "yapıştırma"
        ]).contains(word)
    }

    private static func hasDiscreteUIAction(_ text: String) -> Bool {
        let words = normalizedWords(in: text)
        guard !words.isEmpty else { return false }
        guard !hasNegatedUIAction(words) else { return false }
        guard !hasMetaphoricalUIActionPhrase(text) else { return false }

        return words.indices.contains { index in
            let word = words[index]
            if isHardDiscreteUIActionWord(word) { return true }
            if isAmbiguousDiscreteUIActionWord(word)
                || isEnglishClickPressInflection(word)
                || isTurkishProgressivePressActionWord(word)
                || isSelectActionWord(word) {
                return hasUIActionContext(words, near: index)
                    || hasExecutableActionTarget(words, near: index)
            }
            return false
        }
    }

    private static func hasMetaphoricalUIActionPhrase(_ text: String) -> Bool {
        containsPhrase(
            in: text,
            phrases: [
                "tap into",
                "press release", "press coverage", "press kit", "press conference", "the press",
                "select few", "select group", "selected few", "selected group",
                "ad copy", "sales copy", "copy writing", "copywriter", "copywriting",
                "click with", "click rate", "click rates", "click through rate", "click through rates",
                "copy this strategy", "copy the strategy",
                "paste ideas", "paste together",
                "tap a new market", "tap a market",
                "press on", "select a niche",
                "run rate", "generate revenue", "generate demand", "generate ideas",
                "deploy capital"
            ]
        )
    }

    private static func hasDelayedUIRevealBridge(_ text: String) -> Bool {
        containsPhrase(
            in: text,
            phrases: [
                "later", "later on", "eventually",
                "after a pause", "after the pause", "after a moment", "after a few seconds",
                "seconds later", "minutes later", "after waiting",
                "biraz sonra", "az sonra", "daha sonra", "sonrasında", "sonrasinda"
            ]
        )
    }

    private static func isOpenActionWord(_ word: String) -> Bool {
        [
            "ac", "acin", "aciyorum", "aciyoruz", "aciyor", "acalim",
            "actim", "actik", "acti", "open", "opened", "opening"
        ].contains(word)
    }

    private static func isSelectActionWord(_ word: String) -> Bool {
        [
            "sec", "sectim", "sectik", "sectin", "sectiniz", "secti",
            "seciyorum", "seciyoruz", "seciyor", "secelim",
            "selected", "selecting"
        ].contains(word)
    }

    private static func isDiscreteUIActionWord(_ word: String) -> Bool {
        isHardDiscreteUIActionWord(word) || isAmbiguousDiscreteUIActionWord(word)
    }

    private static func isHardDiscreteUIActionWord(_ word: String) -> Bool {
        Set(["click", "submit", "tikla"]).contains(word)
    }

    private static func isAmbiguousDiscreteUIActionWord(_ word: String) -> Bool {
        Set(["tap", "press", "select", "copy", "paste", "bas", "sec"]).contains(word)
    }

    private static func isTurkishPastPressActionWord(_ word: String) -> Bool {
        Set(["bastim", "bastik", "basti", "bastin", "bastiniz", "bastilar"]).contains(word)
    }

    private static func isWorkflowActionWord(_ word: String) -> Bool {
        Set(["generate", "generating", "generated", "run", "running", "deploy", "deploying", "deployed"]).contains(word)
            || word.hasPrefix("calistir")
    }

    private static func isEnglishDiscreteUIActionInflection(_ word: String) -> Bool {
        Set(["clicked", "clicking", "tapped", "tapping", "pressed", "pressing", "copied", "copying", "pasted", "pasting"]).contains(word)
    }

    private static func isEnglishClickPressInflection(_ word: String) -> Bool {
        Set(["clicked", "clicking", "tapped", "tapping", "pressed", "pressing"]).contains(word)
    }

    private static func isTurkishProgressivePressActionWord(_ word: String) -> Bool {
        word.hasPrefix("basiy")
    }

    private static func isTurkishCopyPasteActionWord(_ word: String) -> Bool {
        word.hasPrefix("kopyal") || word.hasPrefix("yapistir")
    }

    private static func hasUIActionContext(_ words: [String]) -> Bool {
        words.indices.contains { hasUIActionContext(words, near: $0) }
    }

    private static func hasUIActionContext(_ words: [String], near index: Int) -> Bool {
        let contextWords = Set([
            "button", "buton", "screen", "ekran", "cursor", "terminal", "panel", "dashboard",
            "prompt", "field", "form", "repo", "dosya",
            "option", "secenek", "menu", "dropdown", "tab", "key", "keyboard", "command", "komut", "cli"
        ])
        let lowerBound = max(words.startIndex, index - 3)
        let upperBound = min(words.endIndex, index + 4)
        return words[lowerBound..<upperBound].contains { word in
            contextWords.contains(word) || isInflectedUIContextWord(word)
        }
    }

    private static func hasExecutableActionTarget(_ words: [String], near index: Int) -> Bool {
        let targetWords = Set(["generate", "deploy", "run", "export", "render", "build", "prompt", "api", "key"])
        let lowerBound = max(words.startIndex, index - 3)
        let upperBound = min(words.endIndex, index + 4)
        return words[lowerBound..<upperBound].contains { targetWords.contains($0) || $0.hasPrefix("calistir") }
    }

    private static func hasOpenActionTarget(_ words: [String], near index: Int) -> Bool {
        let targetWords = Set(["app", "uygulama", "site", "website", "web", "page", "sayfa", "file", "dosya"])
        let lowerBound = max(words.startIndex, index - 2)
        let upperBound = min(words.endIndex, index + 3)
        return words[lowerBound..<upperBound].contains { word in
            targetWords.contains(word)
                || word.hasPrefix("uygulama")
                || word.hasPrefix("sayfa")
                || word.hasPrefix("dosya")
                || word.hasPrefix("ekran")
        }
    }

    private static func hasWorkflowExecutionContext(_ words: [String]) -> Bool {
        let contextWords = Set([
            "button", "buton", "screen", "ekran", "cursor", "terminal", "panel", "dashboard",
            "prompt", "field", "form", "repo", "dosya", "command", "komut", "cli"
        ])
        return words.indices.contains { index in
            guard isWorkflowActionWord(words[index]) else { return false }
            let lowerBound = max(words.startIndex, index - 3)
            let upperBound = min(words.endIndex, index + 4)
            return words[lowerBound..<upperBound].contains { word in
                contextWords.contains(word) || isInflectedUIContextWord(word)
            }
        }
    }

    private static func isInflectedUIContextWord(_ word: String) -> Bool {
        ["buton", "ekran", "terminal", "panel", "dashboard", "prompt", "field", "form", "repo", "dosya", "secenek", "menu", "komut"]
            .contains { word.hasPrefix($0) }
    }

    private static func hasActionLeadIn(_ words: [String]) -> Bool {
        let leadIns = Set(["now", "then", "next", "simdi", "sonra", "burada", "hadi", "let", "lets"])
        return words.contains(where: leadIns.contains)
    }

    private static func hasExecutionAuxiliary(_ words: [String]) -> Bool {
        let auxiliaries = Set(["ediyorum", "ediyoruz", "ettim", "ettik", "yapiyorum", "yapiyoruz"])
        return words.indices.contains { index in
            guard isWorkflowActionWord(words[index]) else { return false }
            let lowerBound = min(words.endIndex, index + 1)
            let upperBound = min(words.endIndex, index + 3)
            guard lowerBound < upperBound else { return false }
            return words[lowerBound..<upperBound].contains(where: auxiliaries.contains)
        }
    }

    private static func isMeaningfulReveal(_ text: String) -> Bool {
        containsPhrase(in: text, phrases: revealPayoffTriggers)
            || revealPriority(text) >= 8
    }

    private static func isStrongWarning(_ text: String) -> Bool {
        if containsPhrase(in: text, phrases: ["don't", "dont", "avoid", "stop doing", "sakın", "sakin", "asla", "yapma", "yapmayın", "yapmayin"]) {
            return true
        }
        if containsPositiveResolutionPhrase(text) {
            return false
        }
        if containsPhrase(in: text, phrases: ["wrong", "mistake", "yanlış", "yanlis"]) {
            return true
        }
        if containsPhrase(in: text, phrases: ["hata"]) {
            return !hasDirectUIAction(text)
        }
        return false
    }

    private static func containsPositiveResolutionPhrase(_ text: String) -> Bool {
        containsPhrase(
            in: text,
            phrases: ["fix", "fixes", "fixed", "solves", "solved", "works", "handling works", "çözer", "cozer", "düzeltiyor", "duzeltiyor"]
        )
    }

    private static func keywordImportance(_ text: String) -> Int {
        var score = 0
        if containsPhrase(in: text, phrases: ["vibe coding"]) { score += 4 }
        if containsPhrase(in: text, phrases: ["mvp"]) { score += 4 }
        if containsPhrase(in: text, phrases: ["app store"]) { score += 3 }
        if containsPhrase(in: text, phrases: ["yapay zeka", "ai"]) { score += 2 }
        if containsPhrase(in: text, phrases: ["web"]) { score += 2 }
        if containsPhrase(in: text, phrases: ["ürün", "urun", "product"]) { score += 2 }
        if containsPhrase(in: text, phrases: ["kod bilmeyen"]) { score += 2 }
        if containsPhrase(in: text, phrases: ["uygulama", "app"]) { score += 1 }
        if containsPhrase(in: text, phrases: ["kod", "code", "coding"]) { score += 1 }
        return min(score, 6)
    }

    private static func isHookWorthy(_ text: String) -> Bool {
        containsPhrase(in: text, phrases: strongHookTriggers)
            || (keywordImportance(text) >= 2 && containsPhrase(in: text, phrases: hookValueTriggers))
            || (keywordImportance(text) >= 3 && normalizedWords(in: text).count <= 8)
    }

    private static func normalizedWords(in text: String) -> [String] {
        text
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "tr_TR"))
            .replacingOccurrences(of: "ı", with: "i")
            .split { !$0.isLetter && !$0.isNumber }
            .map { String($0) }
            .filter { !$0.isEmpty }
    }

    private static func normalizedToken(_ token: String) -> String {
        token
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "tr_TR"))
            .replacingOccurrences(of: "ı", with: "i")
            .filter { $0.isLetter || $0.isNumber }
    }

    private static let hookAnchorTriggers = [
        "ai", "yapay zeka", "tool", "free", "faster", "minutes", "mvp", "uygulama", "app"
    ]
    private static let hookPayoffAnchorTriggers = [
        "saves hours", "builds apps", "stop doing", "most people", "did you know",
        "cok fazla", "çok fazla", "vazgeciyor", "vazgeçiyor", "buna ayar oluyorum",
        "neden", "niye", "first", "ilk", "gerekiyor", "kod bilmeyen"
    ]
    private static let strongHookTriggers = [
        "stop doing", "most people", "did you know", "nobody knows", "the truth is",
        "here's the thing", "hook", "dikkat", "cok fazla", "çok fazla", "vazgeciyor",
        "vazgeçiyor", "buna ayar oluyorum", "neden", "niye"
    ]
    private static let hookValueTriggers = [
        "saves hours", "builds apps", "faster", "minutes", "free", "para", "money",
        "first", "ilk", "need to", "gerekiyor", "kod bilmeyen"
    ]

    private static let techKeywordTriggers = [
        "ai", "yapay zeka", "artificial intelligence", "mvp", "app store", "web", "tool",
        "araç", "kod", "code", "coding", "vibe", "startup", "ürün", "urun", "product",
        "uygulama", "app", "automated", "otomatik", "launch", "build", "fix", "problem",
        "users", "money"
    ]

    private static let coreRevealPayoffTriggers = [
        "result", "results", "sonuç", "sonucu", "çıktı", "cikti", "appears"
    ]
    private static let generatedCreatedRevealTriggers = [
        "generated the app", "generated an app", "generated app",
        "generated the website", "generated a website", "generated website",
        "generated the page", "generated a page", "generated page",
        "generated the ui", "generated ui", "generated the demo", "generated demo",
        "generated the code", "generated code",
        "generated the output", "generated output",
        "generated the result", "generated result",
        "created the app", "created an app", "created app",
        "created the website", "created a website", "created website",
        "created the page", "created a page", "created page",
        "created the ui", "created ui", "created the demo", "created demo",
        "created the product", "created product",
        "created the output", "created output",
        "created the result", "created result",
        "uygulama oluşturdu", "uygulamayı oluşturdu", "app oluşturdu",
        "site oluşturdu", "siteyi oluşturdu", "sayfa oluşturdu", "sayfayı oluşturdu",
        "kod oluşturdu", "kodu oluşturdu", "sonuç oluşturdu", "sonucu oluşturdu",
        "çıktı oluşturdu", "çıktıyı oluşturdu",
        "uygulama olusturdu", "uygulamayi olusturdu", "app olusturdu",
        "site olusturdu", "siteyi olusturdu", "sayfa olusturdu", "sayfayi olusturdu",
        "kod olusturdu", "kodu olusturdu", "sonuc olusturdu", "sonucu olusturdu",
        "cikti olusturdu", "ciktiyi olusturdu",
        "uygulama olusturuldu", "app olusturuldu", "site olusturuldu",
        "sayfa olusturuldu", "kod olusturuldu", "sonuc olusturuldu", "cikti olusturuldu",
        "uygulama uretildi", "app uretildi", "site uretildi", "sayfa uretildi",
        "kod uretildi", "sonuc uretildi", "cikti uretildi"
    ]
    private static let generatedCreatedRevealVerbAnchorTriggers = [
        "olusturdu", "olusturuldu", "uretti", "uretildi"
    ]
    private static let bigRevealAnchorTriggers = [
        "tam da bu yüzden", "işte tam", "iste tam",
        "türkiye'nin ilk", "turkiyenin ilk", "ilk vibe", "kurdum", "kurduk"
    ]
    private static let productRevealAnchorTriggers = ["vibe coding"]
    private static let revealPayoffTriggers = coreRevealPayoffTriggers
        + generatedCreatedRevealTriggers
        + bigRevealAnchorTriggers
    private static let revealTriggers = revealPayoffTriggers + [
        "builds", "built", "launch", "önce sonra", "once after", "before after"
    ]

    private static let uiActionTriggers = [
        "click", "tap", "press", "open", "select", "generate", "submit", "run", "deploy",
        "copy", "paste", "cursor", "button", "screen", "ui", "tıkla", "tikla", "bas",
        "aç", "ac", "seç", "sec", "çalıştır", "calistir", "kopyala", "yapıştır", "yapistir",
        "ekran", "buton", "terminal", "panel", "dashboard"
    ]
    private static let uiActionAnchorTriggers = [
        "click", "tap", "press", "select", "generate", "submit", "run", "deploy",
        "copy", "paste", "tıkla", "tikla", "bas", "aç", "ac", "seç", "sec",
        "bastım", "bastim", "basıyorum", "basiyorum", "basıyoruz", "basiyoruz",
        "tıklıyorum", "tikliyorum", "tıkladım", "tikladim",
        "açıyorum", "aciyorum", "açıyoruz", "aciyoruz", "açıyor", "aciyor",
        "açtım", "actim", "açtık", "actik", "açtı", "acti",
        "seçiyorum", "seciyorum", "seçiyoruz", "seciyoruz", "seçtim", "sectim",
        "çalıştır", "calistir", "çalıştırıyorum", "calistiriyorum",
        "çalıştırdım", "calistirdim", "kopyala", "yapıştır", "yapistir"
    ]

    private static let warningTriggers = [
        "don't", "wrong", "mistake", "avoid", "error", "bug", "fail", "waste",
        "dont", "yanlış", "hata", "kaçın", "sakın", "asla", "yapma", "yapmayın"
    ]

    private static let ctaTriggers = [
        "follow for more", "follow for part two", "follow me", "follow us", "follow along",
        "hit follow", "like and follow",
        "save this", "save it", "save for later", "save this for later",
        "subscribe", "share this", "share it",
        "comment vibe", "comment below", "leave a comment", "drop a comment",
        "bunu kaydet", "videoyu kaydet", "sonra kaydet", "kaydetmeyi unutma",
        "takip et", "takibe al", "takipte kal", "takip etmeyi unutma",
        "daha fazlası için takip et", "daha fazlasi icin takip et", "abone ol",
        "bunu paylaş", "paylaşmayı unutma", "paylaş", "bunu paylas", "paylasmayi unutma", "paylas",
        "beğen ve takip et", "begen ve takip et",
        "yorum yaz", "yorum bırak", "yorum birak", "yorum at",
        "yorumlara yaz", "yorumlara vibe", "yorumlara bırak", "yorumlara birak",
        "vibe yazıp", "vibe yazip", "büyüyelim", "buyuyelim"
    ]
}

enum TechInfluencerEditDecisionNormalizer {
    static func exportReadyDecisions(
        _ decisions: [EditDecision],
        templateId: String
    ) -> [EditDecision] {
        guard templateId == "tech_influencer" else { return decisions }
        return droppingCloseRevealCombos(decisions)
    }

    private static func droppingCloseRevealCombos(_ decisions: [EditDecision]) -> [EditDecision] {
        let revealImpacts = decisions
            .filter { $0.reason == TechInfluencerEffectCue.techRevealImpactSFX.reason }
            .sorted { $0.time < $1.time }
        guard revealImpacts.count > 1 else { return decisions }

        var keptImpactTimes: [Double] = []
        for impact in revealImpacts {
            if let previous = keptImpactTimes.last,
               impact.time - previous < 3.0 {
                keptImpactTimes.removeLast()
            }
            keptImpactTimes.append(impact.time)
        }

        let droppedImpactTimes = revealImpacts
            .map(\.time)
            .filter { impactTime in
                !keptImpactTimes.contains { abs($0 - impactTime) < 0.001 }
            }
        guard !droppedImpactTimes.isEmpty else { return decisions }

        return decisions.filter { decision in
            guard isRevealComboDecision(decision) else { return true }
            return !droppedImpactTimes.contains { impactTime in
                belongsToRevealCombo(decision, impactTime: impactTime)
            }
        }
    }

    private static func isRevealComboDecision(_ decision: EditDecision) -> Bool {
        TechInfluencerEffectCue(reason: decision.reason)?.isRevealComboCue == true
    }

    private static func belongsToRevealCombo(_ decision: EditDecision, impactTime: Double) -> Bool {
        let expectedOffset = TechInfluencerEffectCue(reason: decision.reason)?.revealComboAnchorOffset
        guard let expectedOffset else { return false }
        let tolerance = decision.reason == TechInfluencerEffectCue.techRevealZoom.reason ? 0.18 : 0.12
        return abs(decision.time - (impactTime + expectedOffset)) <= tolerance
    }
}
