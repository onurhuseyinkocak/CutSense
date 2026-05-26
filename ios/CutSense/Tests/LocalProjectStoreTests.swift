import Foundation
import Testing
@testable import CutSense

@Suite("LocalProjectStore")
@MainActor
struct LocalProjectStoreTests {
    @Test("Local project round-trips imported video metadata")
    func localProjectRoundTrip() {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "cutsense-local-store-tests/\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        LocalProjectStore.testStoreURL = directory.appending(path: "local-projects.json")
        defer {
            LocalProjectStore.testStoreURL = nil
            try? FileManager.default.removeItem(at: directory)
        }

        let userId = UUID()
        let videoPath = directory.appending(path: "raw.mov").path
        let project = Project(
            id: UUID(),
            userId: userId,
            title: "Imported video",
            originalDuration: 12.5,
            finalDuration: nil,
            status: .imported,
            selectedTemplate: nil,
            sourceLocalIdentifier: nil,
            sourceFileName: "raw.mov",
            localProjectPath: videoPath,
            createdAt: Date(),
            updatedAt: Date()
        )

        LocalProjectStore.upsert(project)

        let loaded = LocalProjectStore.load(userId: userId)
        #expect(loaded.count == 1)
        #expect(loaded.first?.id == project.id)
        #expect(loaded.first?.status == .imported)
        #expect(loaded.first?.localProjectPath == videoPath)
        #expect(loaded.first?.sourceFileName == "raw.mov")
        #expect(loaded.first?.originalDuration == 12.5)
    }

    @Test("Local delete removes only the selected project")
    func localDelete() {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "cutsense-local-store-tests/\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        LocalProjectStore.testStoreURL = directory.appending(path: "local-projects.json")
        defer {
            LocalProjectStore.testStoreURL = nil
            try? FileManager.default.removeItem(at: directory)
        }

        let userId = UUID()
        let first = makeProject(userId: userId, title: "First")
        let second = makeProject(userId: userId, title: "Second")
        LocalProjectStore.upsert(first)
        LocalProjectStore.upsert(second)

        LocalProjectStore.delete(first)

        let loaded = LocalProjectStore.load(userId: userId)
        #expect(loaded.count == 1)
        #expect(loaded.first?.id == second.id)
    }

