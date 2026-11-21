import SwiftUI

struct PaywallView: View {
    let language: AppLanguage

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var store = ProStore.shared
    @State private var isWorking = false
    @State private var message: String?
    @State private var revealed = false

    init(language: AppLanguage) {
        self.language = language
    }

    private func t(_ tr: String, _ en: String) -> String { appText(language, tr, en) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Mono.C.text2)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(t("Kapat", "Close"))
            }
            .padding(.horizontal, 12)

            // Scrolls only when large text outgrows the screen; purchase buttons stay pinned below.
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("CutSense Pro")
                        .monoText(.overline)
                        .foregroundStyle(Mono.C.text3)
                        .monoEntrance(0)
                    Text(t("Reklam yok. Daha ince ayar. Tek ödeme.", "No ads. Finer control. Pay once."))
                        .font(.system(size: 34, weight: .semibold))
                        .tracking(-0.8)
                        .lineLimit(3)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(Mono.C.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, Mono.Space.s)
                        .monoEntrance(1)
                    Text(t("İnce ayar: en kısa duraklama ve nefes payı", "Fine-tune: minimum pause and breathing room"))
                        .monoText(.body)
                        .foregroundStyle(Mono.C.text2)
                        .padding(.top, Mono.Space.s)
                        .monoEntrance(2)
                    comparison
                        .padding(.top, Mono.Space.xl)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Mono.Space.l)
                .padding(.bottom, Mono.Space.m)
            }
            .scrollBounceBehavior(.basedOnSize)

            footer
                .padding(.horizontal, Mono.Space.l)
                .padding(.top, Mono.Space.s)
                .padding(.bottom, Mono.Space.xs)
                .overlay(alignment: .top) { Rectangle().fill(Mono.C.hairline).frame(height: 1) }
        }
        .background(Mono.C.bg.ignoresSafeArea())
        .presentationBackground(Mono.C.bg)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .preferredColorScheme(.dark)
        .tint(Mono.C.text)
        .sensoryFeedback(.warning, trigger: message) { _, new in new != nil }
        .sensoryFeedback(.success, trigger: store.isPro) { _, new in new }
        .task {
            withAnimation(Mono.Motion.pick(Mono.Motion.smooth, reduce: reduceMotion).delay(0.15)) { revealed = true }
            if store.product == nil {
                await store.loadProduct()
                if store.product == nil {
                    message = t("Ürün şu an yüklenemedi. Daha sonra tekrar dene.", "The product could not be loaded right now. Try again later.")
                }
            }
        }
    }

    // MARK: - Comparison

    private static let freeWidth: CGFloat = 64
    private static let proWidth: CGFloat = 72

    private var comparison: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                Text(t("Ücretsiz", "Free"))
                    .monoText(.label)
                    .foregroundStyle(Mono.C.text2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(width: Self.freeWidth)
                Text("Pro")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: Self.proWidth)
            }
            .frame(height: 48)
            .accessibilityHidden(true)
            compareRow(0, t("Sınırsız kesim", "Unlimited cuts"), free: true)
            compareRow(1, t("Her kesimi incele", "Review every cut"), free: true)
            compareRow(2, t("Filigran yok", "No watermark"), free: true)
            compareRow(3, t("Reklamsız", "Ad-free"), free: false)
            compareRow(4, t("İnce ayar", "Fine-tune"), free: false)
        }
        .background(alignment: .trailing) {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Mono.C.text)
                .frame(width: Self.proWidth)
                .mask {
                    // Reveal top-down; Reduce Motion fades instead.
                    GeometryReader { geo in
                        Rectangle().frame(height: revealed || reduceMotion ? geo.size.height : 0)
                    }
                }
                .opacity(revealed ? 1 : 0)
        }
    }

    private func compareRow(_ index: Int, _ title: String, free: Bool) -> some View {
        HStack(spacing: 0) {
            Text(title)
                .monoText(.body)
                .foregroundStyle(Mono.C.text)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 8)
            Image(systemName: free ? "checkmark" : "minus")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(free ? Mono.C.text2 : Mono.C.disabled)
                .frame(width: Self.freeWidth)
            Image(systemName: "checkmark")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.black)
                .frame(width: Self.proWidth)
        }
        .frame(minHeight: 48)
        .overlay(alignment: .top) {
            Rectangle().fill(Mono.C.hairline).frame(height: 1).padding(.trailing, Self.proWidth)
        }
        .monoEntrance(index + 3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(free ? t("Ücretsiz", "Free") : "Pro")")
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: Mono.Space.xs) {
            if let message {
                Text(message)
                    .monoText(.caption)
                    .foregroundStyle(Mono.C.text2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .transition(.opacity)
            }

            if let product = store.product {
                Button {
                    guard !isWorking else { return }
                    Task { await buy() }
                } label: {
                    if isWorking {
                        ProgressView().tint(.black)
                    } else {
                        MonoActionLabel(String(format: t("%@ ile aç", "Unlock for %@"), product.displayPrice),
                                        systemImage: "arrow.right")
                    }
                }
                .buttonStyle(MonoPrimaryButtonStyle())
                .padding(.top, Mono.Space.xxs)
            }

            Text(t("Tek seferlik satın alma. Abonelik yok.", "One-time purchase. No subscription."))
                .monoText(.caption)
                .foregroundStyle(Mono.C.text2)
                .multilineTextAlignment(.center)

            Button { Task { await restore() } } label: {
                Text(t("Satın Alımları Geri Yükle", "Restore Purchases"))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .buttonStyle(MonoTertiaryButtonStyle())
            .disabled(isWorking)

            HStack(spacing: Mono.Space.xs) {
                link(t("Koşullar", "Terms"), "https://cutsense.onarika.net/terms")
                Text("·").foregroundStyle(Mono.C.text3).accessibilityHidden(true)
                link(t("Gizlilik", "Privacy"), "https://cutsense.onarika.net/privacy")
            }
        }
        .animation(Mono.Motion.fade, value: message)
    }

    @ViewBuilder
    private func link(_ title: String, _ address: String) -> some View {
        if let url = URL(string: address) {
            Link(title, destination: url)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Mono.C.text3)
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
            message = t("Satın alma onay bekliyor. Onaylanınca Pro açılır.", "Purchase is pending approval. Pro unlocks once it is approved.")
        case .unavailable:
            message = t("Ürün şu an yüklenemedi. Daha sonra tekrar dene.", "The product could not be loaded right now. Try again later.")
        case .failed(let reason?):
            message = String(format: t("Satın alma tamamlanamadı: %@", "Purchase could not be completed: %@"), reason)
        case .failed(nil):
            message = t("Satın alma tamamlanamadı.", "Purchase could not be completed.")
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
            message = t("Geri yüklenecek satın alma bulunamadı.", "No purchase found to restore.")
        }
    }
}
