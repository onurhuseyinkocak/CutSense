import Foundation
import Observation
import Supabase
import AuthenticationServices

@MainActor
@Observable
final class AuthManager {
    #if DEBUG
    var isAuthenticated = false
    var isLoading = true
    #else
    var isAuthenticated = false
    var isLoading = true
    #endif
    var currentUser: User?
    var errorMessage: String?

    /// User id for the pipeline. Real Supabase id when signed in (including anon sessions);
    /// otherwise a stable LOCAL-only UUID stored in UserDefaults so the pipeline can persist
    /// locally without auth. Cloud writes against this local id will fail RLS — that's fine,
    /// LocalProjectStore catches them.
    var effectiveUserId: UUID? {
        if let id = currentUser?.id { return id }
        return Self.localFallbackUserId
    }

    /// Persisted local-only user id used as a last resort when no auth is available.
    private static var localFallbackUserId: UUID {
        let key = "cutsense_local_user_id"
        if let stored = UserDefaults.standard.string(forKey: key),
           let uuid = UUID(uuidString: stored) {
            return uuid
        }
        let new = UUID()
        UserDefaults.standard.set(new.uuidString, forKey: key)
        return new
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
            #if DEBUG
            print("[Auth] Restored session userId=\(session.user.id)")
            #endif
            return
        } catch {
            #if DEBUG
            print("[Auth] No session to restore: \(error)")
            #endif
        }

        #if DEBUG
        // Dev convenience: auto sign in anonymously so the pipeline can persist
        // to Supabase (RLS policies require a valid auth.uid()).
        do {
            let session = try await supabase.auth.signInAnonymously()
            currentUser = session.user
            isAuthenticated = true
            print("[Auth] Anonymous sign-in OK userId=\(session.user.id)")
            return
        } catch {
            print("[Auth] Anonymous sign-in failed: \(error)")
        }
        #endif

        isAuthenticated = false
        currentUser = nil
    }

    func signInWithEmail(_ email: String, password: String) async {
        errorMessage = nil
        do {
            let session = try await supabase.auth.signIn(email: email, password: password)
            currentUser = session.user
            isAuthenticated = true
        } catch {
            #if DEBUG
            print("[Auth] Sign-in failed: \(error)")
            #endif
            errorMessage = "Giriş başarısız. E-posta ve şifrenizi kontrol edip tekrar deneyin."
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
                errorMessage = "Hesabınızı onaylamak için e-postanızı kontrol edin."
            }
        } catch {
            #if DEBUG
            print("[Auth] Sign-up failed: \(error)")
            #endif
            errorMessage = "Kayıt başarısız. Lütfen tekrar deneyin."
        }
    }

    func signInWithApple(credential: ASAuthorizationAppleIDCredential) async {
        errorMessage = nil
        guard let identityToken = credential.identityToken,
              let tokenString = String(data: identityToken, encoding: .utf8) else {
            errorMessage = "Apple ile giriş başarısız. Lütfen tekrar deneyin."
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
            #if DEBUG
            print("[Auth] Apple sign-in failed: \(error)")
            #endif
            errorMessage = "Apple ile giriş başarısız. Lütfen tekrar deneyin."
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
