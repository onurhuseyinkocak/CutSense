import SwiftUI
#if canImport(FoundationModels)
import FoundationModels
#endif

@MainActor
@Observable
final class AnalysisViewModel {
    var currentStep = 0
    var isAnalyzing = false
    var errorMessage: String?
    var audioResult: AudioAnalysisResult?
    var audioQualityReport: AudioQualityGuard.QualityReport?
    var transcriptionResult: TranscriptionResult?
    var roughCutResult: RoughCutResult?
    var cleanupResult: TranscriptCleanupAnalyzer.CleanupResult?
    var takeGroups: [TakeGroup] = []
    var continuityResult: ContinuityChecker.ContinuityResult?
    var meaningResult: MeaningPreservationEngine.PreservationResult?

    var usedSmartAnalysis = false

    // Re-analysis diff
    var previousDecisionSummary: DecisionSummary?
    var analysisDiff: AnalysisDiff?

    struct DecisionSummary: Sendable {
        let keepCount: Int
        let cutCount: Int
        let reviewCount: Int
        let totalSegments: Int
        let classificationMap: [String: String] // text -> action
    }

    struct AnalysisDiff: Sendable {
        let reclassifiedCount: Int
        let newKeepCount: Int
        let newCutCount: Int
        let previousKeepCount: Int
        let previousCutCount: Int
        let examples: [(text: String, oldAction: String, newAction: String)]
    }

    // Live classification state for streaming UI
    var liveClassifications: [(text: String, intent: String)] = []
    var classifiedCount = 0
    var totalSegmentsToClassify = 0

    let steps = [
        "Analyzing audio...",
        "Transcribing speech...",
        "Smart analysis...",
        "Detecting takes & edits...",
        "Building rough cut...",
        "Verifying coherence..."
    ]

    private let transcriptionService = SpeechTranscriptionService()

    func analyze(videoURL: URL, projectId: UUID, userId: UUID) async {
        isAnalyzing = true
        errorMessage = nil
        analysisDiff = nil
        defer { isAnalyzing = false }

        do {
            // Snapshot previous analysis for diff (if re-analyzing)
            await loadPreviousDecisions(projectId: projectId)

            // Update status to analyzing
            try? await PipelineRepository().updateProjectStatus(projectId, status: .analyzing)

            // Step 1: Audio analysis
            currentStep = 0
            audioResult = try await AudioAnalysisService.analyze(url: videoURL)

            // Run audio quality guard from analysis metadata
            if let audio = audioResult {
                // Approximate quality from analysis metadata
                let peakLinear = Float(audio.peakEnergy)
                let avgLinear = Float(audio.averageEnergy)
                let peakDB = peakLinear > 0 ? 20 * log10(peakLinear) : -Float.infinity
                let avgDB = avgLinear > 0 ? 20 * log10(avgLinear) : -Float.infinity
                let dynamicRange = peakDB - avgDB
                audioQualityReport = AudioQualityGuard.QualityReport(
                    peakDB: peakDB,
                    averageDB: avgDB,
                    isClipping: peakDB > -1.0,
                    isTooQuiet: avgDB < -30.0,
                    dynamicRange: dynamicRange,
                    passed: peakDB <= -1.0 && avgDB >= -30.0 && dynamicRange >= 6.0
                )
            }

            // Step 2: Transcription
            currentStep = 1
            transcriptionResult = try await transcriptionService.transcribe(url: videoURL)

            guard let audio = audioResult, var transcript = transcriptionResult else {
                errorMessage = "Analysis failed: missing audio or transcript data."
                return
            }

            // Step 3+4: Smart analysis (LLM on iOS 26+, heuristics fallback)
            currentStep = 2
            liveClassifications = []
            classifiedCount = 0
            totalSegmentsToClassify = transcript.segments.count

            // Fetch user's past AI feedback for few-shot learning
            let feedback = (try? await PipelineRepository().fetchRecentAiFeedback(userId: userId)) ?? []

            let smartResult = await SmartTranscriptAnalyzer.analyze(
                segments: transcript.segments,
                audioAnalysis: audio,
                userFeedback: feedback,
                onProgress: { [weak self] progress in
                    guard let self else { return }
                    self.classifiedCount = progress.classified
                    let displayText = String(progress.segmentText.prefix(40))
                    self.liveClassifications.append((text: displayText, intent: progress.intent))
                    // Keep only last 6 visible for compact UI
                    if self.liveClassifications.count > 6 {
                        self.liveClassifications.removeFirst()
                    }
                }
            )
            usedSmartAnalysis = true
            cleanupResult = TranscriptCleanupAnalyzer.CleanupResult(
                segments: smartResult.cleanedSegments,
                fillersRemoved: smartResult.fillersRemoved,
                restartsDetected: smartResult.restartsDetected,
                duplicatesDetected: smartResult.duplicatesDetected
            )
            transcript = TranscriptionResult(
                fullText: transcript.fullText,
                segments: smartResult.cleanedSegments,
                language: transcript.language,
                overallConfidence: transcript.overallConfidence
            )
            transcriptionResult = transcript

            currentStep = 3
            takeGroups = smartResult.takeGroups

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

            // Compute diff if re-analyzing
            if let prev = previousDecisionSummary, let roughCut = roughCutResult {
                analysisDiff = computeDiff(previous: prev, newDecisions: roughCut.decisions)
            }

            // Save all analysis data to DB
            await saveAnalysisData(projectId: projectId, userId: userId)
        } catch {
            errorMessage = error.localizedDescription
            try? await PipelineRepository().updateProjectStatus(projectId, status: .failed)
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
            #if DEBUG
            print("[CutSense] DB save after analysis failed: \(error.localizedDescription)")
            #endif
        }
    }

