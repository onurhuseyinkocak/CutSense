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

    func deleteProject(projectId: UUID, localVideoPath: String? = nil) async throws {
        // Delete child data first to prevent orphans if FK cascade not configured
        let pipeline = PipelineRepository()
        try await pipeline.deleteCaptionData(projectId: projectId)
        try await pipeline.deleteAnalysisData(projectId: projectId)
        try await supabase.from("exports")
            .delete()
            .eq("project_id", value: projectId.uuidString)
            .execute()

        try await supabase
            .from("projects")
            .delete()
            .eq("id", value: projectId.uuidString)
            .execute()

        // Clean up local video file
        if let path = localVideoPath {
            try? FileManager.default.removeItem(atPath: path)
        }
    }
}
