import SwiftUI

// MARK: - HomeShell
// Hosts the primary tabs of the app: Create (editor) and Account.
// Uses a custom glass tab bar so the chrome stays cinematic and on-brand.

enum HomeTab: String, CaseIterable, Identifiable {
    case create, account
    var id: String { rawValue }

    func title(for language: AppLanguage) -> String {
        switch self {
        case .create: appText(language, "Kes", "Cut")
        case .account: appText(language, "Hesap", "Account")
        }
    }

    var icon: String {
        switch self {
        case .create: "scissors"
        case .account: "person.crop.circle.fill"
        }
    }

}

struct HomeShell: View {
    @State private var tab: HomeTab = .create
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.systemDefault.rawValue

    private var language: AppLanguage { AppLanguage.value(from: languageRaw) }

    var body: some View {
        ZStack {
            CutSenseTheme.canvas.ignoresSafeArea()

            Group {
                switch tab {
                case .create: CreateScreen()
                case .account: NavigationStack { AccountScreen() }
                }
            }
            .padding(.bottom, 76) // reserve space for floating tab bar

            VStack {
                Spacer()
                GlassTabBar(selection: $tab, language: language)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 14)
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Glass Tab Bar

private struct GlassTabBar: View {
    @Binding var selection: HomeTab
    let language: AppLanguage

    var body: some View {
        HStack(spacing: 4) {
            ForEach(HomeTab.allCases) { tab in
                Button {
                    HapticEngine.select()
                    withAnimation(CutSenseTheme.springSnappy) {
                        selection = tab
                    }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 18, weight: .bold))
                        Text(tab.title(for: language))
                            .font(.system(size: 10, weight: .heavy, design: .rounded))
                    }
                    .foregroundStyle(selection == tab ? Color.white : Color.white.opacity(0.65))
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(
                        Group {
                            if selection == tab {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(CutSenseTheme.surfaceHigh)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                                            .strokeBorder(CutSenseTheme.borderStrong, lineWidth: 1)
                                    )
                                    .padding(4)
                            }
                        }
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color.white.opacity(0.04))
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(CutSenseTheme.border, lineWidth: 1)
            }
        )
        .shadow(color: .black.opacity(0.45), radius: 28, y: 14)
    }
}
