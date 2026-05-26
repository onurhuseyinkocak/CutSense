import Foundation
import Supabase

struct PipelineRepository: Sendable {
    private let projectRepo = ProjectRepository()

    /// Returns true when there is a real signed-in Supabase user. Local-mode users
    /// (no auth, just a UserDefaults UUID) skip cloud writes entirely so we don't
    /// burn 5s on each Supabase round-trip just to be rejected by RLS.
    private var hasCloudSession: Bool {
        get async {
            (try? await supabase.auth.session) != nil
        }
    }

    enum PipelineError: Error, LocalizedError {
        case localOnlyMode
        var errorDescription: String? {
            switch self {
            case .localOnlyMode: "Local mode — cloud writes skipped."
            }
        }
    }

    // MARK: - Transcript

    func saveTranscript(
        projectId: UUID,
        userId: UUID,
        transcription: TranscriptionResult
    ) async throws -> UUID {
        guard await hasCloudSession else { throw PipelineError.localOnlyMode }
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
        guard await hasCloudSession else { throw PipelineError.localOnlyMode }
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
        guard await hasCloudSession else { throw PipelineError.localOnlyMode }
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
        guard await hasCloudSession else { throw PipelineError.localOnlyMode }
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
        guard await hasCloudSession else { throw PipelineError.localOnlyMode }
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
        guard await hasCloudSession else { throw PipelineError.localOnlyMode }
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
        guard await hasCloudSession else { throw PipelineError.localOnlyMode }
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

    // MARK: - AI Feedback

    func saveAiFeedback(
        userId: UUID,
        segmentText: String,
        aiClassification: String,
        aiConfidence: Double?,
        aiReason: String?,
        userAction: String,
        language: String?
    ) async throws {
        guard await hasCloudSession else { throw PipelineError.localOnlyMode }
        let insert = AiFeedbackInsert(
            userId: userId,
            segmentText: segmentText,
            aiClassification: aiClassification,
            aiConfidence: aiConfidence,
            aiReason: aiReason,
            userAction: userAction,
            language: language
        )
        try await supabase
            .from("ai_feedback")
            .insert(insert)
            .execute()
    }

    func fetchRecentAiFeedback(userId: UUID, limit: Int = 20) async throws -> [AiFeedbackRow] {
        guard await hasCloudSession else { return [] }
        return try await supabase
            .from("ai_feedback")
            .select()
            .eq("user_id", value: userId.uuidString)
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value
    }

    // MARK: - Fetch (for project resume)

    func fetchTranscript(projectId: UUID) async throws -> TranscriptionResult? {
        guard await hasCloudSession else { return nil }
        let rows: [TranscriptRow] = try await supabase
            .from("transcripts")
            .select()
            .eq("project_id", value: projectId.uuidString)
            .order("created_at", ascending: false)
            .limit(1)
            .execute()
            .value
        guard let row = rows.first else { return nil }

        let segmentRows: [TranscriptSegmentRow] = try await supabase
            .from("transcript_segments")
            .select()
            .eq("project_id", value: projectId.uuidString)
            .order("start_time", ascending: true)
            .execute()
            .value

        let segments = segmentRows.map { s in
            TranscriptSegment(
                startTime: s.startTime,
                endTime: s.endTime,
                text: s.text,
                confidence: Float(s.confidence),
                segmentType: TranscriptSegment.SegmentType(rawValue: s.segmentType) ?? .speech
            )
        }

        return TranscriptionResult(
            fullText: row.fullText,
            segments: segments,
            language: row.language,
            overallConfidence: Float(row.confidence)
        )
    }

    func fetchRoughCutDecisions(projectId: UUID) async throws -> RoughCutResult? {
        guard await hasCloudSession else { return nil }
        let rows: [RoughCutDecisionRow] = try await supabase
            .from("rough_cut_decisions")
            .select()
            .eq("project_id", value: projectId.uuidString)
            .order("start_time", ascending: true)
            .execute()
            .value
        guard !rows.isEmpty else { return nil }

        let decisions = rows.map { r in
            RoughCutDecision(
                startTime: r.startTime,
                endTime: r.endTime,
                action: CutAction(rawValue: r.action) ?? .keep,
                reason: r.reason,
                confidence: Float(r.confidence),
                linkedTranscriptText: r.linkedTranscriptText,
                requiresReview: r.requiresReview
            )
        }

        let keepSegments = decisions.filter { $0.action == .keep }
        let originalDuration = decisions.map(\.endTime).max() ?? 0
        let cleanDuration = TimelineRangeNormalizer
            .includedRanges(from: decisions, assetDuration: originalDuration)
            .reduce(0.0) { $0 + $1.duration }

        return RoughCutResult(
            decisions: decisions,
            originalDuration: originalDuration,
            cleanDuration: cleanDuration,
            keepSegments: keepSegments,
            cutSegments: decisions.filter { $0.action == .cut || $0.action == .trimStart || $0.action == .trimEnd },
            reviewSegments: decisions.filter { $0.requiresReview }
        )
    }

    // MARK: - Cleanup (delete old data before re-insert)

    func deleteAnalysisData(projectId: UUID) async throws {
        guard await hasCloudSession else { return }
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

    func deleteRoughCutDecisions(projectId: UUID) async throws {
        guard await hasCloudSession else { return }
        try await supabase.from("rough_cut_decisions")
            .delete()
            .eq("project_id", value: projectId.uuidString)
            .execute()
    }

    func deleteCaptionData(projectId: UUID) async throws {
        guard await hasCloudSession else { return }
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
        await LocalProjectStore.update(id: projectId) { project in
            project.originalDuration = originalDuration
            project.finalDuration = finalDuration
        }

        guard await hasCloudSession else { return }
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
        await LocalProjectStore.update(id: projectId) { project in
            project.selectedTemplate = templateName
        }

        guard await hasCloudSession else { return }
        try await supabase
            .from("projects")
            .update(["selected_template": templateName, "updated_at": ISO8601DateFormatter().string(from: Date())])
            .eq("id", value: projectId.uuidString)
            .execute()
    }

    func updateProjectLocalPath(
        projectId: UUID,
        path: String
    ) async throws {
        await LocalProjectStore.update(id: projectId) { project in
            project.localProjectPath = path
            project.sourceFileName = URL(fileURLWithPath: path).lastPathComponent
        }

        guard await hasCloudSession else { return }
        try await supabase
            .from("projects")
            .update(["local_project_path": path, "updated_at": ISO8601DateFormatter().string(from: Date())])
            .eq("id", value: projectId.uuidString)
            .execute()
    }

    func updateProjectImportMetadata(
        projectId: UUID,
        path: String,
        metadata: VideoMetadata
    ) async throws {
        let fileName = URL(fileURLWithPath: path).lastPathComponent

        await LocalProjectStore.update(id: projectId) { project in
            project.status = .imported
            project.localProjectPath = path
            project.sourceFileName = fileName
            project.originalDuration = metadata.duration
        }

        guard await hasCloudSession else { return }
        let update = ProjectImportMetadataUpdate(
            status: ProjectStatus.imported.rawValue,
            originalDuration: metadata.duration,
            sourceFileName: fileName,
            localProjectPath: path,
            updatedAt: ISO8601DateFormatter().string(from: Date())
        )
        try await supabase
            .from("projects")
            .update(update)
            .eq("id", value: projectId.uuidString)
            .execute()
    }
}

// MARK: - Insert Models

private struct IdRow: Codable {
    let id: UUID
}

private struct ProjectImportMetadataUpdate: Codable {
    let status: String
    let originalDuration: Double
    let sourceFileName: String
    let localProjectPath: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case status
        case originalDuration = "original_duration"
        case sourceFileName = "source_file_name"
        case localProjectPath = "local_project_path"
        case updatedAt = "updated_at"
    }
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

private struct AiFeedbackInsert: Codable {
    let userId: UUID
    let segmentText: String
    let aiClassification: String
    let aiConfidence: Double?
    let aiReason: String?
    let userAction: String
    let language: String?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case segmentText = "segment_text"
        case aiClassification = "ai_classification"
        case aiConfidence = "ai_confidence"
        case aiReason = "ai_reason"
        case userAction = "user_action"
        case language
    }
}

struct AiFeedbackRow: Codable, Sendable {
    let id: UUID
    let segmentText: String
    let aiClassification: String
    let aiConfidence: Double?
    let aiReason: String?
    let userAction: String
    let language: String?

