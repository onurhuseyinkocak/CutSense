import SwiftUI
import PhotosUI
import AVKit
import UIKit

/// The entire app, one screen: pick a video → cut the silences → save.
struct QuickSilenceView: View {
    @State private var phase: Phase = .idle
    @State private var pickerItem: PhotosPickerItem?
    @State private var importService = VideoImportService()
    @StateObject private var rewardedAd = RewardedInterstitialAdController()
    @State private var saved = false
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var saveNeedsSettings = false
    @State private var saveTask: Task<Void, Never>?
    @State private var savingURL: URL?
    @State private var cutIntensity: QuickSilenceEngine.CutIntensity = .tight
    @State private var workEvents: [String] = []
    @State private var activeJobID: UUID?
    @State private var processingTask: Task<Void, Never>?
    @State private var processingAdTask: Task<Void, Never>?
    @State private var processingAdOverlay: ProcessingAdState?
    @State private var completedProcessingAdBreaks = 0
    @State private var privacyOptionsRequired = false
    @State private var currentInputURL: URL?
    @State private var didStartAutorun = false
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.systemDefault.rawValue

    enum Phase {
        case idle
        case working(WorkingState)
        case done(QuickSilenceEngine.Result)
        case failed(String)
    }

    struct WorkingState {
        let stage: QuickSilenceEngine.ProgressUpdate.Stage
        let progress: Double
        let title: String
        let detail: String
        let events: [String]
    }