    @Test("Pipeline artifacts persist and restore stage outputs")
    func pipelineArtifactsRoundTrip() throws {
        let directory = makeTemporaryDirectory()
        PipelineArtifactStore.testStoreDirectoryURL = directory.appending(path: "artifacts", directoryHint: .isDirectory)
        defer {
            PipelineArtifactStore.testStoreDirectoryURL = nil
            try? FileManager.default.removeItem(at: directory)
        }

        let projectId = UUID()
        let sourceURL = directory.appending(path: "source.mov")
        let transcript = makeTranscript()
        let roughCut = makeRoughCut()

        try PipelineArtifactStore.saveAnalysis(
            projectId: projectId,
            sourceVideoURL: sourceURL,
            transcription: transcript,
            roughCut: roughCut
        )

        let analysisSnapshot = try #require(PipelineArtifactStore.load(projectId: projectId))
        #expect(analysisSnapshot.sourceVideoPath == sourceURL.path)
        #expect(analysisSnapshot.status(of: .audioAnalyzed) == .pending)
        #expect(analysisSnapshot.status(of: .transcribed) == .completed)
        #expect(analysisSnapshot.status(of: .smartAnalyzed) == .completed)
        #expect(analysisSnapshot.status(of: .roughCut) == .completed)
        #expect(analysisSnapshot.status(of: .qualityChecked) == .pending)
        #expect(analysisSnapshot.manifest.transcriptSegmentCount == 2)
        #expect(analysisSnapshot.manifest.roughCutDecisionCount == 2)

        let restoredTranscript = try #require(analysisSnapshot.transcriptionResult)
        #expect(restoredTranscript.fullText == "Merhaba dunya Kes burayi")
        #expect(restoredTranscript.segments.first?.wordTimings.first?.word == "Merhaba")
        #expect(restoredTranscript.segments.first?.aiConfidence == 0.95)

        let restoredRoughCut = try #require(analysisSnapshot.roughCutResult)
        #expect(restoredRoughCut.decisions.first?.action == .keep)
        #expect(restoredRoughCut.cutSegments.count == 1)

        let caption = CaptionSegment(
            startTime: 0,
            endTime: 1.2,
            text: "Merhaba dunya",
            role: .hook,
            style: .hookImpact,
            sceneBehavior: .hookImpact,
            wordTimings: [(word: "Merhaba", start: 0, duration: 0.4)]
        )
        let editDecision = EditDecision(
            time: 0,
            duration: 0.3,
            type: .zoom,
            reason: "Hook emphasis",
            intensity: 0.7
        )
        let editPlan = EditPlan(
            decisions: [editDecision],
            template: .viralCaption,
            totalEffects: 1,
            averageIntensity: 0.7
        )

        try PipelineArtifactStore.saveCaptioning(
            projectId: projectId,
            template: .viralCaption,
            captions: [caption],
            editPlan: editPlan
        )

        let captionSnapshot = try #require(PipelineArtifactStore.load(projectId: projectId))
        #expect(captionSnapshot.status(of: .captioned) == .completed)
        #expect(captionSnapshot.status(of: .editPlanned) == .completed)
        #expect(captionSnapshot.manifest.captionCount == 1)
        #expect(captionSnapshot.manifest.editDecisionCount == 1)
        #expect(captionSnapshot.captionSegments?.first?.wordTimings.first?.word == "Merhaba")
        #expect(captionSnapshot.editPlanResult?.template.id == TemplateConfig.viralCaption.id)

        let qualityReport = QualityReport(
            checks: [
                QualityCheck(
                    name: "Caption count",
                    passed: true,
                    detail: "1 captions generated",
                    severity: .info
                )
            ],
            passed: true,
            score: 100
        )
        let verificationReport = ExportVerificationReport(
            timestamp: Date(),
            outputPath: directory.appending(path: "export.mp4").path,
            passed: true,
            fileSizeBytes: 2048,
            duration: 1.2,
            expectedDuration: 1.2,
            durationDrift: 0,
            resolution: "1080x1920",
            expectedResolution: "1080x1920",
            codec: "avc1",
            hasVideoTrack: true,
            hasAudioTrack: true,
            failedChecks: []
        )
        try Data(count: 2048).write(to: directory.appending(path: "export.mp4"))

        try PipelineArtifactStore.saveExport(
            projectId: projectId,
            fileURL: directory.appending(path: "export.mp4"),
            duration: 1.2,
            resolution: "1080x1920",
            templateName: TemplateConfig.viralCaption.name,
            fileSizeBytes: 2048,
            qualityReport: qualityReport,
            verificationReport: verificationReport
        )

        let exportSnapshot = try #require(PipelineArtifactStore.load(projectId: projectId))
        #expect(exportSnapshot.status(of: .exported) == .completed)
        #expect(exportSnapshot.manifest.hasExport)
        #expect(exportSnapshot.export?.fileSizeBytes == 2048)
        #expect(exportSnapshot.export?.qualityReport?.score == 100)
        #expect(exportSnapshot.export?.verificationReport?.passed == true)
        #expect(exportSnapshot.export?.verificationReport?.resolution == "1080x1920")
    }