    enum CodingKeys: String, CodingKey {
        case id
        case segmentText = "segment_text"
        case aiClassification = "ai_classification"
        case aiConfidence = "ai_confidence"
        case aiReason = "ai_reason"
        case userAction = "user_action"
        case language
    }
}

// MARK: - Fetch Row Models

private struct TranscriptRow: Codable {
    let id: UUID
    let fullText: String
    let language: String
    let confidence: Double

    enum CodingKeys: String, CodingKey {
        case id
        case fullText = "full_text"
        case language, confidence
    }
}

private struct TranscriptSegmentRow: Codable {
    let startTime: Double
    let endTime: Double
    let text: String
    let confidence: Double
    let segmentType: String

    enum CodingKeys: String, CodingKey {
        case startTime = "start_time"
        case endTime = "end_time"
        case text, confidence
        case segmentType = "segment_type"
    }
}

private struct RoughCutDecisionRow: Codable {
    let startTime: Double
    let endTime: Double
    let action: String
    let reason: String
    let confidence: Double
    let linkedTranscriptText: String?
    let requiresReview: Bool

    enum CodingKeys: String, CodingKey {
        case startTime = "start_time"
        case endTime = "end_time"
        case action, reason, confidence
        case linkedTranscriptText = "linked_transcript_text"
        case requiresReview = "requires_review"
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