    struct ProcessingAdState: Equatable {
        let countdown: Int?
        let status: String
        let isOpening: Bool
        let canSkip: Bool
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(colors: [Color(red: 0.05, green: 0.06, blue: 0.09), .black],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 28) {
                header
                Spacer(minLength: 0)
                content
                Spacer(minLength: 0)
                if isIdle {
                    LanguageSwitcher()
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 44)
            .padding(.bottom, showsPersistentBanner ? 132 : 0)

            if showsPersistentBanner {
                AdBannerSlot()
                    .background(.black.opacity(0.72))
            }

        }
        .preferredColorScheme(.dark)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if privacyOptionsRequired {
                    privacyOptionsToolbarButton
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    SettingsScreen()
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: 38, height: 38)
                        .background(.white.opacity(0.1))
                        .foregroundStyle(.white)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(.white.opacity(0.14)))
                }
                .accessibilityLabel(t("Ayarlar", "Settings"))
            }
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            startPickedVideo(item)
        }
        .task {
            if AdMobService.isEnabled {
                rewardedAd.preload()
                await AdMobService.waitForConsentConfiguration()
                privacyOptionsRequired = AdMobService.isPrivacyOptionsRequired
            }
            startAutorunIfRequested()
        }
        .onDisappear {
            cancelActiveWork(returnToIdle: false)
            saveTask?.cancel()
        }
    }

    private var showsPersistentBanner: Bool {
        guard AdMobService.isEnabled else { return false }
        switch phase {
        case .idle, .working:
            return true
        case .done, .failed:
            return false
        }
    }

    private var showsProcessingAdSurface: Bool {
        guard AdMobService.isEnabled else { return false }
        switch phase {
        case .working:
            return processingAdOverlay == nil
        case .idle, .done, .failed:
            return false
        }
    }

    private var privacyOptionsToolbarButton: some View {
        Button {
            Task {
                await AdMobService.presentPrivacyOptions()
                privacyOptionsRequired = AdMobService.isPrivacyOptionsRequired
            }
        } label: {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 15, weight: .bold))
                .frame(width: 38, height: 38)
                .background(.white.opacity(0.1))
                .foregroundStyle(.white)
                .clipShape(Circle())
                .overlay(Circle().stroke(.white.opacity(0.14)))
        }
        .accessibilityLabel(t("Gizlilik seçenekleri", "Privacy options"))
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "scissors")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.white)
            Text(t("Sessizlik Kes", "Cut Silence"))
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(t("Videondaki sessizlikleri ve duraklamaları otomatik kes.", "Automatically remove silence and long pauses from your video."))
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .idle:
            VStack(spacing: 16) {
                let chooseVideoTitle = t("Video Seç", "Choose Video")
                PhotosPicker(selection: $pickerItem, matching: .videos, photoLibrary: .shared()) {
                    Label(chooseVideoTitle, systemImage: "photo.on.rectangle.angled")
                        .frame(maxWidth: .infinity)
                }
                .accessibilityIdentifier("chooseVideoButton")
                .buttonStyle(QSPrimary())

                CutIntensityPicker(selection: $cutIntensity, language: appLanguage)
            }

        case .working(let state):
            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    VStack(spacing: 10) {
                        ProgressView(value: state.progress)
                            .tint(.white)
                            .frame(maxWidth: 280)
                        ProcessingStageDeck(stage: state.stage, progress: state.progress, language: appLanguage)
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

                    if let processingAdOverlay {
                        ProcessingAdCountdownView(state: processingAdOverlay, language: appLanguage) {
                            skipProcessingAdBreak()
                        }
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    }

                    WorkTimeline(events: state.events)
                    if showsProcessingAdSurface {
                        WaitingAdSurface(language: appLanguage)
                    }

                    Button {
                        cancelActiveWork(returnToIdle: true)
                    } label: {
                        Label(t("İptal", "Cancel"), systemImage: "xmark.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(QSSecondary())
                }
                .animation(.easeInOut(duration: 0.22), value: processingAdOverlay)
            }

        case .done(let result):
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                VideoPlayer(player: AVPlayer(url: result.outputURL))
                        .frame(height: min(300, UIScreen.main.bounds.height * 0.34))
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                HStack(spacing: 26) {
                    stat("%\(result.removedPercent)", t("kesildi", "removed"))
                    stat(timeString(result.removedDuration), t("sessizlik", "silence"))
                    stat(timeString(result.outputDuration), t("yeni süre", "new length"))
                }
                    CutIntensityPicker(selection: $cutIntensity, language: appLanguage)
                VStack(spacing: 12) {
                    Button { startSave(result.outputURL) } label: {
                        Label(saveButtonTitle,
                              systemImage: saved ? "checkmark.circle.fill" : "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(QSPrimary()).disabled(saved || isSaving)

                    if let saveError {
                        VStack(spacing: 8) {
                            Text(saveError)
                                .font(.caption)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.orange)
                            if saveNeedsSettings {
                                Button(t("Ayarları Aç", "Open Settings")) { openAppSettings() }
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.white)
                            }
                        }
                    }

                    ShareLink(item: result.outputURL) {
                        Label(t("Paylaş", "Share"), systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(QSSecondary())

                        if currentInputURL != nil {
                            Button {
                                rerunCurrentInput()
                            } label: {
                                Label(t("Aynı Videoyu Tekrar Kes", "Cut Same Video Again"), systemImage: "arrow.clockwise")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(QSSecondary())
                            .disabled(isSaving)
                        }

                    Button(t("Yeni Video", "New Video")) { reset() }
                        .accessibilityIdentifier("newVideoButton")
                        .buttonStyle(QSSecondary())
                        .disabled(isSaving)
                }
                }
            }

        case .failed(let message):
            VStack(spacing: 18) {
                Image(systemName: "exclamationmark.triangle.fill").font(.largeTitle).foregroundStyle(.orange)
                Text(message).font(.callout).multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.8))
                Button(t("Tekrar Dene", "Try Again")) { reset() }.buttonStyle(QSPrimary())
            }
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.system(.title3, design: .rounded).weight(.bold)).foregroundStyle(.white)
            Text(label).font(.caption2).foregroundStyle(.white.opacity(0.55))
        }
    }

    // MARK: - Actions

    private func startPickedVideo(_ item: PhotosPickerItem) {
        let jobID = UUID()
        processingTask?.cancel()
        importService.cancelImport(language: appLanguage)
        activeJobID = jobID
        processingTask = Task { await handlePick(item, jobID: jobID) }
    }

    private func handlePick(_ item: PhotosPickerItem, jobID: UUID) async {
        processingAdTask?.cancel()
        processingAdOverlay = nil
        completedProcessingAdBreaks = 0
        saved = false
        isSaving = false
        saveError = nil
        saveNeedsSettings = false
        saveTask?.cancel()
        savingURL = nil
        workEvents = []
        currentInputURL = nil
        applyProgress(.update(.importing, 0.02, t("Video içe aktarılıyor", "Importing video"), t("Dosya kaynağı hazırlanıyor.", "Preparing the selected file.")), jobID: jobID)
        rewardedAd.preload()

        do {
            let inputURL = try await importVideo(item, jobID: jobID)
            guard isActive(jobID) else { return }
            currentInputURL = inputURL
            try await runCut(inputURL: inputURL, jobID: jobID)
        } catch is CancellationError {
            if isActive(jobID) {
                cancelActiveWork(returnToIdle: true)
            }
        } catch {
            guard isActive(jobID) else { return }
            processingAdTask?.cancel()
            processingAdOverlay = nil
            isSaving = false
            phase = .failed(userFacingMessage(for: error))
        }
    }

    private func startAutorunIfRequested() {
        #if DEBUG
        guard !didStartAutorun else { return }
        guard let path = ProcessInfo.processInfo.environment["CUTSENSE_AUTORUN_VIDEO_URL"], !path.isEmpty else { return }
        let inputURL = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: inputURL.path) else {
            phase = .failed(t("Test videosu bulunamadı.", "Test video was not found."))
            return
        }

        didStartAutorun = true
        let jobID = UUID()
        processingTask?.cancel()
        activeJobID = jobID
        currentInputURL = inputURL
        processingTask = Task {
            do {
                applyProgress(
                    .update(
                        .importing,
                        0.04,
                        t("Video hazır", "Video ready"),
                        t("Test videosu doğrudan işleniyor.", "Test video is being processed directly.")
                    ),
                    jobID: jobID
                )
                try await runCut(inputURL: inputURL, jobID: jobID)
            } catch is CancellationError {
                if isActive(jobID) {
                    cancelActiveWork(returnToIdle: true)
                }
            } catch {
                guard isActive(jobID) else { return }
                processingAdTask?.cancel()
                processingAdOverlay = nil
                phase = .failed(userFacingMessage(for: error))
            }
        }
        #endif
    }

    private func rerunCurrentInput() {
        guard let inputURL = currentInputURL else { return }
        let jobID = UUID()
        processingTask?.cancel()
        activeJobID = jobID
        processingTask = Task {
            do {
                applyProgress(.update(.importing, 0.04, t("Video hazır", "Video ready"), t("Aynı dosya yeni ayarla tekrar kesiliyor.", "Cutting the same file again with the new setting.")), jobID: jobID)
                try await runCut(inputURL: inputURL, jobID: jobID)
            } catch is CancellationError {
                if isActive(jobID) {
                    cancelActiveWork(returnToIdle: true)
                }
            } catch {
                guard isActive(jobID) else { return }
                processingAdTask?.cancel()
                processingAdOverlay = nil
                phase = .failed(userFacingMessage(for: error))
            }
        }
    }

    private func runCut(inputURL: URL, jobID: UUID) async throws {
        let adBreakCount = processingAdBreakCount()
        completedProcessingAdBreaks = 0
        let selectedIntensity = cutIntensity
        let result = try await QuickSilenceEngine.cut(url: inputURL, intensity: selectedIntensity, language: appLanguage) { update in
            applyProgress(update, jobID: jobID)
        }
        guard isActive(jobID) else { return }
        processingAdTask?.cancel()
        processingAdTask = nil
        processingAdOverlay = nil
        saved = false
        saveError = nil
        saveNeedsSettings = false
        phase = .done(result)
        startResultAdBreakIfNeeded(jobID: jobID, totalBreaks: adBreakCount)
    }

    private func startSave(_ url: URL) {
        guard !isSaving else { return }
        saveTask?.cancel()
        savingURL = url
        isSaving = true
        saveError = nil
        saveNeedsSettings = false

        saveTask = Task {
            let result = await PhotosSaveService.saveVideo(at: url)
            guard !Task.isCancelled else { return }
            guard savingURL == url, case .done(let current) = phase, current.outputURL == url else { return }

            isSaving = false
            switch result {
            case .success:
                saved = true
            case .failure(let error):
                saveError = "\(t("Kaydedilemedi", "Could not save")): \(saveErrorMessage(for: error))"
                saveNeedsSettings = (error as? PhotosSaveService.SaveError) == .permissionDenied
            }
        }
    }

    private func reset() {
        cancelActiveWork(returnToIdle: false)
        activeJobID = nil
        pickerItem = nil
        saved = false
        isSaving = false
        saveError = nil
        saveNeedsSettings = false
        saveTask?.cancel()
        savingURL = nil
        workEvents = []
        phase = .idle
        rewardedAd.preload()
    }

    private func cancelActiveWork(returnToIdle: Bool) {
        processingTask?.cancel()
        processingTask = nil
        processingAdTask?.cancel()
        processingAdTask = nil
        processingAdOverlay = nil
        completedProcessingAdBreaks = 0
        importService.cancelImport(language: appLanguage)
        if returnToIdle {
            activeJobID = nil
            workEvents = []
            phase = .idle
        }
    }

    private func importVideo(_ item: PhotosPickerItem, jobID: UUID) async throws -> URL {
        let tracker = Task { @MainActor in
            while !Task.isCancelled {
                let download = importService.downloadProgress
                if download >= 0 {
                    applyProgress(.update(
                        .importing,
                        0.02 + min(max(download, 0), 1) * 0.12,
                        t("iCloud videosu indiriliyor", "Downloading iCloud video"),
                        t("\(Int(download * 100))% indirildi.", "\(Int(download * 100))% downloaded.")
                    ), jobID: jobID)
                } else {
                    applyProgress(.update(
                        .importing,
                        0.04,
                        t("Video içe aktarılıyor", "Importing video"),
                        t("Dosya doğrulanıyor ve yerel depoya alınıyor.", "The file is being validated and stored locally.")
                    ), jobID: jobID)
                }
                try? await Task.sleep(for: .milliseconds(350))
            }
        }

        await importService.importVideo(from: item, language: appLanguage)
        tracker.cancel()
        await tracker.value
        try Task.checkCancellation()
        guard isActive(jobID) else { throw CancellationError() }

        if let message = importService.errorMessage {
            throw ViewFailure(message)
        }
        guard let url = importService.importedVideoURL else {
            throw ViewFailure(t("Video yüklenemedi. Lütfen farklı bir dosya deneyin.", "Could not load the video. Try a different file."))
        }

        applyProgress(.update(.importing, 0.15, t("Video hazır", "Video ready"), t("Ses analizi başlıyor.", "Audio analysis is starting.")), jobID: jobID)
        return url
    }

    private func applyProgress(_ update: QuickSilenceEngine.ProgressUpdate, jobID: UUID) {
        guard isActive(jobID) else { return }
        let event = "\(update.title): \(update.detail)"
        if workEvents.first != event {
            workEvents.insert(event, at: 0)
            workEvents = Array(workEvents.prefix(5))
        }
        phase = .working(WorkingState(
            stage: update.stage,
            progress: update.fraction,
            title: update.title,
            detail: update.detail,
            events: workEvents
        ))
    }

    private func processingAdBreakCount() -> Int {
        guard AdMobService.isEnabled else { return 0 }
        return 1
    }

    private func startResultAdBreakIfNeeded(jobID: UUID, totalBreaks: Int) {
        guard AdMobService.isEnabled, totalBreaks > completedProcessingAdBreaks else { return }
        processingAdTask?.cancel()
        processingAdTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(850))
            guard !Task.isCancelled, isActive(jobID), isDone else { return }
            if !rewardedAd.isReady {
                await rewardedAd.load()
            }
            guard !Task.isCancelled, isActive(jobID), isDone, rewardedAd.isReady else { return }
            let result = await rewardedAd.showIfAvailable()
            if result.wasPresented, isActive(jobID) {
                completedProcessingAdBreaks += 1
            }
        }
    }

    private func presentProcessingAdBreak(jobID: UUID, breakIndex: Int, totalBreaks: Int) async -> Bool {
        guard AdMobService.isEnabled, !Task.isCancelled, isActive(jobID), isWorking else {
            processingAdOverlay = nil
            return false
        }

        if !rewardedAd.isReady {
            await rewardedAd.load()
        }

        guard !Task.isCancelled, isActive(jobID), isWorking, rewardedAd.isReady else {
            processingAdOverlay = nil
            return false
        }

        for number in stride(from: 3, through: 1, by: -1) {
            processingAdOverlay = ProcessingAdState(
                countdown: number,
                status: adBreakCountdownText(breakIndex: breakIndex, totalBreaks: totalBreaks),
                isOpening: false,
                canSkip: false
            )
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, isActive(jobID), isWorking else {
                processingAdOverlay = nil
                return false
            }
        }

        processingAdOverlay = ProcessingAdState(
            countdown: 0,
            status: t("Reklam açılıyor.", "Opening ad."),
            isOpening: true,
            canSkip: false
        )
        let result = await rewardedAd.showIfAvailable()
        let wasPresented = result.wasPresented
        if wasPresented, isActive(jobID) {
            completedProcessingAdBreaks += 1
        }

        guard !Task.isCancelled, isActive(jobID), isWorking else {
            processingAdOverlay = nil
            return wasPresented
        }
        processingAdOverlay = ProcessingAdState(
            countdown: nil,
            status: adBreakCompleteText(result: result),
            isOpening: false,
            canSkip: false
        )
        try? await Task.sleep(for: .milliseconds(700))
        if !Task.isCancelled {
            processingAdOverlay = nil
        }
        return wasPresented
    }

    private func adBreakCountdownText(breakIndex: Int, totalBreaks: Int) -> String {
        if totalBreaks > 1 {
            return t(
                "Uzun video reklamı \(breakIndex)/\(totalBreaks) birazdan açılacak.",
                "Long-video ad \(breakIndex)/\(totalBreaks) will open shortly."
            )
        }
        return t("Reklam birazdan açılacak.", "Ad will open shortly.")
    }

    private func adBreakCompleteText(result: RewardedInterstitialAdResult) -> String {
        switch result {
        case .presented(let rewarded):
            return rewarded ? t("Reklam tamamlandı. İşlem devam ediyor.", "Ad completed. Processing continues.") : t("Reklam kapandı. İşlem devam ediyor.", "Ad closed. Processing continues.")
        case .unavailable:
            return t("Reklam şu an yüklenemedi. İşlem devam ediyor.", "Ad could not load right now. Processing continues.")
        }
    }

    private func skipProcessingAdBreak() {
        processingAdTask?.cancel()
        processingAdTask = nil
        processingAdOverlay = nil
    }

    private func isActive(_ jobID: UUID) -> Bool {
        activeJobID == jobID && !Task.isCancelled
    }

    private var isWorking: Bool {
        if case .working = phase { return true }
        return false
    }

    private var isDone: Bool {
        if case .done = phase { return true }
        return false
    }

    private var isIdle: Bool {
        if case .idle = phase { return true }
        return false
    }

    private var appLanguage: AppLanguage {
        AppLanguage.value(from: languageRaw)
    }

    private func t(_ tr: String, _ en: String) -> String {
        appText(appLanguage, tr, en)
    }

    private func timeString(_ seconds: Double) -> String {
        let s = Int(seconds.rounded()); return String(format: "%d:%02d", s / 60, s % 60)
    }

    private var saveButtonTitle: String {
        if saved { return t("Galeriye Kaydedildi", "Saved to Photos") }
        if isSaving { return t("Kaydediliyor", "Saving") }
        return t("Galeriye Kaydet", "Save to Photos")
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func userFacingMessage(for error: Error) -> String {
        if error is CancellationError {
            return t("İşlem iptal edildi.", "The job was cancelled.")
        }
        if let quickError = error as? QuickSilenceEngine.Failure {
            return quickError.message(for: appLanguage)
        }
        if let audioError = error as? AudioAnalysisError {
            return audioError.message(for: appLanguage)
        }
        if let viewError = error as? ViewFailure {
            return viewError.errorDescription ?? "Video yüklenemedi."
        }
        return t("Video işlenemedi. Lütfen farklı bir video veya daha yumuşak kesim ayarı dene.", "Could not process this video. Try another video or a softer cut setting.")
    }

    private func saveErrorMessage(for error: Error) -> String {
        guard let saveError = error as? PhotosSaveService.SaveError else {
            return error.localizedDescription
        }
        return saveError.message(for: appLanguage)
    }
}