    @Test("Saving a revised analysis invalidates downstream caption and export artifacts")
    func revisedAnalysisInvalidatesDownstreamArtifacts() throws {
        let directory = makeTemporaryDirectory()
        PipelineArtifactStore.testStoreDirectoryURL = directory.appending(path: "artifacts", directoryHint: .isDirectory)
        defer {
            PipelineArtifactStore.testStoreDirectoryURL = nil
            try? FileManager.default.removeItem(at: directory)
        }

        let projectId = UUID()
        let sourceURL = directory.appending(path: "source.mov")
        let transcript = makeTranscript()
        let roughCut = makeRoughCut()
        try PipelineArtifactStore.saveAnalysis(
            projectId: projectId,
            sourceVideoURL: sourceURL,
            transcription: transcript,
            roughCut: roughCut
        )

        let caption = CaptionSegment(
            startTime: 0,
            endTime: 1.2,
            text: "Merhaba dunya",
            role: .hook,
            style: .hookImpact,
            sceneBehavior: .hookImpact
        )
        let editPlan = EditPlan(
            decisions: [
                EditDecision(
                    time: 0,
                    duration: 0.3,
                    type: .zoom,
                    reason: "Hook emphasis",
                    intensity: 0.7
                )
            ],
            template: .viralCaption,
            totalEffects: 1,
            averageIntensity: 0.7
        )
        let qualityReport = QualityReport(
            checks: [
                QualityCheck(
                    name: "Tech event anchoring",
                    passed: true,
                    detail: "anchored",
                    severity: .info
                )
            ],
            passed: true,
            score: 100
        )
        let exportURL = directory.appending(path: "export.mp4")
        try Data(count: 2048).write(to: exportURL)
        let verificationReport = ExportVerificationReport(
            timestamp: Date(),
            outputPath: exportURL.path,
            passed: true,
            fileSizeBytes: 2048,
            duration: 1.2,
            expectedDuration: 1.2,
            durationDrift: 0,
            resolution: "1080x1920",
            expectedResolution: "1080x1920",
            codec: "avc1",
            hasVideoTrack: true,
            hasAudioTrack: true,
            failedChecks: []
        )
        try PipelineArtifactStore.saveCaptioning(
            projectId: projectId,
            template: .viralCaption,
            captions: [caption],
            editPlan: editPlan
        )
        try PipelineArtifactStore.saveExport(
            projectId: projectId,
            fileURL: exportURL,
            duration: 1.2,
            resolution: "1080x1920",
            templateName: TemplateConfig.viralCaption.name,
            fileSizeBytes: 2048,
            qualityReport: qualityReport,
            verificationReport: verificationReport
        )

        try PipelineArtifactStore.saveAnalysis(
            projectId: projectId,
            sourceVideoURL: sourceURL,
            transcription: transcript,
            roughCut: roughCut
        )

        let snapshot = try #require(PipelineArtifactStore.load(projectId: projectId))
        #expect(snapshot.manifest.captionCount == 0)
        #expect(snapshot.manifest.editDecisionCount == 0)
        #expect(!snapshot.manifest.hasExport)
        #expect(snapshot.status(of: .captioned) == .pending)
        #expect(snapshot.status(of: .editPlanned) == .pending)
        #expect(snapshot.status(of: .qualityChecked) == .pending)
        #expect(snapshot.status(of: .exported) == .pending)
    }

    @Test("Quality report stage is persisted only after the quality gate runs")
    func qualityReportPersistsActualGateState() throws {
        let directory = makeTemporaryDirectory()
        PipelineArtifactStore.testStoreDirectoryURL = directory.appending(path: "artifacts", directoryHint: .isDirectory)
        defer {
            PipelineArtifactStore.testStoreDirectoryURL = nil
            try? FileManager.default.removeItem(at: directory)
        }

        let projectId = UUID()
        let sourceURL = directory.appending(path: "source.mov")
        try PipelineArtifactStore.saveAnalysis(
            projectId: projectId,
            sourceVideoURL: sourceURL,
            transcription: makeTranscript(),
            roughCut: makeRoughCut()
        )

        var snapshot = try #require(PipelineArtifactStore.load(projectId: projectId))
        #expect(snapshot.status(of: .qualityChecked) == .pending)

        let failingReport = QualityReport(
            checks: [
                QualityCheck(
                    name: "Tech event anchoring",
                    passed: false,
                    detail: "unanchored: test",
                    severity: .critical,
                    blocksExport: true
                )
            ],
            passed: false,
            score: 0
        )
        try PipelineArtifactStore.saveQualityReport(projectId: projectId, report: failingReport)

        snapshot = try #require(PipelineArtifactStore.load(projectId: projectId))
        #expect(snapshot.status(of: .qualityChecked) == .failed)
        #expect(snapshot.status(of: .exported) == .pending)
        #expect(snapshot.qualityReport?.passed == false)

        let caption = CaptionSegment(
            startTime: 0,
            endTime: 1.2,
            text: "Merhaba dunya",
            role: .hook,
            style: .hookImpact,
            sceneBehavior: .hookImpact
        )
        let editPlan = EditPlan(
            decisions: [
                EditDecision(
                    time: 0,
                    duration: 0.3,
                    type: .zoom,
                    reason: "Hook emphasis",
                    intensity: 0.7
                )
            ],
            template: .viralCaption,
            totalEffects: 1,
            averageIntensity: 0.7
        )
        try PipelineArtifactStore.saveCaptioning(
            projectId: projectId,
            template: .viralCaption,
            captions: [caption],
            editPlan: editPlan
        )

        let passingReport = QualityReport(
            checks: [
                QualityCheck(
                    name: "Tech event anchoring",
                    passed: true,
                    detail: "anchored",
                    severity: .info
                )
            ],
            passed: true,
            score: 100
        )
        try PipelineArtifactStore.saveQualityReport(projectId: projectId, report: passingReport)

        snapshot = try #require(PipelineArtifactStore.load(projectId: projectId))
        #expect(snapshot.status(of: .qualityChecked) == .completed)
        #expect(snapshot.qualityReport?.passed == true)
    }

