import SwiftUI

/// Language, ad privacy choices, legal links and version.
struct SettingsScreen: View {
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.systemDefault.rawValue
    @State private var privacyOptionsRequired = AdMobService.isPrivacyOptionsRequired

    private var language: AppLanguage { AppLanguage.value(from: languageRaw) }
    private func t(_ tr: String, _ en: String) -> String { appText(language, tr, en) }

    private static let site = URL(string: "https://cutsense.onarika.net")

    var body: some View {
        List {
            Section(t("Dil", "Language")) {
                Picker(t("Uygulama dili", "App language"), selection: $languageRaw) {
                    ForEach(AppLanguage.allCases) { option in
                        Text(option.title).tag(option.rawValue)
                    }
                }
            }

            if AdMobService.isEnabled && privacyOptionsRequired {
                Section(t("Reklam gizliliği", "Ad privacy")) {
                    Button(t("Gizlilik tercihlerini yönet", "Manage privacy choices")) {
                        Task {
                            await AdMobService.presentPrivacyOptions()
                            privacyOptionsRequired = AdMobService.isPrivacyOptionsRequired
                        }
                    }
                }
            }

            Section(t("Hakkında", "About")) {
                link(t("Gizlilik Politikası", "Privacy Policy"), path: "privacy")
                link(t("Kullanım Şartları", "Terms of Use"), path: "terms")
                link(t("Destek", "Support"), path: "support")
                LabeledContent(t("Sürüm", "Version"), value: Self.versionText)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.black.ignoresSafeArea())
        .navigationTitle(t("Ayarlar", "Settings"))
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func link(_ title: String, path: String) -> some View {
        if let url = Self.site?.appending(path: path) {
            Link(title, destination: url)
        }
    }

    private static var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}
