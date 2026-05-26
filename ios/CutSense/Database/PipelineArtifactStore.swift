import Foundation

enum PipelineStage: String, Codable, Sendable, CaseIterable {
    case imported
    case audioAnalyzed = "audio_analyzed"
    case transcribed
    case smartAnalyzed = "smart_analyzed"
    case roughCut = "rough_cut"
    case timelineAnalyzed = "timeline_analyzed"
    case templateSelected = "template_selected"
    case captioned
    case editPlanned = "edit_planned"
    case qualityChecked = "quality_checked"
    case exported
}

enum PipelineStageStatus: String, Codable, Sendable {
    case pending
    case running
    case completed
    case failed
}

enum PipelineArtifactStoreError: Error, LocalizedError, Sendable {
    case invalidStageCompletion(stage: PipelineStage, reason: String)

    var errorDescription: String? {
        switch self {
        case .invalidStageCompletion(let stage, let reason):
            "Cannot complete \(stage.rawValue): \(reason)"
        }
    }
}

struct PipelineStageRecord: Codable, Sendable, Equatable {
    let stage: PipelineStage
    var status: PipelineStageStatus
    var artifactCount: Int
    var updatedAt: Date
    var failureMessage: String?
}

struct PipelineRunSnapshot: Codable, Sendable {
    let schemaVersion: Int
    let projectId: UUID
    var sourceVideoPath: String?
    var sourceFingerprint: VideoFileFingerprint?
    var audioAnalysis: AudioAnalysisArtifact?
    var stages: [PipelineStageRecord]
    var transcription: TranscriptionArtifact?
    var roughCut: RoughCutArtifact?
    var captions: [CaptionSegmentArtifact]?
    var editPlan: EditPlanArtifact?
    var qualityReport: QualityReportArtifact?
    var export: ExportArtifact?
    let createdAt: Date
    var updatedAt: Date

    init(projectId: UUID, sourceVideoPath: String? = nil, now: Date = Date()) {
        self.schemaVersion = 1
        self.projectId = projectId
        self.sourceVideoPath = sourceVideoPath
        self.stages = []
        self.createdAt = now
        self.updatedAt = now
    }

    mutating func markCompleted(_ stage: PipelineStage, artifactCount: Int, now: Date = Date()) {
        updateStage(
            stage,
            status: .completed,
            artifactCount: artifactCount,
            failureMessage: nil,
            now: now
        )
    }

    mutating func markFailed(_ stage: PipelineStage, message: String, now: Date = Date()) {
        updateStage(
            stage,
            status: .failed,
            artifactCount: 0,
            failureMessage: message,
            now: now
        )
    }

    func status(of stage: PipelineStage) -> PipelineStageStatus {
        stages.first { $0.stage == stage }?.status ?? .pending
    }

    var transcriptionResult: TranscriptionResult? {
        transcription?.domainValue
    }

    var roughCutResult: RoughCutResult? {
        roughCut?.domainValue
    }

    var captionSegments: [CaptionSegment]? {
        captions?.map(\.domainValue)
    }

    var editPlanResult: EditPlan? {
        editPlan?.domainValue
    }

    func matchesSourceVideo(_ url: URL) -> Bool {
        guard sourceVideoPath == url.path else {
            return false
        }

        guard let sourceFingerprint else { return false }

        return sourceFingerprint == VideoFileFingerprint(url: url)
    }

    private mutating func updateStage(
        _ stage: PipelineStage,
        status: PipelineStageStatus,
        artifactCount: Int,
        failureMessage: String?,
        now: Date
    ) {
        if let index = stages.firstIndex(where: { $0.stage == stage }) {
            stages[index].status = status
            stages[index].artifactCount = artifactCount
            stages[index].updatedAt = now
            stages[index].failureMessage = failureMessage
        } else {
            stages.append(
                PipelineStageRecord(
                    stage: stage,
                    status: status,
                    artifactCount: artifactCount,
                    updatedAt: now,
                    failureMessage: failureMessage
                )
            )
        }
        updatedAt = now
    }

    mutating func removeDownstreamStages(after stage: PipelineStage) {
        guard let stageIndex = PipelineStage.allCases.firstIndex(of: stage) else {
            return
        }
        stages.removeAll { record in
            guard let recordIndex = PipelineStage.allCases.firstIndex(of: record.stage) else {
                return false
            }
            return recordIndex > stageIndex
        }
        updatedAt = Date()
    }
}