    @Test("Caption and edit stages fail instead of completing empty artifacts")
    func captionAndEditStagesRejectEmptyArtifacts() throws {
        let directory = makeTemporaryDirectory()
        PipelineArtifactStore.testStoreDirectoryURL = directory.appending(path: "artifacts", directoryHint: .isDirectory)
        defer {
            PipelineArtifactStore.testStoreDirectoryURL = nil
            try? FileManager.default.removeItem(at: directory)
        }

        let projectId = UUID()
        try PipelineArtifactStore.saveAnalysis(
            projectId: projectId,
            sourceVideoURL: directory.appending(path: "source.mov"),
            transcription: makeTranscript(),
            roughCut: makeRoughCut()
        )

        try PipelineArtifactStore.saveCaptioning(
            projectId: projectId,
            template: .viralCaption,
            captions: [],
            editPlan: nil
        )

        let snapshot = try #require(PipelineArtifactStore.load(projectId: projectId))
        #expect(snapshot.status(of: .captioned) == .failed)
        #expect(snapshot.status(of: .editPlanned) == .failed)
        #expect(snapshot.manifest.captionCount == 0)
        #expect(snapshot.manifest.editDecisionCount == 0)
        #expect(snapshot.status(of: .qualityChecked) == .pending)
    }

    @Test("Passing quality report is downgraded when caption or edit artifacts are missing")
    func qualityReportRequiresCaptionAndEditArtifacts() throws {
        let directory = makeTemporaryDirectory()
        PipelineArtifactStore.testStoreDirectoryURL = directory.appending(path: "artifacts", directoryHint: .isDirectory)
        defer {
            PipelineArtifactStore.testStoreDirectoryURL = nil
            try? FileManager.default.removeItem(at: directory)
        }

        let projectId = UUID()
        try PipelineArtifactStore.saveAnalysis(
            projectId: projectId,
            sourceVideoURL: directory.appending(path: "source.mov"),
            transcription: makeTranscript(),
            roughCut: makeRoughCut()
        )

        let passingReport = QualityReport(
            checks: [
                QualityCheck(
                    name: "Tech event anchoring",
                    passed: true,
                    detail: "anchored",
                    severity: .info
                )
            ],
            passed: true,
            score: 100
        )

        try PipelineArtifactStore.saveQualityReport(projectId: projectId, report: passingReport)

        let snapshot = try #require(PipelineArtifactStore.load(projectId: projectId))
        #expect(snapshot.status(of: .qualityChecked) == .failed)
        #expect(snapshot.qualityReport?.passed == false)
        #expect(snapshot.qualityReport?.failedChecks.contains { $0.name == "Quality prerequisites" } == true)
    }

    @Test("Export stage fails when file or verification evidence is missing")
    func exportStageRequiresFileAndVerificationEvidence() throws {
        let directory = makeTemporaryDirectory()
        PipelineArtifactStore.testStoreDirectoryURL = directory.appending(path: "artifacts", directoryHint: .isDirectory)
        defer {
            PipelineArtifactStore.testStoreDirectoryURL = nil
            try? FileManager.default.removeItem(at: directory)
        }

        let projectId = UUID()
        let sourceURL = directory.appending(path: "source.mov")
        try PipelineArtifactStore.saveAnalysis(
            projectId: projectId,
            sourceVideoURL: sourceURL,
            transcription: makeTranscript(),
            roughCut: makeRoughCut()
        )

        let caption = CaptionSegment(
            startTime: 0,
            endTime: 1.2,
            text: "Merhaba dunya",
            role: .hook,
            style: .hookImpact,
            sceneBehavior: .hookImpact
        )
        let editPlan = EditPlan(
            decisions: [
                EditDecision(
                    time: 0,
                    duration: 0.3,
                    type: .zoom,
                    reason: "Hook emphasis",
                    intensity: 0.7
                )
            ],
            template: .viralCaption,
            totalEffects: 1,
            averageIntensity: 0.7
        )
        try PipelineArtifactStore.saveCaptioning(
            projectId: projectId,
            template: .viralCaption,
            captions: [caption],
            editPlan: editPlan
        )
        let passingReport = QualityReport(
            checks: [
                QualityCheck(
                    name: "Tech event anchoring",
                    passed: true,
                    detail: "anchored",
                    severity: .info
                )
            ],
            passed: true,
            score: 100
        )
        try PipelineArtifactStore.saveQualityReport(projectId: projectId, report: passingReport)

        var didThrow = false
        do {
            try PipelineArtifactStore.saveExport(
                projectId: projectId,
                fileURL: directory.appending(path: "missing-export.mp4"),
                duration: 1.2,
                resolution: "1080x1920",
                templateName: TemplateConfig.viralCaption.name,
                fileSizeBytes: 2048,
                qualityReport: passingReport,
                verificationReport: nil
            )
        } catch {
            didThrow = true
        }

        let snapshot = try #require(PipelineArtifactStore.load(projectId: projectId))
        #expect(didThrow)
        #expect(snapshot.status(of: .exported) == .failed)
        #expect(!snapshot.manifest.hasExport)
    }

