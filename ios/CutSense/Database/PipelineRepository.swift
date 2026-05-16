import Foundation
import Supabase

struct PipelineRepository: Sendable {
    private let projectRepo = ProjectRepository()

    // MARK: - Transcript

    func saveTranscript(
        projectId: UUID,
        userId: UUID,
        transcription: TranscriptionResult
    ) async throws -> UUID {
        let insert = TranscriptInsert(
            projectId: projectId,
            userId: userId,
            fullText: transcription.fullText,
            language: transcription.language,
            confidence: Double(transcription.overallConfidence)
        )
        let row: IdRow = try await supabase
            .from("transcripts")
            .insert(insert)
            .select("id")
            .single()
            .execute()
            .value
        return row.id
    }

    // MARK: - Transcript Segments

    func saveTranscriptSegments(
        transcriptId: UUID,
        projectId: UUID,
        userId: UUID,
        segments: [TranscriptSegment]
    ) async throws {
        guard !segments.isEmpty else { return }
        let inserts = segments.map { seg in
            TranscriptSegmentInsert(
                transcriptId: transcriptId,
                projectId: projectId,
                userId: userId,
                startTime: seg.startTime,
                endTime: seg.endTime,
                text: seg.text,
                confidence: Double(seg.confidence),
                segmentType: seg.segmentType.rawValue
            )
        }
        try await supabase
            .from("transcript_segments")
            .insert(inserts)
            .execute()
    }

    // MARK: - Rough Cut Decisions

    func saveRoughCutDecisions(
        projectId: UUID,
        userId: UUID,
        decisions: [RoughCutDecision]
    ) async throws {
        guard !decisions.isEmpty else { return }
        let inserts = decisions.map { d in
            RoughCutDecisionInsert(
                projectId: projectId,
                userId: userId,
                startTime: d.startTime,
                endTime: d.endTime,
                action: d.action.rawValue,
                reason: d.reason,
                confidence: Double(d.confidence),
                linkedTranscriptText: d.linkedTranscriptText,
                requiresReview: d.requiresReview
            )
        }
        try await supabase
            .from("rough_cut_decisions")
            .insert(inserts)
            .execute()
    }

    // MARK: - Take Groups + Takes

    func saveTakeGroups(
        projectId: UUID,
        userId: UUID,
        takeGroups: [TakeGroup]
    ) async throws {
        for group in takeGroups {
            let groupInsert = TakeGroupInsert(
                projectId: projectId,
                userId: userId,
                groupLabel: "Take group (\(group.takes.count) takes)",
                semanticSummary: group.takes.first?.text
            )
            let row: IdRow = try await supabase
                .from("take_groups")
                .insert(groupInsert)
                .select("id")
                .single()
                .execute()
                .value

            let takeInserts = group.takes.enumerated().map { index, take in
                TakeInsert(
                    takeGroupId: row.id,
                    projectId: projectId,
                    userId: userId,
                    startTime: take.startTime,
                    endTime: take.endTime,
                    text: take.text,
                    score: Double(take.confidence),
                    isSelected: index == group.bestTakeIndex
                )
            }
            try await supabase
                .from("takes")
                .insert(takeInserts)
                .execute()
        }
    }

    // MARK: - Caption Segments

    func saveCaptionSegments(
        projectId: UUID,
        userId: UUID,
        captions: [CaptionSegment]
    ) async throws {
        guard !captions.isEmpty else { return }
        let inserts = captions.map { c in
            CaptionSegmentInsert(
                projectId: projectId,
                userId: userId,
                startTime: c.startTime,
                endTime: c.endTime,
                text: c.text,
                role: c.role.rawValue,
                style: c.style.rawValue,
                sceneBehavior: c.sceneBehavior.rawValue
            )
        }
        try await supabase
            .from("caption_segments")
            .insert(inserts)
            .execute()
    }

    // MARK: - Edit Decisions

    func saveEditDecisions(
        projectId: UUID,
        userId: UUID,
        decisions: [EditDecision]
    ) async throws {
        guard !decisions.isEmpty else { return }
        let inserts = decisions.map { d in
            EditDecisionInsert(
                projectId: projectId,
                userId: userId,
                startTime: d.time,
                endTime: d.time + d.duration,
                type: d.type.rawValue,
                reason: d.reason,
                intensity: Double(d.intensity)
            )
        }
        try await supabase
            .from("edit_decisions")
            .insert(inserts)
            .execute()
    }

    // MARK: - Exports

    func saveExport(
        projectId: UUID,
        userId: UUID,
        localFileName: String?,
        duration: Double?,
        resolution: String?,
        templateName: String?,
        fileSizeBytes: Int64?
    ) async throws {
        let insert = ExportInsert(
            projectId: projectId,
            userId: userId,
            localFileName: localFileName,
            duration: duration,
            resolution: resolution,
            templateName: templateName,
            fileSizeBytes: fileSizeBytes
        )
        try await supabase
            .from("exports")
            .insert(insert)
            .execute()
    }

    // MARK: - Cleanup (delete old data before re-insert)

    func deleteAnalysisData(projectId: UUID) async throws {
        // Order matters: children first due to FK constraints
        try await supabase.from("takes")
            .delete()
            .eq("project_id", value: projectId.uuidString)
            .execute()
        try await supabase.from("take_groups")
            .delete()
            .eq("project_id", value: projectId.uuidString)
            .execute()
        try await supabase.from("rough_cut_decisions")
            .delete()
            .eq("project_id", value: projectId.uuidString)
            .execute()
        try await supabase.from("transcript_segments")
            .delete()
            .eq("project_id", value: projectId.uuidString)
            .execute()
        try await supabase.from("transcripts")
            .delete()
            .eq("project_id", value: projectId.uuidString)
            .execute()
    }