    // MARK: - Re-analysis Diff

    private func loadPreviousDecisions(projectId: UUID) async {
        do {
            guard let oldResult = try await PipelineRepository().fetchRoughCutDecisions(projectId: projectId) else {
                previousDecisionSummary = nil
                return
            }
            var classMap: [String: String] = [:]
            for d in oldResult.decisions {
                if let text = d.linkedTranscriptText {
                    classMap[text] = d.action.rawValue
                }
            }
            previousDecisionSummary = DecisionSummary(
                keepCount: oldResult.keepSegments.count,
                cutCount: oldResult.cutSegments.count,
                reviewCount: oldResult.reviewSegments.count,
                totalSegments: oldResult.decisions.count,
                classificationMap: classMap
            )
        } catch {
            previousDecisionSummary = nil
        }
    }

    private func computeDiff(previous: DecisionSummary, newDecisions: [RoughCutDecision]) -> AnalysisDiff {
        var reclassified = 0
        var examples: [(text: String, oldAction: String, newAction: String)] = []

        for decision in newDecisions {
            guard let text = decision.linkedTranscriptText,
                  let oldAction = previous.classificationMap[text] else { continue }
            let newAction = decision.action.rawValue
            if oldAction != newAction {
                reclassified += 1
                if examples.count < 3 {
                    examples.append((text: String(text.prefix(50)), oldAction: oldAction, newAction: newAction))
                }
            }
        }

        let newKeep = newDecisions.filter { $0.action == .keep }.count
        let newCut = newDecisions.filter { $0.action == .cut || $0.action == .trimStart || $0.action == .trimEnd }.count

        return AnalysisDiff(
            reclassifiedCount: reclassified,
            newKeepCount: newKeep,
            newCutCount: newCut,
            previousKeepCount: previous.keepCount,
            previousCutCount: previous.cutCount,
            examples: examples
        )
    }
}

