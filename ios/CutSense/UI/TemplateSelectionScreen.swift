import SwiftUI
import UniformTypeIdentifiers

struct TemplateSelectionScreen: View {
    let roughCut: RoughCutResult
    let transcription: TranscriptionResult
    let videoURL: URL
    let projectId: UUID
    @State private var selectedTemplate: TemplateConfig?
    @State private var showCaptionPreview = false
    @State private var showBuilder = false
    @State private var editingTemplate: TemplateConfig?
    @State private var showImporter = false
    @State private var importMessage: String?
    @State private var shareURL: URL?
    @State private var showShareSheet = false
    @State private var showHub = false
    @State private var uploadingTemplate: TemplateConfig?
    @State private var showUploadConfirm = false
    private var allTemplates: [TemplateConfig] {
        TemplateConfig.all + CustomTemplateStore.shared.templates
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    Text("Choose a Style")
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                        .padding(.top, 16)

                    ForEach(allTemplates, id: \.id) { template in
                        TemplateCard(
                            template: template,
                            isSelected: selectedTemplate?.id == template.id,
                            isCustom: template.id.hasPrefix("custom_"),
                            onSelect: { selectedTemplate = template },
                            onEdit: {
                                editingTemplate = template
                                showBuilder = true
                            },
                            onDelete: {
                                CustomTemplateStore.shared.delete(template.id)
                                if selectedTemplate?.id == template.id {
                                    selectedTemplate = nil
                                }
                            },
                            onShare: {
                                if let url = CustomTemplateStore.shared.exportFile([template]) {
                                    shareURL = url
                                    showShareSheet = true
                                }
                            },
                            onUpload: {
                                uploadingTemplate = template
                                showUploadConfirm = true
                            }
                        )
                    }

                    HStack(spacing: 12) {
                        Button {
                            editingTemplate = nil
                            showBuilder = true
                        } label: {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                Text("Create")
                            }
                            .font(.subheadline.bold())
                            .foregroundStyle(.white.opacity(0.7))
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.white.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6]))
                                    .foregroundStyle(.white.opacity(0.2))
                            )
                        }
                        .buttonStyle(.plain)

                        Button {
                            showImporter = true
                        } label: {
                            HStack {
                                Image(systemName: "square.and.arrow.down")
                                Text("Import")
                            }
                            .font(.subheadline.bold())
                            .foregroundStyle(.white.opacity(0.7))
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.white.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6]))
                                    .foregroundStyle(.white.opacity(0.2))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal)

                    Button { showHub = true } label: {
                        HStack {
                            Image(systemName: "globe")
                            Text("Community Hub")
                        }
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            LinearGradient(colors: [.purple.opacity(0.3), .blue.opacity(0.3)], startPoint: .leading, endPoint: .trailing)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal)

                    if let msg = importMessage {
                        Text(msg)
                            .font(.caption)
                            .foregroundStyle(.green)
                            .transition(.opacity)
                    }

                    if let selected = selectedTemplate {
                        Button {
                            showCaptionPreview = true
                        } label: {
                            Text("Apply \(selected.name)")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(.white)
                                .foregroundStyle(.black)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .padding(.horizontal, 24)
                    }
                }
                .padding(.bottom, 32)
            }
        }
        .navigationTitle("Template")
        .toolbarColorScheme(.dark, for: .navigationBar)
        .navigationDestination(isPresented: $showCaptionPreview) {
            if let template = selectedTemplate {
                CaptionPreviewScreen(
                    roughCut: roughCut,
                    transcription: transcription,
                    template: template,
                    videoURL: videoURL,
                    projectId: projectId
                )
            }
        }
        .navigationDestination(isPresented: $showHub) {
            TemplateHubScreen()
        }
        .navigationDestination(isPresented: $showBuilder) {
            CustomTemplateBuilderScreen(existing: editingTemplate) { template in
                CustomTemplateStore.shared.save(template)
                selectedTemplate = template
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.cutsenseTemplate, .json],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            let count = CustomTemplateStore.shared.importFile(at: url)
            if count > 0 {
                importMessage = "Imported \(count) template\(count == 1 ? "" : "s")"
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    importMessage = nil
                }
            } else {
                importMessage = "No valid templates found"
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    importMessage = nil
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = shareURL {
                ShareSheet(items: [url])
            }
        }
        .alert("Share to Community", isPresented: $showUploadConfirm) {
            Button("Upload") {
                guard let template = uploadingTemplate else { return }
                Task {
                    guard let userId = try? await supabase.auth.session.user.id else {
                        importMessage = "Sign in to share templates"
                        return
                    }
                    let hub = TemplateHubService()
                    let user = try? await supabase.auth.session.user
                    let displayName = user?.email?.components(separatedBy: "@").first
                    let success = await hub.upload(
                        template: template,
                        authorName: displayName ?? "Anonymous",
                        userId: userId
                    )
                    importMessage = success ? "Uploaded to Community Hub!" : (hub.errorMessage ?? "Upload failed")
                    Task {
                        try? await Task.sleep(for: .seconds(3))
                        importMessage = nil
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let t = uploadingTemplate {
                Text("Share \"\(t.name)\" with the CutSense community? Others will be able to download and use it.")
            }
        }
    }
}

// MARK: - ShareSheet

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

private struct TemplateCard: View {
    let template: TemplateConfig
    let isSelected: Bool
    var isCustom = false
    let onSelect: () -> Void
    var onEdit: (() -> Void)?
    var onDelete: (() -> Void)?
    var onShare: (() -> Void)?
    var onUpload: (() -> Void)?

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(template.name)
                                .font(.headline)
                                .foregroundStyle(.white)
                            if isCustom {
                                Text("Custom")
                                    .font(.system(size: 9).bold())
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.2))
                                    .foregroundStyle(.blue)
                                    .clipShape(Capsule())
                            }
                        }
                        Text(template.description)
                            .font(.caption)
                            .foregroundStyle(.gray)
                    }
                    Spacer()
                    if isCustom {
                        HStack(spacing: 8) {
                            Button { onUpload?() } label: {
                                Image(systemName: "globe")
                                    .font(.caption)
                                    .foregroundStyle(.purple.opacity(0.8))
                            }
                            Button { onShare?() } label: {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.caption)
                                    .foregroundStyle(.gray)
                            }
                            Button { onEdit?() } label: {
                                Image(systemName: "pencil")
                                    .font(.caption)
                                    .foregroundStyle(.gray)
                            }
                            Button { onDelete?() } label: {
                                Image(systemName: "trash")
                                    .font(.caption)
                                    .foregroundStyle(.red.opacity(0.7))
                            }
                        }
                    }
                    intensityBadge
                }

                HStack(spacing: 12) {
                    stylePill(template.hookStyle.displayName, role: "Hook")
                    stylePill(template.defaultStyle.displayName, role: "Default")
                    stylePill(template.emphasisStyle.displayName, role: "Emphasis")
                }
            }
            .padding()
            .background(isSelected ? Color.white.opacity(0.08) : Color.white.opacity(0.03))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.white : Color.clear, lineWidth: 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
    }

    private var intensityBadge: some View {
        Text(template.intensity.displayName)
            .font(.caption2.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(intensityColor.opacity(0.15))
            .foregroundStyle(intensityColor)
            .clipShape(Capsule())
    }

    private var intensityColor: Color {
        switch template.intensity {
        case .low: .green
        case .medium: .yellow
        case .high: .orange
        }
    }

    private func stylePill(_ name: String, role: String) -> some View {
        VStack(spacing: 2) {
            Text(role)
                .font(.system(size: 9))
                .foregroundStyle(.gray)
            Text(name)
                .font(.caption2)
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
