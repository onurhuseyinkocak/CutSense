import SwiftUI

// MARK: - ProSheet

/// Hosts the offer while one is live, otherwise the regular paywall.
struct ProSheet: View {
    let language: AppLanguage

    @Environment(\.dismiss) private var dismiss
    /// Latched on open: a scenePhase refresh mid-purchase (isPro flips, `active` goes nil) must not swap
    /// the panel out before its success seal. Only `onExpired` clears it.
    @State private var offer: OfferCenter.Active?

    init(language: AppLanguage) {
        self.language = language
        let live = ProStore.shared.offerPrices != nil && !ProStore.shared.isPro
        _offer = State(initialValue: live ? OfferCenter.shared.active : nil)
    }

    var body: some View {
        ZStack {
            if let offer {
                OfferPanel(kind: offer.kind, endsAt: offer.endsAt, language: language,
                           onClose: { dismiss() },
                           onExpired: { withAnimation(Mono.Motion.fade) { self.offer = nil } })
                    .transition(.opacity)
            } else {
                PaywallView(language: language)
                    .transition(.opacity)
            }
        }
        .background(Mono.C.bg.ignoresSafeArea())
        .presentationBackground(Mono.C.bg)
    }
}

// MARK: - OfferPanel

struct OfferPanel: View {
    let kind: OfferCenter.Kind
    let endsAt: Date
    let language: AppLanguage
    let onClose: () -> Void
    let onExpired: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var store = ProStore.shared
    @State private var isWorking = false
    @State private var succeeded = false
    @State private var message: String?
    /// 0 regular price big, 1 strike drawn, 2 offer revealed.
    @State private var phase = 0
    @State private var strike: CGFloat = 0
    @Namespace private var priceSpace

    init(kind: OfferCenter.Kind, endsAt: Date, language: AppLanguage,
         onClose: @escaping () -> Void, onExpired: @escaping () -> Void) {
        self.kind = kind
        self.endsAt = endsAt
        self.language = language
        self.onClose = onClose
        self.onExpired = onExpired
    }

