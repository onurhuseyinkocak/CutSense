import Foundation
import Observation
import Supabase
import AuthenticationServices

@MainActor
@Observable
final class AuthManager {
    #if DEBUG
    var isAuthenticated = true
    var isLoading = false
    #else
    var isAuthenticated = false
    var isLoading = true
    #endif
    var currentUser: User?
    var errorMessage: String?

    /// Returns userId for DB operations. In DEBUG, returns a fixed UUID when no user is signed in.
    var effectiveUserId: UUID? {
        if let id = currentUser?.id { return id }
        #if DEBUG
        return UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        #else
        return nil
        #endif
    }

    func restoreSession() async {
        defer { isLoading = false }
        do {
            let session = try await withThrowingTaskGroup(of: Session.self) { group in
                group.addTask {
                    try await supabase.auth.session
                }
                group.addTask {
                    try await Task.sleep(for: .seconds(5))
                    throw CancellationError()
                }
                guard let result = try await group.next() else {
                    throw CancellationError()
                }
                group.cancelAll()
                return result
            }
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

    func signInWithApple(credential: ASAuthorizationAppleIDCredential) async {
        errorMessage = nil
        guard let identityToken = credential.identityToken,
              let tokenString = String(data: identityToken, encoding: .utf8) else {
            errorMessage = "Failed to get Apple identity token."
            return
        }
        do {
            let session = try await supabase.auth.signInWithIdToken(
                credentials: .init(
                    provider: .apple,
                    idToken: tokenString
                )
            )
            currentUser = session.user
            isAuthenticated = true
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
        errorMessage = nil
    }
}
