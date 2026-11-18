import Foundation

enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case tr
    case en

    static let storageKey = "app_language"

    static var systemDefault: AppLanguage {
        Locale.current.language.languageCode?.identifier == "tr" ? .tr : .en
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tr: "Türkçe"
        case .en: "English"
        }
    }

    var shortTitle: String {
        switch self {
        case .tr: "TR"
        case .en: "EN"
        }
    }

    static func value(from rawValue: String) -> AppLanguage {
        AppLanguage(rawValue: rawValue) ?? systemDefault
    }
}

struct AppCopy: Sendable {
    let tr: String
    let en: String

    func value(for language: AppLanguage) -> String {
        switch language {
        case .tr: tr
        case .en: en
        }
    }
}

func appText(_ language: AppLanguage, _ tr: String, _ en: String) -> String {
    AppCopy(tr: tr, en: en).value(for: language)
}

extension AudioAnalysisError {
    func message(for language: AppLanguage) -> String {
        switch self {
        case .cannotAddAudioOutput:
            appText(language, "Ses analizörü video sesini okuyamadı.", "The audio analyzer could not read this video's audio.")
        case .readerStartFailed(let message):
            appText(language, "Ses analizi başlatılamadı: \(message)", "Audio analysis could not start: \(message)")
        case .readerFailed(let message):
            appText(language, "Ses analizi tamamlanamadı: \(message)", "Audio analysis could not finish: \(message)")
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
