import SwiftUI
import AVFoundation

struct ExportScreen: View {
    let sourceURL: URL
    let decisions: [RoughCutDecision]?
    let captions: [CaptionSegment]?
    let template: TemplateConfig?
    let editPlan: EditPlan?
    let projectId: UUID
    let qualityReport: QualityReport?
    @Bindable var exportService: ExportService
    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss
    @State private var didSave = false
    @State private var isSaving = false
    @State private var showPaywall = false
    private var store: SubscriptionManager { .shared }

    init(
        sourceURL: URL,
        exportService: ExportService,
        projectId: UUID,
        decisions: [RoughCutDecision]? = nil,
        captions: [CaptionSegment]? = nil,
        template: TemplateConfig? = nil,
        editPlan: EditPlan? = nil,
        qualityReport: QualityReport? = nil
    ) {
        self.sourceURL = sourceURL
        self.exportService = exportService
        self.projectId = projectId
        self.decisions = decisions
        self.captions = captions
        self.template = template
        self.editPlan = editPlan
        self.qualityReport = qualityReport
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 24) {
                    Spacer()

                    if exportService.isExporting {
                        exportingView
                    } else if let url = exportService.exportedURL {
                        completedView(url: url)
                    } else if let error = exportService.errorMessage, !exportService.isExporting {
                        failedView(error: error)
                    } else {
                        readyView
                    }

                    Spacer()
                }
                .padding(.horizontal, 24)
            }
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(.gray)
                        .disabled(exportService.isExporting || isSaving)
                }
            }
            .onChange(of: exportService.exportedURL != nil) { _, isDone in
                if isDone {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    store.recordExport()
                    // Auto-save to Photos
                    if let url = exportService.exportedURL, !didSave, !isSaving {
                        isSaving = true
                        Task {
                            let saved = await exportService.saveToPhotos(url: url)
                            isSaving = false
                            didSave = saved
                        }
                    }
                }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallScreen()
            }
        }
    }

    private var hasPipeline: Bool {
        decisions != nil && captions != nil && template != nil
    }

    private var hasCriticalFailures: Bool {
        guard let report = qualityReport else { return false }
        return report.checks.contains { !$0.passed && $0.severity == .critical }
    }

    private var readyView: some View {
        VStack(spacing: 20) {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 48))
                .foregroundStyle(.gray)

            Text(hasPipeline ? "Export Edited Video" : "Export 1080x1920 MP4")
                .font(.title3)
                .foregroundStyle(.white)

            if hasPipeline {
                Text("Captions + effects will be burned in")
                    .font(.caption)
                    .foregroundStyle(.gray)
            }

            // Quality warnings
            if let report = qualityReport, !report.passed {
                VStack(spacing: 6) {
                    ForEach(report.failedChecks, id: \.name) { check in
                        HStack(spacing: 6) {
                            Image(systemName: check.severity == .critical ? "xmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(check.severity == .critical ? .red : .orange)
                                .font(.caption)
                            Text(check.detail)
                                .font(.caption)
                                .foregroundStyle(.gray)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(12)
                .background(Color.red.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // Free tier export counter
            if !store.isPro {
                HStack(spacing: 6) {
                    Image(systemName: "film")
                        .foregroundStyle(.yellow)
                    Text("\(store.remainingFreeExports) free export\(store.remainingFreeExports == 1 ? "" : "s") left this month")
                        .font(.caption)
                        .foregroundStyle(.gray)
                }
            }

            Button {
                if store.canExport {
                    Task { await startExport() }
                } else {
                    showPaywall = true
                }
            } label: {
                Text(store.canExport ? "Start Export" : "Upgrade to Export")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(hasCriticalFailures ? Color.gray : (store.canExport ? .white : .yellow))
                    .foregroundStyle(hasCriticalFailures ? .white.opacity(0.5) : .black)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(hasCriticalFailures)

            // Quality score badge
            if let report = qualityReport {
                HStack(spacing: 6) {
                    Image(systemName: report.passed ? "checkmark.shield.fill" : "shield.fill")
                        .foregroundStyle(report.passed ? .green : .orange)
                    Text("Quality: \(report.score)/100")
                        .font(.caption)
                        .foregroundStyle(report.passed ? .green : .orange)
                }
            }
        }
    }

    private var exportingView: some View {
        VStack(spacing: 16) {
            ProgressView(value: exportService.progress)
                .tint(.white)

            Text("\(Int(exportService.progress * 100))%")
                .font(.headline)
                .foregroundStyle(.white)

            Text(exportService.currentStepLabel.isEmpty ? "Exporting..." : exportService.currentStepLabel)
                .foregroundStyle(.gray)

            Button("Cancel") {
                exportService.cancelExport()
                dismiss()
            }
            .foregroundStyle(.red)
        }
    }

    private func failedView(error: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.red)

            Text("Export Failed")
                .font(.title3)
                .foregroundStyle(.white)

            Text(error)
                .font(.caption)
                .foregroundStyle(.gray)
                .multilineTextAlignment(.center)

            Button {
                exportService.errorMessage = nil
                Task { await startExport() }
            } label: {
                Text("Retry")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.white)
                    .foregroundStyle(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            Button("Close") { dismiss() }
                .foregroundStyle(.gray)
        }
    }

    private func completedView(url: URL) -> some View {
        VStack(spacing: 20) {
            Image(systemName: didSave ? "checkmark.seal.fill" : (isSaving ? "arrow.down.circle.fill" : "checkmark.circle.fill"))
                .font(.system(size: 48))
                .foregroundStyle(didSave ? .green : .white)

            Text(didSave ? "Saved to Photos!" : (isSaving ? "Saving to Photos..." : "Export Complete"))
                .font(.title3)
                .foregroundStyle(.white)

            if let error = exportService.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)

                // Show manual save button if auto-save failed
                Button {
                    Task {
                        exportService.errorMessage = nil
                        didSave = await exportService.saveToPhotos(url: url)
                    }
                } label: {
                    Label("Retry Save", systemImage: "photo.on.rectangle")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.white)
                        .foregroundStyle(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }

            ShareLink(item: url) {
                Label("Share", systemImage: "square.and.arrow.up")
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.white.opacity(0.08))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            Button("Done") { dismiss() }
                .foregroundStyle(.gray)
                .padding(.top, 8)
                .disabled(isSaving)
        }
    }

    private func startExport() async {
        // Update status to exporting (skip DB ops if no auth user, e.g. DEBUG mode)
        let userId = authManager.effectiveUserId
        if let userId {
            try? await PipelineRepository().updateProjectStatus(projectId, status: .exporting)
        }

        var exportedURL: URL?
        if let decisions, let captions, let template {
            exportedURL = await exportService.exportWithPipeline(
                sourceURL: sourceURL,
                decisions: decisions,
                captions: captions,
                template: template,
                editPlan: editPlan
            )
        } else {
            exportedURL = await exportService.exportNormalized(from: sourceURL)
        }
        // Save export record to DB or mark failed
        if let userId, let url = exportedURL {
            await saveExportRecord(userId: userId, fileURL: url)
        } else if userId != nil {
            try? await PipelineRepository().updateProjectStatus(projectId, status: .failed)
        }
    }

    private func saveExportRecord(userId: UUID, fileURL: URL) async {
        let pipeline = PipelineRepository()
        do {
            let fileSize = try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int64
            // Get actual exported video duration
            let asset = AVURLAsset(url: fileURL)
            let exportDuration = try? await asset.load(.duration)
            let durationSecs = exportDuration.map { CMTimeGetSeconds($0) }
            try await pipeline.saveExport(
                projectId: projectId,
                userId: userId,
                localFileName: fileURL.lastPathComponent,
                duration: durationSecs,
                resolution: "1080x1920",
                templateName: template?.name,
                fileSizeBytes: fileSize
            )
            try await pipeline.updateProjectStatus(projectId, status: .exported)
        } catch {
            #if DEBUG
            print("[CutSense] DB save after export failed: \(error.localizedDescription)")
            #endif
        }
    }
}
