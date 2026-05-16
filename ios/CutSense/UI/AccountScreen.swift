import SwiftUI

struct AccountScreen: View {
    @Environment(AuthManager.self) private var authManager

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 24) {
                if let user = authManager.currentUser {
                    VStack(spacing: 8) {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(.gray)

                        Text(user.email ?? "No email")
                            .font(.headline)
                            .foregroundStyle(.white)
                    }
                    .padding(.top, 32)
                }

                Spacer()

                VStack(spacing: 12) {
                    Text("Raw videos stay local on your device.")
                        .font(.caption)
                        .foregroundStyle(.gray)

                    Button(role: .destructive) {
                        Task { await authManager.signOut() }
                    } label: {
                        Text("Sign Out")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.red.opacity(0.15))
                            .foregroundStyle(.red)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(.bottom, 32)
            }
            .padding(.horizontal, 24)
        }
        .navigationTitle("Account")
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}
