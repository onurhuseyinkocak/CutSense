import SwiftUI

struct RoughCutReviewScreen: View {
    @State var roughCut: RoughCutResult
    let transcription: TranscriptionResult
    let videoURL: URL
    let projectId: UUID
    @State private var showTemplateSelection = false
    @State private var undoStack: [RoughCutResult] = []
    @State private var redoStack: [RoughCutResult] = []
    @State private var filter: DecisionFilter = .all
    @Environment(AuthManager.self) private var authManager

    private enum DecisionFilter: String, CaseIterable {
        case all = "All"
        case keep = "Keep"
        case cut = "Cut"
        case review = "Review"
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    // Video preview
                    RoughCutPreviewPlayer(
                        videoURL: videoURL,
                        decisions: roughCut.decisions
                    )
                    .padding(.top, 8)

                    // Summary header
                    summaryCard

                    // Filter tabs
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(DecisionFilter.allCases, id: \.self) { f in
                                let count = countForFilter(f)
                                Button {
                                    filter = f
                                } label: {
                                    Text("\(f.rawValue) (\(count))")
                                        .font(.caption.bold())
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(filter == f ? Color.white : Color.white.opacity(0.08))
                                        .foregroundStyle(filter == f ? .black : .white)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                        .padding(.horizontal)
                    }

                    // Decision list
                    VStack(spacing: 1) {
                        ForEach(Array(roughCut.decisions.enumerated()), id: \.element.id) { index, decision in
                            if matchesFilter(decision) {
                                DecisionRow(
                                    decision: decision,
                                    onRestore: {
                                        restoreSegment(at: index)
                                    },
                                    onCut: {
                                        cutSegment(at: index)
                                    }
                                )
                            }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)

                    // Bulk actions for review items
                    if !roughCut.reviewSegments.isEmpty {
                        VStack(spacing: 8) {
                            Text("\(roughCut.reviewSegments.count) items need review")
                                .font(.caption)
                                .foregroundStyle(.yellow)

                            HStack(spacing: 12) {
                                Button {
                                    bulkAction(.keepAll)
                                } label: {
                                    Label("Keep All", systemImage: "checkmark")
                                        .font(.caption.bold())
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(Color.green.opacity(0.15))
                                        .foregroundStyle(.green)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }

                                Button {
                                    bulkAction(.cutAll)
                                } label: {
                                    Label("Cut All", systemImage: "scissors")
                                        .font(.caption.bold())
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(Color.red.opacity(0.15))
                                        .foregroundStyle(.red)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                            }
                        }
                        .padding()
                        .background(Color.yellow.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)
                    }

                    // Actions
                    VStack(spacing: 12) {
                        Button {
                            showTemplateSelection = true
                            Task {
                                let pipeline = PipelineRepository()
                                if let userId = authManager.effectiveUserId {
                                    try? await pipeline.deleteRoughCutDecisions(projectId: projectId)
                                    try? await pipeline.saveRoughCutDecisions(
                                        projectId: projectId,
                                        userId: userId,
                                        decisions: roughCut.decisions
                                    )
                                }
                                try? await pipeline.updateProjectStatus(projectId, status: .reviewed)
                            }
                        } label: {
                            Text("Choose Template")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(.white)
                                .foregroundStyle(.black)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
                }
            }
        }
        .navigationTitle("Rough Cut Review")
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    undo()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .disabled(undoStack.isEmpty)

                Button {
                    redo()
                } label: {
                    Image(systemName: "arrow.uturn.forward")
                }
                .disabled(redoStack.isEmpty)
            }
        }
        .navigationDestination(isPresented: $showTemplateSelection) {
            TemplateSelectionScreen(
                roughCut: roughCut,
                transcription: transcription,
                videoURL: videoURL,
                projectId: projectId
            )
        }
    }

