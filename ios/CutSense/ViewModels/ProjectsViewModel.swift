import SwiftUI

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
