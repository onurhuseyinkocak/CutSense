import Foundation

enum CaptionRoleClassifier {
    // Turkish hook words
    private static let hookPatterns = [
        "dikkat", "önemli", "şok", "inanılmaz", "gerçek şu", "asıl olay",
        "biliyor musun", "merak", "sır", "gizli", "kimse bilmiyor",
        "çok fazla insan", "harika fikir", "vazgeçiyor",
        "buna ayar oluyorum", "neden"
    ]

    // Turkish warning words
    private static let warningPatterns = [
        "uyarı", "dikkat", "sakın", "tehlike", "hata yapma", "yanlış",
        "asla", "kesinlikle"
    ]

    private static let warningPatternsEN = [
        "warning", "wrong", "mistake", "avoid", "don't", "dont",
        "never", "waste", "stop doing"
    ]

    // Turkish reveal words
    private static let revealPatterns = [
        "ortaya çıktı", "ortaya çıkıyor", "işte bu", "tam da bu", "tam da bu yüzden",
        "sonuç bu", "sonuç burada", "sonucu", "çıktı"
    ]

    // Turkish transition words
    private static let transitionPatterns = [
        "ama şimdi", "fakat şimdi", "ancak şimdi", "diğer taraftan", "bunun yanında",
        "bir de", "peki", "şimdi", "gelelim"
    ]

    // Turkish conclusion words
    private static let conclusionPatterns = [
        "sonuç olarak", "özetle", "kısacası", "yani", "toparlarsak",
        "son olarak", "en önemlisi", "yorumlara yaz", "yorumlara vibe",
        "yorum bırak", "yorum birak", "yorum at", "vibe yaz", "katıl", "büyüyelim"
    ]

    // English equivalents
    private static let hookPatternsEN = [
        "attention", "important", "shocking", "unbelievable", "the truth is",
        "did you know", "secret", "nobody knows", "here's the thing",
        "most people", "stop doing", "why", "first", "you need to"
    ]

    private static let revealPatternsEN = [
        "turns out", "here it is", "the answer", "this is it", "that's why"
    ]

    static func classify(
        text: String,
        index: Int,
        totalSegments: Int,
        previousRole: CaptionRole?,
        startTime: Double = 0
    ) -> CaptionRole {
        let lower = text.lowercased()

        let inHookWindow = isHookWindow(index: index, startTime: startTime)
        let isClosingSegment = index == totalSegments - 1

        // Strong opening patterns like "Dikkat..." are hook language only in
        // the opening window. Later uses should keep their warning meaning.
        if inHookWindow,
           index == 0,
           matchesAny(lower, patterns: strongHookPatterns + hookPatterns + hookPatternsEN) {
            return .hook
        }

        if matchesAny(lower, patterns: conclusionPatterns),
           isClosingSegment || containsCTACue(lower) {
            return .conclusion
        }

        if matchesAny(lower, patterns: warningPatterns + warningPatternsEN) {
            return .warning
        }
        if matchesAny(lower, patterns: hookPatterns + hookPatternsEN),
           inHookWindow {
            return .hook
        }
        if matchesAny(lower, patterns: revealPatterns + revealPatternsEN) {
            return .reveal
        }
        if matchesAny(lower, patterns: transitionPatterns),
           !containsUIActionCue(lower) {
            return .transition
        }
        if matchesAny(lower, patterns: conclusionPatterns) {
            return .conclusion
        }

        // Position is a fallback only after semantic roles have had a chance to
        // claim explicit warning/reveal/CTA language.
        if index == 0 {
            return .hook
        }

        if index == totalSegments - 1 {
            return .conclusion
        }

        // Check for keyword-heavy segments (short, punchy)
        let wordCount = text.split(separator: " ").count
        if wordCount <= 3 && previousRole == .regular {
            return .keyword
        }

        return .regular
    }

    private static func matchesAny(_ text: String, patterns: [String]) -> Bool {
        let words = normalizedWords(in: text)
        return patterns.contains { pattern in
            let phraseWords = normalizedWords(in: pattern)
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

    private static func containsCTACue(_ text: String) -> Bool {
        matchesAny(
            text,
            patterns: [
                "yorumlara yaz", "yorumlara vibe", "vibe yaz",
                "comment vibe", "comment below", "follow for more",
                "follow for part two", "follow me", "follow us", "hit follow",
                "like and follow", "save this", "save this for later",
                "subscribe", "drop a comment", "leave a comment",
                "takip et", "takip etmeyi unutma", "daha fazlası için takip et",
                "yorum bırak", "yorum birak", "yorum at"
            ]
        )
    }

    private static func containsUIActionCue(_ text: String) -> Bool {
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
               !matchesAny(text, patterns: ["open source"]) {
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
        matchesAny(
            text,
            patterns: [
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

    private static func isOpenActionWord(_ word: String) -> Bool {
        [
            "ac", "acin", "aciyorum", "aciyoruz", "aciyor", "acalim",
            "actim", "actik", "acti", "open", "opened", "opening"
        ].contains(word)
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

    private static let strongHookPatterns = [
        "dikkat", "gerçek şu", "asıl olay", "biliyor musun",
        "kimse bilmiyor", "the truth is", "here's the thing",
        "did you know", "nobody knows"
    ]

    private static func isHookWindow(index: Int, startTime: Double) -> Bool {
        index <= 1 && startTime <= 3.5
    }

    private static func isSelectActionWord(_ word: String) -> Bool {
        [
            "sec", "sectim", "sectik", "sectin", "sectiniz", "secti",
            "seciyorum", "seciyoruz", "seciyor", "secelim",
            "selected", "selecting"
        ].contains(word)
    }

    private static func normalizedWords(in text: String) -> [String] {
        text
            .split { !$0.isLetter && !$0.isNumber }
            .map { normalized(String($0)) }
            .filter { !$0.isEmpty }
    }

    private static func normalized(_ text: String) -> String {
        text.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "tr_TR")
        )
        .replacingOccurrences(of: "ı", with: "i")
    }
}
