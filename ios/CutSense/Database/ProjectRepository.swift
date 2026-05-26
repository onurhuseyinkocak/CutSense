import Foundation
import Supabase

struct ProjectRepository: Sendable {
    /// Fetch projects: local-first so the user always sees their work even when offline
    /// or when the Supabase project doesn't permit anonymous reads. Cloud results merge in
    /// when available (cloud rows override local ones with the same id).
    @MainActor
    func fetchProjects(userId: UUID) async throws -> [Project] {
        let local = LocalProjectStore.load(userId: userId)
        do {
            let cloud: [Project] = try await supabase
                .from("projects")
                .select()
                .eq("user_id", value: userId.uuidString)
                .order("created_at", ascending: false)
                .execute()
                .value
            // Mirror cloud rows into local store so they survive offline launches
            for p in cloud { LocalProjectStore.upsert(p) }
            return mergeProjects(local: local, cloud: cloud)
        } catch {
            #if DEBUG
            print("[Projects] cloud fetch failed (offline?): \(error.localizedDescription)")
            #endif
            return local
        }
    }

    /// Create a project: write to local store synchronously so the UI ALWAYS gets a
    /// valid Project back. Attempt cloud insert as a best-effort upgrade — if RLS or
    /// network rejects, the project still works locally and can sync later.
    @MainActor
    func createProject(userId: UUID, title: String) async throws -> Project {
        let now = Date()
        let localProject = Project(
            id: UUID(),
            userId: userId,
            title: title,
            originalDuration: nil,
            finalDuration: nil,
            status: .draft,
            selectedTemplate: nil,
            sourceLocalIdentifier: nil,
            sourceFileName: nil,
            localProjectPath: nil,
            createdAt: now,
            updatedAt: now
        )
        LocalProjectStore.upsert(localProject)

        // Best-effort cloud insert. We do NOT throw on failure.
        let request = CreateProjectRequest(
            userId: userId,
            title: title,
            status: ProjectStatus.draft.rawValue
        )
        do {
            let cloud: Project = try await supabase
                .from("projects")
                .insert(request)
                .select()
                .single()
                .execute()
                .value
            // Replace local placeholder with cloud row (canonical id)
            LocalProjectStore.delete(localProject)
            LocalProjectStore.upsert(cloud)
            return cloud
        } catch {
            #if DEBUG
            print("[Projects] cloud insert failed, keeping local-only: \(error.localizedDescription)")
            #endif
            return localProject
        }
    }

    /// Merge local and cloud projects: cloud takes priority on id collisions.
    private func mergeProjects(local: [Project], cloud: [Project]) -> [Project] {
        let cloudIds = Set(cloud.map(\.id))
        let localOnly = local.filter { !cloudIds.contains($0.id) }
        return (cloud + localOnly).sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
    }

    func updateStatus(projectId: UUID, status: ProjectStatus) async throws {
        await LocalProjectStore.update(id: projectId) { project in
            project.status = status
        }

        // Best-effort cloud update; local store is already the offline source of truth.
        do {
            try await supabase
                .from("projects")
                .update(["status": status.rawValue, "updated_at": ISO8601DateFormatter().string(from: Date())])
                .eq("id", value: projectId.uuidString)
                .execute()
        } catch {
            #if DEBUG
            print("[Projects] cloud updateStatus failed, local-only: \(error.localizedDescription)")
            #endif
        }
    }

    @MainActor
    func deleteProject(projectId: UUID, localVideoPath: String? = nil) async throws {
        // Delete from local store first so UI reflects deletion even if cloud is unreachable
        LocalProjectStore.deleteById(projectId)
        PipelineArtifactStore.delete(projectId: projectId)

        // Best-effort cloud cascade
        do {
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
        } catch {
            #if DEBUG
            print("[Projects] cloud delete failed, local-only: \(error.localizedDescription)")
            #endif
        }

        // Clean up local video file
        if let path = localVideoPath {
            try? FileManager.default.removeItem(atPath: path)
        }
    }
}