    private var summaryCard: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Original")
                        .font(.caption)
                        .foregroundStyle(.gray)
                    Text(formatDuration(roughCut.originalDuration))
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                }
                Spacer()
                Image(systemName: "arrow.right")
                    .foregroundStyle(.gray)
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Clean")
                        .font(.caption)
                        .foregroundStyle(.gray)
                    Text(formatDuration(roughCut.cleanDuration))
                        .font(.title2.bold())
                        .foregroundStyle(.green)
                }
            }

            HStack(spacing: 16) {
                badge("\(roughCut.keepSegments.count) kept", color: .green)
                badge("\(roughCut.cutSegments.count) cut", color: .red)
                if !roughCut.reviewSegments.isEmpty {
                    badge("\(roughCut.reviewSegments.count) review", color: .yellow)
                }
            }
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private func matchesFilter(_ decision: RoughCutDecision) -> Bool {
        switch filter {
        case .all: true
        case .keep: decision.action == .keep
        case .cut: decision.action == .cut || decision.action == .trimStart || decision.action == .trimEnd
        case .review: decision.requiresReview
        }
    }

    private func countForFilter(_ f: DecisionFilter) -> Int {
        switch f {
        case .all: roughCut.decisions.count
        case .keep: roughCut.keepSegments.count
        case .cut: roughCut.cutSegments.count
        case .review: roughCut.reviewSegments.count
        }
    }

    private enum BulkReviewAction {
        case keepAll, cutAll
    }

    private func bulkAction(_ action: BulkReviewAction) {
        pushUndo()
        var updated = roughCut.decisions
        for (index, decision) in updated.enumerated() {
            guard decision.requiresReview else { continue }
            let newAction: CutAction = action == .keepAll ? .keep : .cut
            let reason = action == .keepAll ? "Kept by user (bulk)" : "Cut by user (bulk)"
            updated[index] = RoughCutDecision(
                startTime: decision.startTime,
                endTime: decision.endTime,
                action: newAction,
                reason: reason,
                confidence: 1.0,
                linkedTranscriptText: decision.linkedTranscriptText,
                requiresReview: false
            )
        }
        roughCut = recalculate(updated)
    }

    private func pushUndo() {
        undoStack.append(roughCut)
        redoStack.removeAll()
    }

    private func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(roughCut)
        roughCut = previous
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(roughCut)
        roughCut = next
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func restoreSegment(at index: Int) {
        guard index < roughCut.decisions.count else { return }
        pushUndo()
        let old = roughCut.decisions[index]
        saveFeedback(old, userAction: "keep")
        let restored = RoughCutDecision(
            startTime: old.startTime,
            endTime: old.endTime,
            action: .keep,
            reason: "Restored by user",
            confidence: 1.0,
            linkedTranscriptText: old.linkedTranscriptText,
            requiresReview: false
        )
        var updated = roughCut.decisions
        updated[index] = restored
        roughCut = recalculate(updated)
    }

    private func cutSegment(at index: Int) {
        guard index < roughCut.decisions.count else { return }
        pushUndo()
        let old = roughCut.decisions[index]
        saveFeedback(old, userAction: "cut")
        let cut = RoughCutDecision(
            startTime: old.startTime,
            endTime: old.endTime,
            action: .cut,
            reason: "Cut by user",
            confidence: 1.0,
            linkedTranscriptText: old.linkedTranscriptText,
            requiresReview: false
        )
        var updated = roughCut.decisions
        updated[index] = cut
        roughCut = recalculate(updated)
    }

    private func saveFeedback(_ decision: RoughCutDecision, userAction: String) {
        guard let userId = authManager.effectiveUserId,
              let text = decision.linkedTranscriptText else { return }
        Task {
            try? await PipelineRepository().saveAiFeedback(
                userId: userId,
                segmentText: text,
                aiClassification: decision.action.rawValue,
                aiConfidence: Double(decision.confidence),
                aiReason: decision.reason,
                userAction: userAction,
                language: transcription.language
            )
        }
    }

    private func recalculate(_ decisions: [RoughCutDecision]) -> RoughCutResult {
        let keepSegments = decisions.filter { $0.action == .keep }
        let cleanDuration = keepSegments.reduce(0.0) { $0 + ($1.endTime - $1.startTime) }

        return RoughCutResult(
            decisions: decisions,
            originalDuration: roughCut.originalDuration,
            cleanDuration: cleanDuration,
            keepSegments: keepSegments,
            cutSegments: decisions.filter { $0.action == .cut || $0.action == .trimStart || $0.action == .trimEnd },
            reviewSegments: decisions.filter { $0.requiresReview }
        )
    }

    private func formatDuration(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

private struct DecisionRow: View {
    let decision: RoughCutDecision
    let onRestore: () -> Void
    let onCut: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                actionBadge
                Spacer()
                Text("\(formatTime(decision.startTime)) - \(formatTime(decision.endTime))")
                    .font(.caption.monospaced())
                    .foregroundStyle(.gray)
            }

            if let text = decision.linkedTranscriptText {
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(decision.action == .cut ? .gray : .white)
                    .strikethrough(decision.action == .cut)
            }

            HStack(spacing: 6) {
                Text(decision.reason)
                    .font(.caption2)
                    .foregroundStyle(.gray.opacity(0.7))

                if decision.requiresReview {
                    Text("\(Int(decision.confidence * 100))%")
                        .font(.caption2.bold())
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(confidenceBadgeColor.opacity(0.15))
                        .foregroundStyle(confidenceBadgeColor)
                        .clipShape(Capsule())
                }
            }

            if decision.action != .keep {
                HStack {
                    Button("Restore", action: onRestore)
                        .font(.caption.bold())
                        .foregroundStyle(.green)
                }
            }
            if decision.action == .keep || decision.action == .reviewRequired {
                HStack {
                    Button("Cut", action: onCut)
                        .font(.caption.bold())
                        .foregroundStyle(.red)
                }
            }
        }
        .padding()
        .background(backgroundColor)
    }

    private var actionBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: actionIcon)
            Text(decision.action.rawValue.replacingOccurrences(of: "_", with: " ").uppercased())
                .font(.caption2.bold())
        }
        .foregroundStyle(actionColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(actionColor.opacity(0.12))
        .clipShape(Capsule())
    }

    private var actionIcon: String {
        switch decision.action {
        case .keep: "checkmark"
        case .cut, .trimStart, .trimEnd: "scissors"
        case .reviewRequired: "eye"
        default: "questionmark"
        }
    }

    private var actionColor: Color {
        switch decision.action {
        case .keep: .green
        case .cut, .trimStart, .trimEnd: .red
        case .reviewRequired: .yellow
        default: .gray
        }
    }

    private var confidenceBadgeColor: Color {
        if decision.confidence >= 0.7 { return .green }
        if decision.confidence >= 0.5 { return .yellow }
        return .red
    }

    private var backgroundColor: Color {
        switch decision.action {
        case .keep: Color.white.opacity(0.03)
        case .cut, .trimStart, .trimEnd: Color.red.opacity(0.03)
        case .reviewRequired: Color.yellow.opacity(0.05)
        default: Color.white.opacity(0.03)
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        let ms = Int((seconds.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%d:%02d.%d", mins, secs, ms)
    }
}
