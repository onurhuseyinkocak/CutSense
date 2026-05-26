import Foundation

struct QualityReport: Sendable {
    let checks: [QualityCheck]
    let passed: Bool
    let score: Int // 0-100

    var failedChecks: [QualityCheck] {
        checks.filter { !$0.passed }
    }
}

struct QualityCheck: Sendable, Identifiable {
    let id = UUID()
    let name: String
    let passed: Bool
    let detail: String
    let severity: Severity
    let blocksExport: Bool

    enum Severity: String, Codable, Sendable {
        case critical
        case warning
        case info
    }

    init(
        name: String,
        passed: Bool,
        detail: String,
        severity: Severity,
        blocksExport: Bool = false
    ) {
        self.name = name
        self.passed = passed
        self.detail = detail
        self.severity = severity
        self.blocksExport = blocksExport
    }
}

struct TechInfluencerEditPlanVerification: Sendable {
    let eventCount: Int
    let eventKindCounts: [String: Int]
    let decisionCount: Int
    let unsupportedDecisions: [EditDecision]
    let unanchoredDecisions: [EditDecision]
    let missingCombos: [String]
    let forbiddenCombos: [String]

    var eventAnchoringPassed: Bool {
        unsupportedDecisions.isEmpty && unanchoredDecisions.isEmpty
    }

    var comboPassed: Bool {
        missingCombos.isEmpty && forbiddenCombos.isEmpty
    }

    var comboIssues: [String] {
        missingCombos + forbiddenCombos
    }
}

enum TechInfluencerEditPlanVerifier {
    private enum EventKind: CaseIterable, Sendable {
        case hook
        case topicShift
        case reveal
        case uiAction
        case keyword
        case warning
        case cta

        var label: String {
            switch self {
            case .hook: "hook"
            case .topicShift: "topicShift"
            case .reveal: "reveal"
            case .uiAction: "uiAction"
            case .keyword: "keyword"
            case .warning: "warning"
            case .cta: "cta"
            }
        }