    private func t(_ tr: String, _ en: String) -> String { appText(language, tr, en) }
    private var isExpired: Bool { Date() >= endsAt }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button { onClose() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Mono.C.text2)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(t("Kapat", "Close"))
            }
            .padding(.horizontal, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(kind == .welcome ? t("Hoş geldin teklifi", "Welcome offer") : t("15 dakikalık teklif", "15-minute offer"))
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
                    if let prices = store.offerPrices {
                        priceBlock(prices)
                            .padding(.top, Mono.Space.l)
                    }
                    timeRow
                        .padding(.top, Mono.Space.m)
                        .monoEntrance(2)
                    VStack(spacing: 0) {
                        benefit(0, t("Hiç reklam yok", "No ads, ever"))
                        benefit(1, t("İnce ayar: en kısa duraklama ve nefes payı", "Fine-tune: minimum pause and breathing room"))
                        benefit(2, t("Tek seferlik satın alma. Abonelik yok.", "One-time purchase. No subscription."))
                    }
                    .padding(.top, Mono.Space.l)
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
        .overlay {
            if succeeded {
                ZStack {
                    Mono.C.scrim.ignoresSafeArea()
                    MonoCheckSeal(size: 72)
                }
                .transition(.opacity)
            }
        }
        .background(Mono.C.bg.ignoresSafeArea())
        .presentationBackground(Mono.C.bg)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .preferredColorScheme(.dark)
        .tint(Mono.C.text)
        .sensoryFeedback(.warning, trigger: message) { _, new in new != nil }
        .sensoryFeedback(.success, trigger: succeeded) { _, new in new }
        .sensoryFeedback(.impact(weight: .medium), trigger: phase) { _, new in new == 2 && !reduceMotion }
        .task { await reveal() }
        .task(id: endsAt) {
            // One expiry path for both kinds; the countdown view only renders.
            let wait = endsAt.timeIntervalSinceNow
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            guard !Task.isCancelled else { return }
            expireIfIdle()
        }
        .onChange(of: store.offerPrices == nil) { _, gone in
            if gone, !isWorking, !succeeded { onExpired() }
        }
    }

    private func expireIfIdle() {
        // A purchase started inside the window is allowed to finish; buy() re-checks afterwards.
        guard !isWorking, !succeeded else { return }
        onExpired()
    }

    // MARK: Price

    private func reveal() async {
        if store.offerPrices == nil, !isWorking { await store.loadProduct() }
        if reduceMotion {
            strike = 1
            withAnimation(Mono.Motion.fade) { phase = 2 }
            return
        }
        try? await Task.sleep(for: .seconds(0.35))
        withAnimation(.easeInOut(duration: 0.3)) { strike = 1; phase = 1 }
        try? await Task.sleep(for: .seconds(0.3))
        withAnimation(Mono.Motion.smooth) { phase = 2 }
    }

    private func priceBlock(_ prices: ProStore.OfferPrices) -> some View {
        VStack(alignment: .leading, spacing: Mono.Space.xs) {
            if phase < 2 {
                regularPrice(prices.regular, style: .numeralXL)
            } else {
                HStack(alignment: .center, spacing: Mono.Space.s) {
                    Text(prices.offer)
                        .monoText(.numeralXL)
                        .foregroundStyle(Mono.C.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .transition(reduceMotion ? .opacity : AnyTransition(.blurReplace))
                    MonoBadge("\u{2212}\(prices.percent)%", filled: true)
                        .transition(reduceMotion ? .opacity : .scale(scale: 0.6).combined(with: .opacity))
                        .animation(Mono.Motion.pick(Mono.Motion.bouncy, reduce: reduceMotion), value: phase)
                }
                HStack(alignment: .firstTextBaseline, spacing: Mono.Space.xs) {
                    Text(t("Normal fiyat", "Regular price"))
                        .monoText(.caption)
                        .foregroundStyle(Mono.C.text3)
                    regularPrice(prices.regular, style: .numeralM)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(prices.offer), \u{2212}\(prices.percent)%. \(t("Normal fiyat", "Regular price")) \(prices.regular)")
    }

    private func regularPrice(_ text: String, style: Mono.Style) -> some View {
        Text(text)
            .monoText(style)
            .foregroundStyle(phase < 2 ? Mono.C.text : Mono.C.text2)
            .lineLimit(1)
            .overlay {
                // Drawn line, not .strikethrough, so the trim survives the matched-geometry shrink.
                StrikeLine()
                    .trim(from: 0, to: strike)
                    .stroke(phase < 2 ? Mono.C.text : Mono.C.text2, lineWidth: style == .numeralXL ? 3 : 1.5)
            }
            .matchedGeometryEffect(id: "regular", in: priceSpace)
    }

    // MARK: Time

    @ViewBuilder
    private var timeRow: some View {
        switch kind {
        case .welcome:
            Text(String(format: t("Hoş geldin fiyatı %@ tarihine kadar", "Welcome price until %@"), formatted(endsAt, time: true)))
                .monoText(.caption)
                .foregroundStyle(Mono.C.text2)
        case .flash:
            VStack(alignment: .leading, spacing: Mono.Space.xs) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remaining = max(0, endsAt.timeIntervalSince(context.date))
                    VStack(alignment: .leading, spacing: Mono.Space.xs) {
                        Text(clock(remaining))
                            .monoText(.numeralL)
                            .foregroundStyle(Mono.C.text)
                            .contentTransition(.numericText(countsDown: true))
                        Rectangle()
                            .fill(Mono.C.hairline)
                            .frame(height: 2)
                            .overlay(alignment: .leading) {
                                GeometryReader { geo in
                                    Rectangle()
                                        .fill(Mono.C.text)
                                        .frame(width: geo.size.width * min(1, remaining / 900))
                                }
                            }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(clock(remaining))
                }
                Text(String(format: t("%@ itibarıyla biter", "Ends at %@"), formatted(endsAt, time: false)))
                    .monoText(.caption)
                    .foregroundStyle(Mono.C.text2)
                Text(t("Sonrasında normal fiyat geçerli.", "After that, the regular price applies."))
                    .monoText(.caption)
                    .foregroundStyle(Mono.C.text3)
            }
        }
    }

    private func formatted(_ date: Date, time withDate: Bool) -> String {
        let style = withDate
            ? Date.FormatStyle(date: .abbreviated, time: .shortened)
            : Date.FormatStyle(date: .omitted, time: .shortened)
        return date.formatted(style.locale(Locale(identifier: language.rawValue)))
    }

    // MARK: Benefits

    private func benefit(_ index: Int, _ title: String) -> some View {
        HStack(spacing: Mono.Space.s) {
            Image(systemName: "checkmark")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Mono.C.text)
                .accessibilityHidden(true)
            Text(title)
                .monoText(.body)
                .foregroundStyle(Mono.C.text)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 0)
        }
        .frame(minHeight: 48)
        .overlay(alignment: .top) { Rectangle().fill(Mono.C.hairline).frame(height: 1) }
        .monoEntrance(index + 3)
        .accessibilityElement(children: .combine)
    }

    // MARK: Footer

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

            if let prices = store.offerPrices {
                Button {
                    guard !isWorking, !succeeded else { return }
                    Task { await buy() }
                } label: {
                    if isWorking {
                        ProgressView().tint(.black)
                    } else {
                        MonoActionLabel(String(format: t("%@ ile aç", "Unlock for %@"), prices.offer),
                                        systemImage: "arrow.right")
                    }
                }
                .buttonStyle(MonoPrimaryButtonStyle())
                .accessibilityIdentifier("offerBuyButton")
                .padding(.top, Mono.Space.xxs)
            }

            HStack(spacing: Mono.Space.xs) {
                Button { Task { await restore() } } label: {
                    Text(t("Satın Alımları Geri Yükle", "Restore Purchases"))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .buttonStyle(MonoTertiaryButtonStyle())
                .disabled(isWorking)
                dot
                link(t("Koşullar", "Terms"), "https://cutsense.onarika.net/terms")
                dot
                link(t("Gizlilik", "Privacy"), "https://cutsense.onarika.net/privacy")
            }
            .frame(height: 44)
        }
        .animation(Mono.Motion.fade, value: message)
    }

    private var dot: some View {
        Text("·").foregroundStyle(Mono.C.text3).accessibilityHidden(true)
    }

    @ViewBuilder
    private func link(_ title: String, _ address: String) -> some View {
        if let url = URL(string: address) {
            Link(title, destination: url)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Mono.C.text3)
                .lineLimit(1)
                .frame(minHeight: 44)
        }
    }

    private func finishSuccess() async {
        withAnimation(Mono.Motion.fade) { succeeded = true }
        try? await Task.sleep(for: .seconds(0.9))
        onClose()
    }

    private func buy() async {
        isWorking = true
        message = nil
        let outcome = await store.purchaseOffer()
        isWorking = false
        switch outcome {
        case .purchased:
            await finishSuccess()
            return
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
        // The window may have closed while the system sheet was up.
        if isExpired { onExpired() }
    }

    private func restore() async {
        isWorking = true
        message = nil
        await store.restore()
        isWorking = false
        if store.isPro {
            await finishSuccess()
        } else {
            message = t("Geri yüklenecek satın alma bulunamadı.", "No purchase found to restore.")
            if isExpired { onExpired() }
        }
    }
}