    @Test("Saving rough cut edits preserves existing audio analysis")
    func roughCutEditPersistencePreservesAudioAnalysis() throws {
        let directory = makeTemporaryDirectory()
        PipelineArtifactStore.testStoreDirectoryURL = directory.appending(path: "artifacts", directoryHint: .isDirectory)
        defer {
            PipelineArtifactStore.testStoreDirectoryURL = nil
            try? FileManager.default.removeItem(at: directory)
        }

        let projectId = UUID()
        let sourceURL = directory.appending(path: "source.mov")
        let transcript = makeTranscript()
        let roughCut = makeRoughCut()
        let audio = makeAudioAnalysis()

        try PipelineArtifactStore.saveAnalysis(
            projectId: projectId,
            sourceVideoURL: sourceURL,
            transcription: transcript,
            roughCut: roughCut,
            audioAnalysis: audio
        )
        try PipelineArtifactStore.saveAnalysis(
            projectId: projectId,
            sourceVideoURL: sourceURL,
            transcription: transcript,
            roughCut: roughCut
        )

        let snapshot = try #require(PipelineArtifactStore.load(projectId: projectId))
        #expect(snapshot.audioAnalysis?.segments.count == audio.segments.count)
        #expect(snapshot.audioAnalysis?.duration == audio.duration)
        #expect(snapshot.status(of: .audioAnalyzed) == .completed)
    }

    @Test("Restored analysis reapplies current transcript cleanup before captioning")
    func restoredAnalysisReappliesTranscriptCleanup() throws {
        let directory = makeTemporaryDirectory()
        PipelineArtifactStore.testStoreDirectoryURL = directory.appending(path: "artifacts", directoryHint: .isDirectory)
        defer {
            PipelineArtifactStore.testStoreDirectoryURL = nil
            try? FileManager.default.removeItem(at: directory)
        }

        let projectId = UUID()
        let sourceURL = directory.appending(path: "source.mov")
        let badTranscript = TranscriptionResult(
            fullText: "da ürün yapabilirsin MVP çıkarabilsin",
            segments: [
                makeTimedSegment(
                    start: 22.71,
                    end: 25.14,
                    text: "da ürün yapabilirsin MVP çıkarabilsin",
                    confidence: 0.68
                )
            ],
            language: "tr",
            overallConfidence: 0.68
        )
        let keep = RoughCutDecision(
            startTime: 22.71,
            endTime: 25.14,
            action: .keep,
            reason: "Content",
            confidence: 0.9,
            linkedTranscriptText: "da ürün yapabilirsin MVP çıkarabilsin",
            requiresReview: false
        )
        let roughCut = RoughCutResult(
            decisions: [keep],
            originalDuration: 37.9,
            cleanDuration: 2.43,
            keepSegments: [keep],
            cutSegments: [],
            reviewSegments: []
        )
        try PipelineArtifactStore.saveAnalysis(
            projectId: projectId,
            sourceVideoURL: sourceURL,
            transcription: badTranscript,
            roughCut: roughCut
        )

        let viewModel = AnalysisViewModel()
        #expect(viewModel.restoreArtifacts(projectId: projectId, expectedVideoURL: sourceURL))
        let restored = try #require(viewModel.transcriptionResult)

        #expect(restored.segments[0].text == "da ürün çıkarabilsin fikirlerini MVP'ye çevirebilsinler")
        #expect(restored.segments[0].wordTimings.map(\.word) == ["da", "ürün", "çıkarabilsin", "fikirlerini", "MVP'ye", "çevirebilsinler"])
    }

