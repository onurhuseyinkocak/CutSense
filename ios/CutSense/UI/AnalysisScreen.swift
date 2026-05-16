import SwiftUI

@MainActor
@Observable
final class AnalysisViewModel {
    var currentStep = 0
    var isAnalyzing = false
    var errorMessage: String?
    var audioResult: AudioAnalysisResult?
    var transcriptionResult: TranscriptionResult?
    var roughCutResult: RoughCutResult?
    var cleanupResult: TranscriptCleanupAnalyzer.CleanupResult?
    var takeGroups: [TakeGroup] = []
    var continuityResult: ContinuityChecker.ContinuityResult?
    var meaningResult: MeaningPreservationEngine.PreservationResult?

    let steps = [
        "Analyzing audio...",
        "Transcribing speech...",
        "Cleaning transcript...",
        "Detecting takes & edits...",
        "Building rough cut...",
        "Verifying coherence..."
    ]

    private let transcriptionService = SpeechTranscriptionService()

    func analyze(videoURL: URL, projectId: UUID, userId: UUID) async {
        isAnalyzing = true
        errorMessage = nil
        defer { isAnalyzing = false }

        do {
            // Update status to analyzing
            try? await PipelineRepository().updateProjectStatus(projectId, status: .analyzing)

            // Step 1: Audio analysis
            currentStep = 0
            audioResult = try await AudioAnalysisService.analyze(url: videoURL)

            // Step 2: Transcription
            currentStep = 1
            transcriptionResult = try await transcriptionService.transcribe(url: videoURL)

            guard let audio = audioResult, var transcript = transcriptionResult else {
                errorMessage = "Analysis failed: missing audio or transcript data."
                return
            }

            // Step 3: Cleanup (fillers, restarts, duplicates)
            currentStep = 2
            let cleanup = TranscriptCleanupAnalyzer.analyze(transcript.segments)
            cleanupResult = cleanup
            transcript = TranscriptionResult(
                fullText: transcript.fullText,
                segments: cleanup.segments,
                language: transcript.language,
                overallConfidence: transcript.overallConfidence
            )
            transcriptionResult = transcript

            // Step 4: Take detection + edit commands
            currentStep = 3
            takeGroups = TakeDetectionEngine.detectTakeGroups(segments: transcript.segments)

            // Step 5: Rough cut decisions
            currentStep = 4
            var roughCut = RoughCutDecisionEngine.generateDecisions(
                transcription: transcript,
                audioAnalysis: audio
            )

            // Apply take group results — cut non-best takes
            if !takeGroups.isEmpty {
                roughCut = RoughCutDecisionEngine.applyTakeGroups(takeGroups, to: roughCut)
            }
            roughCutResult = roughCut

            // Step 6: Verify coherence
            currentStep = 5
            if let roughCut = roughCutResult {
                let keptTexts = roughCut.keepSegments.compactMap { decision -> TranscriptSegment? in
                    transcript.segments.first { seg in
                        abs(seg.startTime - decision.startTime) < 0.1
                    }
                }

                meaningResult = MeaningPreservationEngine.verify(
                    keptSegments: keptTexts,
                    allSegments: transcript.segments
                )

                continuityResult = ContinuityChecker.check(
                    keptDecisions: roughCut.keepSegments
                )
            }

            // Save all analysis data to DB
            await saveAnalysisData(projectId: projectId, userId: userId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveAnalysisData(projectId: UUID, userId: UUID) async {
        let pipeline = PipelineRepository()

        do {
            guard let transcript = transcriptionResult else { return }

            // Delete old analysis data to prevent duplicates on re-analysis
            try await pipeline.deleteAnalysisData(projectId: projectId)

            // Save transcript
            let transcriptId = try await pipeline.saveTranscript(
                projectId: projectId,
                userId: userId,
                transcription: transcript
            )

            // Save transcript segments
            try await pipeline.saveTranscriptSegments(
                transcriptId: transcriptId,
                projectId: projectId,
                userId: userId,
                segments: transcript.segments
            )

            // Save rough cut decisions
            if let roughCut = roughCutResult {
                try await pipeline.saveRoughCutDecisions(
                    projectId: projectId,
                    userId: userId,
                    decisions: roughCut.decisions
                )

                // Update project durations
                try await pipeline.updateProjectDurations(
                    projectId: projectId,
                    originalDuration: roughCut.originalDuration,
                    finalDuration: roughCut.cleanDuration
                )
            }

            // Save take groups
            if !takeGroups.isEmpty {
                try await pipeline.saveTakeGroups(
                    projectId: projectId,
                    userId: userId,
                    takeGroups: takeGroups
                )
            }

            // Update project status
            try await pipeline.updateProjectStatus(projectId, status: .roughCutReady)
        } catch {
            print("[CutSense] DB save after analysis failed: \(error.localizedDescription)")
        }
    }
}

struct AnalysisScreen: View {
    let videoURL: URL
    let projectId: UUID
    @Environment(AuthManager.self) private var authManager
    @State private var viewModel = AnalysisViewModel()
    @State private var showRoughCut = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if viewModel.isAnalyzing {
                analysisProgressView
            } else if let result = viewModel.roughCutResult {
                analysisDoneView(result)
            } else if let error = viewModel.errorMessage {
                errorView(error)
            } else {
                startView
            }
        }
        .navigationTitle("Analysis")
        .toolbarColorScheme(.dark, for: .navigationBar)
        .navigationDestination(isPresented: $showRoughCut) {
            if let result = viewModel.roughCutResult,
               let transcript = viewModel.transcriptionResult {
                RoughCutReviewScreen(
                    roughCut: result,
                    transcription: transcript,
                    videoURL: videoURL,
                    projectId: projectId
                )
            }
        }
    }

    private var startView: some View {
        VStack(spacing: 20) {
            Image(systemName: "waveform.badge.magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.gray)

            Text("Ready to analyze")
                .font(.title3)
                .foregroundStyle(.white)

            Button {
                guard let userId = authManager.currentUser?.id else { return }
                Task { await viewModel.analyze(videoURL: videoURL, projectId: projectId, userId: userId) }
            } label: {
                Text("Start Analysis")
                    .fontWeight(.semibold)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 14)
                    .background(.white)
                    .foregroundStyle(.black)
                    .clipShape(Capsule())
            }
        }
    }

    private var analysisProgressView: some View {
        VStack(spacing: 24) {
            Spacer()

            ProgressView()
                .tint(.white)
                .scaleEffect(1.2)

            VStack(spacing: 12) {
                ForEach(Array(viewModel.steps.enumerated()), id: \.offset) { index, step in
                    HStack(spacing: 12) {
                        if index < viewModel.currentStep {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else if index == viewModel.currentStep {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "circle")
                                .foregroundStyle(.gray.opacity(0.4))
                        }

                        Text(step)
                            .foregroundStyle(index <= viewModel.currentStep ? .white : .gray.opacity(0.4))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 40)

            Spacer()
        }
    }

    private func analysisDoneView(_ result: RoughCutResult) -> some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text("Analysis Complete")
                .font(.title3)
                .foregroundStyle(.white)

            VStack(spacing: 8) {
                statRow("Original", value: formatDuration(result.originalDuration))
                statRow("Clean cut", value: formatDuration(result.cleanDuration))
                statRow("Segments kept", value: "\(result.keepSegments.count)")
                statRow("Segments cut", value: "\(result.cutSegments.count)")
                statRow("Needs review", value: "\(result.reviewSegments.count)")
                if let cleanup = viewModel.cleanupResult {
                    statRow("Fillers removed", value: "\(cleanup.fillersRemoved)")
                    statRow("Restarts found", value: "\(cleanup.restartsDetected)")
                }
                if !viewModel.takeGroups.isEmpty {
                    statRow("Take groups", value: "\(viewModel.takeGroups.count)")
                }
                if let meaning = viewModel.meaningResult {
                    statRow("Coherence", value: "\(Int(meaning.overallScore))%")
                }
                if let continuity = viewModel.continuityResult {
                    statRow("Continuity", value: "\(Int(continuity.overallScore))%")
                }
            }
            .padding(.horizontal, 40)

            Button {
                showRoughCut = true
            } label: {
                Text("Review Rough Cut")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.white)
                    .foregroundStyle(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 24)

            Spacer()
        }
    }

    private func errorView(_ error: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.red)

            Text(error)
                .foregroundStyle(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button("Retry") {
                guard let userId = authManager.currentUser?.id else { return }
                Task { await viewModel.analyze(videoURL: videoURL, projectId: projectId, userId: userId) }
            }
            .foregroundStyle(.white)
        }
    }

    private func statRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.gray)
            Spacer()
            Text(value).foregroundStyle(.white).fontWeight(.medium)
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