private struct ViewFailure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

private struct CutIntensityPicker: View {
    @Binding var selection: QuickSilenceEngine.CutIntensity
    let language: AppLanguage

    var body: some View {
        VStack(spacing: 8) {
            Picker(appText(language, "Kesim sertliği", "Cut intensity"), selection: $selection) {
                ForEach(QuickSilenceEngine.CutIntensity.allCases) { intensity in
                    Text(intensity.title(for: language)).tag(intensity)
                }
            }
            .pickerStyle(.segmented)

            Text(selection.detail(for: language))
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.58))
                .frame(minHeight: 18)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ProcessingStageDeck: View {
    let stage: QuickSilenceEngine.ProgressUpdate.Stage
    let progress: Double
    let language: AppLanguage

    private var steps: [(stage: QuickSilenceEngine.ProgressUpdate.Stage, title: String, icon: String)] {
        [
            (.importing, appText(language, "İçe aktar", "Import"), "tray.and.arrow.down.fill"),
            (.analyzingAudio, appText(language, "Ses tara", "Scan audio"), "waveform"),
            (.planningCuts, appText(language, "Kesimleri seç", "Plan cuts"), "scissors"),
            (.buildingTimeline, appText(language, "Timeline", "Timeline"), "film.stack.fill"),
            (.exporting, appText(language, "Oluştur", "Create"), "square.and.arrow.up.fill"),
            (.fallbackExport, appText(language, "Uyumluluk", "Compatibility"), "wrench.and.screwdriver.fill"),
            (.verifying, appText(language, "Kontrol", "Check"), "checkmark.seal.fill"),
            (.done, appText(language, "Hazır", "Ready"), "checkmark.circle.fill")
        ]
    }

    private var currentIndex: Int {
        steps.firstIndex { $0.stage == stage } ?? 0
    }

    var body: some View {
        VStack(spacing: 9) {
            HStack {
                Text(stageTitle)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.78))
            }

            VStack(spacing: 7) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    ProcessingStageRow(
                        icon: step.icon,
                        title: step.title,
                        isCurrent: index == currentIndex,
                        isComplete: index < currentIndex
                    )
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(.white.opacity(0.10)))
    }

    private var stageTitle: String {
        switch stage {
        case .importing: appText(language, "Video hazırlanıyor", "Preparing video")
        case .analyzingAudio: appText(language, "Ses analizi", "Audio analysis")
        case .planningCuts: appText(language, "Kesim planı", "Cut plan")
        case .buildingTimeline: appText(language, "Video zaman çizgisi", "Video timeline")
        case .exporting: appText(language, "Dışa aktarım", "Export")
        case .fallbackExport: appText(language, "Uyumluluk modu", "Compatibility mode")
        case .verifying: appText(language, "Çıktı kontrolü", "Output check")
        case .done: appText(language, "Tamamlandı", "Complete")
        }
    }
}