    @Test("Pipeline artifact delete removes project run snapshot")
    func pipelineArtifactDelete() throws {
        let directory = makeTemporaryDirectory()
        PipelineArtifactStore.testStoreDirectoryURL = directory.appending(path: "artifacts", directoryHint: .isDirectory)
        defer {
            PipelineArtifactStore.testStoreDirectoryURL = nil
            try? FileManager.default.removeItem(at: directory)
        }

        let projectId = UUID()
        try PipelineArtifactStore.saveAnalysis(
            projectId: projectId,
            sourceVideoURL: directory.appending(path: "source.mov"),
            transcription: makeTranscript(),
            roughCut: makeRoughCut()
        )
        #expect(PipelineArtifactStore.load(projectId: projectId) != nil)

        PipelineArtifactStore.delete(projectId: projectId)

        #expect(PipelineArtifactStore.load(projectId: projectId) == nil)
    }

    @Test("Pipeline diagnostics persist JSONL stage events")
    func pipelineDiagnosticsPersistEvents() {
        let directory = makeTemporaryDirectory()
        PipelineDiagnostics.testLogURL = directory.appending(path: "pipeline-events.jsonl")
        defer {
            PipelineDiagnostics.testLogURL = nil
            try? FileManager.default.removeItem(at: directory)
        }

        let projectId = UUID()
        PipelineDiagnostics.clear()
        PipelineDiagnostics.record(
            projectId: projectId,
            stage: .audioAnalyzed,
            status: .completed,
            source: .live,
            message: "audio analysis completed",
            artifactCount: 3,
            durationSeconds: 1.25,
            metadata: ["duration": "3.0"]
        )

        let events = PipelineDiagnostics.loadEvents()
        #expect(events.count == 1)
        #expect(events.first?.projectId == projectId)
        #expect(events.first?.stage == .audioAnalyzed)
        #expect(events.first?.status == .completed)
        #expect(events.first?.source == .live)
        #expect(events.first?.artifactCount == 3)
        #expect(events.first?.metadata["duration"] == "3.0")
    }

    private func makeProject(userId: UUID, title: String) -> Project {
        Project(
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
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    private func makeTemporaryDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "cutsense-local-store-tests/\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeTranscript() -> TranscriptionResult {
        var first = TranscriptSegment(
            startTime: 0,
            endTime: 1.2,
            text: "Merhaba dunya",
            confidence: 0.98,
            segmentType: .speech
        )
        first.aiConfidence = 0.95
        first.aiReason = "Clear content"
        first.wordTimings = [
            (word: "Merhaba", start: 0, duration: 0.4),
            (word: "dunya", start: 0.45, duration: 0.4)
        ]

        let second = TranscriptSegment(
            startTime: 1.2,
            endTime: 2.0,
            text: "Kes burayi",
            confidence: 0.90,
            segmentType: .editCommand
        )

        return TranscriptionResult(
            fullText: "Merhaba dunya Kes burayi",
            segments: [first, second],
            language: "tr",
            overallConfidence: 0.94
        )
    }

    private func makeRoughCut() -> RoughCutResult {
        let keep = RoughCutDecision(
            startTime: 0,
            endTime: 1.2,
            action: .keep,
            reason: "Content",
            confidence: 0.95,
            linkedTranscriptText: "Merhaba dunya",
            requiresReview: false
        )
        let cut = RoughCutDecision(
            startTime: 1.2,
            endTime: 2.0,
            action: .cut,
            reason: "Edit command",
            confidence: 0.92,
            linkedTranscriptText: "Kes burayi",
            requiresReview: false
        )

        return RoughCutResult(
            decisions: [keep, cut],
            originalDuration: 2.0,
            cleanDuration: 1.2,
            keepSegments: [keep],
            cutSegments: [cut],
            reviewSegments: []
        )
    }

    private func makeAudioAnalysis() -> AudioAnalysisResult {
        AudioAnalysisResult(
            segments: [
                AudioSegment(startTime: 0, endTime: 1.2, type: .speech, energy: 0.6),
                AudioSegment(startTime: 1.2, endTime: 2.0, type: .silence, energy: 0.02),
            ],
            silenceIntervals: [1.2...2.0],
            averageEnergy: 0.3,
            peakEnergy: 0.8,
            duration: 2.0
        )
    }

    private func makeTimedSegment(
        start: Double,
        end: Double,
        text: String,
        confidence: Float
    ) -> TranscriptSegment {
        var segment = TranscriptSegment(
            startTime: start,
            endTime: end,
            text: text,
            confidence: confidence,
            segmentType: .speech
        )
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        let wordDuration = max(0.01, end - start) / Double(max(1, words.count))
        segment.wordTimings = words.enumerated().map { index, word in
            (
                word: word,
                start: start + Double(index) * wordDuration,
                duration: wordDuration
            )
        }
        return segment
    }
}
