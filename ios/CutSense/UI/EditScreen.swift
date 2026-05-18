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
    @State private var selectedTemplate: TemplateConfig? = TemplateConfig.all.first
    @State private var phase: EditPhase = .analyzing
    @State private var showRoughCutDetail = false
    @State private var didSave = false
    @State private var isSaving = false
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
            guard let userId = authManager.effectiveUserId else { return }
            await analysisVM.analyze(videoURL: videoURL, projectId: projectId, userId: userId)
            if analysisVM.roughCutResult != nil {
                phase = .ready
            } else if let error = analysisVM.errorMessage {
                phase = .failed(error)
            }
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
                Task { await startFullExport() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "bolt.fill")
                    Text("Export")
                }
                .fontWeight(.bold)
                .font(.title3)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(.white)
                .foregroundStyle(.black)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 24)

            if !store.isPro {
                Text("\(store.remainingFreeExports) free export\(store.remainingFreeExports == 1 ? "" : "s") left")
                    .font(.caption)
                    .foregroundStyle(.gray)
            }
        }
        .sheet(isPresented: $showRoughCutDetail) {
            if let roughCut = analysisVM.roughCutResult,
               let transcript = analysisVM.transcriptionResult {
                NavigationStack {
                    RoughCutReviewScreen(
                        roughCut: roughCut,
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
    }

    private func templatePill(_ template: TemplateConfig) -> some View {
        let isSelected = selectedTemplate?.id == template.id
        return Button {
            selectedTemplate = template
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
        }
        .buttonStyle(.plain)
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
                exportService.cancelExport()
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
                    guard let userId = authManager.effectiveUserId else { return }
                    Task {
                        await analysisVM.analyze(videoURL: videoURL, projectId: projectId, userId: userId)
                        if analysisVM.roughCutResult != nil {
                            phase = .ready
                        }
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

        guard store.canExport else {
            // TODO: show paywall
            return
        }

        // Phase: generating captions
        phase = .generatingCaptions
        await captionVM.generate(
            transcription: transcript,
            roughCut: roughCut,
            template: template
        )

        // Save caption data
        if let userId = authManager.effectiveUserId {
            await captionVM.saveCaptionData(
                projectId: projectId,
                userId: userId,
                templateName: template.name
            )
        }

        // Phase: exporting
        phase = .exporting

        if authManager.effectiveUserId != nil {
            try? await PipelineRepository().updateProjectStatus(projectId, status: .exporting)
        }

        let url = await exportService.exportWithPipeline(
            sourceURL: videoURL,
            decisions: roughCut.decisions,
            captions: captionVM.captions,
            template: template,
            editPlan: captionVM.editPlan
        )

        if let url {
            phase = .done(url)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            store.recordExport()

            // Auto-save to Photos
            isSaving = true
            didSave = await exportService.saveToPhotos(url: url)
            isSaving = false

            // Save export record
            if let userId = authManager.effectiveUserId {
                await saveExportRecord(userId: userId, fileURL: url)
            }
        } else {
            phase = .failed(exportService.errorMessage ?? "Export failed")
        }
    }

    private func saveExportRecord(userId: UUID, fileURL: URL) async {
        let pipeline = PipelineRepository()
        do {
            let fileSize = try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int64
            let asset = AVURLAsset(url: fileURL)
            let exportDuration = try? await asset.load(.duration)
            let durationSecs = exportDuration.map { CMTimeGetSeconds($0) }
            try await pipeline.saveExport(
                projectId: projectId,
                userId: userId,
                localFileName: fileURL.lastPathComponent,
                duration: durationSecs,
                resolution: "1080x1920",
                templateName: selectedTemplate?.name,
                fileSizeBytes: fileSize
            )
            try await pipeline.updateProjectStatus(projectId, status: .exported)
        } catch {
            #if DEBUG
            print("[CutSense] DB save after export failed: \(error.localizedDescription)")
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
