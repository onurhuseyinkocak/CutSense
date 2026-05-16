import SwiftUI

struct ExportScreen: View {
    let sourceURL: URL
    let decisions: [RoughCutDecision]?
    let captions: [CaptionSegment]?
    let template: TemplateConfig?
    let editPlan: EditPlan?
    let projectId: UUID
    @Bindable var exportService: ExportService
    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss
    @State private var didExport = false
    @State private var didSave = false

    init(
        sourceURL: URL,
        exportService: ExportService,
        projectId: UUID,
        decisions: [RoughCutDecision]? = nil,
        captions: [CaptionSegment]? = nil,
        template: TemplateConfig? = nil,
        editPlan: EditPlan? = nil
    ) {
        self.sourceURL = sourceURL
        self.exportService = exportService
        self.projectId = projectId
        self.decisions = decisions
        self.captions = captions
        self.template = template
        self.editPlan = editPlan
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
                }
            }
        }
    }

    private var hasPipeline: Bool {
        decisions != nil && captions != nil && template != nil
    }

    private var qualityReport: QualityReport? {
        guard let captions, let template, let editPlan,
              let decisions else { return nil }
        let keepSegs = decisions.filter { $0.action == .keep }
        let cutSegs = decisions.filter { $0.action == .cut || $0.action == .trimStart || $0.action == .trimEnd }
        let reviewSegs = decisions.filter { $0.requiresReview }
        var keepDuration: Double = 0
        for seg in keepSegs { keepDuration += seg.endTime - seg.startTime }
        var cutDuration: Double = 0
        for seg in cutSegs { cutDuration += seg.endTime - seg.startTime }
        let roughCut = RoughCutResult(
            decisions: decisions,
            originalDuration: keepDuration + cutDuration,
            cleanDuration: keepDuration,
            keepSegments: keepSegs,
            cutSegments: cutSegs,
            reviewSegments: reviewSegs
        )
        return QualityGateService.evaluate(
            captions: captions,
            editPlan: editPlan,
            roughCut: roughCut,
            template: template
        )
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

            Button {
                Task { await startExport() }
            } label: {
                Text("Start Export")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.white)
                    .foregroundStyle(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

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

            Text("Exporting...")
                .foregroundStyle(.gray)

            Button("Cancel") {
                exportService.cancelExport()
                dismiss()
            }
            .foregroundStyle(.red)
        }
    }

    private func completedView(url: URL) -> some View {
        VStack(spacing: 20) {
            Image(systemName: didSave ? "checkmark.seal.fill" : "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(didSave ? .green : .white)

            Text(didSave ? "Saved to Photos" : "Export Complete")
                .font(.title3)
                .foregroundStyle(.white)

            if let error = exportService.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if !didSave {
                Button {
                    Task {
                        didSave = await exportService.saveToPhotos(url: url)
                    }
                } label: {
                    Label("Save to Photos", systemImage: "photo.on.rectangle")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.white)
                        .foregroundStyle(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
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
            }

            Button("Done") { dismiss() }
                .foregroundStyle(.gray)
                .padding(.top, 8)
        }
    }

    private func startExport() async {
        // Update status to exporting
        let userId = authManager.currentUser?.id
        if userId != nil {
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
        didExport = true

        // Save export record to DB
        if let userId, let url = exportedURL {
            await saveExportRecord(userId: userId, fileURL: url)
        }
    }

    private func saveExportRecord(userId: UUID, fileURL: URL) async {
        let pipeline = PipelineRepository()
        do {
            let fileSize = try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int64
            try await pipeline.saveExport(
                projectId: projectId,
                userId: userId,
                localFileName: fileURL.lastPathComponent,
                duration: nil,
                resolution: "1080x1920",
                templateName: template?.name,
                fileSizeBytes: fileSize
            )
            try await pipeline.updateProjectStatus(projectId, status: .exported)
        } catch {
            print("[CutSense] DB save after export failed: \(error.localizedDescription)")
        }
    }
}
