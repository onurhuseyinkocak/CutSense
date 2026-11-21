import Foundation

enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case tr, en, es, pt, de, fr, it, ja, ko

    static let storageKey = "app_language"

    static var systemDefault: AppLanguage {
        from(identifier: Locale.preferredLanguages.first ?? "en")
    }

    /// Maps a BCP 47 identifier ("pt-BR", "ja-JP") to a supported language; anything else is English.
    static func from(identifier: String) -> AppLanguage {
        let code = Locale(identifier: identifier).language.languageCode?.identifier ?? ""
        return AppLanguage(rawValue: code) ?? .en
    }

    /// For views that cannot take a language parameter (ad views).
    static var current: AppLanguage {
        value(from: UserDefaults.standard.string(forKey: storageKey) ?? "")
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tr: "Türkçe"
        case .en: "English"
        case .es: "Español"
        case .pt: "Português (Brasil)"
        case .de: "Deutsch"
        case .fr: "Français"
        case .it: "Italiano"
        case .ja: "日本語"
        case .ko: "한국어"
        }
    }

    static func value(from rawValue: String) -> AppLanguage {
        AppLanguage(rawValue: rawValue) ?? systemDefault
    }
}

/// tr and en live at the call site; other languages come from `Translations.table`, keyed by the English string.
func appText(_ language: AppLanguage, _ tr: String, _ en: String) -> String {
    switch language {
    case .tr: tr
    case .en: en
    default: Translations.table[en]?[language] ?? en
    }
}

extension AudioAnalysisError {
    func message(for language: AppLanguage) -> String {
        switch self {
        case .noAudioTrack:
            appText(language, "Bu videoda ses parçası yok. Konuşma içeren bir video seç.", "This video has no audio track. Choose a video with speech.")
        case .cannotAddAudioOutput:
            appText(language, "Ses analizörü video sesini okuyamadı.", "The audio analyzer could not read this video's audio.")
        case .readerStartFailed(let message):
            String(format: appText(language, "Ses analizi başlatılamadı: %@", "Audio analysis could not start: %@"), message)
        case .readerFailed(let message):
            String(format: appText(language, "Ses analizi tamamlanamadı: %@", "Audio analysis could not finish: %@"), message)
        case .noSamplesRead:
            appText(language, "Ses parçası var ama analiz edilecek örnek okunamadı.", "The video has audio, but no analyzable samples could be read.")
        }
    }
}

extension PhotosSaveService.SaveError {
    func message(for language: AppLanguage) -> String {
        switch self {
        case .fileMissing:
            appText(language, "Video dosyası bulunamadı.", "The video file could not be found.")
        case .permissionDenied:
            appText(language, "Fotoğraflar'a ekleme izni gerekli.", "Permission to add to Photos is required.")
        case .assetCreationFailed:
            appText(language, "Fotoğraflar bu video dosyasını kabul etmedi.", "Photos did not accept this video file.")
        }
    }
}
