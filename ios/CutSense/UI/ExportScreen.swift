import SwiftUI

struct ExportScreen: View {
    let sourceURL: URL
    let decisions: [RoughCutDecision]?
    let captions: [CaptionSegment]?
    let template: TemplateConfig?
    @Bindable var exportService: ExportService
    @Environment(\.dismiss) private var dismiss
    @State private var didExport = false
    @State private var didSave = false

    init(
        sourceURL: URL,
        exportService: ExportService,
        decisions: [RoughCutDecision]? = nil,
        captions: [CaptionSegment]? = nil,
        template: TemplateConfig? = nil
    ) {
        self.sourceURL = sourceURL
        self.exportService = exportService
        self.decisions = decisions
        self.captions = captions
        self.template = template
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

    private var readyView: some View {
        VStack(spacing: 20) {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 48))
                .foregroundStyle(.gray)

            Text(hasPipeline ? "Export Edited Video" : "Export 1080x1920 MP4")
                .font(.title3)
                .foregroundStyle(.white)

            if hasPipeline {
                Text("Captions + edits will be burned in")
                    .font(.caption)
                    .foregroundStyle(.gray)
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
        if let decisions, let captions, let template {
            await exportService.exportWithPipeline(
                sourceURL: sourceURL,
                decisions: decisions,
                captions: captions,
                template: template
            )
        } else {
            await exportService.exportNormalized(from: sourceURL)
        }
        didExport = true
    }
}
