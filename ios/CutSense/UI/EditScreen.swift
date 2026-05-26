import SwiftUI
import AVFoundation
import Photos

struct EditScreen: View {
    let videoURL: URL
    let projectId: UUID
    @Environment(AuthManager.self) private var authManager
    @State private var analysisVM = AnalysisViewModel()
    @State private var captionVM = CaptionPreviewViewModel()
    @State private var exportService = ExportService()
    @State private var selectedTemplate: TemplateConfig? = .techInfluencer
    @State private var didUserSelectTemplate = false
    @State private var phase: EditPhase = .analyzing
    @State private var showRoughCutDetail = false
    @State private var showPaywall = false
    @State private var didSave = false
    @State private var isSaving = false
    @State private var isExportPressed = false
    @State private var selectedTemplateForAnimation: UUID?
    @State private var activeExportRunId: UUID?
    @State private var reviewBlockerMessage: String?
    private var store: SubscriptionManager { .shared }

    enum EditPhase {
        case analyzing
        case ready
        case generatingCaptions
        case exporting
        case done(URL)
        case failed(String)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Compact video preview
                VideoPlayerView(url: exportedURL ?? videoURL)
                    .id((exportedURL ?? videoURL).standardizedFileURL.absoluteString)
                    .frame(height: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 12)
                    .padding(.top, 8)

