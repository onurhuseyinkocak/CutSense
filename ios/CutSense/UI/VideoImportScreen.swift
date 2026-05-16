import SwiftUI
import PhotosUI

struct VideoImportScreen: View {
    @Environment(AuthManager.self) private var authManager
    @State private var importService = VideoImportService()
    @State private var exportService = ExportService()
    @State private var selectedItem: PhotosPickerItem?
    @State private var showExport = false
    @State private var showAnalysis = false

    let project: Project
    let onProjectUpdated: (Project) -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if importService.isImporting {
                importingView
            } else if let url = importService.importedVideoURL, let meta = importService.metadata {
                importedView(url: url, metadata: meta)
            } else {
                pickerView
            }
        }
        .navigationTitle(project.title)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onChange(of: selectedItem) { _, newItem in
            guard let newItem else { return }
            Task {
                await importService.importVideo(from: newItem)
            }
        }
        .sheet(isPresented: $showExport) {
            if let url = importService.importedVideoURL {
                ExportScreen(sourceURL: url, exportService: exportService)
            }
        }
    }

    private var importingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(.white)
            Text("Importing video...")
                .foregroundStyle(.gray)
        }
    }

    private var pickerView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "video.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(.gray)

            Text("Select a video to edit")
                .font(.title3)
                .foregroundStyle(.gray)

            PhotosPicker(selection: $selectedItem, matching: .videos) {
                Label("Choose Video", systemImage: "photo.on.rectangle")
                    .fontWeight(.semibold)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(.white)
                    .foregroundStyle(.black)
                    .clipShape(Capsule())
            }

            if let error = importService.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Spacer()
        }
    }

    private func importedView(url: URL, metadata: VideoMetadata) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                // Video preview
                VideoPlayerView(url: url)
                    .frame(height: 400)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)

                // Metadata
                VStack(spacing: 12) {
                    metadataRow("Duration", value: metadata.formattedDuration)
                    metadataRow("Resolution", value: metadata.formattedResolution)
                    metadataRow("Frame Rate", value: "\(Int(metadata.frameRate)) fps")
                    metadataRow("File Size", value: metadata.formattedFileSize)
                    metadataRow("Orientation", value: metadata.orientation.rawValue.capitalized)
                    metadataRow("Audio", value: metadata.hasAudio ? "Yes" : "No")
                }
                .padding(.horizontal, 24)

                if !metadata.isSupported {
                    Text("Video must be under 5 minutes.")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }

                // Actions
                HStack(spacing: 16) {
                    PhotosPicker(selection: $selectedItem, matching: .videos) {
                        Text("Change")
                            .fontWeight(.medium)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.white.opacity(0.08))
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    NavigationLink {
                        if let videoURL = importService.importedVideoURL {
                            AnalysisScreen(videoURL: videoURL)
                        }
                    } label: {
                        Text("Analyze")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(metadata.isSupported && metadata.hasAudio ? .white : .gray)
                            .foregroundStyle(.black)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(!metadata.isSupported || !metadata.hasAudio)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
        }
    }

    private func metadataRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.gray)
            Spacer()
            Text(value)
                .foregroundStyle(.white)
                .fontWeight(.medium)
        }
    }
}