private struct ProcessingStageRow: View {
    let icon: String
    let title: String
    let isCurrent: Bool
    let isComplete: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation) { timeline in
            let pulse = reduceMotion || !isCurrent
                ? CGFloat(1)
                : 1 + CGFloat((sin(timeline.date.timeIntervalSinceReferenceDate * 5) + 1) * 0.06)

            HStack(spacing: 9) {
                ZStack {
                    Circle()
                        .fill(fillColor)
                    Image(systemName: isComplete ? "checkmark" : icon)
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(isCurrent || isComplete ? .black : .white.opacity(0.55))
                }
                .frame(width: 22, height: 22)
                .scaleEffect(pulse)

                Text(title)
                    .font(.system(size: 12, weight: isCurrent ? .bold : .semibold, design: .rounded))
                    .foregroundStyle(isCurrent ? .white : .white.opacity(isComplete ? 0.72 : 0.42))
                    .lineLimit(1)

                Spacer(minLength: 0)

                if isCurrent {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.7)
                }
            }
            .frame(height: 24)
        }
    }

    private var fillColor: Color {
        if isComplete { return .white }
        if isCurrent { return Color(red: 0.78, green: 1.0, blue: 0.45) }
        return .white.opacity(0.08)
    }
}

private struct ProcessingAdCountdownView: View {
    let state: QuickSilenceView.ProcessingAdState
    let language: AppLanguage
    let onSkip: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.12))
                    .frame(width: 58, height: 58)

                if let countdown = state.countdown, countdown > 0 {
                    Text("\(countdown)")
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                } else if state.isOpening {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "play.rectangle.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(appText(language, "Reklam arası", "Ad break"))
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Text(state.status)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            if state.canSkip {
                Button(appText(language, "Atla", "Skip"), action: onSkip)
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.white.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(.white.opacity(0.12)))
    }
}

