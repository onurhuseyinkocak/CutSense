import SwiftUI

@MainActor
@Observable
final class AccountViewModel {
    var projects: [Project] = []
    var feedbackCount = 0
    var isLoading = false

    var totalProjects: Int { projects.count }
    var exportedCount: Int { projects.count(where: { $0.status == .exported }) }

    var totalTimeSaved: Double {
        projects.compactMap { p -> Double? in
            guard let orig = p.originalDuration, let final_ = p.finalDuration else { return nil }
            let saved = orig - final_
            return saved > 0 ? saved : nil
        }.reduce(0, +)
    }

    var totalOriginalDuration: Double {
        projects.compactMap(\.originalDuration).reduce(0, +)
    }

    var averageTimeSavedPercent: Double {
        guard totalOriginalDuration > 0 else { return 0 }
        return (totalTimeSaved / totalOriginalDuration) * 100
    }

    func load(userId: UUID) async {
        isLoading = true
        defer { isLoading = false }
        do {
            projects = try await ProjectRepository().fetchProjects(userId: userId)
            let feedback = try await PipelineRepository().fetchRecentAiFeedback(userId: userId, limit: 1000)
            feedbackCount = feedback.count
        } catch {
            #if DEBUG
            print("[CutSense] Account stats load failed: \(error.localizedDescription)")
            #endif
        }
    }
}

struct AccountScreen: View {
    @Environment(AuthManager.self) private var authManager
    @State private var viewModel = AccountViewModel()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
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

                    // Analytics
                    if viewModel.isLoading {
                        ProgressView().tint(.white).padding()
                    } else if viewModel.totalProjects > 0 {
                        analyticsSection
                    }

                    Spacer(minLength: 40)

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
        }
        .navigationTitle("Account")
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task {
            guard let userId = authManager.currentUser?.id else { return }
            await viewModel.load(userId: userId)
        }
    }

    private var analyticsSection: some View {
        VStack(spacing: 16) {
            Text("Your Stats")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Top row: projects + exports
            HStack(spacing: 12) {
                statCard(
                    icon: "film.stack",
                    value: "\(viewModel.totalProjects)",
                    label: "Projects",
                    color: .blue
                )
                statCard(
                    icon: "checkmark.seal.fill",
                    value: "\(viewModel.exportedCount)",
                    label: "Exported",
                    color: .green
                )
            }

            // Time saved
            if viewModel.totalTimeSaved > 0 {
                HStack(spacing: 12) {
                    statCard(
                        icon: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                        value: formatDuration(viewModel.totalTimeSaved),
                        label: "Time Saved",
                        color: .orange
                    )
                    statCard(
                        icon: "percent",
                        value: "\(Int(viewModel.averageTimeSavedPercent))%",
                        label: "Avg Cut",
                        color: .purple
                    )
                }
            }

            // AI feedback
            if viewModel.feedbackCount > 0 {
                HStack(spacing: 12) {
                    statCard(
                        icon: "brain.head.profile",
                        value: "\(viewModel.feedbackCount)",
                        label: "AI Corrections",
                        color: .cyan
                    )
                    statCard(
                        icon: "arrow.triangle.2.circlepath",
                        value: "Active",
                        label: "Learning",
                        color: .mint
                    )
                }
            }
        }
    }

    private func statCard(icon: String, value: String, label: String, color: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)

            Text(value)
                .font(.title3.bold())
                .foregroundStyle(.white)

            Text(label)
                .font(.caption)
                .foregroundStyle(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func formatDuration(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        if mins >= 60 {
            let hours = mins / 60
            let remainMins = mins % 60
            return "\(hours)h \(remainMins)m"
        }
        return "\(mins)m \(secs)s"
    }
}
