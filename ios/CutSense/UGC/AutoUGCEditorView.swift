import SwiftUI
import PhotosUI
import AVKit

/// Main view for the Auto UGC Editor mode.
/// Flow: Import → Process → Review → Export
/// @MainActor: View helpers read @AppStorage-backed `language` (MainActor-isolated).
@MainActor
struct AutoUGCEditorView: View {
    @State private var project: UGCEditProject?
    @State private var importService = VideoImportService()
    @State private var pickerItem: PhotosPickerItem?
    @State private var phase: EditorPhase = .idle
    @State private var workEvents: [String] = []
    @State private var activeJobID: UUID?
    @State private var processingTask: Task<Void, Never>?
    @State private var intensity: UGCIntensity = .conservative
    @State private var showReview = false
    @State private var isExporting = false
    @State private var saved = false
    @State private var exportedURL: URL?
    @State private var captionStyle: String = "techKinetic"
    @State private var sfxEnabled: Bool = true

    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.systemDefault.rawValue

    enum EditorPhase {
        case idle
        case processing(ProcessingState)
        case review
        case exporting
        case done(URL)
        case failed(String)
    }

    struct ProcessingState {
        let stage: UGCProcessor.Stage
        let progress: Double
        let title: String
        let detail: String
        let events: [String]
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Show background for idle and review states
            if case .idle = phase {
                Color(red: 0.05, green: 0.06, blue: 0.09).ignoresSafeArea()
            }

            switch phase {
            case .idle:
                idleContent
            case .processing(let state):
                processingContent(state: state)
            case .review:
                if let project {
                    UGCReviewScreen(
                        project: project,
                        onBack: { backToIdle() },
                        onExport: { startExport() },
                        onReanalyze: { reanalyze() }
                    )
                }
            case .exporting:
                exportingContent
            case .done(let url):
                doneContent(url: url)
            case .failed(let message):
                failedContent(message: message)
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            startProcessing(item)
        }
    }

    // MARK: - Idle

    private var idleContent: some View {
        VStack(spacing: 28) {
            header
            Spacer(minLength: 0)
            importSection
            Spacer(minLength: 0)
            intensityPicker
            LanguageSwitcher()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 44)
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(colors: [.purple, .pink, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
            Text(appText(language, "Auto UGC Düzenleyici", "Auto UGC Editor"))
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(appText(language,
                         "Uzun konuşma videolarını otomatik düzenle. Tekrarları, hataları ve sessizlikleri temizle.",
                         "Automatically edit long talking-head videos. Clean up repeats, mistakes, and silences."))
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    private var importSection: some View {
        VStack(spacing: 14) {
            PhotosPicker(selection: $pickerItem, matching: .videos, photoLibrary: .shared()) {
                VStack(spacing: 12) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(
                            LinearGradient(colors: [.purple, .pink], startPoint: .leading, endPoint: .trailing)
                        )
                    Text(appText(language, "Video Seç", "Choose Video"))
                        .font(.headline.weight(.bold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 44)
                .background(.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [8, 6]))
                        .foregroundStyle(.white.opacity(0.2))
                )
            }

            Text(appText(language,
                         "Video cihazınızda işlenir. Hiçbir veri yüklenmez.",
                         "Video is processed on your device. No data is uploaded."))
                .font(.caption)
                .foregroundStyle(.white.opacity(0.45))
        }
    }

    private var intensityPicker: some View {
        VStack(spacing: 8) {
            Picker(appText(language, "Düzenleme Yoğunluğu", "Editing Intensity"), selection: $intensity) {
                ForEach(UGCIntensity.allCases) { level in
                    Text(level.title(for: language)).tag(level)
                }
            }
            .pickerStyle(.segmented)

            Text(intensity.detail(for: language))
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.58))
                .frame(minHeight: 18)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Processing

    private func processingContent(state: ProcessingState) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                VStack(spacing: 10) {
                    ProgressView(value: state.progress)
                        .tint(.white)
                        .frame(maxWidth: 280)

                    Text(state.title)
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .foregroundStyle(.white)
                    Text(state.detail)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.65))
                    Text("\(Int(state.progress * 100))%")
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                        .foregroundStyle(.white)
                }
                .padding(.top, 60)

                WorkTimelineUGC(events: state.events)
                    .padding(.horizontal, 24)

