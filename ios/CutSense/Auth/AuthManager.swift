import Foundation
import Observation
import Supabase

@Observable
final class AuthManager {
    var isAuthenticated = false
    var isLoading = true
    var currentUser: User?
    var errorMessage: String?

    func restoreSession() async {
        defer { isLoading = false }
        do {
            let session = try await supabase.auth.session
            currentUser = session.user
            isAuthenticated = true
        } catch {
            isAuthenticated = false
            currentUser = nil
        }
    }

    func signInWithEmail(_ email: String, password: String) async {
        errorMessage = nil
        do {
            let session = try await supabase.auth.signIn(email: email, password: password)
            currentUser = session.user
            isAuthenticated = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signUpWithEmail(_ email: String, password: String) async {
        errorMessage = nil
        do {
            let result = try await supabase.auth.signUp(email: email, password: password)
            if let session = result.session {
                currentUser = session.user
                isAuthenticated = true
            } else {
                errorMessage = "Check your email to confirm your account."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signOut() async {
        do {
            try await supabase.auth.signOut()
        } catch {
            // Best effort
        }
        currentUser = nil
        isAuthenticated = false
    }
}
