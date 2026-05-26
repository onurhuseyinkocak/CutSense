import Foundation

struct RoughCutDecision: Sendable, Identifiable {
    let id = UUID()
    let startTime: Double
    let endTime: Double
    let action: CutAction
    let reason: String
    let confidence: Float
    let linkedTranscriptText: String?
    let requiresReview: Bool

    /// Whether this decision contributes a segment to the final clean timeline.
    /// keep + reviewRequired + replaceWithBetterTake all stay in the timeline.
    var isTimelineIncluded: Bool {
        switch action {
        case .keep, .reviewRequired, .replaceWithBetterTake, .mergeWithNext, .addAudioFade:
            return true
        case .cut, .trimStart, .trimEnd:
            return false
        }
    }
}

enum CutAction: String, Codable, Sendable {
    case keep
    case cut
    case trimStart = "trim_start"
    case trimEnd = "trim_end"
    case replaceWithBetterTake = "replace_with_better_take"
    case mergeWithNext = "merge_with_next"
    case addAudioFade = "add_audio_fade"
    case reviewRequired = "review_required"
}

struct RoughCutResult: Sendable {
    let decisions: [RoughCutDecision]
    let originalDuration: Double
    let cleanDuration: Double
    let keepSegments: [RoughCutDecision]
    let cutSegments: [RoughCutDecision]
    let reviewSegments: [RoughCutDecision]
}

struct TechInfluencerTimelinePlan: Sendable {
    struct Event: Sendable {
        enum Kind: String, Sendable {
            case hook
            case topicShift
            case reveal
            case uiAction
            case keyword
            case warning
            case cta
        }

        let kind: Kind
        let anchorTime: Double
        let sourceStart: Double
        let sourceEnd: Double
        let text: String
        let confidence: Float
        let reason: String
    }

    let events: [Event]
    let sourceDuration: Double
}

enum TechInfluencerTimelineAnalyzer {
    static func analyze(
        transcription: TranscriptionResult,
        audioAnalysis: AudioAnalysisResult
    ) -> TechInfluencerTimelinePlan {
        let speechSegments = transcription.segments
            .filter(isUsableSpeech)
            .sorted { $0.startTime < $1.startTime }
        guard !speechSegments.isEmpty else {
            return TechInfluencerTimelinePlan(events: [], sourceDuration: audioAnalysis.duration)
        }

        var events: [TechInfluencerTimelinePlan.Event] = []
        var lastNoticeableTime: Double = -10
        var lastKeywordTime: Double = -10
        var lastKeywordIndex: Int?
        var lastKeywordScore = 0
        var keywordCount = 0
        var lastTopicShiftTime: Double = -10
        var lastRevealAnchorTime: Double = -10
        var lastRevealIndex: Int?
        var revealCount = 0
        let maxRevealCount = audioAnalysis.duration <= 40
            ? 1
            : min(3, max(1, Int(ceil(audioAnalysis.duration / 35.0))))
        let maxKeywordCount = max(1, min(3, Int(ceil(audioAnalysis.duration / 20.0))))

        for (index, segment) in speechSegments.enumerated() {
            let signals = semanticSignals(
                for: segment,
                index: index,
                totalCount: speechSegments.count,
                sourceDuration: audioAnalysis.duration
            )

            for signal in signals {
                let kind = signal.kind
                let anchor = signal.anchorTime

                switch kind {
                case .hook:
                    events.append(event(kind: kind, segment: segment, anchor: anchor, reason: signal.reason))
                    lastNoticeableTime = anchor
                case .cta:
                    guard anchor - lastNoticeableTime >= 1.2 else { continue }
                    events.append(event(kind: kind, segment: segment, anchor: anchor, reason: signal.reason))
                    lastNoticeableTime = anchor
                case .reveal:
                    if let lastRevealIndex,
                       anchor - lastRevealAnchorTime < 3.0 {
                        let currentPriority = revealPriority(segment.text)
                        let existingPriority = revealPriority(events[lastRevealIndex].text)
                        if currentPriority > existingPriority {
                            events[lastRevealIndex] = event(kind: kind, segment: segment, anchor: anchor, reason: signal.reason)
                            lastRevealAnchorTime = anchor
                            lastNoticeableTime = anchor
                        }
                        continue
                    }

                    let isCoupledToPreviousUI = events.last?.kind == .uiAction
                        && events.last?.text == segment.text
                        && anchor - lastNoticeableTime >= 0.65
                    guard revealCount < maxRevealCount,
                          isCoupledToPreviousUI || anchor - lastNoticeableTime >= 1.0 else { continue }
                    events.append(event(kind: kind, segment: segment, anchor: anchor, reason: signal.reason))
                    lastRevealIndex = events.count - 1
                    lastRevealAnchorTime = anchor
                    revealCount += 1
                    lastNoticeableTime = anchor
                case .topicShift:
                    guard anchor - lastTopicShiftTime >= 4.0,
                          anchor - lastNoticeableTime >= 1.2 else { continue }
                    events.append(event(kind: kind, segment: segment, anchor: anchor, reason: signal.reason))
                    lastTopicShiftTime = anchor
                    lastNoticeableTime = anchor
                case .uiAction:
                    guard anchor - lastNoticeableTime >= 1.0 else { continue }
                    events.append(event(kind: kind, segment: segment, anchor: anchor, reason: signal.reason))
                    lastNoticeableTime = anchor
                case .warning:
                    guard anchor - lastNoticeableTime >= 1.0 else { continue }
                    events.append(event(kind: kind, segment: segment, anchor: anchor, reason: signal.reason))
                    lastNoticeableTime = anchor
                case .keyword:
                    guard signal.score >= 58,
                          anchor - lastNoticeableTime >= 1.0 else { continue }

                    if let lastKeywordIndex,
                       anchor - lastKeywordTime < 3.2 {
                        if signal.score > lastKeywordScore {
                            events[lastKeywordIndex] = event(kind: kind, segment: segment, anchor: anchor, reason: signal.reason)
                            lastKeywordTime = anchor
                            lastKeywordScore = signal.score
                            lastNoticeableTime = anchor
                        }
                        continue
                    }

                    let bypassKeywordCap = signal.score >= 66 && anchor - lastKeywordTime >= 6.0
                    guard (keywordCount < maxKeywordCount || bypassKeywordCap),
                          anchor - lastKeywordTime >= 3.0 else { continue }
                    events.append(event(kind: kind, segment: segment, anchor: anchor, reason: signal.reason))
                    lastKeywordIndex = events.count - 1
                    keywordCount += 1
                    lastKeywordScore = signal.score
                    lastKeywordTime = anchor
                    lastNoticeableTime = anchor
                }
            }
        }

        return TechInfluencerTimelinePlan(events: events, sourceDuration: audioAnalysis.duration)
    }