private struct WorkTimeline: View {
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

private struct WaitingAdSurface: View {
    let language: AppLanguage
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 12) {
            NativeAdCard()
            HStack(spacing: 12) {
                TimelineView(.animation) { timeline in
                    let phase = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                    ZStack {
                        Circle()
                            .stroke(.white.opacity(0.16), lineWidth: 4)
                            .frame(width: 42, height: 42)
                        Circle()
                            .trim(from: 0, to: 0.34)
                            .stroke(.white, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                            .frame(width: 42, height: 42)
                            .rotationEffect(.degrees(phase * 160))
                    }
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 4) {
                    Text(appText(language, "Cihazda işleniyor", "Processing on device"))
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                    Text(appText(language, "Uygulamayı açık tut; çıktı hazır olunca sonuç ekranı açılacak.", "Keep the app open; the result screen appears when the export is ready."))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(.white.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(.white.opacity(0.10)))
        }
    }
}

struct QuickMovie: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent("input-\(UUID().uuidString).mov")
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: received.file, to: dest)
            return QuickMovie(url: dest)
        }
    }
}

private struct QSPrimary: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline).padding(.vertical, 15)
            .frame(maxWidth: .infinity)
            .background(.white).foregroundStyle(.black)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

private struct QSSecondary: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline).padding(.vertical, 14).frame(maxWidth: .infinity)
            .background(.white.opacity(0.08)).foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.14)))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}