        init(_ kind: TechInfluencerEffectEventKind) {
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

    private struct TimelineEvent: Sendable {
        let kind: EventKind
        let startTime: Double
        let endTime: Double
        let anchorTime: Double
        let text: String
    }

    private struct DecisionRoute: Sendable {
        let kind: EventKind
        let mode: TechInfluencerCueAnchorMode
    }

    private static let uiRevealCouplingWindow: Double = 3.05

    static func verify(
        captions: [CaptionSegment],
        decisions: [EditDecision],
        transcription: TranscriptionResult? = nil
    ) -> TechInfluencerEditPlanVerification {
        let events = semanticEvents(captions: captions, transcription: transcription)
        var unsupported: [EditDecision] = []
        var unanchored: [EditDecision] = []

        for decision in decisions {
            guard let route = route(for: decision) else {
                unsupported.append(decision)
                continue
            }

            guard isAnchored(decision, route: route, events: events) else {
                unanchored.append(decision)
                continue
            }
        }

        return TechInfluencerEditPlanVerification(
            eventCount: events.count,
            eventKindCounts: eventKindCounts(events),
            decisionCount: decisions.count,
            unsupportedDecisions: unsupported,
            unanchoredDecisions: unanchored,
            missingCombos: missingCombos(events: events, decisions: decisions),
            forbiddenCombos: forbiddenCombos(events: events, decisions: decisions)
        )
    }

    private static func eventKindCounts(_ events: [TimelineEvent]) -> [String: Int] {
        events.reduce(into: [:]) { counts, event in
            counts[event.kind.label, default: 0] += 1
        }
    }

    private static func semanticEvents(
        captions: [CaptionSegment],
        transcription: TranscriptionResult?
    ) -> [TimelineEvent] {
        let sortedCaptions = captions.sorted { $0.startTime < $1.startTime }
        let captionEvents = sortedCaptions
            .enumerated()
            .flatMap { index, caption in
                events(from: caption, index: index, totalCount: sortedCaptions.count)
            }

        let transcriptEvents = transcriptSemanticEvents(from: transcription)

        var merged: [TimelineEvent] = []
        for event in (captionEvents + transcriptEvents).sorted(by: { $0.anchorTime < $1.anchorTime }) {
            guard !merged.contains(where: { existing in
                existing.kind == event.kind && abs(existing.anchorTime - event.anchorTime) < 0.30
            }) else { continue }
            merged.append(event)
        }
        return coalescedSemanticEvents(merged)
    }

    private static func transcriptSemanticEvents(from transcription: TranscriptionResult?) -> [TimelineEvent] {
        guard let transcription else { return [] }
        let sourceDuration = max(
            transcription.segments.map(\.endTime).max() ?? 0,
            0.1
        )
        let audio = AudioAnalysisResult(
            segments: [],
            silenceIntervals: [],
            averageEnergy: 0,
            peakEnergy: 0,
            duration: sourceDuration
        )
        let plan = TechInfluencerTimelineAnalyzer.analyze(
            transcription: transcription,
            audioAnalysis: audio
        )

        return plan.events.map { event in
            TimelineEvent(
                kind: eventKind(from: event.kind),
                startTime: event.sourceStart,
                endTime: event.sourceEnd,
                anchorTime: event.anchorTime,
                text: event.text
            )
        }
    }

    private static func eventKind(from kind: TechInfluencerTimelinePlan.Event.Kind) -> EventKind {
        switch kind {
        case .hook: .hook
        case .topicShift: .topicShift
        case .reveal: .reveal
        case .uiAction: .uiAction
        case .keyword: .keyword
        case .warning: .warning
        case .cta: .cta
        }
    }

    private static func coalescedSemanticEvents(_ events: [TimelineEvent]) -> [TimelineEvent] {
        var coalesced: [TimelineEvent] = []
        var lastHookIndex: Int?
        var lastHookAnchorTime: Double = -10
        var lastRevealIndex: Int?
        var lastRevealAnchorTime: Double = -10
        var lastCTAIndex: Int?
        var lastCTAAnchorTime: Double = -10
        var lastWarningIndex: Int?
        var lastWarningAnchorTime: Double = -10
        var lastTopicShiftAnchorTime: Double = -10

        for event in events.sorted(by: { $0.startTime < $1.startTime }) {
            if event.kind == .hook,
               let lastHookIndex,
               event.anchorTime - lastHookAnchorTime < 3.0 {
                if event.anchorTime < coalesced[lastHookIndex].anchorTime {
                    coalesced[lastHookIndex] = event
                    lastHookAnchorTime = event.anchorTime
                }
                continue
            }

            if event.kind == .reveal,
               let lastRevealIndex,
               event.anchorTime - lastRevealAnchorTime < 3.0 {
                if revealPriority(event.text) > revealPriority(coalesced[lastRevealIndex].text) {
                    coalesced[lastRevealIndex] = event
                    lastRevealAnchorTime = event.anchorTime
                }
                continue
            }

            if event.kind == .cta,
               let lastCTAIndex,
               event.anchorTime - lastCTAAnchorTime < 4.0 {
                let existing = coalesced[lastCTAIndex]
                if ctaPriority(event.text) >= ctaPriority(existing.text) {
                    coalesced[lastCTAIndex] = TimelineEvent(
                        kind: .cta,
                        startTime: min(existing.startTime, event.startTime),
                        endTime: max(existing.endTime, event.endTime),
                        anchorTime: event.anchorTime,
                        text: "\(existing.text) \(event.text)"
                    )
                    lastCTAAnchorTime = event.anchorTime
                } else {
                    coalesced[lastCTAIndex] = TimelineEvent(
                        kind: .cta,
                        startTime: min(existing.startTime, event.startTime),
                        endTime: max(existing.endTime, event.endTime),
                        anchorTime: existing.anchorTime,
                        text: "\(existing.text) \(event.text)"
                    )
                }
                continue
            }

            if event.kind == .warning,
               let lastWarningIndex,
               event.anchorTime - lastWarningAnchorTime < 3.0 {
                let existing = coalesced[lastWarningIndex]
                if warningPriority(event.text) >= warningPriority(existing.text) {
                    coalesced[lastWarningIndex] = TimelineEvent(
                        kind: .warning,
                        startTime: min(existing.startTime, event.startTime),
                        endTime: max(existing.endTime, event.endTime),
                        anchorTime: event.anchorTime,
                        text: "\(existing.text) \(event.text)"
                    )
                    lastWarningAnchorTime = event.anchorTime
                } else {
                    coalesced[lastWarningIndex] = TimelineEvent(
                        kind: .warning,
                        startTime: min(existing.startTime, event.startTime),
                        endTime: max(existing.endTime, event.endTime),
                        anchorTime: existing.anchorTime,
                        text: "\(existing.text) \(event.text)"
                    )
                }
                continue
            }

            if event.kind == .topicShift,
               event.anchorTime - lastTopicShiftAnchorTime < 4.0 {
                continue
            }

            if event.kind == .topicShift,
               coalesced.contains(where: { existing in
                   isPrimarySemanticEvent(existing.kind)
                       && abs(existing.anchorTime - event.anchorTime) < 1.8
               }) {
                continue
            }

            if isPrimarySemanticEvent(event.kind),
               let topicIndex = coalesced.lastIndex(where: { existing in
                   existing.kind == .topicShift
                       && abs(existing.anchorTime - event.anchorTime) < 1.8
               }) {
                coalesced.remove(at: topicIndex)
            }

            coalesced.append(event)
            switch event.kind {
            case .hook:
                lastHookIndex = coalesced.count - 1
                lastHookAnchorTime = event.anchorTime
            case .reveal:
                lastRevealIndex = coalesced.count - 1
                lastRevealAnchorTime = event.anchorTime
            case .cta:
                lastCTAIndex = coalesced.count - 1
                lastCTAAnchorTime = event.anchorTime
            case .warning:
                lastWarningIndex = coalesced.count - 1
                lastWarningAnchorTime = event.anchorTime
            case .topicShift:
                lastTopicShiftAnchorTime = event.anchorTime
            case .uiAction, .keyword:
                break
            }
        }

        return coalesced
    }

    private static func isPrimarySemanticEvent(_ kind: EventKind) -> Bool {
        switch kind {
        case .hook, .reveal, .uiAction, .warning, .cta:
            true
        case .topicShift, .keyword:
            false
        }
    }

    private static func isSpeechLike(_ segment: TranscriptSegment) -> Bool {
        switch segment.segmentType {
        case .speech, .contentSentence, .suspectedRestart, .suspectedDuplicate:
            true
        case .silence, .filler, .editCommand:
            false
        }
    }

    private static func events(
        from caption: CaptionSegment,
        index: Int,
        totalCount: Int
    ) -> [TimelineEvent] {
        semanticKinds(
            text: caption.text,
            role: caption.role,
            sceneBehavior: caption.sceneBehavior,
            index: index,
            totalCount: totalCount,
            startTime: caption.startTime
        ).map { kind in
            TimelineEvent(
                kind: kind,
                startTime: caption.startTime,
                endTime: caption.endTime,
                anchorTime: anchorTime(kind: kind, text: caption.text, start: caption.startTime, end: caption.endTime, wordTimings: caption.wordTimings),
                text: caption.text
            )
        }
    }

    private static func events(
        from segment: TranscriptSegment,
        index: Int,
        totalCount: Int
    ) -> [TimelineEvent] {
        semanticKinds(
            text: segment.text,
            role: nil,
            sceneBehavior: nil,
            index: index,
            totalCount: totalCount,
            startTime: segment.startTime
        ).map { kind in
            TimelineEvent(
                kind: kind,
                startTime: segment.startTime,
                endTime: segment.endTime,
                anchorTime: anchorTime(kind: kind, text: segment.text, start: segment.startTime, end: segment.endTime, wordTimings: segment.wordTimings),
                text: segment.text
            )
        }
    }

    private static func semanticKinds(
        text: String,
        role: CaptionRole?,
        sceneBehavior: CaptionSceneBehavior?,
        index: Int,
        totalCount: Int,
        startTime: Double
    ) -> [EventKind] {
        var kinds: [EventKind] = []
        func append(_ kind: EventKind) {
            guard !kinds.contains(kind) else { return }
            kinds.append(kind)
        }

        if let primary = classify(
            text: text,
            role: role,
            sceneBehavior: sceneBehavior,
            index: index,
            totalCount: totalCount,
            startTime: startTime
        ) {
            append(primary)
        }

        if (role == .hook || (index == 0 && startTime < 3.0)),
           isHookWorthy(text) {
            append(.hook)
        }

        let isClosingSection = totalCount > 0 && index >= max(1, Int(Double(totalCount) * 0.72))
        if containsCTAPhrase(in: text)
            && (role == .conclusion || isClosingSection) {
            append(.cta)
        }
        if isMeaningfulReveal(text) {
            append(.reveal)
        }
        if role == .warning || isStrongWarning(text) {
            append(.warning)
        }
        if role == .transition || startsTopicShift(text) {
            append(.topicShift)
        }
        if hasDirectUIAction(text) {
            append(.uiAction)
        }
        if kinds.isEmpty || role == .keyword || sceneBehavior == .some(.keywordLockOn) {
            if role == .keyword
                || (sceneBehavior == .some(.keywordLockOn) && keywordImportance(text) >= 2)
                || keywordImportance(text) >= 3 {
                append(.keyword)
            }
        }

        if kinds.contains(where: isPrimarySemanticEvent) {
            kinds.removeAll { kind in
                kind == .topicShift || (kind == .keyword && role != .keyword && sceneBehavior != .some(.keywordLockOn))
            }
        }

        return kinds
    }

    private static func classify(
        text: String,
        role: CaptionRole?,
        sceneBehavior: CaptionSceneBehavior?,
        index: Int,
        totalCount: Int,
        startTime: Double
    ) -> EventKind? {
        switch sceneBehavior {
        case .some(.hookImpact):
            if isOpeningHookCandidate(text: text, role: role, index: index, startTime: startTime) { return .hook }
        case .some(.transitionWhoosh):
            if startsTopicShift(text) { return .topicShift }
        case .some(.punchIn):
            if isMeaningfulReveal(text) { return .reveal }
        case .some(.focusBlur):
            if hasDirectUIAction(text) { return .uiAction }
        case .some(.keywordLockOn):
            if role == .warning || isStrongWarning(text) {
                return .warning
            }
            return keywordImportance(text) >= 2 ? .keyword : nil
        case .some(.underlineReveal):
            return role == .warning || isStrongWarning(text) ? .warning : nil
        case .some(.conclusionHold): return containsCTAPhrase(in: text) ? .cta : nil
        case .some(CaptionSceneBehavior.none), .some(.subtleZoom), nil: break
        }

        if isOpeningHookCandidate(text: text, role: role, index: index, startTime: startTime) { return .hook }

        let isClosingSection = totalCount > 0 && index >= max(1, Int(Double(totalCount) * 0.72))
        if containsCTAPhrase(in: text)
            && (role == .conclusion || isClosingSection) {
            return .cta
        }
        if isMeaningfulReveal(text) { return .reveal }
        if role == .warning || isStrongWarning(text) { return .warning }
        if role == .transition || startsTopicShift(text) { return .topicShift }
        if hasDirectUIAction(text) { return .uiAction }
        if role == .keyword || keywordImportance(text) >= 3 { return .keyword }
        return nil
    }

    private static func isOpeningHookCandidate(
        text: String,
        role: CaptionRole?,
        index: Int,
        startTime: Double
    ) -> Bool {
        (role == .some(.hook) || (index == 0 && startTime < 3.0)) && isHookWorthy(text)
    }

    private static func anchorTime(
        kind: EventKind,
        text: String,
        start: Double,
        end: Double,
        wordTimings: [(word: String, start: Double, duration: Double)]
    ) -> Double {
        let phrases: [String] = switch kind {
        case .hook: hookPayoffAnchorTriggers + hookAnchorTriggers
        case .reveal: revealPayoffTriggers
        case .uiAction: uiActionAnchorTriggers + techKeywordTriggers
        case .keyword: techKeywordTriggers
        case .warning: warningTriggers
        case .topicShift: []
        case .cta: ctaTriggers + techKeywordTriggers
        }

        if kind == .cta {
            if let ctaAnchor = preferredCTAAnchorTime(
                text: text,
                wordTimings: wordTimings,
                start: start,
                end: end
            ) {
                return min(max(ctaAnchor, start), end)
            }
            if end - start > 5.0 {
                return max(start, end - 0.20)
            }
        }

        if kind == .hook,
           let matched = preferredHookAnchorTime(text: text, wordTimings: wordTimings, start: start, end: end) {
            return min(max(matched, start), end)
        }

        if kind == .reveal,
           let matched = preferredRevealAnchorTime(text: text, wordTimings: wordTimings, start: start, end: end) {
            return min(max(matched, start), end)
        }

        if kind == .uiAction,
           let matched = matchingAnchorTime(in: wordTimings, phrases: uiActionAnchorTriggers) {
            return min(max(matched, start), end)
        }

        if let matched = matchingAnchorTime(in: wordTimings, phrases: phrases) {
            return min(max(matched, start), end)
        }

        if kind == .cta,
           let estimated = estimatedPhraseAnchorTime(in: text, phrases: phrases, start: start, end: end) {
            return min(max(estimated, start), end)
        }

        switch kind {
        case .topicShift:
            return start
        case .cta:
            return max(start, end - 0.20)
        case .hook, .reveal, .uiAction, .keyword, .warning:
            return firstWordTime(wordTimings: wordTimings) ?? start
        }
    }

    private static func route(for decision: EditDecision) -> DecisionRoute? {
        guard let cue = TechInfluencerEffectCue(reason: decision.reason) else { return nil }
        guard decision.type == cue.editType else { return nil }
        return DecisionRoute(kind: EventKind(cue.eventKind), mode: cue.routeMode)
    }

    private static func isAnchored(
        _ decision: EditDecision,
        route: DecisionRoute,
        events: [TimelineEvent]
    ) -> Bool {
        events.contains { event in
            guard event.kind == route.kind else { return false }
            switch route.mode {
            case .anchor(let offset, let tolerance):
                return expectedAnchorTimes(for: decision, event: event, offset: offset)
                    .contains { expectedTime in
                        abs(decision.time - expectedTime) <= tolerance
                    }
            case .start(let tolerance):
                return abs(decision.time - event.startTime) <= tolerance
            }
        }
    }

    private static func overlapsSemanticEventWindow(
        _ decision: EditDecision,
        route: DecisionRoute,
        event: TimelineEvent
    ) -> Bool {
        guard route.kind == .reveal || route.kind == .cta else { return false }
        guard TechInfluencerEffectCue(reason: decision.reason)?.isRequiredComboCue == true else { return false }

        let decisionEnd = decision.time + max(0, decision.duration)
        return intervalsOverlap(
            decisionStart: decision.time,
            decisionEnd: decisionEnd,
            event: event
        )
    }

    private static func expectedAnchorTimes(
        for decision: EditDecision,
        event: TimelineEvent,
        offset: Double
    ) -> [Double] {
        let rawTime = event.anchorTime + offset
        let rendererClampedTime = switch decision.type {
        case .sfx:
            max(0.05, rawTime)
        case .zoom, .cutTransition, .colorShift, .flash, .shake:
            max(0, rawTime)
        }

        if abs(rawTime - rendererClampedTime) < 0.001 {
            return [rawTime]
        }
        return [rawTime, rendererClampedTime]
    }

    private static func missingCombos(
        events: [TimelineEvent],
        decisions: [EditDecision]
    ) -> [String] {
        var missing: [String] = []

        let missingHookCount = missingComboCount(
            requiredReasons: TechInfluencerEffectCue.requiredReasons(for: .hook),
            kind: .hook,
            events: events,
            decisions: decisions
        )
        if missingHookCount > 0 {
            missing.append("hook two-phase zoom/impact x\(missingHookCount)")
        }

        let missingTopicShiftCount = missingComboCount(
            requiredReasons: TechInfluencerEffectCue.requiredReasons(for: .topicShift),
            kind: .topicShift,
            events: events,
            decisions: decisions
        )
        if missingTopicShiftCount > 0 {
            missing.append("topic shift motion x\(missingTopicShiftCount)")
        }

        let missingRevealCount = missingComboCount(
            requiredReasons: TechInfluencerEffectCue.requiredReasons(for: .reveal),
            kind: .reveal,
            events: events,
            decisions: decisions
        )
        if missingRevealCount > 0 {
            missing.append("reveal zoom/impact x\(missingRevealCount)")
        }

        let missingUICount = missingComboCount(
            requiredReasons: TechInfluencerEffectCue.requiredReasons(for: .uiAction),
            kind: .uiAction,
            events: events,
            decisions: decisions
        )
        if missingUICount > 0 {
            missing.append("UI zoom/highlight x\(missingUICount)")
        }

        let missingWarningCount = missingComboCount(
            requiredReasons: TechInfluencerEffectCue.requiredReasons(for: .warning),
            kind: .warning,
            events: events,
            decisions: decisions
        )
        if missingWarningCount > 0 {
            missing.append("warning accent x\(missingWarningCount)")
        }

        let missingCTACount = missingComboCount(
            requiredReasons: TechInfluencerEffectCue.requiredReasons(for: .cta),
            kind: .cta,
            events: events,
            decisions: decisions
        )
        if missingCTACount > 0 {
            missing.append("CTA slow-push/ping x\(missingCTACount)")
        }

        return missing
    }

    private static func forbiddenCombos(
        events: [TimelineEvent],
        decisions: [EditDecision]
    ) -> [String] {
        let coupledUIEvents = events.filter { event in
            event.kind == .uiAction && isUIActionCoupledToReveal(event, events: events)
        }
        guard !coupledUIEvents.isEmpty else { return [] }

        let forbiddenReasons = [
            TechInfluencerEffectCue.techUIFocusZoom.reason,
            TechInfluencerEffectCue.techUIClickSFX.reason
        ]
        var violations = Set<String>()

        for event in coupledUIEvents {
            for reason in forbiddenReasons {
                guard let cue = TechInfluencerEffectCue(reason: reason) else { continue }
                let route = DecisionRoute(kind: EventKind(cue.eventKind), mode: cue.routeMode)
                if decisions.contains(where: { decision in
                    decision.reason == reason && isAnchored(decision, route: route, events: [event])
                }) {
                    violations.insert("coupled UI->reveal has extra \(reason)")
                }
            }
        }

        return violations.sorted()
    }

    private static func missingComboCount(
        requiredReasons: [String],
        kind: EventKind,
        events: [TimelineEvent],
        decisions: [EditDecision]
    ) -> Int {
        let eventAnchors = events.filter { $0.kind == kind }
        guard !eventAnchors.isEmpty else { return 0 }

        let missingEvents = eventAnchors.filter { event in
            let effectiveRequiredReasons = requiredComboReasons(
                defaultReasons: requiredReasons,
                kind: kind,
                event: event,
                events: events
            )
            return !effectiveRequiredReasons.allSatisfy { reason in
                decisions.contains { decision in
                    guard decision.reason == reason,
                          let route = route(for: decision) else { return false }
                    return isAnchored(decision, route: route, events: [event])
                }
            }
        }

        if kind == .reveal {
            return missingEvents.filter { event in
                !isCoveredByNearbyCompleteRevealCombo(event, decisions: decisions)
            }.count
        }

        return missingEvents.count
    }

    private static func requiredComboReasons(
        defaultReasons: [String],
        kind: EventKind,
        event: TimelineEvent,
        events: [TimelineEvent]
    ) -> [String] {
        if kind == .uiAction,
           isUIActionCoupledToReveal(event, events: events) {
            return [TechInfluencerEffectCue.techUIHighlightPulse.reason]
        }
        return defaultReasons
    }

    private static func isUIActionCoupledToReveal(_ event: TimelineEvent, events: [TimelineEvent]) -> Bool {
        guard event.kind == .uiAction else { return false }
        return events.contains { candidate in
            guard candidate.kind == .reveal else { return false }
            let anchorGap = candidate.anchorTime - event.anchorTime
            guard anchorGap >= 0, anchorGap <= uiRevealCouplingWindow else { return false }
            guard !sameSpokenWindow(event, candidate) || !hasDelayedUIRevealBridge(event.text) else { return false }
            return sameSpokenWindow(event, candidate)
                || candidate.startTime - event.endTime <= 0.35
                || event.endTime - event.startTime >= anchorGap
        }
    }

    private static func sameSpokenWindow(_ lhs: TimelineEvent, _ rhs: TimelineEvent) -> Bool {
        abs(lhs.startTime - rhs.startTime) < 0.05
            && abs(lhs.endTime - rhs.endTime) < 0.05
    }

    private static func isCoveredByNearbyCompleteRevealCombo(
        _ event: TimelineEvent,
        decisions: [EditDecision]
    ) -> Bool {
        let revealImpacts = decisions.filter {
            $0.reason == TechInfluencerEffectCue.techRevealImpactSFX.reason
        }

        return revealImpacts.contains { impact in
            guard abs(impact.time - event.anchorTime) < 3.0 else { return false }
            return TechInfluencerEffectCue.requiredReasons(for: .reveal).allSatisfy { reason in
                decisions.contains { decision in
                    revealDecision(decision, belongsToComboAt: impact.time, reason: reason)
                }
            }
        }
    }

    private static func revealDecision(
        _ decision: EditDecision,
        belongsToComboAt impactTime: Double,
        reason: String
    ) -> Bool {
        guard decision.reason == reason,
              let cue = TechInfluencerEffectCue(reason: reason),
              let offset = cue.revealComboAnchorOffset else {
            return false
        }

        return abs(decision.time - (impactTime + offset)) <= 0.75
    }

    private static func intervalsOverlap(
        decisionStart: Double,
        decisionEnd: Double,
        event: TimelineEvent
    ) -> Bool {
        min(decisionEnd, event.endTime) > max(decisionStart, event.startTime)
    }

    private static func firstWordTime(
        wordTimings: [(word: String, start: Double, duration: Double)]
    ) -> Double? {
        wordTimings.first?.start
    }

    private static func matchingAnchorTime(
        in wordTimings: [(word: String, start: Double, duration: Double)],
        phrases: [String]
    ) -> Double? {
        matchingAnchorTimes(in: wordTimings, phrases: phrases).min()
    }

    private static func matchingAnchorTimes(
        in wordTimings: [(word: String, start: Double, duration: Double)],
        phrases: [String]
    ) -> [Double] {
        guard !wordTimings.isEmpty, !phrases.isEmpty else { return [] }

        let timingTokens = wordTimings.map { normalizedToken($0.word) }
        let phraseTokens = phrases
            .map { phrase in phrase.split(whereSeparator: \.isWhitespace).map { normalizedToken(String($0)) } }
            .filter { !$0.isEmpty }

        var matches: [Double] = []
        for phrase in phraseTokens {
            guard phrase.count <= timingTokens.count else { continue }
            let lastStartIndex = timingTokens.count - phrase.count
            for startIndex in 0...lastStartIndex where phraseMatches(phrase, timingTokens: timingTokens, at: startIndex) {
                matches.append(wordTimings[startIndex].start)
            }
        }
        return matches
    }

    private static func estimatedPhraseAnchorTime(
        in text: String,
        phrases: [String],
        start: Double,
        end: Double
    ) -> Double? {
        estimatedPhraseAnchorTimes(in: text, phrases: phrases, start: start, end: end).min()
    }

    private static func estimatedPhraseAnchorTimes(
        in text: String,
        phrases: [String],
        start: Double,
        end: Double
    ) -> [Double] {
        let words = normalizedWords(in: text)
        guard !words.isEmpty, end > start else { return [] }

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
        let estimatedWordDuration = (end - start) / Double(words.count)
        return matchIndexes.map { start + estimatedWordDuration * Double($0) }
    }

    private static func preferredCTAAnchorTime(
        text: String,
        wordTimings: [(word: String, start: Double, duration: Double)],
        start: Double,
        end: Double
    ) -> Double? {
        let duration = end - start
        let matches = matchingAnchorTimes(in: wordTimings, phrases: ctaTriggers)
        if let latest = matches.max() {
            return latest
        }

        guard duration <= 5.0 else { return nil }
        return estimatedPhraseAnchorTimes(in: text, phrases: ctaTriggers, start: start, end: end).max()
    }

    private static func preferredHookAnchorTime(
        text: String,
        wordTimings: [(word: String, start: Double, duration: Double)],
        start: Double,
        end: Double
    ) -> Double? {
        matchingAnchorTime(in: wordTimings, phrases: hookPayoffAnchorTriggers)
            ?? estimatedPhraseAnchorTime(in: text, phrases: hookPayoffAnchorTriggers, start: start, end: end)
            ?? matchingAnchorTime(in: wordTimings, phrases: hookAnchorTriggers)
            ?? estimatedPhraseAnchorTime(in: text, phrases: hookAnchorTriggers, start: start, end: end)
    }

    private static func preferredRevealAnchorTime(
        text: String,
        wordTimings: [(word: String, start: Double, duration: Double)],
        start: Double,
        end: Double
    ) -> Double? {
        if let payoff = matchingAnchorTime(in: wordTimings, phrases: coreRevealPayoffTriggers)
            ?? estimatedPhraseAnchorTime(in: text, phrases: coreRevealPayoffTriggers, start: start, end: end) {
            return payoff
        }
        if containsPhrase(in: text, phrases: generatedCreatedRevealTriggers),
           let generatedVerb = matchingAnchorTime(in: wordTimings, phrases: generatedCreatedRevealVerbAnchorTriggers)
            ?? estimatedPhraseAnchorTime(in: text, phrases: generatedCreatedRevealVerbAnchorTriggers, start: start, end: end) {
            return generatedVerb
        }
        if let generated = matchingAnchorTime(in: wordTimings, phrases: generatedCreatedRevealTriggers)
            ?? estimatedPhraseAnchorTime(in: text, phrases: generatedCreatedRevealTriggers, start: start, end: end) {
            return generated
        }
        return preferredProductRevealAnchorTime(text: text, wordTimings: wordTimings, start: start, end: end)
            ?? matchingAnchorTime(in: wordTimings, phrases: bigRevealAnchorTriggers)
            ?? estimatedPhraseAnchorTime(in: text, phrases: bigRevealAnchorTriggers, start: start, end: end)
    }

    private static func preferredProductRevealAnchorTime(
        text: String,
        wordTimings: [(word: String, start: Double, duration: Double)],
        start: Double,
        end: Double
    ) -> Double? {
        guard isBigRevealLeadInCandidate(text) else { return nil }
        return matchingAnchorTime(in: wordTimings, phrases: productRevealAnchorTriggers)
            ?? estimatedPhraseAnchorTime(in: text, phrases: productRevealAnchorTriggers, start: start, end: end)
    }

    private static func phraseWordsMatch(
        _ phraseWords: [String],
        words: [String],
        at startIndex: Int
    ) -> Bool {
        for (offset, phraseWord) in phraseWords.enumerated() {
            let word = words[startIndex + offset]
            guard word == phraseWord || (phraseWord.count >= 4 && word.hasPrefix(phraseWord)) else {
                return false
            }
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
            guard timingToken == phraseToken || (phraseToken.count >= 4 && timingToken.hasPrefix(phraseToken)) else {
                return false
            }
        }
        return true
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

    private static func startsTopicShift(_ text: String) -> Bool {
        let words = normalizedWords(in: text)
        guard !words.isEmpty else { return false }
        return topicShiftTriggers.contains { phrase in
            let phraseWords = normalizedWords(in: phrase)
            guard !phraseWords.isEmpty, phraseWords.count <= words.count else { return false }
            return zip(words.prefix(phraseWords.count), phraseWords).allSatisfy { pair in
                pair.0 == pair.1
            }
        }
    }

    private static func normalizedWords(in text: String) -> [String] {
        normalizedSearchText(text)
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private static func normalizedToken(_ token: String) -> String {
        normalizedSearchText(token)
            .filter { $0.isLetter || $0.isNumber }
    }

    private static func normalizedSearchText(_ text: String) -> String {
        text.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "tr_TR")
        )
        .replacingOccurrences(of: "ı", with: "i")
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

    private static func isStrongWarning(_ text: String) -> Bool {
        if containsPhrase(in: text, phrases: ["don't", "dont", "avoid", "stop doing", "sakin", "asla", "yapma", "yapmayin"]) {
            return true
        }
        if containsPositiveResolutionPhrase(text) {
            return false
        }
        if containsPhrase(in: text, phrases: ["wrong", "mistake", "yanlis"]) {
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
            phrases: ["fix", "fixes", "fixed", "solves", "solved", "works", "handling works", "cozer", "duzeltiyor"]
        )
    }

    private static func warningPriority(_ text: String) -> Int {
        var score = 0
        if containsPhrase(in: text, phrases: ["wrong", "mistake", "yanlis", "hata"]) { score += 5 }
        if containsPhrase(in: text, phrases: ["don't", "dont", "sakin", "asla", "yapmayin"]) { score += 4 }
        if containsPhrase(in: text, phrases: ["waste", "fail", "bug", "error"]) { score += 3 }
        return score
    }

    private static func keywordImportance(_ text: String) -> Int {
        var score = 0
        if containsPhrase(in: text, phrases: ["vibe coding"]) { score += 4 }
        if containsPhrase(in: text, phrases: ["mvp"]) { score += 4 }
        if containsPhrase(in: text, phrases: ["app store"]) { score += 3 }
        if containsPhrase(in: text, phrases: ["yapay zeka", "ai"]) { score += 2 }
        if containsPhrase(in: text, phrases: ["web"]) { score += 2 }
        if containsPhrase(in: text, phrases: ["urun", "product"]) { score += 2 }
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

    private static func isMeaningfulReveal(_ text: String) -> Bool {
        containsPhrase(in: text, phrases: revealPayoffTriggers)
            || revealPriority(text) >= 8
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
        "ai", "yapay zeka", "mvp", "app store", "web", "tool", "kod", "code", "coding",
        "vibe", "startup", "urun", "product", "uygulama", "app", "automated", "otomatik",
        "launch", "build", "fix", "problem", "users", "money"
    ]

    private static let coreRevealPayoffTriggers = [
        "result", "results", "sonuc", "cikti", "appears"
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
        "tam da bu yuzden", "iste tam", "turkiye'nin ilk", "turkiyenin ilk",
        "ilk vibe", "kurdum", "kurduk"
    ]
    private static let productRevealAnchorTriggers = ["vibe coding"]
    private static let revealPayoffTriggers = coreRevealPayoffTriggers
        + generatedCreatedRevealTriggers
        + bigRevealAnchorTriggers
    private static let revealTriggers = revealPayoffTriggers + [
        "builds", "built", "launch", "once after", "before after"
    ]

    private static let uiActionTriggers = [
        "click", "tap", "press", "open", "select", "generate", "submit", "run", "deploy",
        "copy", "paste", "cursor", "button", "screen", "ui", "tikla", "bas", "ac", "sec",
        "calistir", "kopyala", "yapistir", "ekran", "buton", "terminal", "panel", "dashboard"
    ]
    private static let uiActionAnchorTriggers = [
        "click", "tap", "press", "select", "generate", "submit", "run", "deploy",
        "copy", "paste", "tikla", "bas", "ac", "sec",
        "bastim", "basiyorum", "basiyoruz", "tikliyorum", "tikladim",
        "aciyorum", "aciyoruz", "aciyor", "actim", "actik", "acti",
        "seciyorum", "seciyoruz", "sectim", "calistir", "calistiriyorum",
        "calistirdim", "kopyala", "yapistir"
    ]

    private static let warningTriggers = [
        "don't", "wrong", "mistake", "avoid", "error", "bug", "fail", "waste",
        "dont", "yanlis", "hata", "kacin", "sakin", "asla", "yapma", "yapmayin"
    ]

    private static let ctaTriggers = [
        "follow for more", "follow for part two", "follow me", "follow us", "follow along",
        "hit follow", "like and follow",
        "save this", "save it", "save for later", "save this for later",
        "subscribe", "share this", "share it",
        "comment vibe", "comment below", "leave a comment", "drop a comment",
        "bunu kaydet", "videoyu kaydet", "sonra kaydet", "kaydetmeyi unutma",
        "takip et", "takibe al", "takipte kal", "takip etmeyi unutma",
        "daha fazlasi icin takip et", "abone ol",
        "bunu paylas", "paylasmayi unutma", "paylas",
        "begen ve takip et",
        "yorum yaz", "yorum birak", "yorum at",
        "yorumlara yaz", "yorumlara vibe", "yorumlara birak",
        "vibe yazip", "buyuyelim"
    ]

    private static let topicShiftTriggers = [
        "now", "next", "then", "first step", "second step", "third step", "simdi", "sonra",
        "ilk olarak", "ikinci adim", "ucuncu adim", "ama simdi", "burada ise"
    ]
}

enum QualityGateService {
    static func evaluate(
        captions: [CaptionSegment],
        editPlan: EditPlan,
        roughCut: RoughCutResult,
        template: TemplateConfig,
        transcription: TranscriptionResult? = nil,
        audioQuality: AudioQualityGuard.QualityReport? = nil,
        continuity: ContinuityChecker.ContinuityResult? = nil,
        coherence: MeaningPreservationEngine.PreservationResult? = nil
    ) -> QualityReport {
        var checks: [QualityCheck] = []

        // 1. Caption count check
        let captionCount = captions.count
        checks.append(QualityCheck(
            name: "Caption count",
            passed: captionCount > 0,
            detail: captionCount > 0 ? "\(captionCount) captions generated" : "No captions generated",
            severity: captionCount > 0 ? .info : .critical
        ))

        // 2. Caption readability (none too long)
        let overLong = captions.filter { $0.text.count > 80 }
        checks.append(QualityCheck(
            name: "Caption readability",
            passed: overLong.isEmpty,
            detail: overLong.isEmpty ? "All captions readable" : "\(overLong.count) captions exceed 80 chars",
            severity: overLong.isEmpty ? .info : .warning
        ))

        // 3. Caption timing (min display duration)
        let tooShort = captions.filter { $0.endTime - $0.startTime < 0.5 }
        checks.append(QualityCheck(
            name: "Caption timing",
            passed: tooShort.isEmpty,
            detail: tooShort.isEmpty ? "All captions have adequate display time" : "\(tooShort.count) captions under 0.5s",
            severity: tooShort.isEmpty ? .info : .warning
        ))

        let timingTokenMismatches = captions.filter { caption in
            !caption.wordTimings.isEmpty && !captionTimingTokensAlign(caption)
        }
        checks.append(QualityCheck(
            name: "Caption timing token alignment",
            passed: timingTokenMismatches.isEmpty,
            detail: timingTokenMismatches.isEmpty
                ? "Caption timing tokens align with display text"
                : "\(timingTokenMismatches.count) caption(s) use timing tokens that differ from display text",
            severity: timingTokenMismatches.isEmpty ? .info : .warning,
            blocksExport: !timingTokenMismatches.isEmpty
        ))

        let captionTimingArtifacts = captions.filter { caption in
            containsUnresolvedTranscriptArtifact(caption.text)
                || containsUnresolvedTranscriptArtifact(caption.wordTimings.map(\.word).joined(separator: " "))
        }
        checks.append(QualityCheck(
            name: "Caption timing artifact cleanup",
            passed: captionTimingArtifacts.isEmpty,
            detail: captionTimingArtifacts.isEmpty
                ? "No unresolved ASR artifact patterns found in caption text or timing tokens"
                : "\(captionTimingArtifacts.count) caption(s) contain unresolved ASR artifact text/timing tokens",
            severity: captionTimingArtifacts.isEmpty ? .info : .warning,
            blocksExport: !captionTimingArtifacts.isEmpty
        ))

        // 4. Effect density
        let derivedRanges = TimelineRangeNormalizer
            .includedRanges(from: roughCut.decisions, assetDuration: roughCut.originalDuration)
        let derivedCleanDuration = derivedRanges.reduce(0.0) { $0 + $1.duration }
        let durationMatches = roughCut.decisions.isEmpty
            || abs(derivedCleanDuration - roughCut.cleanDuration) <= 0.05
        let effectCountMatches = editPlan.totalEffects == editPlan.decisions.count
        checks.append(QualityCheck(
            name: "Timeline consistency",
            passed: durationMatches && effectCountMatches,
            detail: durationMatches && effectCountMatches
                ? "Timeline duration and effect counts are internally consistent"
                : "cleanDuration \(roughCut.cleanDuration.formatted(.number.precision(.fractionLength(2)))) vs derived \(derivedCleanDuration.formatted(.number.precision(.fractionLength(2)))), effects \(editPlan.totalEffects) vs \(editPlan.decisions.count)",
            severity: durationMatches && effectCountMatches ? .info : .critical,
            blocksExport: !(durationMatches && effectCountMatches)
        ))

        let effectiveCleanDuration = !roughCut.decisions.isEmpty && derivedCleanDuration > 0
            ? derivedCleanDuration
            : roughCut.cleanDuration
        let effectsPerMinute = effectiveCleanDuration > 0
            ? Double(editPlan.decisions.count) / (effectiveCleanDuration / 60.0)
            : 0
        let maxPerMinute = maxEffectsPerMinute(for: template)
        checks.append(QualityCheck(
            name: "Effect density",
            passed: effectsPerMinute <= maxPerMinute,
            detail: String(format: "%.1f effects/min (max %.0f)", effectsPerMinute, maxPerMinute),
            severity: effectsPerMinute <= maxPerMinute ? .info : (template.id == "tech_influencer" ? .critical : .warning),
            blocksExport: template.id == "tech_influencer" && effectsPerMinute > maxPerMinute
        ))

        // 5. Clean duration sanity
        let retentionRatio = roughCut.originalDuration > 0
            ? effectiveCleanDuration / roughCut.originalDuration
            : 0
        let tooMuchCut = retentionRatio < 0.3
        let tooLittleCut = retentionRatio > 0.95
        checks.append(QualityCheck(
            name: "Content retention",
            passed: !tooMuchCut && !tooLittleCut,
            detail: String(format: "%.0f%% retained", retentionRatio * 100),
            severity: tooMuchCut ? .critical : (tooLittleCut ? .warning : .info)
        ))

        // 6. Hook presence
        let hasHook = captions.contains { $0.role == .hook }
        checks.append(QualityCheck(
            name: "Hook presence",
            passed: hasHook,
            detail: hasHook ? "Hook caption found" : "No hook caption — first impression weak",
            severity: hasHook ? .info : .warning
        ))

        // 7. Conclusion presence
        let hasConclusion = captions.contains { $0.role == .conclusion }
        checks.append(QualityCheck(
            name: "Conclusion presence",
            passed: hasConclusion,
            detail: hasConclusion ? "Conclusion caption found" : "No conclusion — ending may feel abrupt",
            severity: hasConclusion ? .info : .warning
        ))

        // 8. Transcription confidence (if available)
        if let transcription {
            let speechSegments = transcription.segments.filter { segment in
                isSpeechLike(segment)
            }
            let lowConfidence = speechSegments.filter { transcriptGateConfidence($0) < 0.55 }
            let veryLowConfidence = speechSegments.filter { transcriptGateConfidence($0) < 0.35 }
            let totalSpeechDuration = speechSegments.reduce(0.0) { total, segment in
                total + max(0, segment.endTime - segment.startTime)
            }
            let lowConfidenceDuration = lowConfidence.reduce(0.0) { total, segment in
                total + max(0, segment.endTime - segment.startTime)
            }
            let lowConfidenceRatio = totalSpeechDuration > 0
                ? lowConfidenceDuration / totalSpeechDuration
                : (speechSegments.isEmpty
                ? 0
                : Double(lowConfidence.count) / Double(speechSegments.count))
            let qualityConfidence = transcription.qualityConfidence
            let passed = !transcription.recognitionStatus.isPartial
                && qualityConfidence >= 0.70
                && veryLowConfidence.isEmpty
                && lowConfidenceRatio < 0.20
            let lowest = speechSegments.map(transcriptGateConfidence).min() ?? qualityConfidence
            let detail = String(
                format: "Quality %.0f%%, display %.0f%%, lowest %.0f%%, %.0f%% low-confidence duration, %d/%d low-confidence segments, status %@",
                qualityConfidence * 100,
                transcription.overallConfidence * 100,
                lowest * 100,
                lowConfidenceRatio * 100,
                lowConfidence.count,
                speechSegments.count,
                transcription.recognitionStatus.rawValue
            )
            checks.append(QualityCheck(
                name: "Transcription confidence",
                passed: passed,
                detail: detail,
                severity: passed ? .info : .critical,
                blocksExport: !passed
            ))

            let unresolvedArtifacts = speechSegments.filter {
                containsUnresolvedTranscriptArtifact($0.text)
            }
            checks.append(QualityCheck(
                name: "Transcript artifact cleanup",
                passed: unresolvedArtifacts.isEmpty,
                detail: unresolvedArtifacts.isEmpty
                    ? "No unresolved ASR artifact patterns found"
                    : "\(unresolvedArtifacts.count) segment(s) contain unresolved ASR artifact patterns",
                severity: unresolvedArtifacts.isEmpty ? .info : .critical,
                blocksExport: !unresolvedArtifacts.isEmpty
            ))

            let includedRanges = includedRangesForQuality(roughCut)
            let keptSpeechDuration = speechSegments.reduce(0.0) { total, segment in
                total + includedRanges.reduce(0.0) { rangeTotal, range in
                    rangeTotal + intersectionDuration(
                        start: segment.startTime,
                        end: segment.endTime,
                        range: range
                    )
                }
            }
            let captionedSpeechDuration = speechSegments.reduce(0.0) { total, segment in
                total + captionedKeptDuration(
                    for: segment,
                    includedRanges: includedRanges,
                    captions: captions
                )
            }
            let captionCoverage = keptSpeechDuration > 0
                ? captionedSpeechDuration / keptSpeechDuration
                : 0
            let captionCoveragePassed = captionCoverage >= 0.75
            checks.append(QualityCheck(
                name: "Caption coverage",
                passed: captionCoveragePassed,
                detail: "\(percent(captionCoverage)) of kept speech has captions",
                severity: captionCoveragePassed ? .info : (captionCoverage >= 0.65 ? .warning : .critical),
                blocksExport: !captionCoveragePassed
            ))

            let lowTrustSegments = transcription.segments.filter { segment in
                guard isSpeechLike(segment), transcriptQualityConfidence(segment) < 0.70 else {
                    return false
                }

                let segmentDuration = max(0, segment.endTime - segment.startTime)
                guard segmentDuration > 0 else { return false }

                let destructiveCutOverlap = roughCut.cutSegments.filter { decision in
                    !isAudioOnlySilenceCut(decision)
                }.reduce(0.0) { total, decision in
                    total + max(0, min(segment.endTime, decision.endTime) - max(segment.startTime, decision.startTime))
                }
                let silenceTrimOverlap = roughCut.cutSegments.filter { decision in
                    isAudioOnlySilenceCut(decision)
                }.reduce(0.0) { total, decision in
                    total + max(0, min(segment.endTime, decision.endTime) - max(segment.startTime, decision.startTime))
                }
                let keptOverlap = includedRanges.reduce(0.0) { total, range in
                    total + intersectionDuration(
                        start: segment.startTime,
                        end: segment.endTime,
                        range: range
                    )
                }
                let semanticKeptOverlap = min(segmentDuration, keptOverlap + silenceTrimOverlap)

                return destructiveCutOverlap / segmentDuration > 0.35
                    || semanticKeptOverlap / segmentDuration < 0.55
            }
            checks.append(QualityCheck(
                name: "Cut trust",
                passed: lowTrustSegments.isEmpty,
                detail: lowTrustSegments.isEmpty
                    ? "No low-confidence transcript was hard-cut"
                    : "\(lowTrustSegments.count) low-confidence transcript segment(s) substantially hard-cut",
                severity: lowTrustSegments.isEmpty ? .info : .critical,
                blocksExport: !lowTrustSegments.isEmpty
            ))
        }

        let reviewCount = roughCut.decisions.filter(\.requiresReview).count
        checks.append(QualityCheck(
            name: "Review required",
            passed: reviewCount == 0,
            detail: reviewCount == 0 ? "No uncertain edit decisions" : "\(reviewCount) edit decision(s) require review",
            severity: reviewCount == 0 ? .info : .critical,
            blocksExport: reviewCount != 0
        ))

        // 9. Audio quality (if available)
        if let aq = audioQuality {
            let passed = aq.passed
            var detail = String(format: "Peak: %.1fdB, Avg: %.1fdB", aq.peakDB, aq.averageDB)
            if aq.isClipping { detail += " [CLIPPING]" }
            if aq.isTooQuiet { detail += " [TOO QUIET]" }
            checks.append(QualityCheck(
                name: "Audio quality",
                passed: passed,
                detail: detail,
                severity: aq.isClipping ? .critical : (passed ? .info : .warning),
                blocksExport: !passed
            ))
        }

        // 10. Continuity (if available)
        if let cont = continuity {
            let hasBadTransitions = cont.roughTransitions > 0
            let passed = cont.overallScore >= 60
            checks.append(QualityCheck(
                name: "Continuity",
                passed: passed,
                detail: String(format: "%.0f%% smooth (%d rough transitions)", cont.overallScore, cont.roughTransitions),
                severity: hasBadTransitions && !passed ? .warning : .info,
                blocksExport: !passed
            ))
        }

        // 11. Coherence (if available)
        if let coh = coherence {
            let passed = coh.isCoherent
            let highIssues = coh.issues.filter { $0.severity == .high }.count
            checks.append(QualityCheck(
                name: "Coherence",
                passed: passed,
                detail: passed
                    ? String(format: "Score: %.0f/100", coh.overallScore)
                    : "\(highIssues) critical coherence issue(s) — meaning may be lost",
                severity: passed ? .info : .warning,
                blocksExport: !passed
            ))
        }

        if template.id == "tech_influencer" {
            checks.append(contentsOf: techInfluencerPromptChecks(
                captions: captions,
                editPlan: editPlan,
                roughCut: roughCut,
                transcription: transcription
            ))
        }

        // Score
        let criticalFails = checks.filter { !$0.passed && $0.severity == .critical }.count
        let warningFails = checks.filter { !$0.passed && $0.severity == .warning }.count
        let score = max(0, 100 - criticalFails * 30 - warningFails * 10)
        let blockingFails = checks.filter { !$0.passed && $0.blocksExport }.count
        let passed = criticalFails == 0 && blockingFails == 0 && score >= 80

        return QualityReport(checks: checks, passed: passed, score: score)
    }

    private static func isSpeechLike(_ segment: TranscriptSegment) -> Bool {
        switch segment.segmentType {
        case .speech, .contentSentence, .suspectedRestart, .suspectedDuplicate:
            return true
        case .silence, .filler, .editCommand:
            return false
        }
    }

    private static func transcriptQualityConfidence(_ segment: TranscriptSegment) -> Float {
        segment.rawConfidence ?? segment.confidence
    }

    private static func transcriptGateConfidence(_ segment: TranscriptSegment) -> Float {
        let rawConfidence = transcriptQualityConfidence(segment)
        guard let raw = segment.rawConfidence,
              segment.confidence > raw + 0.10,
              !containsUnresolvedTranscriptArtifact(segment.text) else {
            return rawConfidence
        }

        return segment.confidence
    }

    private static func overlaps(
        segmentStart: Double,
        segmentEnd: Double,
        range: TimelineRange
    ) -> Bool {
        min(segmentEnd, range.endTime) > max(segmentStart, range.startTime)
    }

    private static func intersectionDuration(
        start: Double,
        end: Double,
        range: TimelineRange
    ) -> Double {
        max(0, min(end, range.endTime) - max(start, range.startTime))
    }

    private static func captionedKeptDuration(
        for segment: TranscriptSegment,
        includedRanges: [TimelineRange],
        captions: [CaptionSegment]
    ) -> Double {
        let intervals = includedRanges.flatMap { keepRange in
            captions.compactMap { caption -> TimelineRange? in
                let start = max(segment.startTime, keepRange.startTime, caption.startTime)
                let end = min(segment.endTime, keepRange.endTime, caption.endTime)
                guard end > start else { return nil }
                return TimelineRange(startTime: start, endTime: end)
            }
        }

        return mergedDuration(intervals)
    }

    private static func includedRangesForQuality(_ roughCut: RoughCutResult) -> [TimelineRange] {
        let ranges = TimelineRangeNormalizer.includedRanges(
            from: roughCut.decisions,
            assetDuration: roughCut.originalDuration
        )
        if ranges.isEmpty,
           roughCut.decisions.isEmpty,
           roughCut.originalDuration > 0 {
            return [TimelineRange(startTime: 0, endTime: roughCut.originalDuration)]
        }
        return ranges
    }

    private static func mergedDuration(_ ranges: [TimelineRange]) -> Double {
        guard !ranges.isEmpty else { return 0 }

        let sorted = ranges.sorted { $0.startTime < $1.startTime }
        var merged: [TimelineRange] = []

        for range in sorted {
            guard let last = merged.last else {
                merged.append(range)
                continue
            }

            if range.startTime <= last.endTime {
                merged[merged.count - 1] = TimelineRange(
                    startTime: last.startTime,
                    endTime: max(last.endTime, range.endTime)
                )
            } else {
                merged.append(range)
            }
        }

        return merged.reduce(0.0) { total, range in
            total + max(0, range.endTime - range.startTime)
        }
    }

    private static func isAudioOnlySilenceCut(_ decision: RoughCutDecision) -> Bool {
        decision.linkedTranscriptText == nil
            && decision.reason.localizedStandardContains("silence")
    }

    private static func containsUnresolvedTranscriptArtifact(_ text: String) -> Bool {
        let patterns = [
            #"\b(BAP|Bolding|Kolding)\b"#,
            #"\bby\s+Cording\b"#,
            #"\bby\s+Holding\b"#,
            #"^Holding\s+topluluğu\b"#,
            #"\b(Way|Vay)\s+coin\b"#,
            #"\b(vay|vip|var)\s+Kolding\b"#,
            #"\btoplu\s+vay\s+Coding\b"#,
            #"\bkurdun\s+koy\s+duymayan\b"#,
            #"dövün\s+çıkarabilsin"#,
            #"\bVPN\s+çevire"#,
            #"\bMHP\s*'?\s*ye\b"#,
            #"\byorumlara\s+(vay|vip|var)\s+biraz\b"#,
            #"\byorumları\s+(vay|vip|var)\s+yaz\b"#,
            #"\bistersen\s+yorumları\b"#,
            #"\byorumları\s+Vibe\s+yazıp\b"#,
            #"^(vay|vip|var)\s+biraz\s+birlikte\b"#,
            #"\bcod\b"#,
            #"\bVP\b"#,
            #"\bfikirlerin\s+en\b"#,
            #"\bfikirlerine\s+MVP'ye\b"#,
            #"\bürün\s+yapabilirsin\s+MVP\s+çıkarabilsin\b"#,
            #"\bulaş\s+abil\b"#,
            #"\bAnd\s+roid\s*'\s*de\b"#,
            #"\b(App|Apple)\s+Store\s*'\s*da\b"#,
            #"\bweb\s+e\b"#,
            #"\be\s*'?\s*ye\s+anlatmay[iı]\b"#,
            #"\byayınlayabilir\s+sin\s+ler\b"#,
            #"\bulaşabilsin\s+ler\b"#,
            #"\b(göndere|çevir|çevire)\s+bil\s+sin"#,
            #"\bg\s+bilmeyen\b"#,
            #"^'ye\b"#,
            #"\s'\s*[ade]\b"#
        ]

        return patterns.contains { pattern in
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                return false
            }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            return regex.firstMatch(in: text, options: [], range: range) != nil
        }
    }

    private static func captionTimingTokensAlign(_ caption: CaptionSegment) -> Bool {
        let displayWords = normalizedTimingWords(caption.text)
        let timingWords = caption.wordTimings.map { normalizedTimingToken($0.word) }
        guard !displayWords.isEmpty, displayWords.count == timingWords.count else { return false }
        return zip(displayWords, timingWords).allSatisfy(==)
    }

    private static func normalizedTimingWords(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map { normalizedTimingToken(String($0)) }
    }

    private static func normalizedTimingToken(_ word: String) -> String {
        word
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    private static func percent(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(0)))
    }

    private static func maxEffectsPerMinute(for template: TemplateConfig) -> Double {
        if template.id == "tech_influencer" { return 65 }
        return switch template.intensity {
        case .low:
            30
        case .medium:
            45
        case .high:
            75
        }
    }

    private static func techInfluencerPromptChecks(
        captions: [CaptionSegment],
        editPlan: EditPlan,
        roughCut: RoughCutResult,
        transcription: TranscriptionResult?
    ) -> [QualityCheck] {
        var checks: [QualityCheck] = []
        let decisions = editPlan.decisions
        let reasons = Set(decisions.map(\.reason))
        let verification = TechInfluencerEditPlanVerifier.verify(
            captions: captions,
            decisions: decisions,
            transcription: transcription
        )

        let randomViralEffects = decisions.filter { decision in
            decision.type == .flash
                || decision.type == .shake
                || decision.reason.localizedStandardContains("viral")
        }
        checks.append(QualityCheck(
            name: "Tech prompt random effects",
            passed: randomViralEffects.isEmpty,
            detail: randomViralEffects.isEmpty
                ? "No viral flash/shake/random effects"
                : "\(randomViralEffects.count) non-tech random effect(s) present",
            severity: randomViralEffects.isEmpty ? .info : .critical,
            blocksExport: !randomViralEffects.isEmpty
        ))

        let invalidWhooshes = decisions.filter { decision in
            guard decision.type == .sfx,
                  SFXAssetManager.sound(for: decision) == .whoosh else { return false }
            let reason = decision.reason.lowercased()
            return !(reason.contains("hook")
                || reason.contains("topic")
                || reason.contains("reveal")
                || reason.contains("transition"))
        }
        checks.append(QualityCheck(
            name: "Tech prompt whoosh intent",
            passed: invalidWhooshes.isEmpty,
            detail: invalidWhooshes.isEmpty
                ? "Whooshes are tied to hook/topic/reveal/transition events"
                : "\(invalidWhooshes.count) whoosh cue(s) without semantic movement",
            severity: invalidWhooshes.isEmpty ? .info : .critical,
            blocksExport: !invalidWhooshes.isEmpty
        ))

        let hookExpected = (verification.eventKindCounts["hook"] ?? 0) > 0
        let hookComboPassed = !hookExpected || (
            TechInfluencerEffectCue.requiredReasons(for: .hook).allSatisfy { reasons.contains($0) }
        )
        checks.append(QualityCheck(
            name: "Tech prompt hook combo",
            passed: hookComboPassed,
            detail: hookComboPassed
                ? "Hook has two-phase zoom and impact tied to the spoken phrase; riser is optional"
                : "Hook caption exists but two-phase zoom/impact combo is missing",
            severity: hookComboPassed ? .info : .critical,
            blocksExport: !hookComboPassed
        ))

        let revealExpected = captions.contains { caption in
            caption.role == .reveal || caption.sceneBehavior == .punchIn
        }
        let revealComboPassed = !revealExpected || (
            TechInfluencerEffectCue.requiredReasons(for: .reveal).allSatisfy { reasons.contains($0) }
        )
        checks.append(QualityCheck(
            name: "Tech prompt reveal combo",
            passed: revealComboPassed,
            detail: revealComboPassed
                ? "Reveal has zoom/impact tied to the payoff word"
                : "Reveal caption exists but zoom/impact cue is incomplete",
            severity: revealComboPassed ? .info : .critical,
            blocksExport: !revealComboPassed
        ))

        let zoomViolations = closeZoomPairs(decisions)
        checks.append(QualityCheck(
            name: "Tech prompt zoom spacing",
            passed: zoomViolations == 0,
            detail: zoomViolations == 0
                ? "Zoom spacing respects Tech prompt density"
                : "\(zoomViolations) zoom pair(s) closer than 2.5s",
            severity: zoomViolations == 0 ? .info : .critical,
            blocksExport: zoomViolations > 0
        ))

        let weakZooms = decisions.filter { decision in
            guard decision.type == .zoom,
                  let requiredScale = requiredTechZoomPeakScale(for: decision) else {
                return false
            }
            return VisualEffectTuning.zoomPeakScale(for: decision) < requiredScale
        }
        checks.append(QualityCheck(
            name: "Tech prompt zoom strength",
            passed: weakZooms.isEmpty,
            detail: weakZooms.isEmpty
                ? "Semantic zooms render at prompt-level visible strength"
                : "\(weakZooms.count) zoom cue(s) too weak: \(weakZooms.prefix(3).map(\.reason).joined(separator: ", "))",
            severity: weakZooms.isEmpty ? .info : .critical,
            blocksExport: !weakZooms.isEmpty
        ))

        let revealSpacingViolations = closeRevealComboPairs(decisions)
        checks.append(QualityCheck(
            name: "Tech prompt reveal combo spacing",
            passed: revealSpacingViolations == 0,
            detail: revealSpacingViolations == 0
                ? "Big reveal combos respect 3s spacing"
                : "\(revealSpacingViolations) reveal combo pair(s) closer than 3s",
            severity: revealSpacingViolations == 0 ? .info : .critical,
            blocksExport: revealSpacingViolations > 0
        ))

        let sfxCount = decisions.filter { $0.type == .sfx }.count
        let duration = roughCut.cleanDuration > 0 ? roughCut.cleanDuration : roughCut.originalDuration
        let decisionLimit = techDecisionLimit(for: duration)
        checks.append(QualityCheck(
            name: "Tech prompt decision count",
            passed: decisions.count <= decisionLimit,
            detail: "\(decisions.count) effect decision(s), max \(decisionLimit) for duration",
            severity: decisions.count <= decisionLimit ? .info : .critical,
            blocksExport: decisions.count > decisionLimit
        ))

        let sfxLimit = techSFXLimit(for: duration)
        checks.append(QualityCheck(
            name: "Tech prompt SFX count",
            passed: sfxCount <= sfxLimit,
            detail: "\(sfxCount) SFX cue(s), max \(sfxLimit) for duration",
            severity: sfxCount <= sfxLimit ? .info : .critical,
            blocksExport: sfxCount > sfxLimit
        ))

        let windowMax = maxEffectsInSlidingWindow(decisions, window: 10.0)
        let windowLimit = editPlan.template.editGrammar.maxEffectsPerTenSeconds
        checks.append(QualityCheck(
            name: "Tech prompt 10s density",
            passed: windowMax <= windowLimit,
            detail: "\(windowMax) effect cue(s) in busiest 10s window, max \(windowLimit)",
            severity: windowMax <= windowLimit ? .info : .critical,
            blocksExport: windowMax > windowLimit
        ))

        let exportReadyDecisions = techExportReadyDecisions(decisions: decisions, roughCut: roughCut)
        let exportWindowMax = maxEffectsInSlidingWindow(exportReadyDecisions, window: 10.0)
        checks.append(QualityCheck(
            name: "Tech export-ready 10s density",
            passed: exportWindowMax <= windowLimit,
            detail: "\(exportWindowMax) exported effect cue(s) in busiest 10s window, max \(windowLimit)",
            severity: exportWindowMax <= windowLimit ? .info : .critical,
            blocksExport: exportWindowMax > windowLimit
        ))

        let duplicateCueViolations = duplicateSemanticCueViolations(decisions)
        checks.append(QualityCheck(
            name: "Tech prompt duplicate cue guard",
            passed: duplicateCueViolations.isEmpty,
            detail: duplicateCueViolations.isEmpty
                ? "No duplicate semantic cue repeated on the same event"
                : "\(duplicateCueViolations.count) duplicate cue group(s): \(duplicateCueViolations.prefix(3).joined(separator: ", "))",
            severity: duplicateCueViolations.isEmpty ? .info : .critical,
            blocksExport: !duplicateCueViolations.isEmpty
        ))

        let captionVariety = techCaptionVisualVariety(captions)
        checks.append(QualityCheck(
            name: "Tech caption visual variety",
            passed: captionVariety.passed,
            detail: captionVariety.detail,
            severity: captionVariety.passed ? .info : .critical,
            blocksExport: !captionVariety.passed
        ))

        let exportSurvivability = techExportReadySemanticSurvivability(
            captions: captions,
            decisions: decisions,
            roughCut: roughCut,
            transcription: transcription
        )
        checks.append(QualityCheck(
            name: "Tech export-ready semantic survivability",
            passed: exportSurvivability.passed,
            detail: exportSurvivability.detail,
            severity: exportSurvivability.passed ? .info : .critical,
            blocksExport: !exportSurvivability.passed
        ))

        let unsupportedDetail = verification.unsupportedDecisions
            .prefix(3)
            .map { "\($0.reason) @ \($0.time.formatted(.number.precision(.fractionLength(2))))s" }
            .joined(separator: ", ")
        let unanchoredDetail = verification.unanchoredDecisions
            .prefix(3)
            .map { "\($0.reason) @ \($0.time.formatted(.number.precision(.fractionLength(2))))s" }
            .joined(separator: ", ")
        let anchoringDetail: String
        if verification.eventAnchoringPassed {
            anchoringDetail = "\(verification.decisionCount) decision(s) tied to \(verification.eventCount) semantic timeline event(s)"
        } else {
            anchoringDetail = [
                verification.unsupportedDecisions.isEmpty ? nil : "unsupported: \(unsupportedDetail)",
                verification.unanchoredDecisions.isEmpty ? nil : "unanchored: \(unanchoredDetail)"
            ]
            .compactMap { $0 }
            .joined(separator: " | ")
        }
        checks.append(QualityCheck(
            name: "Tech event anchoring",
            passed: verification.eventAnchoringPassed,
            detail: anchoringDetail,
            severity: verification.eventAnchoringPassed ? .info : .critical,
            blocksExport: !verification.eventAnchoringPassed
        ))

        checks.append(QualityCheck(
            name: "Tech event combos",
            passed: verification.comboPassed,
            detail: verification.comboPassed
                ? "Required Tech Influencer event combos are complete"
                : "Combo issue(s): \(verification.comboIssues.joined(separator: ", "))",
            severity: verification.comboPassed ? .info : .critical,
            blocksExport: !verification.comboPassed
        ))

        return checks
    }

    private static func requiredTechZoomPeakScale(for decision: EditDecision) -> Double? {
        TechInfluencerEffectCue(reason: decision.reason)?.requiredPeakScale
    }

    private static func techDecisionLimit(for duration: Double) -> Int {
        if duration <= 12 { return 7 }
        if duration <= 40 { return 9 }
        return min(18, max(11, Int(ceil(duration / 5.5))))
    }

    private static func techCaptionVisualVariety(_ captions: [CaptionSegment]) -> (passed: Bool, detail: String) {
        guard captions.count >= 5 else {
            return (true, "Short Tech edit has too few captions for variety gate")
        }

        let uniqueStyleCount = Set(captions.map(\.style)).count
        let uniqueVerticalBands = Set(captions.map { CaptionLayoutTuning.verticalBandKey(for: $0) }).count
        let longestStyleRun = longestConsecutiveStyleRun(captions)
        let passed = uniqueStyleCount >= 3 && uniqueVerticalBands >= 3 && longestStyleRun <= 3

        if passed {
            return (
                true,
                "\(uniqueStyleCount) caption style(s), \(uniqueVerticalBands) safe vertical band(s), max same-style run \(longestStyleRun)"
            )
        }

        return (
            false,
            "Needs >=3 styles, >=3 safe vertical bands, max same-style run <=3; got styles=\(uniqueStyleCount), bands=\(uniqueVerticalBands), run=\(longestStyleRun)"
        )
    }

    private static func longestConsecutiveStyleRun(_ captions: [CaptionSegment]) -> Int {
        let sorted = captions.sorted { $0.startTime < $1.startTime }
        guard let first = sorted.first else { return 0 }

        var currentStyle = first.style
        var currentRun = 0
        var longestRun = 0

        for caption in sorted {
            if caption.style == currentStyle {
                currentRun += 1
            } else {
                longestRun = max(longestRun, currentRun)
                currentStyle = caption.style
                currentRun = 1
            }
        }

        return max(longestRun, currentRun)
    }

    private static func techExportReadySemanticSurvivability(
        captions: [CaptionSegment],
        decisions: [EditDecision],
        roughCut: RoughCutResult,
        transcription: TranscriptionResult?
    ) -> (passed: Bool, detail: String) {
        let sourceVerification = TechInfluencerEditPlanVerifier.verify(
            captions: captions,
            decisions: decisions,
            transcription: transcription
        )

        let ranges = includedRangesForQuality(roughCut)
        let mapping = TimelineMapper.buildMapping(from: ranges)
        let cleanDuration = ranges.reduce(0.0) { $0 + max(0, $1.duration) }
        let exportReadyCaptions = TimelineMapper.exportReadyCaptions(
            TimelineMapper.remapCaptions(captions, mapping: mapping),
            totalDuration: cleanDuration
        )
        let exportReadyTranscription = transcription.map {
            TimelineMapper.remapTranscription($0, mapping: mapping)
        }
        let exportReadyDecisions = techExportReadyDecisions(decisions: decisions, roughCut: roughCut)

        let exportVerification = TechInfluencerEditPlanVerifier.verify(
            captions: exportReadyCaptions,
            decisions: exportReadyDecisions,
            transcription: exportReadyTranscription
        )
        let missingReasons = semanticDecisionReasonLosses(
            source: decisions,
            exportReady: exportReadyDecisions,
            sourceVerification: sourceVerification,
            exportVerification: exportVerification
        )
        let eventCoveragePassed = semanticEventCoveragePassed(
            source: sourceVerification.eventKindCounts,
            exportReady: exportVerification.eventKindCounts
        )
        let passed = eventCoveragePassed
            && exportVerification.eventAnchoringPassed
            && exportVerification.comboPassed
            && missingReasons.isEmpty

        if passed {
            return (
                true,
                "\(exportReadyCaptions.count)/\(captions.count) caption(s), \(exportReadyDecisions.count)/\(decisions.count) decision(s), \(exportVerification.eventCount) semantic event(s) survive export remap"
            )
        }

        var details: [String] = []
        if !eventCoveragePassed {
            details.append("events \(exportVerification.eventCount)/\(sourceVerification.eventCount)")
        }
        if !exportVerification.unanchoredDecisions.isEmpty {
            let unanchored = exportVerification.unanchoredDecisions
                .prefix(3)
                .map(\.reason)
                .joined(separator: ", ")
            details.append("unanchored after remap: \(unanchored)")
        }
        if !exportVerification.missingCombos.isEmpty {
            details.append("missing combos: \(exportVerification.missingCombos.prefix(3).joined(separator: ", "))")
        }
        if !exportVerification.forbiddenCombos.isEmpty {
            details.append("forbidden combos: \(exportVerification.forbiddenCombos.prefix(3).joined(separator: ", "))")
        }
        if !missingReasons.isEmpty {
            details.append("lost semantic cue(s): \(missingReasons.prefix(4).joined(separator: ", "))")
        }
        return (false, details.joined(separator: " | "))
    }

    private static func techExportReadyDecisions(
        decisions: [EditDecision],
        roughCut: RoughCutResult
    ) -> [EditDecision] {
        let ranges = includedRangesForQuality(roughCut)
        let mapping = TimelineMapper.buildMapping(from: ranges)
        let sourceTimedDecisions = decisions.filter { !ExportService.isCleanTimelineDecision($0) }
        let cleanTimedDecisions = decisions.filter { ExportService.isCleanTimelineDecision($0) }
        let remappedDecisions = TimelineMapper.remapEditDecisions(
            sourceTimedDecisions,
            mapping: mapping
        ) + cleanTimedDecisions
        return TechInfluencerEditDecisionNormalizer.exportReadyDecisions(
            remappedDecisions,
            templateId: "tech_influencer"
        )
    }

    private static func semanticDecisionReasonLosses(
        source: [EditDecision],
        exportReady: [EditDecision],
        sourceVerification: TechInfluencerEditPlanVerification,
        exportVerification: TechInfluencerEditPlanVerification
    ) -> [String] {
        let sourceCounts = semanticDecisionReasonCounts(source)
        let exportCounts = semanticDecisionReasonCounts(exportReady)
        let compressedRevealEvents = max(
            0,
            (sourceVerification.eventKindCounts["reveal"] ?? 0)
                - (exportVerification.eventKindCounts["reveal"] ?? 0)
        )

        return sourceCounts.keys.sorted().compactMap { reason in
            let missing = (sourceCounts[reason] ?? 0) - (exportCounts[reason] ?? 0)
            let allowedLoss = isRevealComboReason(reason) ? compressedRevealEvents : 0
            guard missing > allowedLoss else { return nil }
            return "\(reason) x\(missing)"
        }
    }

    private static func semanticEventCoveragePassed(
        source: [String: Int],
        exportReady: [String: Int]
    ) -> Bool {
        for kind in ["hook", "topicShift", "uiAction", "warning", "cta"] {
            if (source[kind] ?? 0) > 0, (exportReady[kind] ?? 0) == 0 {
                return false
            }
        }
        if (source["reveal"] ?? 0) > 0, (exportReady["reveal"] ?? 0) == 0 {
            return false
        }
        return true
    }

    private static func isRevealComboReason(_ reason: String) -> Bool {
        TechInfluencerEffectCue(reason: reason)?.isRevealComboCue == true
    }

    private static func semanticDecisionReasonCounts(_ decisions: [EditDecision]) -> [String: Int] {
        decisions.reduce(into: [:]) { counts, decision in
            guard TechInfluencerEffectCue.semanticReasons.contains(decision.reason) else { return }
            counts[decision.reason, default: 0] += 1
        }
    }

    private static func maxEffectsInSlidingWindow(_ decisions: [EditDecision], window: Double) -> Int {
        let times = decisions.map(\.time).sorted()
        guard !times.isEmpty else { return 0 }
        var maxCount = 0
        var startIndex = 0
        for endIndex in times.indices {
            while times[endIndex] - times[startIndex] > window {
                startIndex += 1
            }
            maxCount = max(maxCount, endIndex - startIndex + 1)
        }
        return maxCount
    }

    private static func duplicateSemanticCueViolations(_ decisions: [EditDecision]) -> [String] {
        let semanticDecisions = decisions
            .filter { TechInfluencerEffectCue.semanticReasons.contains($0.reason) }
            .sorted { $0.time < $1.time }
        let grouped = Dictionary(grouping: semanticDecisions, by: \.reason)
        return grouped.compactMap { entry in
            let reason = entry.key
            let groupedDecisions = entry.value
            guard let cue = TechInfluencerEffectCue(reason: reason) else { return nil }
            let minimumSpacing = duplicateCueMinimumSpacing(for: cue)
            let sorted = groupedDecisions.sorted { $0.time < $1.time }
            for index in 1..<sorted.count where sorted[index].time - sorted[index - 1].time < minimumSpacing {
                return reason
            }
            return nil
        }
        .sorted()
    }

    private static func duplicateCueMinimumSpacing(for cue: TechInfluencerEffectCue) -> Double {
        switch cue.eventKind {
        case .hook:
            return 1.50
        case .topicShift:
            return 3.00
        case .reveal:
            return 3.00
        case .uiAction:
            return 1.50
        case .keyword:
            return 2.00
        case .warning:
            return 2.00
        case .cta:
            return 4.00
        }
    }

    private static func closeRevealComboPairs(_ decisions: [EditDecision]) -> Int {
        let revealImpacts = decisions
            .filter { $0.type == .sfx && $0.reason == TechInfluencerEffectCue.techRevealImpactSFX.reason }
            .sorted { $0.time < $1.time }
        guard revealImpacts.count >= 2 else { return 0 }

        var violations = 0
        for index in 1..<revealImpacts.count where revealImpacts[index].time - revealImpacts[index - 1].time < 3.0 {
            violations += 1
        }
        return violations
    }

    private static func techSFXLimit(for duration: Double) -> Int {
        if duration <= 12 { return 3 }
        if duration <= 40 { return 5 }
        return min(12, max(6, Int(ceil(duration / 7.5))))
    }

    private static func closeZoomPairs(_ decisions: [EditDecision]) -> Int {
        let zooms = decisions
            .filter { $0.type == .zoom }
            .sorted { $0.time < $1.time }
        guard zooms.count >= 2 else { return 0 }

        var violations = 0
        for index in 1..<zooms.count where zoomsConflict(zooms[index - 1], zooms[index]) {
            if isAllowedHookZoomPair(zooms[index - 1], zooms[index]) { continue }
            if isProtectedAfterHookZoomPair(zooms: zooms, index: index) { continue }
            violations += 1
        }
        return violations
    }

    private static func zoomsConflict(_ lhs: EditDecision, _ rhs: EditDecision) -> Bool {
        let lhsEnd = lhs.time + max(0, lhs.duration)
        let rhsEnd = rhs.time + max(0, rhs.duration)
        let overlap = min(lhsEnd, rhsEnd) - max(lhs.time, rhs.time)
        if overlap > 0 { return true }
        let visualGap = max(rhs.time, lhs.time) - min(lhsEnd, rhsEnd)
        return visualGap < 0.85
    }

    private static func isAllowedHookZoomPair(_ first: EditDecision, _ second: EditDecision) -> Bool {
        let reasons = Set([first.reason, second.reason])
        return first.type == .zoom
            && second.type == .zoom
            && reasons == [
                TechInfluencerEffectCue.hookSlowPushInZoom.reason,
                TechInfluencerEffectCue.hookSentenceBackZoom.reason
            ]
    }

    private static func isProtectedAfterHookZoomPair(zooms: [EditDecision], index: Int) -> Bool {
        let previous = zooms[index - 1]
        guard previous.reason == TechInfluencerEffectCue.hookSentenceBackZoom.reason,
              zooms[..<(index - 1)].contains(where: { isAllowedHookZoomPair($0, previous) }) else {
            return false
        }

        return zooms[index].time - (previous.time + previous.duration) >= 0.90
    }
}