    func deleteCaptionData(projectId: UUID) async throws {
        try await supabase.from("edit_decisions")
            .delete()
            .eq("project_id", value: projectId.uuidString)
            .execute()
        try await supabase.from("caption_segments")
            .delete()
            .eq("project_id", value: projectId.uuidString)
            .execute()
    }

    // MARK: - Project Status Helpers

    func updateProjectStatus(_ projectId: UUID, status: ProjectStatus) async throws {
        try await projectRepo.updateStatus(projectId: projectId, status: status)
    }

    func updateProjectDurations(
        projectId: UUID,
        originalDuration: Double,
        finalDuration: Double
    ) async throws {
        let update = DurationUpdate(
            originalDuration: originalDuration,
            finalDuration: finalDuration,
            updatedAt: ISO8601DateFormatter().string(from: Date())
        )
        try await supabase
            .from("projects")
            .update(update)
            .eq("id", value: projectId.uuidString)
            .execute()
    }

    func updateProjectTemplate(
        projectId: UUID,
        templateName: String
    ) async throws {
        try await supabase
            .from("projects")
            .update(["selected_template": templateName, "updated_at": ISO8601DateFormatter().string(from: Date())])
            .eq("id", value: projectId.uuidString)
            .execute()
    }
}

// MARK: - Insert Models

private struct IdRow: Codable {
    let id: UUID
}

private struct TranscriptInsert: Codable {
    let projectId: UUID
    let userId: UUID
    let fullText: String
    let language: String
    let confidence: Double

    enum CodingKeys: String, CodingKey {
        case projectId = "project_id"
        case userId = "user_id"
        case fullText = "full_text"
        case language, confidence
    }
}

private struct TranscriptSegmentInsert: Codable {
    let transcriptId: UUID
    let projectId: UUID
    let userId: UUID
    let startTime: Double
    let endTime: Double
    let text: String
    let confidence: Double
    let segmentType: String

    enum CodingKeys: String, CodingKey {
        case transcriptId = "transcript_id"
        case projectId = "project_id"
        case userId = "user_id"
        case startTime = "start_time"
        case endTime = "end_time"
        case text, confidence
        case segmentType = "segment_type"
    }
}

private struct RoughCutDecisionInsert: Codable {
    let projectId: UUID
    let userId: UUID
    let startTime: Double
    let endTime: Double
    let action: String
    let reason: String
    let confidence: Double
    let linkedTranscriptText: String?
    let requiresReview: Bool

    enum CodingKeys: String, CodingKey {
        case projectId = "project_id"
        case userId = "user_id"
        case startTime = "start_time"
        case endTime = "end_time"
        case action, reason, confidence
        case linkedTranscriptText = "linked_transcript_text"
        case requiresReview = "requires_review"
    }
}

private struct TakeGroupInsert: Codable {
    let projectId: UUID
    let userId: UUID
    let groupLabel: String?
    let semanticSummary: String?

    enum CodingKeys: String, CodingKey {
        case projectId = "project_id"
        case userId = "user_id"
        case groupLabel = "group_label"
        case semanticSummary = "semantic_summary"
    }
}

private struct TakeInsert: Codable {
    let takeGroupId: UUID
    let projectId: UUID
    let userId: UUID
    let startTime: Double
    let endTime: Double
    let text: String
    let score: Double
    let isSelected: Bool

    enum CodingKeys: String, CodingKey {
        case takeGroupId = "take_group_id"
        case projectId = "project_id"
        case userId = "user_id"
        case startTime = "start_time"
        case endTime = "end_time"
        case text, score
        case isSelected = "is_selected"
    }
}

private struct CaptionSegmentInsert: Codable {
    let projectId: UUID
    let userId: UUID
    let startTime: Double
    let endTime: Double
    let text: String
    let role: String
    let style: String
    let sceneBehavior: String

    enum CodingKeys: String, CodingKey {
        case projectId = "project_id"
        case userId = "user_id"
        case startTime = "start_time"
        case endTime = "end_time"
        case text, role, style
        case sceneBehavior = "scene_behavior"
    }
}

private struct EditDecisionInsert: Codable {
    let projectId: UUID
    let userId: UUID
    let startTime: Double
    let endTime: Double
    let type: String
    let reason: String
    let intensity: Double

    enum CodingKeys: String, CodingKey {
        case projectId = "project_id"
        case userId = "user_id"
        case startTime = "start_time"
        case endTime = "end_time"
        case type, reason, intensity
    }
}

private struct ExportInsert: Codable {
    let projectId: UUID
    let userId: UUID
    let localFileName: String?
    let duration: Double?
    let resolution: String?
    let templateName: String?
    let fileSizeBytes: Int64?

    enum CodingKeys: String, CodingKey {
        case projectId = "project_id"
        case userId = "user_id"
        case localFileName = "local_file_name"
        case duration, resolution
        case templateName = "template_name"
        case fileSizeBytes = "file_size_bytes"
    }
}

private struct DurationUpdate: Codable {
    let originalDuration: Double
    let finalDuration: Double
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case originalDuration = "original_duration"
        case finalDuration = "final_duration"
        case updatedAt = "updated_at"
    }
}
