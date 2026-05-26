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
            } else {
                // App is fully usable in "local mode" even without auth. AuthScreen is
                // only opened when the user explicitly chooses to sign in (e.g. from
                // AccountScreen) so cloud sync becomes available.
                ProjectsScreen()
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