                Button {
                    cancelProcessing()
                } label: {
                    Label(appText(language, "İptal", "Cancel"), systemImage: "xmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .font(.headline)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .background(.white.opacity(0.08))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 24)
            }
        }
        .padding(.vertical, 44)
        .background(Color(red: 0.05, green: 0.06, blue: 0.09).ignoresSafeArea())
    }

    // MARK: - Exporting

    private var exportingContent: some View {
        VStack(spacing: 20) {
            ProgressView()
                .tint(.white)
                .scaleEffect(1.5)
            Text(appText(language, "Dışa aktarılıyor…", "Exporting…"))
                .font(.headline)
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.05, green: 0.06, blue: 0.09).ignoresSafeArea())
    }

    // MARK: - Done

    private func doneContent(url: URL) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.green)

                Text(appText(language, "Düzenleme Tamamlandı", "Edit Complete"))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                if let project {
                    HStack(spacing: 20) {
                        statItem(value: project.originalDurationFormatted, label: appText(language, "Orijinal", "Original"))
                        statItem(value: project.editedDurationFormatted, label: appText(language, "Düzenlenmiş", "Edited"))
#error("RECON GAP: lines 241-337 of AutoUGCEditorView.swift unrecoverable")
    private func startProcessing(_ item: PhotosPickerItem) {
#error("RECON GAP: lines 339-344 of AutoUGCEditorView.swift unrecoverable")
    private func handleProcessing(_ item: PhotosPickerItem, jobID: UUID) async {
#error("RECON GAP: lines 346-375 of AutoUGCEditorView.swift unrecoverable")
            let project = UGCEditProject(sourceVideoURL: inputURL, originalDuration: result.originalDuration)
#error("RECON GAP: lines 377-406 of AutoUGCEditorView.swift unrecoverable")
    private func importVideo(_ item: PhotosPickerItem, jobID: UUID) async throws -> URL {
#error("RECON GAP: lines 408-469 of AutoUGCEditorView.swift unrecoverable")
                switch result {
                case .success:
                    saved = true
                case .failure(let error):
                    #if DEBUG
                    print("[UGC] Save failed: \(error.localizedDescription)")
                    #endif
                }
            }
        }
    }

    private func reanalyze() {
        guard let inputURL = project?.sourceVideoURL else { return }
        // Sync settings from project before clearing
        if let proj = project {
            captionStyle = proj.selectedCaptionStyle
            sfxEnabled = proj.sfxEnabled
        }
        let jobID = UUID()
        processingTask?.cancel()
        activeJobID = jobID
        project = nil
        exportedURL = nil
        workEvents = []
        processingTask = Task { await handleReanalysis(url: inputURL, jobID: jobID) }
    }

    private func handleReanalysis(url: URL, jobID: UUID) async {
        let lang = await safeLanguage()
        phase = .processing(ProcessingState(
            stage: .preparing,
            progress: 0.01,
            title: appText(lang, "Yeniden analiz ediliyor", "Re-analyzing"),
            detail: appText(lang, "Video yeniden işleniyor.", "Video is being reprocessed."),
            events: []
        ))

        do {
            let currentLang = await safeLanguage()
            let result = try await UGCProcessor.process(
                url: url,
                intensity: intensity,
                language: currentLang,
                captionStyle: captionStyle,
                sfxEnabled: sfxEnabled
            ) { [jobID] update in
                Task { @MainActor in
                    self.applyProgress(update, jobID: jobID)
                }
            }
            guard isActive(jobID) else { return }

            let project = UGCEditProject(sourceVideoURL: url, originalDuration: result.originalDuration)
            project.takeGroups = result.takeGroups
            project.editDecisions = result.editDecisions
            project.timelineSegments = result.timelineSegments
            project.finalCompositionURL = result.outputURL
            project.phase = .reviewReady
            project.intensity = intensity
            project.exportMetadata = result.exportMetadata
            project.faceResults = result.faceResults
            project.silenceIntervals = result.silenceIntervals
            self.project = project
            exportedURL = result.outputURL
            phase = .review
        } catch is CancellationError {
            if isActive(jobID) { backToIdle() }
        } catch {
            guard isActive(jobID) else { return }
            let msg = (error as? UGCProcessor.ProcessingError)?.errorDescription ?? error.localizedDescription
            phase = .failed(msg)
        }
    }

    private func cancelProcessing() {
        processingTask?.cancel()
        processingTask = nil
        activeJobID = nil
        workEvents = []
        phase = .idle
    }

    private func backToIdle() {
        processingTask?.cancel()
        processingTask = nil
        activeJobID = nil
        project = nil
        exportedURL = nil
        saved = false
        isExporting = false
        workEvents = []
        phase = .idle
    }

    private func isActive(_ jobID: UUID) -> Bool {
        activeJobID == jobID && !Task.isCancelled
    }

    // Accessed from processing closures that run on background actors.
    // Use `language` directly only in view body or MainActor-marked functions.
    private var language: AppLanguage {
        AppLanguage.value(from: languageRaw)
    }

    /// Safely read the current language from any context by hopping to MainActor.
    private nonisolated func safeLanguage() async -> AppLanguage {
        await MainActor.run { AppLanguage.value(from: languageRaw) }
    }


}

// MARK: - Supporting Views

private struct WorkTimelineUGC: View {
    let events: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(events.enumerated()), id: \.offset) { index, event in
                HStack(alignment: .top, spacing: 9) {
                    Circle()
                        .fill(index == 0 ? .white : .white.opacity(0.35))
                        .frame(width: 7, height: 7)
                        .padding(.top, 5)
                    Text(event)
                        .font(.caption)
                        .foregroundStyle(index == 0 ? .white.opacity(0.9) : .white.opacity(0.55))
                        .lineLimit(2)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(.white.opacity(0.1)))
    }
}
