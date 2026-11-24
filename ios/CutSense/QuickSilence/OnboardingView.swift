import SwiftUI

/// First-launch onboarding, 3 pages, then the welcome offer when it can be sold. Policy: docs/offer-policy-owner.md.
/// The caller persists completion in `onFinish`; this view only tells OfferCenter how onboarding ended.
struct OnboardingView: View {
    private let onFinish: () -> Void
    private let freeze: Double?

    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.systemDefault.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page: Int
    @State private var enteredAt = Date.now
    @State private var showsOffer = false

    private static let pageCount = 3
    private static let badgeTimes: [Double] = [0.8, 0.95, 1.1]

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        let first = env["CUTSENSE_ONBOARDING_PAGE"].flatMap(Int.init).map { min(max($0, 0), Self.pageCount - 1) } ?? 0
        freeze = env["CUTSENSE_ONBOARDING_FREEZE"].flatMap(Double.init)
        #else
        let first = 0
        freeze = nil
        #endif
        _page = State(initialValue: first)
    }

    private var language: AppLanguage { AppLanguage.value(from: languageRaw) }
    private func t(_ tr: String, _ en: String) -> String { appText(language, tr, en) }
    private var isLast: Bool { page == Self.pageCount - 1 }

    var body: some View {
        ZStack {
            if showsOffer {
                OfferPanel(kind: .welcome, endsAt: nil, language: language, onClose: finish, onExpired: finish)
                    .transition(.opacity)
            } else {
                pages.transition(.opacity)
            }
        }
        .animation(Mono.Motion.pick(Mono.Motion.smooth, reduce: reduceMotion), value: showsOffer)
    }

    private var pages: some View {
        GeometryReader { geo in
            let screenHeight = geo.size.height + geo.safeAreaInsets.top + geo.safeAreaInsets.bottom
            VStack(spacing: 0) {
                topBar
                OnboardingStage(page: page, language: language, fixedTime: freeze)
                    .frame(height: min(300, screenHeight * 0.36))
                    .padding(.top, Mono.Space.xs)
                copy
                    .padding(.top, 28)
                Spacer(minLength: 0)
                // A 1.0.x Pro owner upgrading sees onboarding too; the ads line isn't true for them.
                if isLast && !ProStore.shared.isPro {
                    Text(t("Reklamlı ve ücretsiz. Tek seferlik Pro reklamları kaldırır.", "Free with ads. One-time Pro removes them."))
                        .monoText(.caption)
                        .foregroundStyle(Mono.C.text3)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, minHeight: 16)
                        .padding(.bottom, Mono.Space.xs)
                        .transition(.opacity)
                }
                Button(action: advance) {
                    MonoActionLabel(isLast ? t("Kesmeye başla", "Start cutting") : t("Devam", "Continue"), systemImage: "arrow.right")
                }
                .buttonStyle(MonoPrimaryButtonStyle())
                .accessibilityIdentifier("onboardingContinue")
            }
            .padding(.horizontal, Mono.Space.l)
            .padding(.bottom, Mono.Space.m)
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .foregroundStyle(Mono.C.text)
        .background(Mono.C.bg.ignoresSafeArea())
        .contentShape(Rectangle())
        .gesture(swipe)
        .sensoryFeedback(.impact(flexibility: .soft), trigger: page)
        .transaction { if freeze != nil { $0.disablesAnimations = true; $0.animation = nil } }
        // The title's 96 pt box and the fixed stage clip at accessibility sizes.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .preferredColorScheme(.dark)
    }

    // MARK: Parts

    private var topBar: some View {
        HStack {
            HStack(spacing: 6) {
                ForEach(0..<Self.pageCount, id: \.self) { i in
                    Capsule()
                        .fill(i == page ? Mono.C.text : Mono.C.strong)
                        .frame(width: 24, height: 3)
                }
            }
            .accessibilityHidden(true)
            Spacer()
            Button(t("Geç", "Skip"), action: offerOrFinish)
                .buttonStyle(MonoTertiaryButtonStyle())
                .accessibilityIdentifier("onboardingSkip")
        }
        .frame(height: 44)
    }

    private var copy: some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 0) {
                Text("CutSense")
                    .monoText(.overline)
                    .foregroundStyle(Mono.C.text3)
                    .frame(height: 14)
                    .monoEntrance(0)
                Text(title)
                    .monoText(.display)
                    .frame(maxHeight: 96, alignment: .topLeading)
                    .padding(.top, Mono.Space.xs)
                    .accessibilityAddTraits(.isHeader)
                    .monoEntrance(1)
                Text(message)
                    .monoText(.body)
                    .foregroundStyle(Mono.C.text2)
                    .lineLimit(3)
                    .minimumScaleFactor(0.85)
                    .frame(maxHeight: 60, alignment: .topLeading)
                    .padding(.top, Mono.Space.s)
                    .monoEntrance(2)
                if isLast { badges.padding(.top, Mono.Space.s) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .id(page)
            .transition(reduceMotion ? AnyTransition.opacity : AnyTransition(.blurReplace))
        }
    }

    private var title: String {
        switch page {
        case 0: t("Sessizliği kes. Konuşma kalsın.", "Cut the silence. Keep the talk.")
        case 1: t("Her kesim senin onayında.", "You approve every cut.")
        default: t("Videon iPhone'undan hiç çıkmaz.", "Your video never leaves your iPhone.")
        }
    }

    private var message: String {
        switch page {
        case 0: t("CutSense videondaki her duraklamayı bulur, boşluğu saniyeler içinde kapatır.",
                  "CutSense finds every pause in your video and closes the gap in seconds.")
        case 1: t("Kaydetmeden önce her kesimi gör. Tek dokunuşla duraklamayı geri al.",
                  "See each cut before saving. Keep a pause with one tap.")
        default: t("Her şey cihazda çalışır. Yükleme yok, hesap yok, filigran yok.",
                   "Everything runs on-device. No upload, no account, no watermark.")
        }
    }

    /// Badges land at 0.8 / 0.95 / 1.1 s after page 3 appears; an explicit schedule, no per-frame clock.
    @ViewBuilder
    private var badges: some View {
        if let fixed = freeze ?? (reduceMotion ? OnboardingTimeline.restTime[page] : nil) {
            badgeRow(Self.badgeTimes.filter { $0 <= fixed }.count)
        } else {
            TimelineView(.explicit(Self.badgeTimes.map { enteredAt.addingTimeInterval($0) })) { tl in
                badgeRow(Self.badgeTimes.filter { enteredAt.addingTimeInterval($0) <= tl.date }.count)
            }
        }
    }

    private func badgeRow(_ count: Int) -> some View {
        let items = [t("Yükleme yok", "No upload"), t("Hesap yok", "No account"), t("Filigran yok", "No watermark")]
        let badge = { (i: Int) in
            MonoBadge(items[i])
                .fixedSize()
                .transition(reduceMotion ? .opacity : .scale(scale: 0.8).combined(with: .opacity))
        }
        // QA-FIX: long translations (de "Kein Wasserzeichen", es/pt) truncated in one row; wrap the third badge instead.
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: Mono.Space.xs) { ForEach(0..<count, id: \.self, content: badge) }
            VStack(alignment: .leading, spacing: Mono.Space.xs) {
                HStack(spacing: Mono.Space.xs) { ForEach(0..<min(count, 2), id: \.self, content: badge) }
                if count > 2 { badge(2) }
            }
        }
        .frame(minHeight: 22, alignment: .leading)
        .animation(Mono.Motion.pick(Mono.Motion.bouncy, reduce: reduceMotion), value: count)
    }

    // MARK: Navigation

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 20).onEnded { value in
            let dx = value.translation.width
            guard abs(dx) > 50, abs(dx) > abs(value.translation.height) else { return }
            go(to: page + (dx < 0 ? 1 : -1))
        }
    }

    private func advance() {
        guard isLast else { return go(to: page + 1) }
        offerOrFinish()
    }

    /// Start cutting and Skip both land on the welcome offer when it can be shown.
    private func offerOrFinish() {
        let store = ProStore.shared
        if store.welcomePrices != nil, !store.isPro { showsOffer = true } else { finish() }
    }

    /// Every exit: Skip, Start cutting without an offer, and the offer's close / Not now / success.
    private func finish() {
        OfferCenter.shared.noteOnboardingFinished(purchased: ProStore.shared.isPro)
        onFinish()
    }

    private func go(to target: Int) {
        guard (0..<Self.pageCount).contains(target), target != page else { return }
        withAnimation(Mono.Motion.pick(Mono.Motion.smooth, reduce: reduceMotion)) {
            page = target
            enteredAt = .now
        }
    }
}

#if DEBUG
#Preview("Onboarding") { OnboardingView {} }
#endif
