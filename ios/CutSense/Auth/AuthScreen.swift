import SwiftUI
import AuthenticationServices

struct AuthScreen: View {
    @Environment(AuthManager.self) private var authManager
    @State private var email = ""
    @State private var password = ""
    @State private var isSignUp = false
    @State private var isSubmitting = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                // Logo area
                VStack(spacing: 8) {
                    Text("CutSense")
                        .font(.system(size: 40, weight: .bold, design: .default))
                        .foregroundStyle(.white)

                    Text("Messy recording in. Polished video out.")
                        .font(.subheadline)
                        .foregroundStyle(.gray)
                }

                Spacer()

                // Auth form
                VStack(spacing: 16) {
                    TextField("Email", text: $email)
                        .textFieldStyle(.plain)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .padding()
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.white)

                    SecureField("Password", text: $password)
                        .textFieldStyle(.plain)
                        .textContentType(isSignUp ? .newPassword : .password)
                        .padding()
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.white)

                    if let error = authManager.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }

                    Button {
                        submit()
                    } label: {
                        Group {
                            if isSubmitting {
                                ProgressView().tint(.black)
                            } else {
                                Text(isSignUp ? "Create Account" : "Sign In")
                                    .fontWeight(.semibold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.white)
                        .foregroundStyle(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(isSubmitting || email.isEmpty || password.isEmpty)

                    Button {
                        isSignUp.toggle()
                        authManager.errorMessage = nil
                    } label: {
                        Text(isSignUp ? "Already have an account? Sign In" : "Don't have an account? Sign Up")
                            .font(.subheadline)
                            .foregroundStyle(.gray)
                    }
                }

                // Divider
                HStack {
                    Rectangle().frame(height: 0.5).foregroundStyle(.gray.opacity(0.4))
                    Text("or").font(.caption).foregroundStyle(.gray)
                    Rectangle().frame(height: 0.5).foregroundStyle(.gray.opacity(0.4))
                }

                // Sign in with Apple
                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { _ in
                    // Apple Sign In handled in Phase 1
                }
                .signInWithAppleButtonStyle(.white)
                .frame(height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                Spacer().frame(height: 24)
            }
            .padding(.horizontal, 24)
        }
    }

    private func submit() {
        isSubmitting = true
        Task {
            if isSignUp {
                await authManager.signUpWithEmail(email, password: password)
            } else {
                await authManager.signInWithEmail(email, password: password)
            }
            isSubmitting = false
        }
    }
}
