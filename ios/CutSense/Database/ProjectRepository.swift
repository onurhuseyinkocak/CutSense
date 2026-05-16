import Foundation
import Supabase

struct ProjectRepository: Sendable {
    func fetchProjects(userId: UUID) async throws -> [Project] {
        try await supabase
            .from("projects")
            .select()
            .eq("user_id", value: userId.uuidString)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    func createProject(userId: UUID, title: String) async throws -> Project {
        let request = CreateProjectRequest(
            userId: userId,
            title: title,
            status: ProjectStatus.draft.rawValue
        )
        return try await supabase
            .from("projects")
            .insert(request)
            .select()
            .single()
            .execute()
            .value
    }

    func updateStatus(projectId: UUID, status: ProjectStatus) async throws {
        try await supabase
            .from("projects")
            .update(["status": status.rawValue, "updated_at": ISO8601DateFormatter().string(from: Date())])
            .eq("id", value: projectId.uuidString)
            .execute()
    }

    func deleteProject(projectId: UUID) async throws {
        try await supabase
            .from("projects")
            .delete()
            .eq("id", value: projectId.uuidString)
            .execute()
    }
}
