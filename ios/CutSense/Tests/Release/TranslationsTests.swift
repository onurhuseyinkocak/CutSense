import XCTest
@testable import CutSense

final class TranslationsTests: XCTestCase {
    private let translated: [AppLanguage] = [.es, .pt, .de, .fr, .it, .ja, .ko]

    /// Ordered format specifiers, ignoring literal "%%".
    private func specifiers(_ s: String) -> [String] {
        let pattern = try! NSRegularExpression(pattern: "%(?:%|l{0,2}[a-zA-Z@]|\\.\\d+[a-zA-Z])")
        return pattern.matches(in: s, range: NSRange(s.startIndex..., in: s))
            .map { String(s[Range($0.range, in: s)!]) }
            .filter { $0 != "%%" }
    }

    func testNoDuplicateKeys() {
        XCTAssertEqual(Translations.rows.count, Translations.table.count)
    }

    func testEveryEntryHasAllLanguagesAndMatchingPlaceholders() {
        XCTAssertFalse(Translations.table.isEmpty)
        for (english, values) in Translations.table {
            for language in translated {
                let value = values[language] ?? ""
                XCTAssertFalse(value.trimmingCharacters(in: .whitespaces).isEmpty, "\(language) missing for \"\(english)\"")
                XCTAssertEqual(specifiers(value), specifiers(english), "\(language) placeholders differ for \"\(english)\"")
            }
        }
    }

    func testAppTextRouting() {
        XCTAssertEqual(appText(.tr, "Paylaş", "Share"), "Paylaş")
        XCTAssertEqual(appText(.en, "Paylaş", "Share"), "Share")
        XCTAssertEqual(appText(.de, "Paylaş", "Share"), "Teilen")
        XCTAssertEqual(appText(.ja, "x", "not in table"), "not in table")
        XCTAssertEqual(String(format: appText(.ja, "%@ ile aç", "Unlock for %@"), "¥500"), "¥500で解除")
    }

    func testLanguagesHaveTitles() {
        XCTAssertEqual(AppLanguage.allCases.count, 9)
        for language in AppLanguage.allCases { XCTAssertFalse(language.title.isEmpty) }
        XCTAssertEqual(Set(AppLanguage.allCases.map(\.title)).count, 9)
    }

    func testSystemDefaultMapping() {
        XCTAssertEqual(AppLanguage.from(identifier: "tr-TR"), .tr)
        XCTAssertEqual(AppLanguage.from(identifier: "pt-BR"), .pt)
        XCTAssertEqual(AppLanguage.from(identifier: "pt-PT"), .pt)
        XCTAssertEqual(AppLanguage.from(identifier: "de-DE"), .de)
        XCTAssertEqual(AppLanguage.from(identifier: "ja-JP"), .ja)
        XCTAssertEqual(AppLanguage.from(identifier: "ko"), .ko)
        XCTAssertEqual(AppLanguage.from(identifier: "zh-Hans-CN"), .en)
        XCTAssertEqual(AppLanguage.from(identifier: ""), .en)
    }

    func testStoredRawValuesStillDecode() {
        XCTAssertEqual(AppLanguage.value(from: "tr"), .tr)
        XCTAssertEqual(AppLanguage.value(from: "en"), .en)
        XCTAssertEqual(AppLanguage.value(from: "fr"), .fr)
    }
}
