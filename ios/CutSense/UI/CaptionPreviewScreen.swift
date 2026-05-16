import SwiftUI

@MainActor
@Observable
final class CaptionPreviewViewModel {
    var captions: [CaptionSegment] = []
    var editPlan: EditPlan?
    var qualityReport: QualityReport?
    var isProcessing = false

    func generate(
        transcription: TranscriptionResult,
        roughCut: RoughCutResult,
        template: TemplateConfig
    ) {
        isProcessing = true
        defer { isProcessing = false }

        captions = CaptionEngine.generateCaptions(
            from: transcription,
            roughCut: roughCut,
            template: template
        )

        let plan = EditDecisionEngine.generateEditPlan(
            captions: captions,
            roughCut: roughCut,
            template: template
        )
        editPlan = plan

        qualityReport = QualityGateService.evaluate(
            captions: captions,
            editPlan: plan,
            roughCut: roughCut,
            template: template
        )

        // Debug log entire timeline state
        let debugLog = TimelineDebugLogger.generate(
            roughCut: roughCut,
            captions: captions,
            editPlan: plan,
            qualityReport: qualityReport
        )
        TimelineDebugLogger.printLog(debugLog)
    }

    func saveCaptionData(projectId: UUID, userId: UUID, templateName: String) async {
        let pipeline = PipelineRepository()
        do {
            try await pipeline.updateProjectTemplate(projectId: projectId, templateName: templateName)
            try await pipeline.updateProjectStatus(projectId, status: .styling)

            // Delete old caption/edit data to prevent duplicates on re-generation
            try await pipeline.deleteCaptionData(projectId: projectId)

            try await pipeline.saveCaptionSegments(
                projectId: projectId,
                userId: userId,
                captions: captions
            )

            if let plan = editPlan {
                try await pipeline.saveEditDecisions(
                    projectId: projectId,
                    userId: userId,
                    decisions: plan.decisions
                )
            }
        } catch {
            print("[CutSense] DB save after captioning failed: \(error.localizedDescription)")
        }
    }
}

struct CaptionPreviewScreen: View {
    let roughCut: RoughCutResult
    let transcription: TranscriptionResult
    let template: TemplateConfig
    let videoURL: URL
    let projectId: UUID
    @Environment(AuthManager.self) private var authManager
    @State private var viewModel = CaptionPreviewViewModel()
    @State private var showExport = false
    @State private var exportService = ExportService()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if viewModel.isProcessing {
                ProgressView("Generating captions...")
                    .tint(.white)
                    .foregroundStyle(.white)
            } else {
                ScrollView {
                    VStack(spacing: 20) {
                        statsHeader

                        VStack(spacing: 1) {
                            ForEach(viewModel.captions) { caption in
                                CaptionRow(caption: caption)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)

                        if let plan = viewModel.editPlan, !plan.decisions.isEmpty {
                            editDecisionsSection(plan)
                        }

                        if let report = viewModel.qualityReport {
                            qualitySection(report)
                        }

                        Button {
                            showExport = true
                        } label: {
                            Text("Export Video")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(.white)
                                .foregroundStyle(.black)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 32)
                    }
                }
            }
        }
        .navigationTitle("Captions")
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task {
            viewModel.generate(
                transcription: transcription,
                roughCut: roughCut,
                template: template
            )
            // Save caption data to DB after generation
            if let userId = authManager.currentUser?.id {
                await viewModel.saveCaptionData(
                    projectId: projectId,
                    userId: userId,
                    templateName: template.name
                )
            }
        }
        .sheet(isPresented: $showExport) {
            ExportScreen(
                sourceURL: videoURL,
                exportService: exportService,
                projectId: projectId,
                decisions: roughCut.decisions,
                captions: viewModel.captions,
                template: template,
                editPlan: viewModel.editPlan
            )
        }
    }

    private var statsHeader: some View {
        HStack(spacing: 16) {
            statItem("\(viewModel.captions.count)", label: "Captions")
            statItem("\(viewModel.editPlan?.totalEffects ?? 0)", label: "Effects")
            if let avg = viewModel.editPlan?.averageIntensity {
                statItem(String(format: "%.0f%%", avg * 100), label: "Intensity")
            }
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private func statItem(_ value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3.bold())
                .foregroundStyle(.white)
            Text(label)
                .font(.caption)
                .foregroundStyle(.gray)
        }
        .frame(maxWidth: .infinity)
    }

    private func editDecisionsSection(_ plan: EditPlan) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Edit Decisions")
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal)

            VStack(spacing: 1) {
                ForEach(plan.decisions) { decision in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(decision.type.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                                .font(.subheadline)
                                .foregroundStyle(.white)
                            Text(decision.reason)
                                .font(.caption2)
                                .foregroundStyle(.gray)
                        }
                        Spacer()
                        Text(formatTime(decision.time))
                            .font(.caption.monospaced())
                            .foregroundStyle(.gray)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.03))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
        }
    }

    private func qualitySection(_ report: QualityReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Quality Gate")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                Text("\(report.score)/100")
                    .font(.headline.bold())
                    .foregroundStyle(report.passed ? .green : .red)
            }
            .padding(.horizontal)

            VStack(spacing: 1) {
                ForEach(report.checks) { check in
                    HStack {
                        Image(systemName: check.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(check.passed ? .green : (check.severity == .critical ? .red : .yellow))
                            .font(.caption)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(check.name)
                                .font(.caption)
                                .foregroundStyle(.white)
                            Text(check.detail)
                                .font(.caption2)
                                .foregroundStyle(.gray)
                        }
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.03))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

private struct CaptionRow: View {
    let caption: CaptionSegment

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                roleBadge
                styleBadge
                if caption.sceneBehavior != .none {
                    behaviorBadge
                }
                Spacer()
                Text("\(formatTime(caption.startTime)) - \(formatTime(caption.endTime))")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.gray)
            }

            Text(caption.text)
                .font(.subheadline)
                .foregroundStyle(.white)
        }
        .padding()
        .background(Color.white.opacity(0.03))
    }

    private var roleBadge: some View {
        Text(caption.role.rawValue.uppercased())
            .font(.system(size: 9, weight: .bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(roleColor.opacity(0.15))
            .foregroundStyle(roleColor)
            .clipShape(Capsule())
    }

    private var styleBadge: some View {
        Text(caption.style.displayName)
            .font(.system(size: 9))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.white.opacity(0.08))
            .foregroundStyle(.white.opacity(0.7))
            .clipShape(Capsule())
    }

    private var behaviorBadge: some View {
        Text(caption.sceneBehavior.displayName)
            .font(.system(size: 9))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.purple.opacity(0.15))
            .foregroundStyle(.purple)
            .clipShape(Capsule())
    }

    private var roleColor: Color {
        switch caption.role {
        case .hook: .orange
        case .warning: .red
        case .reveal: .yellow
        case .keyword: .cyan
        case .transition: .blue
        case .conclusion: .green
        case .regular: .gray
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