struct PipelineArtifactManifest: Sendable, Equatable {
    let hasTranscript: Bool
    let transcriptSegmentCount: Int
    let hasRoughCut: Bool
    let roughCutDecisionCount: Int
    let hasCaptions: Bool
    let captionCount: Int
    let hasEditPlan: Bool
    let editDecisionCount: Int
    let hasExport: Bool
}

extension PipelineRunSnapshot {
    var manifest: PipelineArtifactManifest {
        PipelineArtifactManifest(
            hasTranscript: transcription != nil,
            transcriptSegmentCount: transcription?.segments.count ?? 0,
            hasRoughCut: roughCut != nil,
            roughCutDecisionCount: roughCut?.decisions.count ?? 0,
            hasCaptions: captions?.isEmpty == false,
            captionCount: captions?.count ?? 0,
            hasEditPlan: editPlan != nil,
            editDecisionCount: editPlan?.decisions.count ?? 0,
            hasExport: export != nil
        )
    }
}

@MainActor
enum PipelineArtifactStore {
    static var testStoreDirectoryURL: URL?

    static func load(projectId: UUID) -> PipelineRunSnapshot? {
        guard let data = try? Data(contentsOf: artifactURL(for: projectId)) else {
            return nil
        }
        return try? JSONDecoder.pipelineArtifacts.decode(PipelineRunSnapshot.self, from: data)
    }

    static func saveAnalysis(
        projectId: UUID,
        sourceVideoURL: URL,
        transcription: TranscriptionResult,
        roughCut: RoughCutResult,
        audioAnalysis: AudioAnalysisResult? = nil,
        invalidateDownstreamArtifacts: Bool = true
    ) throws {
        var snapshot = load(projectId: projectId) ?? PipelineRunSnapshot(projectId: projectId)
        snapshot.sourceVideoPath = sourceVideoURL.path
        snapshot.sourceFingerprint = VideoFileFingerprint(url: sourceVideoURL)
        if let audioAnalysis {
            snapshot.audioAnalysis = AudioAnalysisArtifact(audioAnalysis)
        }
        snapshot.transcription = TranscriptionArtifact(transcription)
        snapshot.roughCut = RoughCutArtifact(roughCut)
        if invalidateDownstreamArtifacts {
            snapshot.captions = nil
            snapshot.editPlan = nil
            snapshot.qualityReport = nil
            snapshot.export = nil
            snapshot.removeDownstreamStages(after: .roughCut)
        }
        snapshot.markCompleted(.imported, artifactCount: 1)
        if let audioAnalysis = snapshot.audioAnalysis {
            snapshot.markCompleted(.audioAnalyzed, artifactCount: audioAnalysis.segments.count)
        }
        if transcription.segments.isEmpty {
            snapshot.markFailed(.transcribed, message: "Transcription artifact has no segments")
        } else if transcription.recognitionStatus.isPartial {
            snapshot.markFailed(
                .transcribed,
                message: "Transcription returned \(transcription.recognitionStatus.rawValue) instead of final recognition"
            )
        } else {
            snapshot.markCompleted(.transcribed, artifactCount: transcription.segments.count)
        }

        if transcription.segments.isEmpty {
            snapshot.markFailed(.smartAnalyzed, message: "Smart analysis missing transcript input")
        } else {
            snapshot.markCompleted(.smartAnalyzed, artifactCount: transcription.segments.count)
        }

        if roughCut.decisions.isEmpty {
            snapshot.markFailed(.roughCut, message: "Rough cut artifact has no decisions")
        } else {
            snapshot.markCompleted(.roughCut, artifactCount: roughCut.decisions.count)
        }
        try write(snapshot)
    }

