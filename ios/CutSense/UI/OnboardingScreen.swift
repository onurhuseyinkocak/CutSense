import SwiftUI

struct OnboardingScreen: View {
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var currentPage = 0
    @State private var dragOffset: CGFloat = 0

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            showLogo: true,
            animation: "sparkles.rectangle.stack",
            title: "CutSense Studio",
            subtitle: "Videonu otomatik düzenle, sonra her ayrıntıya kendin dokun."
        ),
        OnboardingPage(
            animation: "waveform.badge.magnifyingglass",
            title: "Konuşmayı anla",
            subtitle: "Konuşma dilini seç, altyazıyı kontrol et, hatalı kelimeleri düzelt."
        ),
        OnboardingPage(
            animation: "timeline.selection",
            title: "Son söz sende",
            subtitle: "Klipleri, altyazıları, efektleri ve sesleri zaman çizgisinden düzenle."
        ),
    ]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    if currentPage < pages.count - 1 {
                        Button("Skip") {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                                hasSeenOnboarding = true
                            }
                        }
                        .accessibilityIdentifier("onboardingSkipButton")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.trailing, 24)
                        .padding(.top, 12)
                    }
                }
                .frame(height: 44)

                GeometryReader { geo in
                    HStack(spacing: 0) {
                        ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                            OnboardingPageView(page: page, isActive: index == currentPage)
                                .frame(width: geo.size.width)
                        }
                    }
                    .offset(x: -CGFloat(currentPage) * geo.size.width + dragOffset)
                    .animation(.spring(response: 0.4, dampingFraction: 0.85), value: currentPage)
                    .gesture(
                        DragGesture(minimumDistance: 20)
                            .onChanged { value in
                                dragOffset = value.translation.width
                            }
                            .onEnded { value in
                                let threshold: CGFloat = geo.size.width * 0.25
                                if value.translation.width < -threshold, currentPage < pages.count - 1 {
                                    currentPage += 1
                                } else if value.translation.width > threshold, currentPage > 0 {
                                    currentPage -= 1
                                }
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                    dragOffset = 0
                                }
                            }
                    )
                }

                HStack(spacing: 8) {
                    ForEach(0..<pages.count, id: \.self) { index in
                        Capsule()
                            .fill(index == currentPage ? Color.white : Color.white.opacity(0.25))
                            .frame(
                                width: index == currentPage ? 24 : 8,
                                height: 8
                            )
                            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: currentPage)
                    }
                }
                .padding(.bottom, 32)

                Button {
                    if currentPage < pages.count - 1 {
                        currentPage += 1
                    } else {
                        hasSeenOnboarding = true
                    }
                } label: {
                    Text(currentPage < pages.count - 1 ? "Continue" : "Get Started")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.white)
                        .foregroundStyle(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .accessibilityIdentifier("onboardingContinueButton")
                .padding(.horizontal, 24)
                .padding(.bottom, 48)
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Page Model

private struct OnboardingPage {
    let showLogo: Bool
    let animation: String
    let title: String
    let subtitle: String

    init(showLogo: Bool = false, animation: String, title: String, subtitle: String) {
        self.showLogo = showLogo
        self.animation = animation
        self.title = title
        self.subtitle = subtitle
    }
}

// MARK: - Page View

private struct OnboardingPageView: View {
    let page: OnboardingPage
    let isActive: Bool

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            ZStack {
                Image(systemName: page.animation)
                    .font(.system(size: 90, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.mint)
                    .frame(width: 240, height: 240)

                if page.showLogo {
                    Image("SplashLogo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 100, height: 100)
                        .clipShape(RoundedRectangle(cornerRadius: 22))
                        .shadow(color: .white.opacity(0.15), radius: 20)
                }
            }
            .frame(width: 260, height: 260)

            VStack(spacing: 14) {
                Text(page.title)
                    .font(.title.bold())
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text(page.subtitle)
                    .font(.body)
                    .foregroundStyle(.gray)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 32)
            }

            Spacer()
            Spacer()
        }
    }
}
