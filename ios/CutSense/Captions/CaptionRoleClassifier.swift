import Foundation

enum CaptionRoleClassifier {
    // Turkish hook words
    private static let hookPatterns = [
        "dikkat", "önemli", "şok", "inanılmaz", "gerçek şu", "asıl olay",
        "biliyor musun", "merak", "sır", "gizli", "kimse bilmiyor"
    ]

    // Turkish warning words
    private static let warningPatterns = [
        "uyarı", "dikkat", "sakın", "tehlike", "hata yapma", "yanlış",
        "asla", "kesinlikle", "çok önemli"
    ]

    // Turkish reveal words
    private static let revealPatterns = [
        "asıl", "gerçek", "sır", "aslında", "meğer", "ortaya çık",
        "işte bu", "tam da bu", "sonuç"
    ]

    // Turkish transition words
    private static let transitionPatterns = [
        "ama", "fakat", "ancak", "diğer taraftan", "bunun yanında",
        "bir de", "peki", "şimdi", "gelelim"
    ]

    // Turkish conclusion words
    private static let conclusionPatterns = [
        "sonuç olarak", "özetle", "kısacası", "yani", "toparlarsak",
        "son olarak", "en önemlisi"
    ]

    // English equivalents
    private static let hookPatternsEN = [
        "attention", "important", "shocking", "unbelievable", "the truth is",
        "did you know", "secret", "nobody knows", "here's the thing"
    ]

    private static let revealPatternsEN = [
        "actually", "the real", "turns out", "here it is", "the secret",
        "the answer", "this is it"
    ]

    static func classify(
        text: String,
        index: Int,
        totalSegments: Int,
        previousRole: CaptionRole?
    ) -> CaptionRole {
        let lower = text.lowercased()

        // First segment is always hook candidate
        if index == 0 {
            return .hook
        }

        // Last segment is conclusion candidate
        if index == totalSegments - 1 {
            return .conclusion
        }

        // Check patterns
        if matchesAny(lower, patterns: hookPatterns + hookPatternsEN) {
            return .hook
        }
        if matchesAny(lower, patterns: warningPatterns) {
            return .warning
        }
        if matchesAny(lower, patterns: revealPatterns + revealPatternsEN) {
            return .reveal
        }
        if matchesAny(lower, patterns: transitionPatterns) {
            return .transition
        }
        if matchesAny(lower, patterns: conclusionPatterns) {
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
        patterns.contains { text.contains($0) }
    }
}