    static func saveCaptioning(
        projectId: UUID,
        template: TemplateConfig,
        captions: [CaptionSegment],
        editPlan: EditPlan?
    ) throws {
        var snapshot = load(projectId: projectId) ?? PipelineRunSnapshot(projectId: projectId)
        snapshot.captions = captions.map(CaptionSegmentArtifact.init)
        snapshot.qualityReport = nil
        snapshot.export = nil
        snapshot.removeDownstreamStages(after: .captioned)

        guard !captions.isEmpty else {
            snapshot.captions = nil
            snapshot.editPlan = nil
            snapshot.markFailed(.captioned, message: "No captions generated")
            snapshot.markFailed(.editPlanned, message: "Edit plan skipped because caption generation produced no captions")
            try write(snapshot)
            return
        }

        snapshot.markCompleted(.captioned, artifactCount: captions.count)

        if let editPlan {
            snapshot.editPlan = EditPlanArtifact(editPlan)
            if editPlan.decisions.isEmpty {
                snapshot.markFailed(.editPlanned, message: "Edit plan contains no edit decisions")
            } else {
                snapshot.markCompleted(.editPlanned, artifactCount: editPlan.decisions.count)
            }
        } else {
            snapshot.editPlan = nil
            snapshot.markFailed(.editPlanned, message: "Edit plan missing")
        }
        try write(snapshot)
    }

    static func saveQualityReport(
        projectId: UUID,
        report: QualityReport
    ) throws {
        var snapshot = load(projectId: projectId) ?? PipelineRunSnapshot(projectId: projectId)
        let validatedReport = qualityReportByEnforcingPrerequisites(report, snapshot: snapshot)
        snapshot.qualityReport = QualityReportArtifact(validatedReport)
        snapshot.export = validatedReport.passed ? snapshot.export : nil
        if validatedReport.passed {
            snapshot.markCompleted(.qualityChecked, artifactCount: validatedReport.checks.count)
        } else {
            let failureMessage = validatedReport.failedChecks.isEmpty
                ? "Quality gate failed"
                : validatedReport.failedChecks.map { "\($0.name): \($0.detail)" }.joined(separator: " | ")
            snapshot.markFailed(.qualityChecked, message: failureMessage)
            snapshot.removeDownstreamStages(after: .qualityChecked)
        }
        try write(snapshot)
    }

    static func saveExport(
        projectId: UUID,
        fileURL: URL,
        duration: Double?,
        resolution: String?,
        templateName: String?,
        fileSizeBytes: Int64?,
        qualityReport: QualityReport? = nil,
        verificationReport: ExportVerificationReport? = nil
    ) throws {
        var snapshot = load(projectId: projectId) ?? PipelineRunSnapshot(projectId: projectId)
        let actualFileSize = fileSize(at: fileURL) ?? fileSizeBytes
        var persistedQualityReport: QualityReport?
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            snapshot.export = nil
            snapshot.markFailed(.exported, message: "Export file missing at \(fileURL.path)")
            try write(snapshot)
            throw PipelineArtifactStoreError.invalidStageCompletion(
                stage: .exported,
                reason: "Export file missing at \(fileURL.path)"
            )
        }
        guard (actualFileSize ?? 0) > 0 else {
            snapshot.export = nil
            snapshot.markFailed(.exported, message: "Export file is empty")
            try write(snapshot)
            throw PipelineArtifactStoreError.invalidStageCompletion(stage: .exported, reason: "Export file is empty")
        }

        if let qualityReport {
            let validatedReport = qualityReportByEnforcingPrerequisites(qualityReport, snapshot: snapshot)
            persistedQualityReport = validatedReport
            snapshot.qualityReport = QualityReportArtifact(validatedReport)
            if validatedReport.passed {
                snapshot.markCompleted(.qualityChecked, artifactCount: validatedReport.checks.count)
            } else {
                let failureMessage = validatedReport.failedChecks.isEmpty
                    ? "Quality gate failed"
                    : validatedReport.failedChecks.map { "\($0.name): \($0.detail)" }.joined(separator: " | ")
                snapshot.markFailed(.qualityChecked, message: failureMessage)
                snapshot.export = nil
                snapshot.markFailed(.exported, message: "Export blocked by failed quality gate")
                try write(snapshot)
                throw PipelineArtifactStoreError.invalidStageCompletion(
                    stage: .exported,
                    reason: "Export blocked by failed quality gate"
                )
            }
        } else {
            snapshot.export = nil
            snapshot.markFailed(.exported, message: "Export missing quality report")
            try write(snapshot)
            throw PipelineArtifactStoreError.invalidStageCompletion(
                stage: .exported,
                reason: "Export missing quality report"
            )
        }

