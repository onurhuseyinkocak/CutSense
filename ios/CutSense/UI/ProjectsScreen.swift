import SwiftUI

@MainActor
@Observable
final class ProjectsViewModel {
    var projects: [Project] = []
    var isLoading = false
    var showNewProject = false
    var errorMessage: String?

    private let repository = ProjectRepository()

    func loadProjects(userId: UUID) async {
        isLoading = true
        defer { isLoading = false }
        do {
            projects = try await repository.fetchProjects(userId: userId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createProject(userId: UUID, title: String) async {
        do {
            let project = try await repository.createProject(userId: userId, title: title)
            projects.insert(project, at: 0)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteProject(_ project: Project) async {
        do {
            try await repository.deleteProject(projectId: project.id)
            projects.removeAll { $0.id == project.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct ProjectsScreen: View {
    @Environment(AuthManager.self) private var authManager
    @State private var viewModel = ProjectsViewModel()
    @State private var newProjectTitle = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if viewModel.isLoading {
                    ProgressView().tint(.white)
                } else if viewModel.projects.isEmpty {
                    emptyState
                } else {
                    projectList
                }
            }
            .navigationTitle("Projects")
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        AccountScreen()
                    } label: {
                        Image(systemName: "person.circle")
                            .foregroundStyle(.white)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.showNewProject = true
                    } label: {
                        Image(systemName: "plus")
                            .foregroundStyle(.white)
                    }
                }
            }
            .alert("New Project", isPresented: $viewModel.showNewProject) {
                TextField("Project title", text: $newProjectTitle)
                Button("Create") {
                    guard let userId = authManager.currentUser?.id else { return }
                    let title = newProjectTitle.isEmpty ? "Untitled" : newProjectTitle
                    Task {
                        await viewModel.createProject(userId: userId, title: title)
                    }
                    newProjectTitle = ""
                }
                Button("Cancel", role: .cancel) {
                    newProjectTitle = ""
                }
            }
            .task {
                guard let userId = authManager.currentUser?.id else { return }
                await viewModel.loadProjects(userId: userId)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var emptyState: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "film.stack")
                .font(.system(size: 48))
                .foregroundStyle(.gray)

            Text("No projects yet")
                .font(.title3)
                .foregroundStyle(.gray)

            Text("Import a video to get started")
                .font(.subheadline)
                .foregroundStyle(.gray.opacity(0.7))

            Button {
                viewModel.showNewProject = true
            } label: {
                Label("New Project", systemImage: "plus")
                    .fontWeight(.semibold)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(.white)
                    .foregroundStyle(.black)
                    .clipShape(Capsule())
            }

            Spacer()
        }
    }

    private var projectList: some View {
        List {
            ForEach(viewModel.projects) { project in
                NavigationLink {
                    VideoImportScreen(project: project) { updated in
                        if let idx = viewModel.projects.firstIndex(where: { $0.id == updated.id }) {
                            viewModel.projects[idx] = updated
                        }
                    }
                } label: {
                    ProjectRow(project: project)
                }
                .listRowBackground(Color.white.opacity(0.05))
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        Task { await viewModel.deleteProject(project) }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }
}

private struct ProjectRow: View {
    let project: Project

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(project.title)
                .font(.headline)
                .foregroundStyle(.white)

            HStack(spacing: 12) {
                Label(project.status.rawValue.replacingOccurrences(of: "_", with: " ").capitalized,
                      systemImage: statusIcon)
                    .font(.caption)
                    .foregroundStyle(statusColor)

                if let duration = project.originalDuration {
                    Label(formatDuration(duration), systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.gray)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var statusIcon: String {
        switch project.status {
        case .draft: "doc"
        case .imported: "checkmark.circle"
        case .analyzing: "waveform"
        case .roughCutReady: "scissors"
        case .reviewed: "eye"
        case .styling: "paintbrush"
        case .exporting: "square.and.arrow.up"
        case .exported: "checkmark.seal"
        case .failed: "exclamationmark.triangle"
        }
    }

    private var statusColor: Color {
        switch project.status {
        case .exported: .green
        case .failed: .red
        case .analyzing, .exporting: .yellow
        default: .gray
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