struct AnalysisScreen: View {
    let videoURL: URL
    let projectId: UUID
    @Environment(AuthManager.self) private var authManager
    @State private var viewModel = AnalysisViewModel()
    @State private var showRoughCut = false
    @State private var didPrewarm = false

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
        .task {
            // Prewarm on-device LLM for faster first response
            if !didPrewarm {
                didPrewarm = true
                #if canImport(FoundationModels)
                if #available(iOS 26, *) {
                    Task.detached { @Sendable in
                        let session = FoundationModels.LanguageModelSession()
                        await session.prewarm()
                    }
                }
                #endif
            }
            // Auto-start analysis when screen appears (user already tapped Analyze)
            guard viewModel.roughCutResult == nil && !viewModel.isAnalyzing && viewModel.errorMessage == nil else { return }
            guard let userId = authManager.currentUser?.id else { return }
            await viewModel.analyze(videoURL: videoURL, projectId: projectId, userId: userId)
        }
        .onChange(of: viewModel.roughCutResult != nil) { _, isDone in
            if isDone {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }
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

            // Live classification feed during smart analysis
            if viewModel.currentStep == 2 && !viewModel.liveClassifications.isEmpty {
                liveClassificationView
            }

            Spacer()
        }
    }

    private var liveClassificationView: some View {
        VStack(spacing: 8) {
            if viewModel.totalSegmentsToClassify > 0 {
                Text("\(viewModel.classifiedCount)/\(viewModel.totalSegmentsToClassify) segments")
                    .font(.caption)
                    .foregroundStyle(.gray)
            }

            VStack(spacing: 4) {
                ForEach(Array(viewModel.liveClassifications.enumerated()), id: \.offset) { index, item in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(intentColor(item.intent))
                            .frame(width: 8, height: 8)

                        Text(item.text)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.8))
                            .lineLimit(1)

                        Spacer()

                        Text(item.intent)
                            .font(.caption2)
                            .foregroundStyle(intentColor(item.intent))
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: viewModel.liveClassifications.count)
        }
        .padding(.horizontal, 40)
        .padding(.top, 8)
    }

    private func intentColor(_ intent: String) -> Color {
        switch intent {
        case "content": .green
        case "filler", "editCommand": .red
        case "restart": .yellow
        case "duplicate": .orange
        default: .gray
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
                if let aq = viewModel.audioQualityReport {
                    statRow("Audio quality", value: aq.passed ? "Good" : (aq.isClipping ? "Clipping!" : "Weak"))
                }
                if let meaning = viewModel.meaningResult {
                    statRow("Coherence", value: "\(Int(meaning.overallScore))%")
                }
                if viewModel.usedSmartAnalysis {
                    statRow("Analysis", value: "On-device AI")
                }
                if let continuity = viewModel.continuityResult {
                    statRow("Continuity", value: "\(Int(continuity.overallScore))%")
                }
            }
            .padding(.horizontal, 40)

            // Re-analysis diff
            if let diff = viewModel.analysisDiff, diff.reclassifiedCount > 0 {
                diffSection(diff)
            }

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

    private func diffSection(_ diff: AnalysisViewModel.AnalysisDiff) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "brain.head.profile")
                    .foregroundStyle(.cyan)
                Text("AI learned from your feedback")
                    .font(.caption.bold())
                    .foregroundStyle(.cyan)
            }

            Text("\(diff.reclassifiedCount) segment\(diff.reclassifiedCount == 1 ? "" : "s") reclassified")
                .font(.caption)
                .foregroundStyle(.white)

            if diff.newKeepCount != diff.previousKeepCount {
                let delta = diff.newKeepCount - diff.previousKeepCount
                Text("Keep: \(diff.previousKeepCount) → \(diff.newKeepCount) (\(delta > 0 ? "+" : "")\(delta))")
                    .font(.caption2)
                    .foregroundStyle(.gray)
            }

            ForEach(Array(diff.examples.enumerated()), id: \.offset) { _, ex in
                HStack(spacing: 4) {
                    Text("\"\(ex.text)\"")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                    Spacer()
                    Text(ex.oldAction)
                        .font(.caption2)
                        .foregroundStyle(.red)
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundStyle(.gray)
                    Text(ex.newAction)
                        .font(.caption2)
                        .foregroundStyle(.green)
                }
            }
        }
        .padding()
        .background(Color.cyan.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 24)
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