        guard verificationReport?.passed == true else {
            let message = verificationReport?.failureSummary ?? "Export verification report missing"
            snapshot.export = nil
            snapshot.markFailed(.exported, message: message)
            try write(snapshot)
            throw PipelineArtifactStoreError.invalidStageCompletion(stage: .exported, reason: message)
        }

        snapshot.export = ExportArtifact(
            localFileName: fileURL.lastPathComponent,
            filePath: fileURL.path,
            duration: duration,
            resolution: resolution,
            templateName: templateName,
            fileSizeBytes: actualFileSize,
            qualityReport: persistedQualityReport.map(QualityReportArtifact.init),
            verificationReport: verificationReport
        )
        snapshot.markCompleted(.exported, artifactCount: 1)
        try write(snapshot)
    }

    static func delete(projectId: UUID) {
        try? FileManager.default.removeItem(at: artifactURL(for: projectId))
    }

    static func deleteAll() {
        try? FileManager.default.removeItem(at: storeDirectory)
        try? FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
    }

    private static var storeDirectory: URL {
        if let testStoreDirectoryURL {
            try? FileManager.default.createDirectory(at: testStoreDirectoryURL, withIntermediateDirectories: true)
            return testStoreDirectoryURL
        }

        let directory = URL.applicationSupportDirectory
            .appending(path: "CutSense", directoryHint: .isDirectory)
            .appending(path: "PipelineArtifacts", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func artifactURL(for projectId: UUID) -> URL {
        storeDirectory.appending(path: "\(projectId.uuidString).json")
    }

    private static func write(_ snapshot: PipelineRunSnapshot) throws {
        let data = try JSONEncoder.pipelineArtifacts.encode(snapshot)
        try data.write(to: artifactURL(for: snapshot.projectId), options: [.atomic])
    }

    private static func fileSize(at url: URL) -> Int64? {
        let value = try? FileManager.default.attributesOfItem(atPath: url.path)[.size]
        if let int64 = value as? Int64 {
            return int64
        }
        if let number = value as? NSNumber {
            return number.int64Value
        }
        return nil
    }

    private static func qualityReportByEnforcingPrerequisites(
        _ report: QualityReport,
        snapshot: PipelineRunSnapshot
    ) -> QualityReport {
        var checks = report.checks
        var missing: [String] = []

        if snapshot.captions?.isEmpty != false {
            missing.append("captions")
        }
        if snapshot.editPlan?.decisions.isEmpty != false {
            missing.append("edit plan decisions")
        }

        guard !missing.isEmpty else { return report }

        checks.append(QualityCheck(
            name: "Quality prerequisites",
            passed: false,
            detail: "Missing persisted artifact(s): \(missing.joined(separator: ", "))",
            severity: .critical,
            blocksExport: true
        ))

        return QualityReport(
            checks: checks,
            passed: false,
            score: min(report.score, 0)
        )
    }
}

struct WordTimingArtifact: Codable, Sendable, Equatable {
    let word: String
    let start: Double
    let duration: Double
}

struct VideoFileFingerprint: Codable, Sendable, Equatable {
    let fileSizeBytes: Int64?
    let modificationDate: Date?

    init(url: URL) {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        self.fileSizeBytes = attributes?[.size] as? Int64
        self.modificationDate = attributes?[.modificationDate] as? Date
    }
}

struct AudioSegmentArtifact: Codable, Sendable {
    let startTime: Double
    let endTime: Double
    let type: AudioSegmentType
    let energy: Float

    init(_ segment: AudioSegment) {
        self.startTime = segment.startTime
        self.endTime = segment.endTime
        self.type = segment.type
        self.energy = segment.energy
    }

    var domainValue: AudioSegment {
        AudioSegment(
            startTime: startTime,
            endTime: endTime,
            type: type,
            energy: energy
        )
    }
}

struct AudioAnalysisArtifact: Codable, Sendable {
    let segments: [AudioSegmentArtifact]
    let silenceIntervals: [ClosedRangeArtifact]
    let averageEnergy: Float
    let peakEnergy: Float
    let duration: Double

    init(_ result: AudioAnalysisResult) {
        self.segments = result.segments.map(AudioSegmentArtifact.init)
        self.silenceIntervals = result.silenceIntervals.map(ClosedRangeArtifact.init)
        self.averageEnergy = result.averageEnergy
        self.peakEnergy = result.peakEnergy
        self.duration = result.duration
    }

    var domainValue: AudioAnalysisResult {
        AudioAnalysisResult(
            segments: segments.map(\.domainValue),
            silenceIntervals: silenceIntervals.map { $0.lowerBound...$0.upperBound },
            averageEnergy: averageEnergy,
            peakEnergy: peakEnergy,
            duration: duration
        )
    }
}

struct ClosedRangeArtifact: Codable, Sendable {
    let lowerBound: Double
    let upperBound: Double

    init(_ range: ClosedRange<Double>) {
        self.lowerBound = range.lowerBound
        self.upperBound = range.upperBound
    }
}

struct TranscriptSegmentArtifact: Codable, Sendable {
    let startTime: Double
    let endTime: Double
    let text: String
    let confidence: Float
    let segmentType: TranscriptSegment.SegmentType
    let aiConfidence: Float?
    let aiReason: String?
    let rawConfidence: Float?
    let wordTimings: [WordTimingArtifact]

    init(_ segment: TranscriptSegment) {
        self.startTime = segment.startTime
        self.endTime = segment.endTime
        self.text = segment.text
        self.confidence = segment.confidence
        self.segmentType = segment.segmentType
        self.aiConfidence = segment.aiConfidence
        self.aiReason = segment.aiReason
        self.rawConfidence = segment.rawConfidence
        self.wordTimings = segment.wordTimings.map {
            WordTimingArtifact(word: $0.word, start: $0.start, duration: $0.duration)
        }
    }

    var domainValue: TranscriptSegment {
        var segment = TranscriptSegment(
            startTime: startTime,
            endTime: endTime,
            text: text,
            confidence: confidence,
            segmentType: segmentType
        )
        segment.aiConfidence = aiConfidence
        segment.aiReason = aiReason
        segment.rawConfidence = rawConfidence
        segment.wordTimings = wordTimings.map {
            (word: $0.word, start: $0.start, duration: $0.duration)
        }
        return segment
    }
}

struct TranscriptionArtifact: Codable, Sendable {
    let fullText: String
    let segments: [TranscriptSegmentArtifact]
    let language: String
    let overallConfidence: Float
    let rawOverallConfidence: Float?
    let recognitionStatus: TranscriptionRecognitionStatus?

    init(_ result: TranscriptionResult) {
        self.fullText = result.fullText
        self.segments = result.segments.map(TranscriptSegmentArtifact.init)
        self.language = result.language
        self.overallConfidence = result.overallConfidence
        self.rawOverallConfidence = result.rawOverallConfidence
        self.recognitionStatus = result.recognitionStatus
    }

    var domainValue: TranscriptionResult {
        TranscriptionResult(
            fullText: fullText,
            segments: segments.map(\.domainValue),
            language: language,
            overallConfidence: overallConfidence,
            rawOverallConfidence: rawOverallConfidence,
            recognitionStatus: recognitionStatus ?? .final
        )
    }
}

struct RoughCutDecisionArtifact: Codable, Sendable {
    let startTime: Double
    let endTime: Double
    let action: CutAction
    let reason: String
    let confidence: Float
    let linkedTranscriptText: String?
    let requiresReview: Bool

    init(_ decision: RoughCutDecision) {
        self.startTime = decision.startTime
        self.endTime = decision.endTime
        self.action = decision.action
        self.reason = decision.reason
        self.confidence = decision.confidence
        self.linkedTranscriptText = decision.linkedTranscriptText
        self.requiresReview = decision.requiresReview
    }

    var domainValue: RoughCutDecision {
        RoughCutDecision(
            startTime: startTime,
            endTime: endTime,
            action: action,
            reason: reason,
            confidence: confidence,
            linkedTranscriptText: linkedTranscriptText,
            requiresReview: requiresReview
        )
    }
}

struct RoughCutArtifact: Codable, Sendable {
    let decisions: [RoughCutDecisionArtifact]
    let originalDuration: Double
    let cleanDuration: Double

    init(_ result: RoughCutResult) {
        self.decisions = result.decisions.map(RoughCutDecisionArtifact.init)
        self.originalDuration = result.originalDuration
        self.cleanDuration = result.cleanDuration
    }

    var domainValue: RoughCutResult {
        let domainDecisions = decisions.map(\.domainValue)
        return RoughCutResult(
            decisions: domainDecisions,
            originalDuration: originalDuration,
            cleanDuration: cleanDuration,
            keepSegments: domainDecisions.filter { $0.action == .keep },
            cutSegments: domainDecisions.filter { $0.action == .cut || $0.action == .trimStart || $0.action == .trimEnd },
            reviewSegments: domainDecisions.filter(\.requiresReview)
        )
    }
}

struct CaptionSegmentArtifact: Codable, Sendable {
    let id: UUID
    let startTime: Double
    let endTime: Double
    let text: String
    let role: CaptionRole
    let style: CaptionStyle
    let sceneBehavior: CaptionSceneBehavior
    let wordTimings: [WordTimingArtifact]

    init(_ caption: CaptionSegment) {
        self.id = caption.id
        self.startTime = caption.startTime
        self.endTime = caption.endTime
        self.text = caption.text
        self.role = caption.role
        self.style = caption.style
        self.sceneBehavior = caption.sceneBehavior
        self.wordTimings = caption.wordTimings.map {
            WordTimingArtifact(word: $0.word, start: $0.start, duration: $0.duration)
        }
    }

    var domainValue: CaptionSegment {
        CaptionSegment(
            id: id,
            startTime: startTime,
            endTime: endTime,
            text: text,
            role: role,
            style: style,
            sceneBehavior: sceneBehavior,
            wordTimings: wordTimings.map { (word: $0.word, start: $0.start, duration: $0.duration) }
        )
    }
}

struct EditDecisionArtifact: Codable, Sendable {
    let time: Double
    let duration: Double
    let type: EditType
    let reason: String
    let intensity: Float

    init(_ decision: EditDecision) {
        self.time = decision.time
        self.duration = decision.duration
        self.type = decision.type
        self.reason = decision.reason
        self.intensity = decision.intensity
    }

    var domainValue: EditDecision {
        EditDecision(
            time: time,
            duration: duration,
            type: type,
            reason: reason,
            intensity: intensity
        )
    }
}

struct EditPlanArtifact: Codable, Sendable {
    let decisions: [EditDecisionArtifact]
    let template: TemplateConfig
    let totalEffects: Int
    let averageIntensity: Float

    init(_ plan: EditPlan) {
        self.decisions = plan.decisions.map(EditDecisionArtifact.init)
        self.template = plan.template
        self.totalEffects = plan.totalEffects
        self.averageIntensity = plan.averageIntensity
    }

    init(
        decisions: [EditDecisionArtifact],
        template: TemplateConfig,
        totalEffects: Int,
        averageIntensity: Float
    ) {
        self.decisions = decisions
        self.template = template
        self.totalEffects = totalEffects
        self.averageIntensity = averageIntensity
    }

    var domainValue: EditPlan {
        EditPlan(
            decisions: decisions.map(\.domainValue),
            template: template,
            totalEffects: totalEffects,
            averageIntensity: averageIntensity
        )
    }
}

struct ExportArtifact: Codable, Sendable {
    let localFileName: String
    let filePath: String
    let duration: Double?
    let resolution: String?
    let templateName: String?
    let fileSizeBytes: Int64?
    let qualityReport: QualityReportArtifact?
    let verificationReport: ExportVerificationReport?
}

struct QualityReportArtifact: Codable, Sendable {
    let passed: Bool
    let score: Int
    let failedChecks: [QualityCheckArtifact]
    let checks: [QualityCheckArtifact]

    init(_ report: QualityReport) {
        self.passed = report.passed
        self.score = report.score
        self.failedChecks = report.failedChecks.map(QualityCheckArtifact.init)
        self.checks = report.checks.map(QualityCheckArtifact.init)
    }
}

struct QualityCheckArtifact: Codable, Sendable {
    let name: String
    let passed: Bool
    let detail: String
    let severity: QualityCheck.Severity
    let blocksExport: Bool

    init(_ check: QualityCheck) {
        self.name = check.name
        self.passed = check.passed
        self.detail = check.detail
        self.severity = check.severity
        self.blocksExport = check.blocksExport
    }
}

private extension JSONDecoder {
    static var pipelineArtifacts: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private extension JSONEncoder {
    static var pipelineArtifacts: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}
