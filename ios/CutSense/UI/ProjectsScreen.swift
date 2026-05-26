import SwiftUI
import PhotosUI

@MainActor
@Observable
final class ProjectsViewModel {
    var projects: [Project] = []
    var isLoading = false
    var errorMessage: String?

    private let repository = ProjectRepository()

    func loadProjects(userId: UUID) async {
        isLoading = true
        defer { isLoading = false }
        do {
            projects = try await repository.fetchProjects(userId: userId)
        } catch {
            #if DEBUG
            print("[Projects] fetch failed: \(error)")
            #endif
            errorMessage = "Projeler yüklenemedi. İnternet bağlantınızı kontrol edin."
        }
    }

    func createProject(userId: UUID, title: String) async -> Project? {
        do {
            let project = try await repository.createProject(userId: userId, title: title)
            projects.insert(project, at: 0)
            return project
        } catch {
            #if DEBUG
            print("[Projects] create failed: \(error)")
            #endif
            errorMessage = "Proje oluşturulamadı. Lütfen tekrar deneyin."
            return nil
        }
    }

    func deleteProject(_ project: Project) async {
        do {
            try await repository.deleteProject(projectId: project.id, localVideoPath: project.localProjectPath)
            projects.removeAll { $0.id == project.id }
        } catch {
            #if DEBUG
            print("[Projects] delete failed: \(error)")
            #endif
            errorMessage = "Proje silinemedi. Lütfen tekrar deneyin."
        }
    }

    func replaceProject(_ project: Project) {
        if let index = projects.firstIndex(where: { $0.id == project.id }) {
            projects[index] = project
        } else {
            projects.insert(project, at: 0)
        }
    }
}

struct ProjectsScreen: View {
    @Environment(AuthManager.self) private var authManager
    @State private var viewModel = ProjectsViewModel()
    @State private var selectedItem: PhotosPickerItem?
    @State private var importService = VideoImportService()
    @State private var activeProject: Project?
    @State private var activeVideoURL: URL?
    @State private var showEdit = false
    @State private var isCreating = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if viewModel.isLoading {
                    ProgressView().tint(.white)
                } else if isCreating || importService.isImporting {
                    VStack(spacing: 12) {
                        ProgressView().tint(.white)
                        Text("Importing video...")
                            .foregroundStyle(.gray)
                    }
                } else if viewModel.projects.isEmpty {
                    emptyState
                } else {
                    projectList
                }

                if let errorMessage = currentErrorMessage {
                    VStack {
                        ErrorBanner(message: errorMessage)
                            .padding(.horizontal)
                            .padding(.top)
                        Spacer()
                    }
                }
            }
            .navigationTitle("CutSense")
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        AccountScreen()
                    } label: {
                        Image(systemName: "person.circle")
                            .foregroundStyle(.white)
                    }
                    .accessibilityLabel("Account")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    PhotosPicker(selection: $selectedItem, matching: .videos) {
                        Image(systemName: "plus")
                            .foregroundStyle(.white)
                    }
                    .accessibilityLabel("New Video")
                }
            }
            .onChange(of: selectedItem) { _, newItem in
                guard let newItem else { return }
                Task { await handleVideoImport(newItem) }
            }
            .task {
                guard let userId = authManager.effectiveUserId else { return }
                await viewModel.loadProjects(userId: userId)
            }
            .onAppear {
                guard !viewModel.projects.isEmpty,
                      let userId = authManager.effectiveUserId else { return }
                Task { await viewModel.loadProjects(userId: userId) }
            }
            .refreshable {
                guard let userId = authManager.effectiveUserId else { return }
                await viewModel.loadProjects(userId: userId)
            }
            .navigationDestination(isPresented: $showEdit) {
                if let project = activeProject, let url = activeVideoURL {
                    EditScreen(videoURL: url, projectId: project.id)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func handleVideoImport(_ item: PhotosPickerItem) async {
        isCreating = true
        defer {
            isCreating = false
            selectedItem = nil
        }

        await importService.importVideo(from: item)
        guard let videoURL = importService.importedVideoURL else { return }
        guard let metadata = importService.metadata else {
            viewModel.errorMessage = "Video bilgileri okunamadı. Lütfen farklı bir dosya deneyin."
            return
        }
        guard let userId = authManager.effectiveUserId else { return }

        // Auto-create project with date-based title
        let title = "Video \(Date().formatted(.dateTime.month(.abbreviated).day().hour().minute()))"

        guard var project = await viewModel.createProject(userId: userId, title: title) else { return }

        // Save import metadata locally first; cloud sync is best-effort.
        let pipeline = PipelineRepository()
        try? await pipeline.updateProjectImportMetadata(
            projectId: project.id,
            path: videoURL.path,
            metadata: metadata
        )

        project.status = .imported
        project.localProjectPath = videoURL.path
        project.sourceFileName = videoURL.lastPathComponent
        project.originalDuration = metadata.duration
        viewModel.replaceProject(project)

        activeProject = project
        activeVideoURL = videoURL
        showEdit = true
    }

    private func resumeProject(_ project: Project) {
        guard let path = project.localProjectPath,
              FileManager.default.fileExists(atPath: path) else {
            viewModel.errorMessage = "Video file not found. Re-import needed."
            return
        }
        activeProject = project
        activeVideoURL = URL(fileURLWithPath: path)
        showEdit = true
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

            PhotosPicker(selection: $selectedItem, matching: .videos) {
                Label("Import Video", systemImage: "plus")
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
                Button {
                    resumeProject(project)
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

    private var currentErrorMessage: String? {
        importService.errorMessage ?? viewModel.errorMessage
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
