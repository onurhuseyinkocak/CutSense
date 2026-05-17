import SwiftUI
import PhotosUI

struct VideoImportScreen: View {
    @Environment(AuthManager.self) private var authManager
    @State private var importService = VideoImportService()
    @State private var selectedItem: PhotosPickerItem?
    @State private var showAnalysis = false
    @State private var showResumedReview = false
    @State private var resumedVideoURL: URL?
    @State private var resumedRoughCut: RoughCutResult?
    @State private var resumedTranscription: TranscriptionResult?
    @State private var isLoadingResume = false

    let project: Project
    let onProjectUpdated: (Project) -> Void

    private var effectiveVideoURL: URL? {
        importService.importedVideoURL ?? resumedVideoURL
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if importService.isImporting {
                importingView
            } else if let url = effectiveVideoURL, let meta = importService.metadata {
                importedView(url: url, metadata: meta)
            } else if effectiveVideoURL != nil {
                // Has URL but metadata not yet loaded
                ProgressView("Loading video info...")
                    .tint(.white)
                    .foregroundStyle(.white)
            } else {
                pickerView
            }
        }
        .navigationTitle(project.title)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task {
            // If project already has a local video file cached, try to resume
            if project.status != .draft, let path = project.localProjectPath {
                let url = URL(fileURLWithPath: path)
                if FileManager.default.fileExists(atPath: path) {
                    resumedVideoURL = url
                    importService.metadata = await VideoMetadataService.extract(from: url)
                }
            }
        }
        .onChange(of: selectedItem) { _, newItem in
            guard let newItem else { return }
            Task {
                await importService.importVideo(from: newItem)
                // Update project status to imported and save local path
                if let url = importService.importedVideoURL {
                    let pipeline = PipelineRepository()
                    try? await pipeline.updateProjectStatus(project.id, status: .imported)
                    try? await pipeline.updateProjectLocalPath(projectId: project.id, path: url.path)
                }
            }
        }
        .navigationDestination(isPresented: $showAnalysis) {
            if let url = effectiveVideoURL {
                AnalysisScreen(videoURL: url, projectId: project.id)
            }
        }
        .navigationDestination(isPresented: $showResumedReview) {
            if let roughCut = resumedRoughCut,
               let transcript = resumedTranscription,
               let url = effectiveVideoURL {
                RoughCutReviewScreen(
                    roughCut: roughCut,
                    transcription: transcript,
                    videoURL: url,
                    projectId: project.id
                )
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

                // Resume for previously analyzed projects
                if canResume {
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Previously analyzed")
                                .font(.caption)
                                .foregroundStyle(.gray)
                        }

                        Button {
                            Task { await resumeProject() }
                        } label: {
                            HStack {
                                if isLoadingResume {
                                    ProgressView().tint(.black)
                                } else {
                                    Image(systemName: "play.fill")
                                }
                                Text("Continue to Review")
                            }
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.green)
                            .foregroundStyle(.black)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .disabled(isLoadingResume)
                    }
                    .padding(.horizontal, 24)
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

                    Button {
                        showAnalysis = true
                    } label: {
                        Text(project.status == .draft || project.status == .imported ? "Analyze" : "Re-Analyze")
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

    private var canResume: Bool {
        switch project.status {
        case .roughCutReady, .reviewed, .styling, .exported:
            return true
        default:
            return false
        }
    }

    private func resumeProject() async {
        isLoadingResume = true
        defer { isLoadingResume = false }
        let pipeline = PipelineRepository()
        do {
            let transcript = try await pipeline.fetchTranscript(projectId: project.id)
            let roughCut = try await pipeline.fetchRoughCutDecisions(projectId: project.id)
            guard let transcript, let roughCut else {
                // Data missing — fall back to re-analysis
                showAnalysis = true
                return
            }
            // Use project's original duration if available
            let finalRoughCut: RoughCutResult
            if let origDuration = project.originalDuration, origDuration > 0 {
                finalRoughCut = RoughCutResult(
                    decisions: roughCut.decisions,
                    originalDuration: origDuration,
                    cleanDuration: roughCut.cleanDuration,
                    keepSegments: roughCut.keepSegments,
                    cutSegments: roughCut.cutSegments,
                    reviewSegments: roughCut.reviewSegments
                )
            } else {
                finalRoughCut = roughCut
            }
            resumedRoughCut = finalRoughCut
            resumedTranscription = transcript
            showResumedReview = true
        } catch {
            // On error, fall back to re-analysis
            showAnalysis = true
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
