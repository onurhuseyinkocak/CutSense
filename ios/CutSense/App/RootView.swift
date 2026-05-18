import SwiftUI

struct RootView: View {
    @Environment(AuthManager.self) private var authManager
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false

    var body: some View {
        Group {
            #if DEBUG
            // Bypass auth + onboarding in DEBUG builds for simulator testing
            ProjectsScreen()
            #else
            if !hasSeenOnboarding {
                OnboardingScreen()
            } else if authManager.isLoading {
                LoadingView()
            } else if authManager.isAuthenticated {
                ProjectsScreen()
            } else {
                AuthScreen()
            }
            #endif
        }
        .task(id: hasSeenOnboarding) {
            #if DEBUG
            // Skip session restore in debug — no Supabase needed
            #else
            if hasSeenOnboarding {
                await authManager.restoreSession()
            }
            #endif
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
