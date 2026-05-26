import Foundation

enum CaptionSceneEventPlanner {
    static func assignSceneBehaviors(
        to captions: [CaptionSegment],
        template: TemplateConfig
    ) -> [CaptionSegment] {
        var result = captions
        let grammar = template.editGrammar
        var lastBehaviorTime: Double = -10

        for i in result.indices {
            let caption = result[i]
            let timeSinceLastBehavior = caption.startTime - lastBehaviorTime

            let behavior = determineBehavior(
                role: caption.role,
                grammar: grammar,
                timeSinceLastBehavior: timeSinceLastBehavior,
                text: caption.text
            )

            result[i].sceneBehavior = behavior
            if behavior != .none {
                lastBehaviorTime = caption.startTime
            }
        }

        return result
    }

    private static func determineBehavior(
        role: CaptionRole,
        grammar: TemplateEditGrammar,
        timeSinceLastBehavior: Double,
        text: String
    ) -> CaptionSceneBehavior {
        if grammar.id == "tech_influencer" {
            if canPromoteToUIAction(role: role, text: text),
               containsUIActionTrigger(text),
               timeSinceLastBehavior >= min(grammar.minimumBehaviorGap, 0.90) {
                return .focusBlur
            }

            guard timeSinceLastBehavior >= grammar.minimumBehaviorGap else { return .none }

            if role == .hook,
               !isHookWorthy(text) {
                return .none
            }

            if role == .regular,
               containsTechTrigger(text) {
                return .keywordLockOn
            }
        } else {
            guard timeSinceLastBehavior >= grammar.minimumBehaviorGap else { return .none }
        }

        if role == .regular { return grammar.regularBehavior }
        return grammar.roleBehaviors[role] ?? .none
    }

    private static func canPromoteToUIAction(role: CaptionRole, text: String) -> Bool {
        guard role != .warning,
              !containsWarningCue(text) else {
            return false
        }

        switch role {
        case .regular, .transition, .keyword:
            return true
        case .hook, .warning, .reveal, .conclusion:
            return false
        }
    }

    private static func containsWarningCue(_ text: String) -> Bool {
        if containsPhrase(in: text, phrases: ["don't", "dont", "avoid", "kaçın", "sakın", "asla", "yapma", "yapmayın"]) {
            return true
        }
        if containsPositiveResolutionPhrase(text) {
            return false
        }
        if containsPhrase(in: text, phrases: ["wrong", "mistake", "yanlış"]) {
            return true
        }
        if containsPhrase(in: text, phrases: ["error", "bug", "fail", "waste", "hata"]) {
            return !containsUIActionTrigger(text)
        }
        return false
    }

    private static func containsPositiveResolutionPhrase(_ text: String) -> Bool {
        containsPhrase(
            in: text,
            phrases: ["fix", "fixes", "fixed", "solves", "solved", "works", "handling works", "çözer", "cozer", "düzeltiyor", "duzeltiyor"]
        )
    }

    private static func containsTechTrigger(_ text: String) -> Bool {
        let words = normalizedWords(in: text)
        guard !words.isEmpty else { return false }

        let highValuePhrases = [
            "yapay zeka", "vibe coding", "app store", "mvp"
        ]
        guard !isNegatedTechMention(words) else { return false }
        if highValuePhrases.contains(where: { phraseMatches($0, words: words) }) {
            return true
        }

        let singleValueWords = Set(["ai", "startup", "launch"])
        let singleMatches = words.filter(singleValueWords.contains).count
        guard singleMatches > 0 else { return false }
        return words.count <= 5 || words.contains("coding") || words.contains("uygulama")
    }

    private static func containsUIActionTrigger(_ text: String) -> Bool {
        let words = normalizedWords(in: text)
        guard !words.isEmpty else { return false }
        guard !hasNegatedUIAction(words) else { return false }
        guard !hasMetaphoricalUIActionPhrase(words) else { return false }

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
               !phraseMatches("open source", words: words) {
                return hasUIActionContext(words, near: index)
                    || hasOpenActionTarget(words, near: index)
            }
            if isWorkflowActionWord(word) {
                return hasWorkflowExecutionContext(words) || hasExecutionAuxiliary(words)
            }
            return false
        }
    }

    private static func hasMetaphoricalUIActionPhrase(_ words: [String]) -> Bool {
        [
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
        ].contains { phraseMatches($0, words: words) }
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

    private static func isHookWorthy(_ text: String) -> Bool {
        containsPhrase(in: text, phrases: strongHookTriggers)
            || (keywordImportance(text) >= 2 && containsPhrase(in: text, phrases: hookValueTriggers))
            || (keywordImportance(text) >= 3 && normalizedWords(in: text).count <= 8)
    }

    private static func phraseMatches(_ phrase: String, words: [String]) -> Bool {
        let phraseWords = normalizedWords(in: phrase)
        guard !phraseWords.isEmpty, phraseWords.count <= words.count else { return false }

        return words.indices.contains { startIndex in
            let endIndex = startIndex + phraseWords.count
            guard endIndex <= words.count else { return false }
            return zip(words[startIndex..<endIndex], phraseWords).allSatisfy { $0 == $1 }
        }
    }

    private static func isNegatedTechMention(_ words: [String]) -> Bool {
        let negators = Set(["degil", "yok", "atmadim", "atmadik", "gondermedim", "gondermedik", "not", "no"])
        guard words.contains(where: negators.contains) else { return false }
        let techWords = Set(["mvp", "app", "store", "vibe", "coding", "ai", "web", "launch", "urun", "product"])
        return words.contains(where: techWords.contains)
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

    private static func containsPhrase(in text: String, phrases: [String]) -> Bool {
        let words = normalizedWords(in: text)
        guard !words.isEmpty else { return false }
        return phrases.contains { phraseMatches($0, words: words) }
    }

    private static let strongHookTriggers = [
        "stop doing", "most people", "did you know", "nobody knows", "the truth is",
        "here's the thing", "hook", "dikkat", "cok fazla", "çok fazla", "vazgeciyor",
        "vazgeçiyor", "buna ayar oluyorum", "neden", "niye"
    ]

    private static let hookValueTriggers = [
        "saves hours", "builds apps", "faster", "minutes", "free", "para", "money",
        "first", "ilk", "need to", "gerekiyor", "kod bilmeyen"
    ]

    private static func normalizedWords(in text: String) -> [String] {
        text
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "tr_TR"))
            .replacingOccurrences(of: "ı", with: "i")
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { !$0.isEmpty }
    }
}