    private static func isUsableSpeech(_ segment: TranscriptSegment) -> Bool {
        let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty,
              segmentQualityConfidence(segment) >= 0.45,
              segment.endTime > segment.startTime else {
            return false
        }
        switch segment.segmentType {
        case .speech, .contentSentence, .suspectedRestart, .suspectedDuplicate:
            return true
        case .silence, .filler, .editCommand:
            return false
        }
    }

    private struct SemanticSignal {
        let kind: TechInfluencerTimelinePlan.Event.Kind
        let anchorTime: Double
        let score: Int
        let reason: String
        let text: String
    }

    private static func semanticSignals(
        for segment: TranscriptSegment,
        index: Int,
        totalCount: Int,
        sourceDuration: Double
    ) -> [SemanticSignal] {
        let isOpening = index == 0 && segment.startTime < 3.0
        let isClosingSection = index >= max(1, Int(Double(totalCount) * 0.72))

        let hasCTA = containsCTAPhrase(in: segment.text)
        let hasWarning = isStrongWarning(segment.text)
        let hasReveal = isMeaningfulReveal(segment.text)
        let hasUIAction = hasDirectUIAction(segment.text)
        let hasKeyword = containsPhrase(in: segment.text, phrases: techKeywordTriggers)
        let hasTopicShift = startsTopicShift(segment.text)
        let forceClosingCTA = (hasCTA && (isClosingSection || isClosingCTAWindow(segment, sourceDuration: sourceDuration)))

        var candidates: [SemanticSignal] = []
        if isOpening && isHookWorthy(segment.text) {
            candidates.append(signal(
                kind: .hook,
                segment: segment,
                score: 100 + (hasKeyword ? 6 : 0),
                reason: "opening hook"
            ))
        }
        if hasWarning {
            candidates.append(signal(kind: .warning, segment: segment, score: 86, reason: "warning/problem phrase"))
        }
        if hasUIAction {
            candidates.append(signal(kind: .uiAction, segment: segment, score: 82, reason: "UI/action phrase"))
        }
        if hasReveal {
            candidates.append(signal(
                kind: .reveal,
                segment: segment,
                score: 78 + revealPriority(segment.text),
                reason: "result/reveal phrase"
            ))
        }
        if forceClosingCTA {
            candidates.append(signal(
                kind: .cta,
                segment: segment,
                score: (forceClosingCTA ? 120 : 74) + (hasCTA ? 16 : 0) + (isClosingSection ? 6 : 0),
                reason: hasCTA ? "explicit CTA phrase" : "closing CTA"
            ))
        }
        if hasTopicShift {
            candidates.append(signal(
                kind: .topicShift,
                segment: segment,
                score: 62 + (speechRate(in: segment) >= 3.2 ? 5 : 0),
                reason: "new section or pace-change phrase"
            ))
        }
        if hasKeyword && !forceClosingCTA {
            let importance = keywordImportance(segment.text)
            candidates.append(signal(
                kind: .keyword,
                segment: segment,
                score: 50 + importance * 4,
                reason: importance >= 3 ? "high-value tech keyword phrase" : "tech keyword phrase"
            ))
        }

        return filteredSemanticSignals(candidates)
    }

    private static func signal(
        kind: TechInfluencerTimelinePlan.Event.Kind,
        segment: TranscriptSegment,
        score: Int,
        reason: String
    ) -> SemanticSignal {
        SemanticSignal(
            kind: kind,
            anchorTime: anchorTime(for: kind, segment: segment),
            score: score,
            reason: reason,
            text: segment.text
        )
    }

    private static func filteredSemanticSignals(_ candidates: [SemanticSignal]) -> [SemanticSignal] {
        let ranked = candidates.sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return semanticPriority(lhs.kind) > semanticPriority(rhs.kind)
        }

        var selected: [SemanticSignal] = []
        for candidate in ranked {
            if selected.contains(where: { $0.kind == candidate.kind }) { continue }
            if selected.contains(where: { abs($0.anchorTime - candidate.anchorTime) < 0.55 }) { continue }
            if !selected.isEmpty,
               !allowsCompoundSignal(candidate, with: selected) {
                continue
            }
            if candidate.kind == .keyword,
               selected.contains(where: { semanticPriority($0.kind) >= semanticPriority(.uiAction) }) {
                continue
            }
            if candidate.kind == .topicShift,
               selected.contains(where: { semanticPriority($0.kind) >= semanticPriority(.uiAction) && abs($0.anchorTime - candidate.anchorTime) < 1.0 }) {
                continue
            }
            if candidate.kind != .hook,
               let hook = selected.first(where: { $0.kind == .hook }),
               abs(hook.anchorTime - candidate.anchorTime) < 1.2 {
                continue
            }
            selected.append(candidate)
            if selected.count == 2 { break }
        }

