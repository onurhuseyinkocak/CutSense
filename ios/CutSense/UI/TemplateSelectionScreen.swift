import SwiftUI

struct TemplateSelectionScreen: View {
    let roughCut: RoughCutResult
    let transcription: TranscriptionResult
    let videoURL: URL
    let projectId: UUID
    @State private var selectedTemplate: TemplateConfig?
    @State private var showCaptionPreview = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    Text("Choose a Style")
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                        .padding(.top, 16)

                    ForEach(TemplateConfig.all, id: \.id) { template in
                        TemplateCard(
                            template: template,
                            isSelected: selectedTemplate?.id == template.id
                        ) {
                            selectedTemplate = template
                        }
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
    }
}

private struct TemplateCard: View {
    let template: TemplateConfig
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(template.name)
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text(template.description)
                            .font(.caption)
                            .foregroundStyle(.gray)
                    }
                    Spacer()
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
