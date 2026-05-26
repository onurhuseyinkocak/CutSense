import Foundation

enum CaptionEngine {
    private static let minimumCaptionConfidence: Float = 0.45

    static func generateCaptions(
        from transcription: TranscriptionResult,
        roughCut: RoughCutResult,
        template: TemplateConfig
    ) -> [CaptionSegment] {
        let includedRanges = TimelineRangeNormalizer.includedRanges(
            from: roughCut.decisions,
            assetDuration: roughCut.originalDuration
        )

        let keptTranscriptSegments: [TranscriptSegment]
        if roughCut.decisions.isEmpty {
            keptTranscriptSegments = transcription.segments
        } else {
            keptTranscriptSegments = transcription.segments.filter { transcriptSegment in
                includedRanges.contains { range in
                    overlaps(transcriptSegment, range: range)
                }
            }
        }

        let captionableSegments = keptTranscriptSegments.filter { segment in
            segment.confidence >= minimumCaptionConfidence
        }

        guard !captionableSegments.isEmpty else { return [] }

        // Classify roles
        var captions: [CaptionSegment] = []
        var previousRole: CaptionRole?

        for (index, segment) in captionableSegments.enumerated() {
            let role = CaptionRoleClassifier.classify(
                text: segment.text,
                index: index,
                totalSegments: captionableSegments.count,
                previousRole: previousRole,
                startTime: segment.startTime
            )

            let style = styleForSegment(
                role: role,
                segment: segment,
                index: index,
                template: template
            )

            captions.append(CaptionSegment(
                startTime: captionStartTime(for: segment, template: template),
                endTime: captionEndTime(for: segment, template: template),
                text: segment.text,
                role: role,
                style: style,
                wordTimings: alignedWordTimings(for: segment)
            ))

            previousRole = role
        }

        // Assign scene behaviors
        captions = CaptionSceneEventPlanner.assignSceneBehaviors(
            to: captions,
            template: template
        )

        // Validate readability
        captions = CaptionReadabilityGuard.validate(captions, template: template)
        if template.id == "tech_influencer" {
            captions = enforceTechInfluencerStyleVariety(captions)
        }

        return captions
    }

    private static func captionStartTime(for segment: TranscriptSegment, template: TemplateConfig) -> Double {
        guard template.id == "tech_influencer" else { return segment.startTime }
        return max(0, segment.startTime - 0.08)
    }

    private static func captionEndTime(for segment: TranscriptSegment, template: TemplateConfig) -> Double {
        guard template.id == "tech_influencer" else { return segment.endTime }
        return segment.endTime + 0.10
    }

    private static func overlaps(_ segment: TranscriptSegment, range: TimelineRange) -> Bool {
        min(segment.endTime, range.endTime) > max(segment.startTime, range.startTime)
    }

    private static func styleForSegment(
        role: CaptionRole,
        segment: TranscriptSegment,
        index: Int,
        template: TemplateConfig
    ) -> CaptionStyle {
        if template.id == "tech_influencer" {
            return techInfluencerStyle(role: role, text: segment.text, index: index, template: template)
        }

        if template.id == "viral_caption" {
            return viralStyle(role: role, text: segment.text, index: index, template: template)
        }

        switch role {
        case .hook:
            return template.hookStyle
        case .reveal, .warning:
            return template.emphasisStyle
        case .keyword:
            return template.keywordStyle
        case .conclusion:
            return template.conclusionStyle
        default:
            return template.defaultStyle
        }
    }

    private static func techInfluencerStyle(
        role: CaptionRole,
        text: String,
        index: Int,
        template: TemplateConfig
    ) -> CaptionStyle {
        switch role {
        case .hook:
            return .hookImpact
        case .warning:
            return .focusStatement
        case .keyword:
            return .neonGlow
        case .reveal:
            if containsUIActionTerm(text) { return .typewriterClean }
            return .neonGlow
        case .transition:
            return .typewriterClean
        case .conclusion:
            return .premiumLowerThird
        case .regular:
            if containsWarningTerm(text) { return .focusStatement }
            if containsUIActionTerm(text) { return .typewriterClean }
            if containsRevealTerm(text) { return .neonGlow }
            if containsTechTerm(text) {
                return index.isMultiple(of: 2) ? .neonGlow : .premiumLowerThird
            }
            return .focusStatement
        }
    }