        return selected.sorted { $0.anchorTime < $1.anchorTime }
    }

    private static func allowsCompoundSignal(
        _ candidate: SemanticSignal,
        with selected: [SemanticSignal]
    ) -> Bool {
        guard selected.count == 1,
              let existing = selected.first,
              isUIRevealPair(existing.kind, candidate.kind) else {
            return false
        }

        let uiAction = existing.kind == .uiAction ? existing : candidate
        let reveal = existing.kind == .reveal ? existing : candidate
        let gap = reveal.anchorTime - uiAction.anchorTime
        guard !hasDelayedUIRevealBridge(uiAction.text) else { return false }
        return gap >= 0.65 && gap <= 3.05
    }

    private static func isUIRevealPair(
        _ lhs: TechInfluencerTimelinePlan.Event.Kind,
        _ rhs: TechInfluencerTimelinePlan.Event.Kind
    ) -> Bool {
        (lhs == .uiAction && rhs == .reveal)
            || (lhs == .reveal && rhs == .uiAction)
    }

    private static func semanticPriority(_ kind: TechInfluencerTimelinePlan.Event.Kind) -> Int {
        switch kind {
        case .hook: 100
        case .warning: 90
        case .reveal: 84
        case .uiAction: 82
        case .cta: 78
        case .topicShift: 62
        case .keyword: 50
        }
    }

    private static func isClosingCTAWindow(_ segment: TranscriptSegment, sourceDuration: Double) -> Bool {
        segment.startTime >= max(6.0, sourceDuration * 0.62)
    }

    private static func speechRate(in segment: TranscriptSegment) -> Double {
        let wordCount = Double(max(1, normalizedWords(in: segment.text).count))
        return wordCount / max(0.25, segment.endTime - segment.startTime)
    }

    private static func classify(
        _ segment: TranscriptSegment,
        index: Int,
        totalCount: Int
    ) -> TechInfluencerTimelinePlan.Event.Kind? {
        if index == 0 && segment.startTime < 3.0 { return .hook }

        let isClosingSection = index >= max(1, Int(Double(totalCount) * 0.72))
        if isClosingSection && containsCTAPhrase(in: segment.text) {
            return .cta
        }
        if containsPhrase(in: segment.text, phrases: warningTriggers) { return .warning }
        if isMeaningfulReveal(segment.text) { return .reveal }
        if hasDirectUIAction(segment.text) { return .uiAction }
        if startsTopicShift(segment.text) { return .topicShift }
        if containsPhrase(in: segment.text, phrases: techKeywordTriggers) { return .keyword }
        return nil
    }

    private static func event(
        kind: TechInfluencerTimelinePlan.Event.Kind,
        segment: TranscriptSegment,
        anchor: Double,
        reason: String
    ) -> TechInfluencerTimelinePlan.Event {
        TechInfluencerTimelinePlan.Event(
            kind: kind,
            anchorTime: max(segment.startTime, min(anchor, segment.endTime)),
            sourceStart: segment.startTime,
            sourceEnd: segment.endTime,
            text: segment.text,
            confidence: segmentQualityConfidence(segment),
            reason: reason
        )
    }

    private static func segmentQualityConfidence(_ segment: TranscriptSegment) -> Float {
        let qualityConfidence = segment.rawConfidence ?? segment.confidence
        guard let rawConfidence = segment.rawConfidence,
              segment.confidence > rawConfidence + 0.10,
              isTrustedTechPostProcessedText(segment.text) else {
            return qualityConfidence
        }
        return segment.confidence
    }

    private static func isTrustedTechPostProcessedText(_ text: String) -> Bool {
        let lower = text.lowercased()
        return [
            "vibe coding",
            "mvp",
            "app store",
            "web",
            "ürün",
            "urun",
            "kod bilmeyen",
            "yapay zeka",
            "yorumlara vibe",
            "vibe yazıp",
            "büyüyelim",
            "buyuyelim"
        ].contains { lower.localizedStandardContains($0) }
    }

    private static func anchorTime(
        for kind: TechInfluencerTimelinePlan.Event.Kind,
        segment: TranscriptSegment
    ) -> Double {
        switch kind {
        case .hook:
            return preferredHookAnchorTime(in: segment) ?? firstWordTime(in: segment)
        case .reveal:
            return preferredRevealAnchorTime(in: segment)
                ?? firstWordTime(in: segment)
        case .uiAction:
            return phraseAnchorTime(in: segment, phrases: uiActionAnchorTriggers)
                ?? phraseAnchorTime(in: segment, phrases: techKeywordTriggers)
                ?? firstWordTime(in: segment)
        case .keyword:
            return phraseAnchorTime(in: segment, phrases: techKeywordTriggers) ?? firstWordTime(in: segment)
        case .warning:
            return phraseAnchorTime(in: segment, phrases: warningTriggers) ?? firstWordTime(in: segment)
        case .topicShift:
            return firstWordTime(in: segment)
        case .cta:
            if let ctaAnchor = preferredCTAAnchorTime(in: segment) {
                return ctaAnchor
            }
            if segment.endTime - segment.startTime > 5.0 {
                return max(segment.startTime, segment.endTime - 0.20)
            }
            return phraseAnchorTime(in: segment, phrases: techKeywordTriggers)
                ?? max(segment.startTime, segment.endTime - 0.20)
        }
    }

    private static func firstWordTime(in segment: TranscriptSegment) -> Double {
        segment.wordTimings.first?.start ?? segment.startTime
    }

    private static func preferredHookAnchorTime(in segment: TranscriptSegment) -> Double? {
        phraseAnchorTime(in: segment, phrases: hookPayoffAnchorTriggers)
            ?? phraseAnchorTime(in: segment, phrases: hookAnchorTriggers)
    }

    private static func phraseAnchorTime(
        in segment: TranscriptSegment,
        phrases: [String]
    ) -> Double? {
        matchingAnchorTime(in: segment, phrases: phrases)
            ?? estimatedPhraseAnchorTime(in: segment.text, phrases: phrases, start: segment.startTime, end: segment.endTime)
    }

    private static func matchingAnchorTime(
        in segment: TranscriptSegment,
        phrases: [String]
    ) -> Double? {
        matchingAnchorTimes(in: segment, phrases: phrases).min()
    }

    private static func matchingAnchorTimes(
        in segment: TranscriptSegment,
        phrases: [String]
    ) -> [Double] {
        guard !segment.wordTimings.isEmpty else { return [] }
        let timingTokens = segment.wordTimings.map { normalizedToken($0.word) }
        let phraseTokens = phrases
            .map { phrase in phrase.split(whereSeparator: \.isWhitespace).map { normalizedToken(String($0)) } }
            .filter { !$0.isEmpty }

        var matches: [Double] = []
        for phrase in phraseTokens {
            guard phrase.count <= timingTokens.count else { continue }
            for startIndex in 0...(timingTokens.count - phrase.count) {
                let slice = timingTokens[startIndex..<(startIndex + phrase.count)]
                guard zip(slice, phrase).allSatisfy({ timingToken, phraseToken in
                    timingToken == phraseToken || (phraseToken.count >= 4 && timingToken.hasPrefix(phraseToken))
                }) else { continue }
                matches.append(segment.wordTimings[startIndex].start)
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

        var matches: [Double] = []
        for phrase in phrases {
            let phraseWords = normalizedWords(in: phrase)
            guard !phraseWords.isEmpty, phraseWords.count <= words.count else { continue }
            for startIndex in 0...(words.count - phraseWords.count) {
                let endIndex = startIndex + phraseWords.count
                let slice = words[startIndex..<endIndex]
                guard zip(slice, phraseWords).allSatisfy({ pair in
                    pair.0 == pair.1 || (pair.1.count >= 4 && pair.0.hasPrefix(pair.1))
                }) else { continue }

                let progress = Double(startIndex) / Double(max(words.count, 1))
                matches.append(start + (end - start) * progress)
            }
        }

        return matches
    }

    private static func preferredCTAAnchorTime(in segment: TranscriptSegment) -> Double? {
        let duration = segment.endTime - segment.startTime
        let matches = matchingAnchorTimes(in: segment, phrases: ctaTriggers)
        if let latest = matches.max() {
            return latest
        }

        guard duration <= 5.0 else { return nil }
        return estimatedPhraseAnchorTimes(
            in: segment.text,
            phrases: ctaTriggers,
            start: segment.startTime,
            end: segment.endTime
        ).max()
    }

    private static func preferredRevealAnchorTime(in segment: TranscriptSegment) -> Double? {
        if let payoff = phraseAnchorTime(in: segment, phrases: coreRevealPayoffTriggers) {
            return payoff
        }
        if containsPhrase(in: segment.text, phrases: generatedCreatedRevealTriggers),
           let generatedVerb = phraseAnchorTime(in: segment, phrases: generatedCreatedRevealVerbAnchorTriggers) {
            return generatedVerb
        }
        if let generated = phraseAnchorTime(in: segment, phrases: generatedCreatedRevealTriggers) {
            return generated
        }
        if isBigRevealLeadInCandidate(segment.text),
           let product = phraseAnchorTime(in: segment, phrases: productRevealAnchorTriggers) {
            return product
        }
        return phraseAnchorTime(in: segment, phrases: bigRevealAnchorTriggers)
            ?? phraseAnchorTime(in: segment, phrases: productRevealAnchorTriggers)
    }

    private static func startsTopicShift(_ text: String) -> Bool {
        let words = normalizedWords(in: text)
        guard !words.isEmpty else { return false }
        let phrases = topicShiftTriggers
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
    private static let topicShiftTriggers = [
        "now", "next", "then", "first step", "second step", "third step", "şimdi", "sonra",
        "ilk olarak", "ikinci adım", "ucuncu adim", "üçüncü adım", "ama şimdi", "burada ise"
    ]
}

enum RoughCutDecisionEngine {
    /// Silence thresholds (seconds) — tuned for social media pacing
    private static let maxIntraSpeechSilence: Double = 0.40
    private static let maxInterIdeaSilence: Double = 0.7
    private static let techDeadAirSilenceThreshold: Double = 0.34
    private static let maxSentenceContinuationGap: Double = 0.70
    private static let techWordBoundaryGuard: Double = 0.05
    /// Breathing room to keep around speech (seconds)
    private static let breathingRoom: Double = 0.10
    private static let minimumSpeechConfidenceForDestructiveCut: Float = 0.70
    private static let minimumAIConfidenceForDestructiveCut: Float = 0.85

    static func generateTechInfluencerDecisions(
        transcription: TranscriptionResult,
        audioAnalysis: AudioAnalysisResult,
        takeGroups: [TakeGroup] = []
    ) -> RoughCutResult {
        let plan = TechInfluencerTimelineAnalyzer.analyze(
            transcription: transcription,
            audioAnalysis: audioAnalysis
        )
        return generateTechInfluencerDecisions(
            transcription: transcription,
            audioAnalysis: audioAnalysis,
            takeGroups: takeGroups,
            timelinePlan: plan
        )
    }

    static func generateTechInfluencerDecisions(
        transcription: TranscriptionResult,
        audioAnalysis: AudioAnalysisResult,
        takeGroups: [TakeGroup],
        timelinePlan: TechInfluencerTimelinePlan
    ) -> RoughCutResult {
        let guardedResult = generateDecisions(
            transcription: transcription,
            audioAnalysis: audioAnalysis
        )
        let guardedTranscriptDecisions = guardedResult.decisions.filter { decision in
            isGuardedTranscriptDecision(decision)
                && !canAutoResolveTechTranscriptReview(decision, transcription: transcription)
        }
        let guardedTranscriptRanges = guardedTranscriptDecisions.map {
            TimelineRange(startTime: $0.startTime, endTime: $0.endTime)
        }

        var decisions: [RoughCutDecision] = []
        let speechSegments = transcription.segments
            .filter { isTechTimelineSpeech($0) }
            .sorted { $0.startTime < $1.startTime }

        guard !speechSegments.isEmpty else {
            return generateDecisions(
                transcription: transcription,
                audioAnalysis: audioAnalysis,
                takeGroups: takeGroups
            )
        }

        let semanticRanges = semanticKeepRanges(
            from: speechSegments,
            duration: audioAnalysis.duration
        )
        let protectedContinuationGaps = sentenceContinuationGapRanges(from: speechSegments)
        let protectedWordRanges = wordProtectionRanges(from: speechSegments)
        let keepRanges = semanticRanges.flatMap { keepRange in
            subtractRanges(
                from: keepRange,
                blockedRanges: guardedTranscriptRanges
            )
        }
        for range in keepRanges {
            let linkedText = linkedTextForRange(range, segments: speechSegments)
            decisions.append(RoughCutDecision(
                startTime: range.startTime,
                endTime: range.endTime,
                action: .keep,
                reason: "Tech semantic keep - \(semanticReason(for: range, plan: timelinePlan))",
                confidence: confidenceForRange(range, segments: speechSegments),
                linkedTranscriptText: linkedText,
                requiresReview: false
            ))
        }

        let techSilenceCuts = techSilenceCutRanges(
            from: audioAnalysis.silenceIntervals,
            keepRanges: keepRanges,
            protectedRanges: guardedTranscriptRanges + protectedContinuationGaps + protectedWordRanges
        )
        for range in techSilenceCuts {
            decisions.append(RoughCutDecision(
                startTime: range.startTime,
                endTime: range.endTime,
                action: .cut,
                reason: "Tech pacing silence (\((range.endTime - range.startTime).formatted(.number.precision(.fractionLength(2))))s removed)",
                confidence: 0.86,
                linkedTranscriptText: nil,
                requiresReview: false
            ))
        }

        decisions.append(contentsOf: guardedTranscriptDecisions)

        let protectedIncludedRanges = guardedTranscriptDecisions
            .filter(\.isTimelineIncluded)
            .map { TimelineRange(startTime: $0.startTime, endTime: $0.endTime) }
        let includedRanges = TimelineRangeNormalizer.coalesce(
            keepRanges + protectedIncludedRanges,
            maxGap: 0.05
        )
        let cutRanges = complementCuts(
            keptRanges: includedRanges,
            duration: audioAnalysis.duration
        )
        for range in cutRanges {
            guard !guardedTranscriptRanges.contains(where: { overlaps(range, $0) }) else {
                continue
            }
            decisions.append(RoughCutDecision(
                startTime: range.startTime,
                endTime: range.endTime,
                action: .cut,
                reason: "Tech pacing dead air/inter-idea gap",
                confidence: 0.88,
                linkedTranscriptText: nil,
                requiresReview: false
            ))
        }

        decisions = subtractCutsFromKeeps(decisions)
        decisions.sort { $0.startTime < $1.startTime }
        let result = buildResult(decisions: decisions, originalDuration: audioAnalysis.duration)
        guard !takeGroups.isEmpty else { return result }
        return applyTakeGroups(takeGroups, to: result)
    }

    static func generateDecisions(
        transcription: TranscriptionResult,
        audioAnalysis: AudioAnalysisResult
    ) -> RoughCutResult {
        var decisions: [RoughCutDecision] = []

        // Analyze each transcript segment
        for (index, segment) in transcription.segments.enumerated() {
            let previousSegment = index > 0 ? transcription.segments[index - 1] : nil
            let nextSegment = index < transcription.segments.count - 1 ? transcription.segments[index + 1] : nil
            // Handle segments classified by SmartTranscriptAnalyzer / heuristics
            let aiConf = segment.aiConfidence
            let lowConfidence = aiConf != nil && aiConf! < 0.7
            let canDestructivelyCut = canApplyDestructiveCut(segment: segment, aiConfidence: aiConf)
            let needsTranscriptReview = transcriptQualityConfidence(segment) < minimumSpeechConfidenceForDestructiveCut

            switch segment.segmentType {
            case .editCommand:
                let reason = segment.aiReason ?? "Edit command detected"
                decisions.append(RoughCutDecision(
                    startTime: segment.startTime,
                    endTime: segment.endTime,
                    action: canDestructivelyCut ? .cut : .reviewRequired,
                    reason: canDestructivelyCut ? reason : reviewReason(for: reason, segment: segment, aiConfidence: aiConf),
                    confidence: min(aiConf ?? 0.90, segment.confidence),
                    linkedTranscriptText: segment.text,
                    requiresReview: !canDestructivelyCut
                ))
                continue
            case .filler:
                let reason = segment.aiReason ?? "Filler word detected"
                let fillerDuration = segment.endTime - segment.startTime
                // Only cut fillers if they're pure short fillers (< 1s) and high confidence
                // Longer "fillers" are often misclassified content
                if fillerDuration > 1.0 || lowConfidence || needsTranscriptReview {
                    decisions.append(RoughCutDecision(
                        startTime: segment.startTime,
                        endTime: segment.endTime,
                        action: .reviewRequired,
                        reason: fillerDuration > 1.0
                            ? "Long filler — likely content: \(reason)"
                            : reviewReason(for: reason, segment: segment, aiConfidence: aiConf),
                        confidence: min(aiConf ?? 0.50, segment.confidence),
                        linkedTranscriptText: segment.text,
                        requiresReview: true
                    ))
                } else {
                    decisions.append(RoughCutDecision(
                        startTime: segment.startTime,
                        endTime: segment.endTime,
                        action: .cut,
                        reason: reason,
                        confidence: aiConf ?? 0.90,
                        linkedTranscriptText: segment.text,
                        requiresReview: false
                    ))
                }
                continue
            case .suspectedRestart:
                let reason = segment.aiReason ?? "Suspected restart — cleaner take follows"
                let hasRestartEvidence = hasRestartEvidence(segment, next: nextSegment)
                let shouldCut = canDestructivelyCut && hasRestartEvidence
                decisions.append(RoughCutDecision(
                    startTime: segment.startTime,
                    endTime: segment.endTime,
                    action: shouldCut ? .cut : .reviewRequired,
                    reason: shouldCut ? reason : reviewReason(
                        for: hasRestartEvidence ? reason : "No adjacent restart evidence — \(reason)",
                        segment: segment,
                        aiConfidence: aiConf
                    ),
                    confidence: min(aiConf ?? 0.60, segment.confidence),
                    linkedTranscriptText: segment.text,
                    requiresReview: !shouldCut
                ))
                continue
            case .suspectedDuplicate:
                let reason = segment.aiReason ?? "Duplicate content detected"
                let hasDuplicateEvidence = hasDuplicateEvidence(
                    segment,
                    previous: previousSegment,
                    next: nextSegment
                )
                let shouldCut = canDestructivelyCut && hasDuplicateEvidence
                decisions.append(RoughCutDecision(
                    startTime: segment.startTime,
                    endTime: segment.endTime,
                    action: shouldCut ? .cut : .reviewRequired,
                    reason: shouldCut ? reason : reviewReason(
                        for: hasDuplicateEvidence ? reason : "No adjacent duplicate evidence — \(reason)",
                        segment: segment,
                        aiConfidence: aiConf
                    ),
                    confidence: min(aiConf ?? 0.75, segment.confidence),
                    linkedTranscriptText: segment.text,
                    requiresReview: !shouldCut
                ))
                continue
            case .speech where needsTranscriptReview, .contentSentence where needsTranscriptReview:
                decisions.append(RoughCutDecision(
                    startTime: segment.startTime,
                    endTime: segment.endTime,
                    action: .keep,
                    reason: reviewReason(for: "Low transcript confidence; keep content but require review", segment: segment, aiConfidence: aiConf),
                    confidence: transcriptQualityConfidence(segment),
                    linkedTranscriptText: segment.text,
                    requiresReview: true
                ))
                continue
            case .contentSentence where lowConfidence:
                let reason = segment.aiReason ?? "Content (low confidence)"
                decisions.append(RoughCutDecision(
                    startTime: segment.startTime,
                    endTime: segment.endTime,
                    action: .keep,
                    reason: "AI uncertain: \(reason)",
                    confidence: aiConf ?? 0.50,
                    linkedTranscriptText: segment.text,
                    requiresReview: true
                ))
                continue
            case .speech, .silence, .contentSentence:
                break // Fall through to edit command detection
            }

            // Run edit command detection
            let analysis = ContextAwareEditCommandDetector.analyze(
                segment: segment,
                previousSegment: previousSegment,
                nextSegment: nextSegment,
                audioResult: audioAnalysis
            )

            switch analysis.intent {
            case .editCommand:
                let canCutContextCommand = transcriptQualityConfidence(segment) >= minimumSpeechConfidenceForDestructiveCut
                    && analysis.confidence >= minimumAIConfidenceForDestructiveCut
                decisions.append(RoughCutDecision(
                    startTime: segment.startTime,
                    endTime: segment.endTime,
                    action: canCutContextCommand ? .cut : .reviewRequired,
                    reason: canCutContextCommand ? analysis.reason : reviewReason(
                        for: analysis.reason,
                        segment: segment,
                        aiConfidence: analysis.confidence
                    ),
                    confidence: min(analysis.confidence, segment.confidence),
                    linkedTranscriptText: segment.text,
                    requiresReview: !canCutContextCommand
                ))

            case .uncertain:
                decisions.append(RoughCutDecision(
                    startTime: segment.startTime,
                    endTime: segment.endTime,
                    action: .reviewRequired,
                    reason: analysis.reason,
                    confidence: analysis.confidence,
                    linkedTranscriptText: segment.text,
                    requiresReview: true
                ))

            case .contentSentence:
                decisions.append(RoughCutDecision(
                    startTime: segment.startTime,
                    endTime: segment.endTime,
                    action: .keep,
                    reason: analysis.reason,
                    confidence: analysis.confidence,
                    linkedTranscriptText: segment.text,
                    requiresReview: false
                ))
            }
        }

        // Process silence intervals — only cut clearly excessive silences
        for silence in audioAnalysis.silenceIntervals {
            let duration = silence.upperBound - silence.lowerBound

            if duration > maxInterIdeaSilence {
                // Long silence between ideas — trim but keep generous breathing room
                let trimmedStart = silence.lowerBound + breathingRoom
                // Keep a natural pause at the end (0.3s feels organic)
                let trimmedEnd = silence.upperBound - max(breathingRoom, 0.3)

                if trimmedEnd > trimmedStart + 0.1 {
                    decisions.append(RoughCutDecision(
                        startTime: trimmedStart,
                        endTime: trimmedEnd,
                        action: .cut,
                        reason: "Long silence (\(String(format: "%.1f", duration))s)",
                        confidence: 0.85,
                        linkedTranscriptText: nil,
                        requiresReview: false
                    ))
                }
            }
            // Medium silences (0.4-0.7s) are natural pauses — DON'T trim them
            // They give the video breathing room and feel natural
        }

        // Split keep segments that overlap with silence cuts
        decisions = subtractCutsFromKeeps(decisions)

        // Sort by start time
        decisions.sort { $0.startTime < $1.startTime }

        return buildResult(decisions: decisions, originalDuration: audioAnalysis.duration)
    }

    static func generateDecisions(
        transcription: TranscriptionResult,
        audioAnalysis: AudioAnalysisResult,
        takeGroups: [TakeGroup]
    ) -> RoughCutResult {
        let result = generateDecisions(
            transcription: transcription,
            audioAnalysis: audioAnalysis
        )
        guard !takeGroups.isEmpty else { return result }
        return applyTakeGroups(takeGroups, to: result)
    }

    private static func canApplyDestructiveCut(
        segment: TranscriptSegment,
        aiConfidence: Float?
    ) -> Bool {
        guard transcriptQualityConfidence(segment) >= minimumSpeechConfidenceForDestructiveCut else {
            return false
        }
        guard let aiConfidence else {
            return true
        }
        return aiConfidence >= minimumAIConfidenceForDestructiveCut
    }

    private static func isTechTimelineSpeech(_ segment: TranscriptSegment) -> Bool {
        let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty,
              segment.endTime > segment.startTime,
              techTimelineConfidence(segment) >= 0.45 else {
            return false
        }

        switch segment.segmentType {
        case .speech, .contentSentence:
            return true
        case .suspectedRestart, .suspectedDuplicate:
            return techTimelineConfidence(segment) < minimumSpeechConfidenceForDestructiveCut
        case .filler:
            return segment.endTime - segment.startTime > 1.0
        case .silence, .editCommand:
            return false
        }
    }

    private static func isGuardedTranscriptDecision(_ decision: RoughCutDecision) -> Bool {
        guard decision.linkedTranscriptText != nil else { return false }
        return decision.action != .keep || decision.requiresReview
    }

    private static func canAutoResolveTechTranscriptReview(
        _ decision: RoughCutDecision,
        transcription: TranscriptionResult
    ) -> Bool {
        guard decision.action == .keep,
              decision.requiresReview,
              decision.reason.localizedStandardContains("low transcript confidence") else {
            return false
        }

        let overlappingSegments = transcription.segments.filter { segment in
            segment.startTime < decision.endTime && segment.endTime > decision.startTime
        }
        guard !overlappingSegments.isEmpty else { return false }

        return overlappingSegments.allSatisfy { segment in
            techTimelineConfidence(segment) >= 0.68
                && isTrustedTechPostProcessedText(segment.text)
        }
    }

    private static func subtractRanges(
        from range: TimelineRange,
        blockedRanges: [TimelineRange]
    ) -> [TimelineRange] {
        var remaining = [range]

        for blocked in blockedRanges where overlaps(range, blocked) {
            remaining = remaining.flatMap { candidate -> [TimelineRange] in
                guard overlaps(candidate, blocked) else { return [candidate] }

                var pieces: [TimelineRange] = []
                let before = TimelineRange(
                    startTime: candidate.startTime,
                    endTime: min(candidate.endTime, blocked.startTime)
                )
                let after = TimelineRange(
                    startTime: max(candidate.startTime, blocked.endTime),
                    endTime: candidate.endTime
                )
                if before.duration >= TimelineRangeNormalizer.defaultMinimumDuration {
                    pieces.append(before)
                }
                if after.duration >= TimelineRangeNormalizer.defaultMinimumDuration {
                    pieces.append(after)
                }
                return pieces
            }
        }

        return remaining
    }

    private static func techSilenceCutRanges(
        from silenceIntervals: [ClosedRange<Double>],
        keepRanges: [TimelineRange],
        protectedRanges: [TimelineRange]
    ) -> [TimelineRange] {
        var cuts: [TimelineRange] = []

        for silence in silenceIntervals {
            let silenceDuration = silence.upperBound - silence.lowerBound
            guard silenceDuration > techDeadAirSilenceThreshold else { continue }

            for keepRange in keepRanges {
                let clippedStart = max(keepRange.startTime, silence.lowerBound + 0.08)
                let clippedEnd = min(keepRange.endTime, silence.upperBound - 0.08)
                let cut = TimelineRange(startTime: clippedStart, endTime: clippedEnd)
                guard cut.duration >= 0.16 else {
                    continue
                }
                cuts.append(contentsOf: subtractRanges(
                    from: cut,
                    blockedRanges: protectedRanges
                ).filter { $0.duration >= 0.16 })
            }
        }

        return TimelineRangeNormalizer.coalesce(cuts, maxGap: 0.05)
    }

    private static func wordProtectionRanges(from segments: [TranscriptSegment]) -> [TimelineRange] {
        let ranges = segments.flatMap { segment in
            segment.wordTimings.compactMap { timing -> TimelineRange? in
                guard timing.start.isFinite,
                      timing.duration.isFinite,
                      timing.duration > 0 else {
                    return nil
                }

                let start = max(0, timing.start - techWordBoundaryGuard)
                let end = timing.start + timing.duration + techWordBoundaryGuard
                guard end - start >= TimelineRangeNormalizer.defaultMinimumDuration else {
                    return nil
                }

                return TimelineRange(startTime: start, endTime: end)
            }
        }

        return TimelineRangeNormalizer.coalesce(ranges, maxGap: 0.02)
    }

    private static func overlaps(_ left: TimelineRange, _ right: TimelineRange) -> Bool {
        min(left.endTime, right.endTime) > max(left.startTime, right.startTime)
    }

    private static func semanticKeepRanges(
        from segments: [TranscriptSegment],
        duration: Double
    ) -> [TimelineRange] {
        let padded = segments.map { segment in
            let speechStart = segment.wordTimings.first?.start ?? segment.startTime
            let speechEnd = segment.wordTimings.last.map { $0.start + $0.duration } ?? segment.endTime
            return (
                segment: segment,
                range: TimelineRange(
                    startTime: max(0, min(segment.startTime, speechStart) - 0.10),
                    endTime: min(duration, max(segment.endTime, speechEnd) + 0.12)
                )
            )
        }.filter {
            $0.range.endTime > $0.range.startTime
        }

        guard let first = padded.first else { return [] }

        var ranges: [TimelineRange] = []
        var currentStart = first.range.startTime
        var currentEnd = first.range.endTime
        var previousSegment = first.segment

        for item in padded.dropFirst() {
            let gap = item.range.startTime - currentEnd
            if gap <= techDeadAirSilenceThreshold
                || shouldProtectContinuationGap(previous: previousSegment, next: item.segment, gap: gap) {
                currentEnd = max(currentEnd, item.range.endTime)
            } else {
                ranges.append(TimelineRange(startTime: currentStart, endTime: currentEnd))
                currentStart = item.range.startTime
                currentEnd = item.range.endTime
            }
            previousSegment = item.segment
        }

        ranges.append(TimelineRange(startTime: currentStart, endTime: currentEnd))
        return ranges
    }

    private static func sentenceContinuationGapRanges(from segments: [TranscriptSegment]) -> [TimelineRange] {
        let sorted = segments.sorted { $0.startTime < $1.startTime }
        guard sorted.count > 1 else { return [] }

        return zip(sorted, sorted.dropFirst()).compactMap { previous, next in
            let gap = next.startTime - previous.endTime
            guard gap > techDeadAirSilenceThreshold,
                  shouldProtectContinuationGap(previous: previous, next: next, gap: gap) else {
                return nil
            }
            return TimelineRange(startTime: previous.endTime, endTime: next.startTime)
        }
    }

    private static func shouldProtectContinuationGap(
        previous: TranscriptSegment,
        next: TranscriptSegment,
        gap: Double
    ) -> Bool {
        guard gap > techDeadAirSilenceThreshold,
              gap <= maxSentenceContinuationGap else {
            return false
        }

        if startsWithPhrase(next.text, phrases: continuationStartPhrases) {
            return true
        }

        if endsWithTerminalPunctuation(previous.text),
           startsWithPhrase(next.text, phrases: hardBoundaryStartPhrases) {
            return false
        }

        return !endsWithTerminalPunctuation(previous.text)
            && !startsWithPhrase(next.text, phrases: hardBoundaryStartPhrases)
    }

    private static func complementCuts(
        keptRanges: [TimelineRange],
        duration: Double
    ) -> [TimelineRange] {
        guard duration.isFinite, duration > 0 else { return [] }
        var cuts: [TimelineRange] = []
        var cursor = 0.0

        for range in keptRanges.sorted(by: { $0.startTime < $1.startTime }) {
            let gapStart = cursor
            let gapEnd = max(gapStart, range.startTime)
            if gapEnd - gapStart > 0.35 {
                cuts.append(TimelineRange(startTime: gapStart, endTime: gapEnd))
            }
            cursor = max(cursor, range.endTime)
        }

        if duration - cursor > 0.35 {
            cuts.append(TimelineRange(startTime: cursor, endTime: duration))
        }
        return cuts
    }

    private static func semanticReason(
        for range: TimelineRange,
        plan: TechInfluencerTimelinePlan
    ) -> String {
        let kinds = plan.events
            .filter { event in
                event.sourceStart < range.endTime && event.sourceEnd > range.startTime
            }
            .map(\.kind.rawValue)
        guard !kinds.isEmpty else { return "speech phrase" }
        return Array(Set(kinds)).sorted().joined(separator: ",")
    }

    private static func linkedTextForRange(
        _ range: TimelineRange,
        segments: [TranscriptSegment]
    ) -> String? {
        let texts = segments
            .filter { $0.startTime < range.endTime && $0.endTime > range.startTime }
            .map(\.text)
        guard !texts.isEmpty else { return nil }
        return texts.joined(separator: " ")
    }

    private static func confidenceForRange(
        _ range: TimelineRange,
        segments: [TranscriptSegment]
    ) -> Float {
        let overlapping = segments.filter { $0.startTime < range.endTime && $0.endTime > range.startTime }
        guard !overlapping.isEmpty else { return 0.80 }
        return overlapping.reduce(Float(0)) { $0 + techTimelineConfidence($1) } / Float(overlapping.count)
    }

    private static func reviewReason(
        for reason: String,
        segment: TranscriptSegment,
        aiConfidence: Float?
    ) -> String {
        let qualityConfidence = transcriptQualityConfidence(segment)
        let transcriptPercent = Int((qualityConfidence * 100).rounded())
        if qualityConfidence < minimumSpeechConfidenceForDestructiveCut {
            return "Review: low transcript confidence (\(transcriptPercent)%) — \(reason)"
        }
        if let aiConfidence, aiConfidence < minimumAIConfidenceForDestructiveCut {
            let aiPercent = Int((aiConfidence * 100).rounded())
            return "Review: low AI confidence (\(aiPercent)%) — \(reason)"
        }
        return "Review: \(reason)"
    }

    private static func transcriptQualityConfidence(_ segment: TranscriptSegment) -> Float {
        segment.rawConfidence ?? segment.confidence
    }

    private static func techTimelineConfidence(_ segment: TranscriptSegment) -> Float {
        let qualityConfidence = transcriptQualityConfidence(segment)
        guard let rawConfidence = segment.rawConfidence,
              segment.confidence > rawConfidence + 0.10,
              isTrustedTechPostProcessedText(segment.text) else {
            return qualityConfidence
        }
        return segment.confidence
    }

    private static func isTrustedTechPostProcessedText(_ text: String) -> Bool {
        let lower = text.lowercased()
        return [
            "vibe coding",
            "mvp",
            "app store",
            "web",
            "ürün",
            "urun",
            "kod bilmeyen",
            "yapay zeka",
            "yorumlara vibe",
            "vibe yazıp",
            "büyüyelim",
            "buyuyelim"
        ].contains { lower.localizedStandardContains($0) }
    }

    private static func hasRestartEvidence(
        _ segment: TranscriptSegment,
        next: TranscriptSegment?
    ) -> Bool {
        guard let next else { return false }
        let words = normalizedWords(segment.text)
        let nextWords = normalizedWords(next.text)
        guard words.count >= 3, nextWords.count >= 3 else { return false }
        let prefixCount = commonPrefixWordCount(words, nextWords)
        return prefixCount >= 3 && Double(prefixCount) / Double(words.count) > 0.6
    }

    private static func hasDuplicateEvidence(
        _ segment: TranscriptSegment,
        previous: TranscriptSegment?,
        next: TranscriptSegment?
    ) -> Bool {
        [previous, next].compactMap(\.self).contains { neighbor in
            jaccardSimilarity(normalizedWords(segment.text), normalizedWords(neighbor.text)) > 0.80
        }
    }

    private static func normalizedWords(_ text: String) -> [String] {
        text
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
    }

    private static func endsWithTerminalPunctuation(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = trimmed.last else { return false }
        return [".", "!", "?"].contains(String(last))
    }

    private static func startsWithPhrase(_ text: String, phrases: [String]) -> Bool {
        let words = normalizedWords(text)
        guard !words.isEmpty else { return false }
        return phrases.contains { phrase in
            let phraseWords = normalizedWords(phrase)
            guard !phraseWords.isEmpty, phraseWords.count <= words.count else { return false }
            return zip(words.prefix(phraseWords.count), phraseWords).allSatisfy { pair in
                pair.0 == pair.1
            }
        }
    }

    private static let continuationStartPhrases = [
        "ve", "ya da", "veya", "çünkü", "cunku", "ki", "için", "icin",
        "and", "or", "because", "so that", "to", "then"
    ]

    private static let hardBoundaryStartPhrases = [
        "şimdi", "simdi", "sonra", "ilk", "ikinci", "üçüncü", "ucuncu",
        "ama", "fakat", "bu yüzden", "bu yuzden", "işte", "iste",
        "now", "next", "then", "first", "second", "third", "but", "however"
    ]

    private static func commonPrefixWordCount(_ left: [String], _ right: [String]) -> Int {
        var count = 0
        for (leftWord, rightWord) in zip(left, right) {
            guard leftWord == rightWord else { break }
            count += 1
        }
        return count
    }

    private static func jaccardSimilarity(_ left: [String], _ right: [String]) -> Double {
        let leftSet = Set(left)
        let rightSet = Set(right)
        let union = leftSet.union(rightSet)
        guard !union.isEmpty else { return 0 }
        return Double(leftSet.intersection(rightSet).count) / Double(union.count)
    }

    /// Apply take group results: mark non-best takes as cut
    static func applyTakeGroups(
        _ takeGroups: [TakeGroup],
        to result: RoughCutResult
    ) -> RoughCutResult {
        guard !takeGroups.isEmpty else { return result }

        var decisions = result.decisions

        for group in takeGroups {
            for (takeIndex, take) in group.takes.enumerated() {
                guard takeIndex != group.bestTakeIndex else { continue }

                // Find the decision that covers this non-best take and mark it as cut
                if let decisionIndex = decisions.firstIndex(where: { decision in
                    decision.action == .keep &&
                    abs(decision.startTime - take.startTime) < 0.2
                }) {
                    let old = decisions[decisionIndex]
                    decisions[decisionIndex] = RoughCutDecision(
                        startTime: old.startTime,
                        endTime: old.endTime,
                        action: .cut,
                        reason: "Non-best take (group has \(group.takes.count) takes, best is #\(group.bestTakeIndex + 1))",
                        confidence: 0.85,
                        linkedTranscriptText: old.linkedTranscriptText,
                        requiresReview: false
                    )
                }
            }
        }

        return buildResult(decisions: decisions, originalDuration: result.originalDuration)
    }

    /// Splits keep segments around overlapping cut/trim segments so timeline builder
    /// actually removes silences from within speech segments.
    private static func subtractCutsFromKeeps(_ decisions: [RoughCutDecision]) -> [RoughCutDecision] {
        let cuts = decisions.filter { $0.action == .cut || $0.action == .trimStart || $0.action == .trimEnd }
        let keeps = decisions.filter { $0.action == .keep }
        var nonKeeps = decisions.filter { $0.action != .keep }

        for keep in keeps {
            // Find cuts that overlap this keep segment
            let overlapping = cuts.filter { cut in
                cut.startTime < keep.endTime && cut.endTime > keep.startTime
            }.sorted { $0.startTime < $1.startTime }

            guard !overlapping.isEmpty else {
                nonKeeps.append(keep)
                continue
            }

            // Split the keep segment around each cut
            var cursor = keep.startTime
            for cut in overlapping {
                let cutStart = max(cut.startTime, keep.startTime)
                let cutEnd = min(cut.endTime, keep.endTime)

                // Keep region before this cut (minimum 0.15s to avoid AVFoundation stutter on sub-100ms segments)
                if cursor < cutStart && cutStart - cursor > 0.15 {
                    nonKeeps.append(RoughCutDecision(
                        startTime: cursor,
                        endTime: cutStart,
                        action: .keep,
                        reason: keep.reason,
                        confidence: keep.confidence,
                        linkedTranscriptText: linkedTextSlice(for: keep, startTime: cursor, endTime: cutStart),
                        requiresReview: false
                    ))
                }
                cursor = cutEnd
            }

            // Keep region after last cut (minimum 0.15s to avoid stutter)
            if cursor < keep.endTime && keep.endTime - cursor > 0.15 {
                nonKeeps.append(RoughCutDecision(
                    startTime: cursor,
                    endTime: keep.endTime,
                    action: .keep,
                    reason: keep.reason,
                    confidence: keep.confidence,
                    linkedTranscriptText: linkedTextSlice(for: keep, startTime: cursor, endTime: keep.endTime),
                    requiresReview: false
                ))
            }
        }

        return nonKeeps
    }

    private static func linkedTextSlice(
        for keep: RoughCutDecision,
        startTime: Double,
        endTime: Double
    ) -> String? {
        guard let text = keep.linkedTranscriptText else { return nil }
        if startTime <= keep.startTime + 0.001 && endTime >= keep.endTime - 0.001 {
            return text
        }

        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return text }

        let duration = max(0.001, keep.endTime - keep.startTime)
        let startRatio = min(max((startTime - keep.startTime) / duration, 0), 1)
        let endRatio = min(max((endTime - keep.startTime) / duration, 0), 1)
        let startIndex = min(words.count - 1, max(0, Int((startRatio * Double(words.count)).rounded(.down))))
        let rawEndIndex = Int((endRatio * Double(words.count)).rounded(.up))
        let endIndex = min(words.count, max(startIndex + 1, rawEndIndex))

        return words[startIndex..<endIndex].joined(separator: " ")
    }

    private static func buildResult(
        decisions: [RoughCutDecision],
        originalDuration: Double
    ) -> RoughCutResult {
        let keepSegments = decisions.filter { $0.action == .keep }
        let cleanDuration = TimelineRangeNormalizer
            .includedRanges(from: decisions, assetDuration: originalDuration)
            .reduce(0.0) { $0 + $1.duration }

        return RoughCutResult(
            decisions: decisions,
            originalDuration: originalDuration,
            cleanDuration: cleanDuration,
            keepSegments: keepSegments,
            cutSegments: decisions.filter { $0.action == .cut || $0.action == .trimStart || $0.action == .trimEnd },
            reviewSegments: decisions.filter { $0.requiresReview }
        )
    }
}
