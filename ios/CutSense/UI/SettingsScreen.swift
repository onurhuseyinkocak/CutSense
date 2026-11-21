import SwiftUI

/// Language, storage, Pro, ad privacy choices, legal links and version.
struct SettingsScreen: View {
    /// Files of the video being reviewed; Clear never deletes these.
    let urlsInUse: Set<URL>

    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.systemDefault.rawValue
    @State private var privacyOptionsRequired = AdMobService.isPrivacyOptionsRequired
    @State private var store = ProStore.shared
    @State private var usage: Int64 = 0
    @State private var showsPaywall = false
    @State private var isRestoring = false
    @State private var restoreMessage: String?

    private var language: AppLanguage { AppLanguage.value(from: languageRaw) }
    private func t(_ tr: String, _ en: String) -> String { appText(language, tr, en) }

    private static let site = URL(string: "https://cutsense.onarika.net")

    init(urlsInUse: Set<URL> = []) {
        self.urlsInUse = urlsInUse
    }

    var body: some View {
        List {
            Section(t("Dil", "Language")) {
                Picker(t("Uygulama dili", "App language"), selection: $languageRaw) {
                    ForEach(AppLanguage.allCases) { option in
                        Text(option.title).tag(option.rawValue)
                    }
                }
            }

            Section {
                LabeledContent(t("Geçici dosyalar", "Temporary files"),
                               value: ByteCountFormatter.string(fromByteCount: usage, countStyle: .file))
                    .accessibilityIdentifier("storageUsageRow")
                Button(t("Temizle", "Clear")) {
                    _ = WorkFiles.clearUnused(keeping: urlsInUse)
                    usage = WorkFiles.usageBytes()
                }
                .disabled(usage == 0)
            } header: {
                Text(t("Depolama", "Storage"))
            } footer: {
                Text(t("CutSense videolarının kopyasını saklamaz.", "CutSense keeps no copies of your videos."))
            }

            Section {
                LabeledContent(t("Durum", "Status"),
                               value: store.isPro ? t("Açık", "Unlocked") : t("Ücretsiz sürüm", "Free version"))
                if store.canOfferPro {
                    Button(t("Pro'yu Aç", "Unlock Pro")) { showsPaywall = true }
                }
                Button {
                    Task { await restore() }
                } label: {
                    if isRestoring { ProgressView() } else { Text(t("Satın Alımları Geri Yükle", "Restore Purchases")) }
                }
                .disabled(isRestoring)
            } header: {
                Text("CutSense Pro")
            } footer: {
                if let restoreMessage { Text(restoreMessage) }
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
        .onAppear { usage = WorkFiles.usageBytes() }
        .task { if store.product == nil { await store.loadProduct() } }
        .sheet(isPresented: $showsPaywall) { PaywallView(language: language) }
    }

    private func restore() async {
        isRestoring = true
        restoreMessage = nil
        await store.restore()
        isRestoring = false
        restoreMessage = store.isPro
            ? t("Pro geri yüklendi.", "Pro restored.")
            : t("Geri yüklenecek satın alma bulunamadı.", "No purchase found to restore.")
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