    private static func viralStyle(
        role: CaptionRole,
        text: String,
        index: Int,
        template: TemplateConfig
    ) -> CaptionStyle {
        switch role {
        case .hook, .conclusion:
            return .hookImpact
        case .keyword, .warning:
            return .glitchBold
        case .reveal:
            return .neonGlow
        case .transition:
            return .boldCenterViral
        case .regular:
            if containsTechTerm(text) || index.isMultiple(of: 4) {
                return .neonGlow
            }
            return template.defaultStyle
        }
    }

    private static func containsTechTerm(_ text: String) -> Bool {
        let lower = text.lowercased()
        return [
            "ai",
            "yapay zeka",
            "mvp",
            "app store",
            "android",
            "web",
            "kod",
            "code",
            "coding",
            "vibe",
            "startup",
            "ürün",
            "uygulama"
        ].contains { lower.localizedStandardContains($0) }
    }

    private static func containsWarningTerm(_ text: String) -> Bool {
        containsAny(
            text,
            terms: [
                "wrong", "mistake", "problem", "avoid", "don't", "dont", "waste",
                "yanlış", "hata", "sorun", "kaçın", "sakin", "sakın", "boşa", "kaybet"
            ]
        )
    }

    private static func containsUIActionTerm(_ text: String) -> Bool {
        containsAny(
            text,
            terms: [
                "click", "tap", "cursor", "button", "generate", "dashboard", "screen", "ui",
                "tıkla", "tikla", "buton", "ekran", "arayüz", "olustur", "oluştur"
            ]
        )
    }

    private static func containsRevealTerm(_ text: String) -> Bool {
        containsAny(
            text,
            terms: [
                "result", "appears", "launch", "launches", "proof", "before after",
                "sonuç", "sonuc", "çıktı", "cikti", "ortaya", "işte", "iste", "yayın", "yayin"
            ]
        )
    }

    private static func containsAny(_ text: String, terms: [String]) -> Bool {
        let lower = text.lowercased()
        return terms.contains { lower.localizedStandardContains($0) }
    }

    private static func enforceTechInfluencerStyleVariety(_ captions: [CaptionSegment]) -> [CaptionSegment] {
        var result = captions.sorted { $0.startTime < $1.startTime }
        var currentStyle: CaptionStyle?
        var currentRun = 0

        for index in result.indices {
            if result[index].style == currentStyle {
                currentRun += 1
            } else {
                currentStyle = result[index].style
                currentRun = 1
            }

            guard currentRun > 3,
                  let replacement = techInfluencerRunBreakStyle(
                    for: result[index],
                    previousStyle: currentStyle
                  ) else {
                continue
            }

            result[index].style = replacement
            currentStyle = replacement
            currentRun = 1
        }

        return result
    }

    private static func techInfluencerRunBreakStyle(
        for caption: CaptionSegment,
        previousStyle: CaptionStyle?
    ) -> CaptionStyle? {
        let candidates: [CaptionStyle] = switch caption.role {
        case .regular, .keyword:
            [.premiumLowerThird, .focusStatement, .typewriterClean]
        case .reveal:
            [.focusStatement, .premiumLowerThird]
        case .conclusion:
            [.focusStatement]
        case .hook, .warning, .transition:
            []
        }

        return candidates.first { $0 != previousStyle }
    }

    private static func alignedWordTimings(for segment: TranscriptSegment) -> [(word: String, start: Double, duration: Double)] {
        let words = timingWords(in: segment.text)
        guard !words.isEmpty else { return [] }

        if segment.wordTimings.count == words.count {
            return zip(words, segment.wordTimings).map { pair in
                let (word, timing) = pair
                return (word: word, start: timing.start, duration: timing.duration)
            }
        }

        let start = max(segment.startTime, segment.wordTimings.first?.start ?? segment.startTime)
        let rawEnd = segment.wordTimings.last.map { $0.start + $0.duration } ?? segment.endTime
        let end = min(max(rawEnd, start + 0.01), max(segment.endTime, start + 0.01))
        return proportionalWordTimings(words: words, start: start, end: end)
    }

    private static func timingWords(in text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    private static func proportionalWordTimings(
        words: [String],
        start: Double,
        end: Double
    ) -> [(word: String, start: Double, duration: Double)] {
        guard !words.isEmpty else { return [] }

        let span = max(0.01, end - start)
        let weights = words.map { word in
            max(1, word.filter { !$0.isWhitespace }.count)
        }
        let totalWeight = max(1, weights.reduce(0, +))
        var cursor = start

        return words.enumerated().map { index, word in
            let isLast = index == words.indices.last
            let duration = isLast
                ? max(0.01, end - cursor)
                : max(0.01, span * Double(weights[index]) / Double(totalWeight))
            defer { cursor += duration }
            return (word: word, start: cursor, duration: duration)
        }
    }
}
