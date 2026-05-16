import SwiftUI

struct RootView: View {
    @Environment(AuthManager.self) private var authManager
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false

    var body: some View {
        Group {
            if !hasSeenOnboarding {
                OnboardingScreen()
            } else if authManager.isLoading {
                LoadingView()
            } else if authManager.isAuthenticated {
                ProjectsScreen()
            } else {
                AuthScreen()
            }
        }
        .task(id: hasSeenOnboarding) {
            if hasSeenOnboarding {
                await authManager.restoreSession()
            }
        }
    }
}

private struct LoadingView: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ProgressView()
                .tint(.white)
        }
    }
}
