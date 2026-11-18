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
    @State private var contentLanguage: UGCContentLanguage = .automatic
    @State private var isExporting = false
    @State private var saved = false
    @State private var exportedURL: URL?
    // Start with a readable lower-safe caption treatment. The high-impact
    // treatment remains an explicit style choice, rather than making every
    // newly imported video look like an oversized meme subtitle.
    @State private var captionStyle: String = "subtitleMinimal"
    @State private var captionsEnabled = true
    @State private var sfxEnabled: Bool = true
    @State private var processingStartedAt: Date?

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
                    UGCStudioView(
                        project: project,
                        onBack: { backToIdle() },
                        onRender: { renderProjectEdits() },
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
            contentLanguagePicker
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
        let chooseVideoTitle = appText(language, "Video Seç", "Choose Video")
        return VStack(spacing: 14) {
            PhotosPicker(selection: $pickerItem, matching: .videos, photoLibrary: .shared()) {
                VStack(spacing: 12) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(
                            LinearGradient(colors: [.purple, .pink], startPoint: .leading, endPoint: .trailing)
                        )
                    Text(chooseVideoTitle)
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

    private var contentLanguagePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(appText(language, "Videodaki konuşma dili", "Spoken language"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.7))
            Picker("", selection: $contentLanguage) {
                ForEach(UGCContentLanguage.allCases) { item in
                    Text(item.title(for: language)).tag(item)
                }
            }
#error("RECON GAP: lines 181-273 of AutoUGCEditorView.swift unrecoverable")
                        statItem(value: "-" + project.timeSavedFormatted, label: appText(language, "Kesildi", "Removed"))
#error("RECON GAP: lines 275-349 of AutoUGCEditorView.swift unrecoverable")
                .foregroundStyle(.white.opacity(0.8))
                .padding(.horizontal, 24)
            Button {
                backToIdle()
            } label: {
                Text(appText(language, "Tekrar Dene", "Try Again"))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(.white)
                    .foregroundStyle(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.05, green: 0.06, blue: 0.09).ignoresSafeArea())
    }

    // MARK: - Actions

    private func startProcessing(_ item: PhotosPickerItem) {
        let jobID = UUID()
        processingTask?.cancel()
        activeJobID = jobID
        processingTask = Task { await handleProcessing(item, jobID: jobID) }
    }

    private func handleProcessing(_ item: PhotosPickerItem, jobID: UUID) async {
        processingStartedAt = Date()
        let lang = await safeLanguage()
        phase = .processing(ProcessingState(
            stage: .preparing,
            progress: 0.01,
            title: appText(lang, "Video içe aktarılıyor", "Importing video"),
            detail: appText(lang, "Dosya kaynağı hazırlanıyor.", "Preparing the selected file."),
            events: []
        ))

        do {
            let inputURL = try await importVideo(item, jobID: jobID)
            guard isActive(jobID) else { return }

            workEvents = []
            let currentLang = await safeLanguage()
            let result = try await UGCProcessor.process(
                url: inputURL,
                intensity: intensity,
                language: currentLang,
                contentLanguage: contentLanguage,
                captionStyle: captionStyle,
                captionsEnabled: captionsEnabled,
                sfxEnabled: sfxEnabled
            ) { [jobID] update in
                Task { @MainActor in
                    self.applyProgress(update, jobID: jobID)
                }
            }

            guard isActive(jobID) else { return }

            // Create project state
            let project = UGCEditProject(sourceVideoURL: inputURL, originalDuration: result.originalDuration)
            project.takeGroups = result.takeGroups
            project.editDecisions = result.editDecisions
            project.timelineSegments = result.timelineSegments
            project.captions = result.captions
            project.transcriptResult = result.transcriptResult
            project.finalCompositionURL = result.outputURL
            project.phase = .reviewReady
            project.intensity = intensity
            project.exportMetadata = result.exportMetadata
            project.faceResults = result.faceResults
            project.silenceIntervals = result.silenceIntervals
            project.selectedCaptionStyle = captionStyle
            project.captionsEnabled = captionsEnabled
            project.sourceLikelyHasBurnedCaptions = result.sourceLikelyHasBurnedCaptions
            project.sfxEnabled = sfxEnabled
            self.project = project

            exportedURL = result.outputURL
            phase = .review

        } catch is CancellationError {
            if isActive(jobID) { backToIdle() }
        } catch {
            guard isActive(jobID) else { return }
            let message: String
            if let procError = error as? UGCProcessor.ProcessingError {
                message = procError.errorDescription ?? error.localizedDescription
            } else if let transcriptError = error as? SpeechTranscriptionService.TranscriptionError {
                message = transcriptError.errorDescription ?? error.localizedDescription
            } else {
                message = error.localizedDescription
            }
            phase = .failed(message)
        }
    }

    private func importVideo(_ item: PhotosPickerItem, jobID: UUID) async throws -> URL {
        await importService.importVideo(from: item)
        try Task.checkCancellation()
        guard isActive(jobID) else { throw CancellationError() }

        if let errorMessage = importService.errorMessage {
            throw NSError(domain: "UGC", code: 1, userInfo: [NSLocalizedDescriptionKey: errorMessage])
        }
        guard let url = importService.importedVideoURL else {
            let lang2 = await safeLanguage()
            throw NSError(domain: "UGC", code: 2, userInfo: [NSLocalizedDescriptionKey: appText(lang2, "Video yüklenemedi.", "Could not load video.")])
#error("RECON GAP: lines 460-512 of AutoUGCEditorView.swift unrecoverable")
                let result = try await UGCProcessor.renderEdited(
#error("RECON GAP: lines 514-518 of AutoUGCEditorView.swift unrecoverable")
                    captionStyle: project.selectedCaptionStyle,
                    captionsEnabled: project.captionsEnabled,
                    sfxEnabled: project.sfxEnabled
#error("RECON GAP: lines 522-543 of AutoUGCEditorView.swift unrecoverable")
                    #if DEBUG
#error("RECON GAP: lines 545-555 of AutoUGCEditorView.swift unrecoverable")
            captionStyle = proj.selectedCaptionStyle
            captionsEnabled = proj.captionsEnabled
            sfxEnabled = proj.sfxEnabled
#error("RECON GAP: lines 559-585 of AutoUGCEditorView.swift unrecoverable")
                captionStyle: captionStyle,
                captionsEnabled: captionsEnabled,
                sfxEnabled: sfxEnabled
#error("RECON GAP: lines 589-606 of AutoUGCEditorView.swift unrecoverable")
            project.selectedCaptionStyle = captionStyle
            project.captionsEnabled = captionsEnabled
            project.sourceLikelyHasBurnedCaptions = result.sourceLikelyHasBurnedCaptions
            project.sfxEnabled = sfxEnabled
#error("RECON GAP: end of AutoUGCEditorView.swift unknown (file may continue past line 610)")