private struct StrikeLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX - 2, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX + 2, y: rect.midY))
        return path
    }
}

private func clock(_ remaining: TimeInterval) -> String {
    let total = max(0, Int(remaining))
    return String(format: "%02d:%02d", total / 60, total % 60)
}

// MARK: - OfferPill

struct OfferPill: View {
    let language: AppLanguage
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var offers = OfferCenter.shared
    @State private var store = ProStore.shared

    init(language: AppLanguage, action: @escaping () -> Void) {
        self.language = language
        self.action = action
    }

    private var visible: Bool { offers.active != nil && !store.isPro && store.offerPrices != nil }

    var body: some View {
        // Always-present container so the insertion animation and haptic fire.
        ZStack {
            if visible, let active = offers.active, let prices = store.offerPrices {
                Button(action: action) {
                    label(active, percent: prices.percent)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("offerPill")
                .accessibilityLabel(appText(language, "Pro teklifi", "Pro offer"))
                .transition(reduceMotion ? .opacity : .scale(scale: 0.9).combined(with: .opacity))
            }
        }
        .animation(Mono.Motion.pick(Mono.Motion.bouncy, reduce: reduceMotion), value: visible)
        .sensoryFeedback(.impact(weight: .light), trigger: visible) { _, new in new }
        .task(id: offers.active?.endsAt) {
            guard let endsAt = offers.active?.endsAt else { return }
            let wait = endsAt.timeIntervalSinceNow
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            guard !Task.isCancelled else { return }
            offers.refresh()
        }
    }

    @ViewBuilder
    private func label(_ active: OfferCenter.Active, percent: Int) -> some View {
        let base = "Pro \u{2212}\(percent)%"
        Group {
            if active.kind == .flash {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    capsule("\(base) · \(clock(active.endsAt.timeIntervalSince(context.date)))")
                }
            } else {
                capsule(base)
            }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    private func capsule(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .bold).monospacedDigit())
            .foregroundStyle(.black)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(Capsule().fill(Mono.C.text))
            .accessibilityValue(text)
    }
}
