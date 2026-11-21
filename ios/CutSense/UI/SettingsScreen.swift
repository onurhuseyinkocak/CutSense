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
    @State private var adFreeUntil = AdFreePass.expiry

    private var language: AppLanguage { AppLanguage.value(from: languageRaw) }
    private func t(_ tr: String, _ en: String) -> String { appText(language, tr, en) }

    private static let site = URL(string: "https://cutsense.onarika.net")
    private static let reviewURL = URL(string: "https://apps.apple.com/app/id6770024868?action=write-review")

    init(urlsInUse: Set<URL> = []) {
        self.urlsInUse = urlsInUse
    }

    var body: some View {
        List {
            // Always reachable for non-Pro users so App Review can find the IAP even if the product loads late.
            if !store.isPro {
                Section {
                    proCard
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }

            Section {
                Picker(selection: $languageRaw) {
                    ForEach(AppLanguage.allCases) { option in
                        Text(option.title).tag(option.rawValue)
                    }
                } label: {
                    row(t("Uygulama dili", "App language"), "globe")
                }
            } header: {
                header(t("Dil", "Language"))
            }
            .monoRows()

            Section {
                HStack(spacing: Mono.Space.s) {
                    glyph("internaldrive")
                    LabeledContent {
                        // The formatter writes "Zero KB" for 0.
                        Text(usage == 0 ? "0 KB" : ByteCountFormatter.string(fromByteCount: usage, countStyle: .file))
                            .contentTransition(.numericText())
                    } label: {
                        Text(t("Geçici dosyalar", "Temporary files"))
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("storageUsageRow")
                Button {
                    _ = WorkFiles.clearUnused(keeping: urlsInUse)
                    withAnimation(Mono.Motion.smooth) { usage = WorkFiles.usageBytes() }
                } label: {
                    row(t("Temizle", "Clear"), "trash")
                }
                .disabled(usage == 0)
            } header: {
                header(t("Depolama", "Storage"))
            } footer: {
                footer(t("CutSense videolarının kopyasını saklamaz.", "CutSense keeps no copies of your videos."))
            }
            .monoRows()

            Section {
                if store.isPro {
                    HStack(spacing: Mono.Space.s) {
                        glyph("checkmark.seal.fill", color: Mono.C.text)
                        LabeledContent(t("Durum", "Status"), value: t("Açık", "Unlocked"))
                    }
                    .accessibilityElement(children: .combine)
                } else if let adFreeUntil {
                    HStack(spacing: Mono.Space.s) {
                        glyph("pause.circle")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(t("Banner reklamlar şu saate kadar kapalı", "Banner ads paused until"))
                            Text(adFreeUntil.formatted(.dateTime.day().month(.abbreviated).hour().minute()
                                .locale(Locale(identifier: language == .pt ? "pt-BR" : language.rawValue))))
                                .monoText(.numeralM, size: 15)
                                .foregroundStyle(Mono.C.text2)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
                Button {
                    Task { await restore() }
                } label: {
                    HStack(spacing: Mono.Space.s) {
                        glyph("arrow.clockwise")
                        if isRestoring {
                            ProgressView()
                        } else {
                            Text(t("Satın Alımları Geri Yükle", "Restore Purchases"))
                        }
                    }
                }
                .disabled(isRestoring)
            } header: {
                header("CutSense Pro")
            } footer: {
                if let restoreMessage { footer(restoreMessage) }
            }
            .monoRows()

            if AdMobService.isEnabled && privacyOptionsRequired {
                Section {
                    Button {
                        Task {
                            await AdMobService.presentPrivacyOptions()
                            privacyOptionsRequired = AdMobService.isPrivacyOptionsRequired
                        }
                    } label: {
                        row(t("Gizlilik tercihlerini yönet", "Manage privacy choices"), "hand.raised")
                    }
                } header: {
                    header(t("Reklam gizliliği", "Ad privacy"))
                }
                .monoRows()
            }

            Section {
                link(t("Gizlilik Politikası", "Privacy Policy"), path: "privacy", glyph: "doc.text")
                link(t("Kullanım Şartları", "Terms of Use"), path: "terms", glyph: "doc.plaintext")
                link(t("Destek", "Support"), path: "support", glyph: "questionmark.circle")
                link(t("CutSense'i Değerlendir", "Rate CutSense"), url: Self.reviewURL, glyph: "star")
                HStack(spacing: Mono.Space.s) {
                    glyph("info.circle")
                    LabeledContent(t("Sürüm", "Version"), value: Self.versionText)
                }
                .accessibilityElement(children: .combine)
            } header: {
                header(t("Hakkında", "About"))
            }
            .monoRows()
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Mono.C.bg.ignoresSafeArea())
        .tint(Mono.C.text)
        .navigationTitle(t("Ayarlar", "Settings"))
        .preferredColorScheme(.dark)
        .sensoryFeedback(.success, trigger: store.isPro) { _, new in new }
        .onAppear {
            usage = WorkFiles.usageBytes()
            adFreeUntil = AdFreePass.expiry
        }
        .task { if store.product == nil { await store.loadProduct() } }
        .sheet(isPresented: $showsPaywall) { ProSheet(language: language) }
    }

    private var proCard: some View {
        Button { showsPaywall = true } label: {
            HStack(spacing: Mono.Space.m) {
                VStack(alignment: .leading, spacing: Mono.Space.xxs) {
                    Text("CutSense Pro")
                        .monoText(.headline)
                        .foregroundStyle(.black)
                    Text(t("Tek seferlik satın alma. Abonelik yok.", "One-time purchase. No subscription."))
                        .monoText(.label)
                        .foregroundStyle(Mono.C.onWhite2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Mono.C.text)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(.black))
            }
            .padding(20)
            .background(Mono.C.text, in: RoundedRectangle(cornerRadius: Mono.Radius.card, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Mono.Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(t("Pro'yu Aç", "Unlock Pro"))
        .accessibilityAddTraits(.isButton)
    }

    private func glyph(_ name: String, color: Color = Mono.C.text2) -> some View {
        Image(systemName: name)
            .font(.system(size: 17, weight: .regular))
            .foregroundStyle(color)
            .frame(width: 28)
            .accessibilityHidden(true)
    }

    private func row(_ title: String, _ glyphName: String) -> some View {
        HStack(spacing: Mono.Space.s) {
            glyph(glyphName)
            Text(title)
        }
    }

    private func header(_ text: String) -> some View {
        Text(text)
            .monoText(.overline)
            .foregroundStyle(Mono.C.text3)
            .textCase(nil)
    }

    private func footer(_ text: String) -> some View {
        Text(text)
            .monoText(.caption)
            .foregroundStyle(Mono.C.text3)
            .padding(.bottom, Mono.Space.xs)
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
    private func link(_ title: String, path: String, glyph glyphName: String) -> some View {
        link(title, url: Self.site?.appending(path: path), glyph: glyphName)
    }

    @ViewBuilder
    private func link(_ title: String, url: URL?, glyph glyphName: String) -> some View {
        if let url {
            Link(destination: url) {
                HStack(spacing: Mono.Space.s) {
                    glyph(glyphName)
                    Text(title)
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Mono.C.text3)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    private static var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}

private extension View {
    func monoRows() -> some View {
        listRowBackground(Mono.C.raised).listRowSeparatorTint(Mono.C.hairline)
    }
}