                ScrollView {
                    VStack(spacing: 16) {
                        switch phase {
                        case .analyzing:
                            analyzingSection
                        case .ready:
                            readySection
                        case .generatingCaptions:
                            generatingCaptionsSection
                        case .exporting:
                            exportingSection
                        case .done:
                            doneSection
                        case .failed(let error):
                            failedSection(error)
                        }
                    }
                    .padding(.top, 16)
                    .padding(.bottom, 40)
                }
            }
        }
        .navigationTitle("Edit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task {
            await loadOrAnalyze()
        }
    }

    private var exportedURL: URL? {
        if case .done(let url) = phase { return url }
        return nil
    }

    // MARK: - Analyzing

    private var analyzingSection: some View {
        VStack(spacing: 16) {
            ForEach(Array(analysisVM.steps.enumerated()), id: \.offset) { index, step in
                HStack(spacing: 12) {
                    if index < analysisVM.currentStep {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.body)
                    } else if index == analysisVM.currentStep {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "circle")
                            .foregroundStyle(.gray.opacity(0.3))
                    }
                    Text(step)
                        .foregroundStyle(index <= analysisVM.currentStep ? .white : .gray.opacity(0.4))
                        .font(.subheadline)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if analysisVM.currentStep == 2 && !analysisVM.liveClassifications.isEmpty {
                liveClassificationFeed
            }
        }
        .padding(.horizontal, 24)
    }

    private var liveClassificationFeed: some View {
        VStack(spacing: 4) {
            if analysisVM.totalSegmentsToClassify > 0 {
                Text("\(analysisVM.classifiedCount)/\(analysisVM.totalSegmentsToClassify)")
                    .font(.caption)
                    .foregroundStyle(.gray)
            }
            ForEach(Array(analysisVM.liveClassifications.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 6) {
                    Circle()
                        .fill(item.intent == "content" ? .green : (item.intent == "filler" ? .red : .yellow))
                        .frame(width: 6, height: 6)
                    Text(item.text)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                    Spacer()
                    Text(item.intent)
                        .font(.caption2)
                        .foregroundStyle(.gray)
                }
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Ready (analysis done → pick template → export)

    private var readySection: some View {
        VStack(spacing: 20) {
            // Quick stats
            if let result = analysisVM.roughCutResult {
                HStack(spacing: 0) {
                    quickStat(formatDuration(result.originalDuration), label: "Original")
                    Image(systemName: "arrow.right")
                        .foregroundStyle(.gray)
                        .font(.caption)
                        .frame(maxWidth: .infinity)
                    quickStat(formatDuration(result.cleanDuration), label: "Clean", color: .green)
                    quickStat("\(result.cutSegments.count)", label: "Cuts", color: .red)
                }
                .padding()
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)

                if let reviewNotice = reviewNoticeText(for: result) {
                    ReviewRequiredBanner(
                        message: reviewNotice,
                        action: {
                            showRoughCutDetail = true
                        }
                    )
                    .padding(.horizontal)
                }
            }

            // Optional: fine-tune rough cut
            Button {
                showRoughCutDetail = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.3")
                    Text("Fine-tune cuts")
                }
                .font(.caption)
                .foregroundStyle(.gray)
            }

            // Template picker
            VStack(alignment: .leading, spacing: 10) {
                Text("Style")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(TemplateConfig.all, id: \.id) { template in
                            templatePill(template)
                        }
                    }
                    .padding(.horizontal)
                }
            }

            // Export button
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { isExportPressed = true }
                Task { await startFullExport() }
                withAnimation(.easeInOut(duration: 0.15)) { isExportPressed = false }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "bolt.fill")
                    Text("Export")
                }
                .fontWeight(.bold)
                .font(.title3)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(LinearGradient(colors: [.white, Color.white.opacity(0.85)], startPoint: .top, endPoint: .bottom))
                .foregroundStyle(.black)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .shadow(color: .white.opacity(0.3), radius: 12, y: 4)
                .scaleEffect(isExportPressed ? 0.97 : 1.0)
            }
            .padding(.horizontal, 24)

            if !store.isPro {
                Text("\(store.remainingFreeExports) free export\(store.remainingFreeExports == 1 ? "" : "s") left")
                    .font(.caption)
                    .foregroundStyle(.gray)
            }
        }
        .sheet(
            isPresented: $showRoughCutDetail,
            onDismiss: {
                if analysisVM.roughCutResult?.reviewSegments.isEmpty == true {
                    reviewBlockerMessage = nil
                }
            }
        ) {
            if analysisVM.roughCutResult != nil,
               let transcript = analysisVM.transcriptionResult {
                NavigationStack {
                    RoughCutReviewScreen(
                        roughCut: Binding(
                            get: { self.analysisVM.roughCutResult! },
                            set: { self.applyReviewedRoughCut($0) }
                        ),
                        transcription: transcript,
                        videoURL: videoURL,
                        projectId: projectId
                    )
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Done") { showRoughCutDetail = false }
                                .foregroundStyle(.white)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallScreen()
        }
    }

    private func reviewNoticeText(for result: RoughCutResult) -> String? {
        if !result.reviewSegments.isEmpty {
            return "\(result.reviewSegments.count) uncertain cut decision(s) need review before export."
        }
        return reviewBlockerMessage
    }

    private func applyReviewedRoughCut(_ roughCut: RoughCutResult) {
        analysisVM.roughCutResult = roughCut
        captionVM.invalidate()
        if roughCut.reviewSegments.isEmpty {
            reviewBlockerMessage = nil
        }
    }

    private func templatePill(_ template: TemplateConfig) -> some View {
        let isSelected = selectedTemplate?.id == template.id
        @GestureState var isPressing = false

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedTemplate = template
                didUserSelectTemplate = true
                captionVM.invalidate()
                HapticEngine.select()
            }
        } label: {
            VStack(spacing: 6) {
                Text(template.name)
                    .font(.subheadline.bold())
                    .foregroundStyle(isSelected ? .black : .white)
                Text(template.intensity.displayName)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? .black.opacity(0.6) : .gray)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(isSelected ? Color.white : Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.clear : Color.white.opacity(0.1), lineWidth: 1)
            )
            .shadow(color: isSelected ? Color.white.opacity(0.2) : Color.clear, radius: 8, y: 2)
            .scaleEffect(isPressing ? 0.95 : 1.0)
        }
        .buttonStyle(.plain)
        .gesture(
            LongPressGesture(minimumDuration: 0.05)
                .updating($isPressing) { _, state, _ in
                    state = true
                }
        )
    }

    // MARK: - Generating Captions

    private var generatingCaptionsSection: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(.white)
            Text("Preparing captions & effects...")
                .foregroundStyle(.gray)
                .font(.subheadline)
        }
        .padding(.top, 40)
    }

    // MARK: - Exporting

    private var exportingSection: some View {
        VStack(spacing: 16) {
            ProgressView(value: exportService.progress)
                .tint(.white)
                .padding(.horizontal, 24)

            Text("\(Int(exportService.progress * 100))%")
                .font(.title2.bold())
                .foregroundStyle(.white)

            Text(exportService.currentStepLabel.isEmpty ? "Exporting..." : exportService.currentStepLabel)
                .font(.subheadline)
                .foregroundStyle(.gray)

            Button("Cancel") {
                activeExportRunId = nil
                exportService.cancelExport()
                exportService = ExportService()
                phase = .ready
            }
            .foregroundStyle(.red)
            .font(.caption)
        }
        .padding(.top, 20)
    }

    // MARK: - Done

    private var doneSection: some View {
        VStack(spacing: 20) {
            Image(systemName: didSave ? "checkmark.seal.fill" : (isSaving ? "arrow.down.circle.fill" : "checkmark.circle.fill"))
                .font(.system(size: 44))
                .foregroundStyle(didSave ? .green : .white)

            Text(didSave ? "Saved to Photos!" : (isSaving ? "Saving..." : "Export Complete"))
                .font(.title3.bold())
                .foregroundStyle(.white)

            if let url = exportedURL {
                ShareLink(item: url) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.white.opacity(0.08))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, 24)

                Button {
                    resetForNewExport()
                } label: {
                    Text("Edit Again")
                        .font(.subheadline)
                        .foregroundStyle(.gray)
                }
            }
        }
        .padding(.top, 20)
    }

    // MARK: - Failed

    private func failedSection(_ error: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.red)

            Text("Failed")
                .font(.title3.bold())
                .foregroundStyle(.white)

            Text(error)
                .font(.caption)
                .foregroundStyle(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button {
                if analysisVM.roughCutResult != nil {
                    phase = .ready
                } else {
                    phase = .analyzing
                    Task {
                        await loadOrAnalyze(useCachedArtifacts: false)
                    }
                }
            } label: {
                Text("Retry")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.white)
                    .foregroundStyle(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 24)
        }
        .padding(.top, 20)
    }

    // MARK: - Export Logic

    private func startFullExport() async {
        guard let roughCut = analysisVM.roughCutResult,
              let transcript = analysisVM.transcriptionResult,
              let template = selectedTemplate else { return }

        let includedRanges = TimelineRangeNormalizer.includedRanges(
            from: roughCut.decisions,
            assetDuration: roughCut.originalDuration
        )
        guard !includedRanges.isEmpty || roughCut.decisions.isEmpty else {
            phase = .failed("Rough cut removed every segment. Fine-tune cuts and restore at least one segment before exporting.")
            return
        }

        await store.checkSubscriptionStatus()
        guard store.canExport else {
            showPaywall = true
            return
        }

        guard roughCut.reviewSegments.isEmpty else {
            promptCutReviewBeforeExport(
                roughCut: roughCut,
                failedChecks: "Review required"
            )
            return
        }

        let runId = UUID()
        activeExportRunId = runId
        defer {
            if activeExportRunId == runId {
                activeExportRunId = nil
            }
        }

        // Phase: generating captions
        phase = .generatingCaptions
        let restoredCaptionArtifacts = !CutSenseDebugRuntime.forcePipelineExecution
            && captionVM.restoreArtifacts(projectId: projectId, template: template)
        if !restoredCaptionArtifacts {
            await captionVM.generate(
                transcription: transcript,
                roughCut: roughCut,
                template: template,
                audioQuality: analysisVM.audioQualityReport,
                projectId: projectId
            )
            guard isActiveExportRun(runId) else { return }

            // Save caption data
            if let userId = authManager.effectiveUserId {
                await captionVM.saveCaptionData(
                    projectId: projectId,
                    userId: userId,
                    template: template
                )
            }
        } else {
            captionVM.evaluateQuality(
                transcription: transcript,
                roughCut: roughCut,
                template: template,
                audioQuality: analysisVM.audioQualityReport,
                projectId: projectId
            )
        }
        guard isActiveExportRun(runId) else { return }

        guard let report = captionVM.qualityReport else {
            PipelineDiagnostics.record(
                projectId: projectId,
                stage: .exported,
                status: .failed,
                source: .export,
                message: "export blocked because quality gate did not produce a report"
            )
            phase = .failed("Export quality check failed: missing quality report")
            return
        }

        if !report.passed {
            let failedChecks = report.failedChecks.map(\.name).joined(separator: ", ")
            let failedCheckDetails = report.failedChecks.map { "\($0.name): \($0.detail)" }.joined(separator: " | ")
            PipelineDiagnostics.record(
                projectId: projectId,
                stage: .exported,
                status: .failed,
                source: .export,
                message: "export blocked by quality gate",
                metadata: [
                    "score": "\(report.score)",
                    "failedChecks": failedChecks,
                    "failedCheckDetails": failedCheckDetails
                ]
            )
            if report.failedChecks.contains(where: { $0.name == "Review required" }) {
                promptCutReviewBeforeExport(
                    roughCut: roughCut,
                    failedChecks: failedChecks
                )
            } else {
                phase = .failed("Export quality check failed: \(failedChecks)")
            }
            return
        }

        // Phase: exporting
        await store.checkSubscriptionStatus()
        guard store.canExport else {
            showPaywall = true
            return
        }
        let isProEntitled = store.isPro

        phase = .exporting
        let exportStart = Date()
        PipelineDiagnostics.record(
            projectId: projectId,
            stage: .exported,
            status: .running,
            source: .export,
            message: "export started from edit screen",
            metadata: [
                "template": template.id,
                "debugProOverride": "\(CutSenseDebugRuntime.forceProEntitlement)"
            ]
        )

        if authManager.effectiveUserId != nil {
            try? await PipelineRepository().updateProjectStatus(projectId, status: .exporting)
        }
        guard isActiveExportRun(runId) else { return }

        let url = await exportService.exportWithPipeline(
            sourceURL: videoURL,
            decisions: roughCut.decisions,
            captions: captionVM.captions,
            template: template,
            editPlan: captionVM.editPlan,
            isProEntitled: isProEntitled
        )
        guard isActiveExportRun(runId) else { return }

        if let url {
            let fileSize = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64
            let verification = exportService.lastVerificationReport
            PipelineDiagnostics.record(
                projectId: projectId,
                stage: .exported,
                status: .completed,
                source: .export,
                message: "export completed from edit screen",
                artifactCount: 1,
                durationSeconds: Date().timeIntervalSince(exportStart),
                metadata: [
                    "fileSizeBytes": "\(fileSize ?? 0)",
                    "outputPath": url.path,
                    "postExportVerified": "\(verification?.passed ?? false)",
                    "postExportFailures": verification?.failureSummary ?? "",
                    "resolution": verification?.resolution ?? ""
                ]
            )
            phase = .done(url)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            store.recordExport()

            // Auto-save to Photos
            isSaving = true
            didSave = await exportService.saveToPhotos(url: url)
            isSaving = false

            // Save export record
            if let userId = authManager.effectiveUserId {
                await saveExportRecord(
                    userId: userId,
                    fileURL: url,
                    qualityReport: captionVM.qualityReport,
                    verificationReport: verification
                )
            }
        } else {
            PipelineDiagnostics.record(
                projectId: projectId,
                stage: .exported,
                status: .failed,
                source: .export,
                message: exportService.errorMessage ?? "export failed from edit screen",
                durationSeconds: Date().timeIntervalSince(exportStart)
            )
            phase = .failed(exportService.errorMessage ?? "Export failed")
        }
    }

    private func isActiveExportRun(_ runId: UUID) -> Bool {
        activeExportRunId == runId
    }

    private func promptCutReviewBeforeExport(roughCut: RoughCutResult, failedChecks: String) {
        reviewBlockerMessage = "\(roughCut.reviewSegments.count) uncertain cut decision(s) need review before export."
        PipelineDiagnostics.record(
            projectId: projectId,
            stage: .exported,
            status: .failed,
            source: .export,
            message: "export waiting for rough cut review",
            metadata: [
                "reviewCount": "\(roughCut.reviewSegments.count)",
                "failedChecks": failedChecks
            ]
        )
        phase = .ready
        showRoughCutDetail = true
    }

    private func loadOrAnalyze(useCachedArtifacts: Bool = true) async {
        guard let userId = authManager.effectiveUserId else {
            phase = .failed("User session unavailable.")
            return
        }

        let shouldUseCache = useCachedArtifacts && !CutSenseDebugRuntime.forcePipelineExecution
        if shouldUseCache,
           analysisVM.restoreArtifacts(projectId: projectId, expectedVideoURL: videoURL) {
            await applyAutonomousTemplateSelection()
            phase = .ready
            return
        }

        if CutSenseDebugRuntime.forcePipelineExecution {
            PipelineDiagnostics.record(
                projectId: projectId,
                stage: .imported,
                status: .running,
                source: .live,
                message: "debug forced live pipeline execution; cache bypassed"
            )
        }

        await analysisVM.analyze(videoURL: videoURL, projectId: projectId, userId: userId)
        if analysisVM.roughCutResult != nil {
            await applyAutonomousTemplateSelection()
            phase = .ready
        } else if let error = analysisVM.errorMessage {
            phase = .failed(error)
        } else {
            phase = .failed("Analysis did not produce a rough cut.")
        }
    }

    private func applyAutonomousTemplateSelection() async {
        guard !didUserSelectTemplate,
              let transcript = analysisVM.transcriptionResult,
              let roughCut = analysisVM.roughCutResult,
              let audio = analysisVM.audioResult else {
            return
        }

        guard let selection = await TemplateRecommendationEngine.selectAutonomousTemplate(
            transcription: transcript,
            roughCut: roughCut,
            audio: audio,
            sourceURL: videoURL
        ) else { return }

        let previousTemplateId = selectedTemplate?.id
        selectedTemplate = selection.template
        if previousTemplateId != selection.template.id {
            captionVM.invalidate()
        }

        PipelineDiagnostics.record(
            projectId: projectId,
            stage: .templateSelected,
            status: .completed,
            source: .live,
            message: "autonomous template selected",
            metadata: [
                "template": selection.template.id,
                "reason": selection.recommendation.reason,
                "score": selection.recommendation.score.formatted(.number.precision(.fractionLength(1))),
                "confidence": selection.recommendation.confidence.formatted(.number.precision(.fractionLength(2))),
                "intensityLevel": selection.intensityLevel.formatted(.number.precision(.fractionLength(2)))
            ]
        )
    }

    private func saveExportRecord(
        userId: UUID,
        fileURL: URL,
        qualityReport: QualityReport?,
        verificationReport: ExportVerificationReport?
    ) async {
        let pipeline = PipelineRepository()
        let fileSize = try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int64
        let asset = AVURLAsset(url: fileURL)
        let exportDuration = try? await asset.load(.duration)
        let durationSecs = verificationReport?.duration ?? exportDuration.map { CMTimeGetSeconds($0) }
        let resolution = verificationReport?.resolution

        do {
            try PipelineArtifactStore.saveExport(
                projectId: projectId,
                fileURL: fileURL,
                duration: durationSecs,
                resolution: resolution,
                templateName: selectedTemplate?.name,
                fileSizeBytes: fileSize,
                qualityReport: qualityReport,
                verificationReport: verificationReport
            )
        } catch {
            #if DEBUG
            print("[CutSense] Local export artifact save failed: \(error.localizedDescription)")
            #endif
        }

        do {
            try await pipeline.saveExport(
                projectId: projectId,
                userId: userId,
                localFileName: fileURL.lastPathComponent,
                duration: durationSecs,
                resolution: resolution,
                templateName: selectedTemplate?.name,
                fileSizeBytes: fileSize
            )
        } catch {
            #if DEBUG
            print("[CutSense] Cloud export record save failed: \(error.localizedDescription)")
            #endif
        }

        do {
            try await pipeline.updateProjectStatus(projectId, status: .exported)
        } catch {
            #if DEBUG
            print("[CutSense] Export status update failed: \(error.localizedDescription)")
            #endif
        }
    }

    private func resetForNewExport() {
        phase = .ready
        exportService = ExportService()
        didSave = false
        isSaving = false
    }

    // MARK: - Helpers

    private func quickStat(_ value: String, label: String, color: Color = .white) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3.bold())
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.gray)
        }
        .frame(maxWidth: .infinity)
    }

    private func formatDuration(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

private struct ReviewRequiredBanner: View {
    let message: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "eye.trianglebadge.exclamationmark")
                    .foregroundStyle(.yellow)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button("Review Cuts", systemImage: "eye", action: action)
                .font(.caption.bold())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.yellow.opacity(0.16))
                .foregroundStyle(.yellow)
                .clipShape(.rect(cornerRadius: 8))
        }
        .padding()
        .background(Color.yellow.opacity(0.06))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.yellow.opacity(0.25), lineWidth: 1)
        )
        .clipShape(.rect(cornerRadius: 12))
    }
}
