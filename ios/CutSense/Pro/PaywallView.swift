import SwiftUI

struct PaywallView: View {
    let language: AppLanguage

    @Environment(\.dismiss) private var dismiss
    @State private var store = ProStore.shared
    @State private var isWorking = false
    @State private var message: String?

    private static let accent = Color(red: 182 / 255, green: 243 / 255, blue: 92 / 255)

    init(language: AppLanguage) {
        self.language = language
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.05, green: 0.06, blue: 0.09), .black],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white.opacity(0.7))
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(appText(language, "Kapat", "Close"))
                }

                Text("CutSense Pro")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                VStack(alignment: .leading, spacing: 16) {
                    bullet("nosign", appText(language, "Reklamsız, sonsuza dek", "No ads, ever"))
                    bullet("slider.horizontal.3", appText(language, "İnce ayar: en kısa duraklama ve nefes payı", "Fine-tune: minimum pause and breathing room"))
                    bullet("checkmark.seal", appText(language, "Tek seferlik satın alma. Abonelik yok.", "One-time purchase. No subscription."))
                }

                comparison

                Spacer(minLength: 0)

                if let message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.75))
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 12) {
                    if let product = store.product {
                        Button { Task { await buy() } } label: {
                            Group {
                                if isWorking {
                                    ProgressView().tint(.black)
                                } else {
                                    Text(String(format: appText(language, "%@ ile aç", "Unlock for %@"), product.displayPrice))
                                }
                            }
                            .font(.system(.headline, design: .rounded).weight(.bold))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity, minHeight: 54)
                            .background(Self.accent, in: Capsule())
                        }
                        .disabled(isWorking)
                    }

                    Button { Task { await restore() } } label: {
                        Text(appText(language, "Satın Alımları Geri Yükle", "Restore Purchases"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .disabled(isWorking)

                    HStack(spacing: 20) {
                        link(appText(language, "Koşullar", "Terms"), "https://cutsense.onarika.net/terms")
                        link(appText(language, "Gizlilik", "Privacy"), "https://cutsense.onarika.net/privacy")
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .preferredColorScheme(.dark)
        .task {
            if store.product == nil {
                await store.loadProduct()
                if store.product == nil {
                    message = appText(language, "Ürün şu an yüklenemedi. Daha sonra tekrar dene.", "The product could not be loaded right now. Try again later.")
                }
            }
        }
    }

    private var comparison: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Text(appText(language, "Ücretsiz", "Free")).frame(width: 64)
                Text("Pro").foregroundStyle(Self.accent).frame(width: 64)
            }
            .font(.footnote.weight(.bold))
            .foregroundStyle(.white.opacity(0.7))
            .padding(.bottom, 8)
            compareRow(appText(language, "Sınırsız kesim", "Unlimited cuts"), free: true)
            compareRow(appText(language, "Her kesimi incele", "Review every cut"), free: true)
            compareRow(appText(language, "Filigran yok", "No watermark"), free: true)
            compareRow(appText(language, "Reklamsız", "Ad-free"), free: false)
            compareRow(appText(language, "İnce ayar", "Fine-tune"), free: false)
        }
        .padding(16)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func compareRow(_ title: String, free: Bool) -> some View {
        HStack {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 8)
            mark(free).frame(width: 64)
            mark(true).frame(width: 64)
        }
        .padding(.vertical, 7)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(free ? appText(language, "Ücretsiz", "Free") : "Pro")")
    }

    private func mark(_ included: Bool) -> some View {
        Image(systemName: included ? "checkmark" : "minus")
            .font(.subheadline.weight(.bold))
            .foregroundStyle(included ? Self.accent : .white.opacity(0.3))
    }

    private func bullet(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Self.accent)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(text)
                .font(.system(.body, design: .rounded).weight(.medium))
                .foregroundStyle(.white)
        }
    }

    @ViewBuilder
    private func link(_ title: String, _ address: String) -> some View {
        if let url = URL(string: address) {
            Link(title, destination: url)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.6))
                .frame(minHeight: 44)
        }
    }

    private func buy() async {
        isWorking = true
        defer { isWorking = false }
        message = nil
        switch await store.purchase() {
        case .purchased:
            dismiss()
        case .cancelled:
            break
        case .pending:
            message = appText(language, "Satın alma onay bekliyor. Onaylanınca Pro açılır.", "Purchase is pending approval. Pro unlocks once it is approved.")
        case .failed(let reason):
            message = String(format: appText(language, "Satın alma tamamlanamadı: %@", "Purchase could not be completed: %@"), reason)
        }
    }

    private func restore() async {
        isWorking = true
        defer { isWorking = false }
        message = nil
        await store.restore()
        if store.isPro {
            dismiss()
        } else {
            message = appText(language, "Geri yüklenecek satın alma bulunamadı.", "No purchase found to restore.")
        }
    }
}
