import SwiftUI
import PhotosUI
import StoreKit
import UIKit

/// The entire app, one screen: pick a video → analyze → review the cuts → save or share.
/// Export runs only on Save/Share; no output file exists while reviewing.
struct QuickSilenceView: View {
    @State private var phase: Phase = .idle
    @State private var pickerItem: PhotosPickerItem?
    @State private var importService = VideoImportService()
    @StateObject private var rewardedAd = RewardedInterstitialAdController()
    @State private var store = ProStore.shared
    @State private var session = WorkSession()
    @State private var preview = PreviewPlayer()
    @State private var analysis: QuickSilenceEngine.Analysis?
    @State private var plan: QuickSilenceEngine.CutPlan?
    // Balanced by default: over-cutting is the top complaint about silence removers.
    @State private var cutIntensity: QuickSilenceEngine.CutIntensity = .balanced
    @State private var cutSettings = QuickSilenceEngine.CutSettings(.balanced)
    @State private var exportProgress: Double?
    @State private var exportTask: Task<Void, Never>?
    @State private var saved = false
    @State private var saveError: String?
    @State private var saveNeedsSettings = false
    @State private var activeJobID: UUID?
    @State private var processingTask: Task<Void, Never>?
    @State private var processingAdTask: Task<Void, Never>?
    @State private var processingAdOverlay: ProcessingAdState?
    @State private var privacyOptionsRequired = false
    @State private var didStartAutorun = false
    @State private var showsPaywall = false
    @State private var showsFineTune = false
    /// False while Settings is pushed on top; full-screen ads wait for it.
    @State private var isScreenVisible = true
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.systemDefault.rawValue
    @Environment(\.requestReview) private var requestReview

    enum Phase {
        case idle
        case working(WorkingState)
        case review
        case failed(String)
    }

    struct WorkingState {
        let progress: Double
        let title: String
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

            if case .review = phase, let current = plan, let inputURL = session.inputURL {
                // Not Binding($plan): its force-unwrap crashes when New Video clears the plan while
                // the review screen is still updating on the way out.
                review(plan: Binding(get: { plan ?? current }, set: { if plan != nil { plan = $0 } }), inputURL: inputURL)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            } else {
                VStack(spacing: 28) {
                    // Hidden while working so a loaded native ad still fits a 6.1" screen.
                    if !isWorking { header }
                    Spacer(minLength: 0)
                    content
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 44)
                .padding(.bottom, showsPersistentBanner ? AdBannerSlot.height + 8 : 0)
            }

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
                if privacyOptionsRequired && !store.isPro {
                    privacyOptionsToolbarButton
                }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                if isIdle && store.canOfferPro {
                    Button { showsPaywall = true } label: {
                        Text("PRO")
                            .font(.system(size: 13, weight: .heavy, design: .rounded))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 12)
                            .frame(height: 30)
                            .background(qsAccent, in: Capsule())
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("CutSense Pro")
                    .accessibilityIdentifier("proCapsule")
                }
                NavigationLink {
                    SettingsScreen(urlsInUse: session.urlsInUse)
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: 38, height: 38)
                        .background(.white.opacity(0.1))
                        .foregroundStyle(.white)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(.white.opacity(0.14)))
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .disabled(isWorking || exportTask != nil)
                .accessibilityLabel(t("Ayarlar", "Settings"))
                .accessibilityIdentifier("settingsButton")
            }
        }
        .sheet(isPresented: $showsPaywall) {
            PaywallView(language: appLanguage)
        }
        .sheet(isPresented: $showsFineTune) {
            FineTuneSheet(settings: cutSettings, language: appLanguage) { newSettings in
                cutSettings = newSettings
                replan()
            }
        }
        .onAppear { isScreenVisible = true }
        .onDisappear {
            isScreenVisible = false
            preview.pause()
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            startPickedVideo(item)
        }
        .onChange(of: cutIntensity) { _, intensity in
            cutSettings = QuickSilenceEngine.CutSettings(intensity)
            replan()
        }
        .task {
            // Entitlements first, so a returning Pro owner never sees the consent form or ad preload.
            await ProStore.shared.refresh()
            if AdMobService.isEnabled {
                rewardedAd.preload()
                await AdMobService.waitForConsentConfiguration()
                privacyOptionsRequired = AdMobService.isPrivacyOptionsRequired
            }
            startAutorunIfRequested()
        }
    }

    private var showsPersistentBanner: Bool {
        guard AdMobService.isEnabled, !store.isPro, !AdFreePass.isActive else { return false }
        switch phase {
        case .idle, .working: return true
        case .review, .failed: return false
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
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
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
        case .idle, .review:
            VStack(spacing: 16) {
                let chooseVideoTitle = t("Video Seç", "Choose Video")
                PhotosPicker(selection: $pickerItem, matching: .videos, photoLibrary: .shared()) {
                    Label(chooseVideoTitle, systemImage: "photo.on.rectangle.angled")
                        .frame(maxWidth: .infinity)
                }
                .accessibilityIdentifier("chooseVideoButton")
                .buttonStyle(QSPrimary())

                Text(t("Ücretsiz · Filigransız · Cihazda", "Free · No watermark · On-device"))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(qsAccent.opacity(0.9))

                CutIntensityPicker(selection: $cutIntensity, language: appLanguage, hint: nil)
                    .padding(.top, 8)
            }

        case .working(let state):
            VStack(spacing: 18) {
                VStack(spacing: 10) {
                    ProgressView(value: state.progress)
                        .tint(qsAccent)
                        .frame(maxWidth: 280)
                    Text(state.title)
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .foregroundStyle(.white)
                    Text("\(Int(state.progress * 100))%")
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }

                Button {
                    cancelActiveWork(returnToIdle: true)
                } label: {
                    Label(t("İptal", "Cancel"), systemImage: "xmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(QSSecondary())

                // Below Cancel so a late-loading ad never shifts the button.
                if AdMobService.isEnabled && !store.isPro && !AdFreePass.isActive {
                    NativeAdCard()
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

    private func review(plan: Binding<QuickSilenceEngine.CutPlan>, inputURL: URL) -> some View {
        ReviewScreen(
            inputURL: inputURL,
            plan: plan,
            waveform: analysis?.windowRMS ?? [],
            intensity: $cutIntensity,
            usesPresetSettings: cutSettings == QuickSilenceEngine.CutSettings(cutIntensity),
            preview: preview,
            language: appLanguage,
            exportProgress: exportProgress,
            saved: saved,
            saveError: saveError,
            saveNeedsSettings: saveNeedsSettings,
            fineTune: store.isPro ? .unlocked : (store.canOfferPro ? .locked : .hidden),
            onSave: startSave,
            onShare: startShare,
            onNewVideo: reset,
            onCancelExport: cancelExport,
            onFineTune: { if store.isPro { showsFineTune = true } else { showsPaywall = true } },
            onOpenSettings: openAppSettings
        )
        .onChange(of: plan.wrappedValue) {
            saved = false
            saveError = nil
            session.discardOutput()
        }
        .overlay(alignment: .top) {
            if let processingAdOverlay {
                ProcessingAdCountdownView(
                    state: processingAdOverlay,
                    language: appLanguage,
                    onSkip: skipProcessingAdBreak,
                    onRemoveAds: store.canOfferPro ? {
                        skipProcessingAdBreak()
                        showsPaywall = true
                    } : nil
                )
                .padding(8)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: processingAdOverlay)
    }

    // MARK: - Pick, import, analyze

    private func startPickedVideo(_ item: PhotosPickerItem) {
        cancelActiveWork(returnToIdle: false)
        endVideo()
        let jobID = UUID()
        activeJobID = jobID
        processingTask = Task { await handlePick(item, jobID: jobID) }
    }

    private func handlePick(_ item: PhotosPickerItem, jobID: UUID) async {
        applyProgress(0.02, t("Video içe aktarılıyor", "Importing video"), jobID: jobID)
        rewardedAd.preload()
        do {
            let inputURL = try await importVideo(item, jobID: jobID)
            guard isActive(jobID) else { return }
            try await analyzeAndReview(inputURL: inputURL, jobID: jobID)
        } catch {
            handleWorkError(error, jobID: jobID)
        }
    }

    private func startAutorunIfRequested() {
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        if env["CUTSENSE_SHOW_PAYWALL"] == "1" { showsPaywall = true }
        guard !didStartAutorun else { return }
        guard let path = env["CUTSENSE_AUTORUN_VIDEO_URL"], !path.isEmpty else { return }
        // Relative paths resolve against Documents so a device run can use a file copied in with devicectl.
        let inputURL = path.hasPrefix("/") ? URL(fileURLWithPath: path) : URL.documentsDirectory.appending(path: path)
        guard FileManager.default.fileExists(atPath: inputURL.path) else {
            phase = .failed(t("Test videosu bulunamadı.", "Test video was not found."))
            return
        }

        didStartAutorun = true
        let jobID = UUID()
        activeJobID = jobID
        processingTask = Task {
            do {
                applyProgress(0.04, t("Video hazır", "Video ready"), jobID: jobID)
                // Lets a screenshot catch the processing screen; the fixture analyzes in under a second.
                if let hold = Double(env["CUTSENSE_AUTORUN_HOLD_SECONDS"] ?? "") {
                    try await Task.sleep(for: .seconds(hold))
                }
                try await analyzeAndReview(inputURL: inputURL, jobID: jobID)
            } catch {
                handleWorkError(error, jobID: jobID)
            }
        }
        #endif
    }

    private func analyzeAndReview(inputURL: URL, jobID: UUID) async throws {
        session.begin(input: inputURL)
        let result = try await QuickSilenceEngine.analyze(url: inputURL, language: appLanguage) { update in
            applyProgress(0.4 + max(0, update.fraction - 0.08) / 0.10 * 0.6, update.title, jobID: jobID)
        }
        guard isActive(jobID) else { return }
        cutSettings = QuickSilenceEngine.CutSettings(cutIntensity)
        plan = try QuickSilenceEngine.plan(result, settings: cutSettings)
        analysis = result
        saved = false
        saveError = nil
        saveNeedsSettings = false
        phase = .review
        startResultAdBreakIfNeeded(jobID: jobID)
    }

    private func handleWorkError(_ error: Error, jobID: UUID) {
        guard isActive(jobID) else { return }
        if error is CancellationError {
            cancelActiveWork(returnToIdle: true)
            return
        }
        fail(userFacingMessage(for: error))
    }

    private func importVideo(_ item: PhotosPickerItem, jobID: UUID) async throws -> URL {
        let tracker = Task { @MainActor in
            while !Task.isCancelled {
                let download = importService.downloadProgress
                if download >= 0 {
                    applyProgress(0.02 + min(max(download, 0), 1) * 0.38, t("iCloud videosu indiriliyor", "Downloading iCloud video"), jobID: jobID)
                } else {
                    applyProgress(0.04, t("Video içe aktarılıyor", "Importing video"), jobID: jobID)
                }
                try? await Task.sleep(for: .milliseconds(350))
            }
        }

        await importService.importVideo(from: item)
        tracker.cancel()
        await tracker.value
        try Task.checkCancellation()
        guard isActive(jobID) else { throw CancellationError() }

        if let error = importService.error {
            throw ViewFailure(error.message(for: appLanguage))
        }
        guard let url = importService.importedVideoURL else {
            throw ViewFailure(t("Video yüklenemedi. Lütfen farklı bir dosya deneyin.", "Could not load the video. Try a different file."))
        }
        return url
    }

    /// Import fills 0...0.4 of the bar, analysis (which reports 0.08...0.18) the rest.
    private func applyProgress(_ fraction: Double, _ title: String, jobID: UUID) {
        // Analysis posts progress through detached tasks that can land after review opened.
        guard isActive(jobID), !isReview else { return }
        phase = .working(WorkingState(progress: min(max(fraction, 0), 1), title: title))
    }

    // MARK: - Review

    /// Intensity or fine-tune change: re-plan from the cached scan (no new analysis, no export).
    private func replan() {
        guard let analysis, case .review = phase else { return }
        do {
            plan = try QuickSilenceEngine.plan(analysis, settings: cutSettings)
        } catch {
            fail(userFacingMessage(for: error))
        }
    }

    private func startSave() {
        runExport { url in
            let result = await PhotosSaveService.saveVideo(at: url)
            session.discardOutput()
            switch result {
            case .success:
                saved = true
                scheduleReviewPrompt()
            case .failure(let error):
                saveError = String(format: t("Kaydedilemedi: %@", "Could not save: %@"), saveErrorMessage(for: error))
                saveNeedsSettings = (error as? PhotosSaveService.SaveError) == .permissionDenied
            }
        }
    }

    private func startShare() {
        runExport { url in
            ShareSheet.present(url) { session.discardOutput() }
        }
    }

    /// Exports the current plan into the session's single output slot, then hands it to `finish`.
    /// No ads may appear meanwhile: leaving the app kills the export.
    private func runExport(then finish: @escaping @MainActor (URL) async -> Void) {
        guard exportTask == nil, let plan, let inputURL = session.inputURL else { return }
        let size = (try? inputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let available = WorkFiles.availableBytes()  // 0 means the volume could not be read; don't block on that
        guard available == 0 || Double(available) >= Double(size) * 1.1 else {
            // Keep the review: the user can free space and retry without re-importing.
            saveError = t("Yeterli boş alan yok. Biraz yer açıp tekrar dene.", "Not enough free storage. Free up some space and try again.")
            saveNeedsSettings = false
            return
        }
        skipProcessingAdBreak()
        preview.pause()
        saveError = nil
        saveNeedsSettings = false
        exportProgress = 0
        UIApplication.shared.isIdleTimerDisabled = true
        let language = appLanguage
        exportTask = Task {
            defer {
                UIApplication.shared.isIdleTimerDisabled = false
                exportProgress = nil
                exportTask = nil
            }
            do {
                let result = try await QuickSilenceEngine.export(url: inputURL, plan: plan, language: language) { update in
                    if exportProgress != nil { exportProgress = max(0, (update.fraction - 0.28) / 0.72) }
                }
                // Register before any early return so the file can never be orphaned.
                session.setOutput(result.outputURL)
                guard !Task.isCancelled else {
                    session.discardOutput()
                    return
                }
                // Overlay stays up until `finish` returns so nothing can delete the file mid-save.
                await finish(result.outputURL)
            } catch {
                session.discardOutput()
                // Export failures stay on review so the user can retry or pick a softer setting.
                if !(error is CancellationError) { saveError = userFacingMessage(for: error) }
            }
        }
    }

    private func cancelExport() {
        exportTask?.cancel()
    }

    private func scheduleReviewPrompt() {
        let key = "review_prompt_version"
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        guard UserDefaults.standard.string(forKey: key) != version else { return }
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            guard !AdMobService.hasPresentedContent else { return }
            UserDefaults.standard.set(version, forKey: key)
            requestReview()
        }
    }

    // MARK: - Teardown

    /// Deletes this video's working files (never the user's original) and forgets its plan.
    private func endVideo() {
        exportTask?.cancel()
        session.end()
        importService.discardImport()
        preview.reset()
        analysis = nil
        plan = nil
        saved = false
        saveError = nil
        saveNeedsSettings = false
    }

    private func fail(_ message: String) {
        cancelActiveWork(returnToIdle: false)
        endVideo()
        activeJobID = nil
        phase = .failed(message)
    }

    private func reset() {
        cancelActiveWork(returnToIdle: false)
        endVideo()
        activeJobID = nil
        pickerItem = nil
        phase = .idle
        rewardedAd.preload()
    }

    private func cancelActiveWork(returnToIdle: Bool) {
        processingTask?.cancel()
        processingTask = nil
        skipProcessingAdBreak()
        importService.cancelImport()
        if returnToIdle {
            endVideo()
            activeJobID = nil
            pickerItem = nil
            phase = .idle
        }
    }

    // MARK: - Rewarded ad break

    /// Rewarded interstitial once per video, on first entry to review. The intro states the reward
    /// (24 h without banner ads) and offers Skip, as AdMob requires. Shown only if the ad is
    /// ready within 3 s and nothing (share sheet, alert, export) is in the way.
    private func startResultAdBreakIfNeeded(jobID: UUID) {
        guard AdMobService.isEnabled else { return }
        processingAdTask?.cancel()
        processingAdTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(850))
            guard !Task.isCancelled, isActive(jobID), isReview else { return }
            if !rewardedAd.isReady {
                Task { await rewardedAd.load() }
                for _ in 0..<15 where !rewardedAd.isReady {
                    try? await Task.sleep(for: .milliseconds(200))
                }
            }
            guard canShowResultAd(jobID: jobID) else { return }

            for number in stride(from: 3, through: 1, by: -1) {
                processingAdOverlay = ProcessingAdState(
                    countdown: number,
                    status: t(
                        "Kısa bir reklam izle, 24 saat banner reklam görme. İstemiyorsan atla.",
                        "Watch a short ad and get 24 hours without banner ads. Skip if you'd rather not."
                    ),
                    isOpening: false,
                    canSkip: true
                )
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, canShowResultAd(jobID: jobID) else {
                    processingAdOverlay = nil
                    return
                }
            }
            processingAdOverlay = nil
            preview.pause()
            let result = await rewardedAd.showIfAvailable()
            guard result.wasPresented else { return }
            if case .presented(rewarded: true) = result {
                AdFreePass.grantReward()
                processingAdOverlay = ProcessingAdState(
                    countdown: nil,
                    status: t("Teşekkürler! 24 saat banner reklam yok.", "Thanks! No banner ads for 24 hours."),
                    isOpening: false,
                    canSkip: false
                )
                try? await Task.sleep(for: .seconds(2.5))
                if !Task.isCancelled { processingAdOverlay = nil }
            }
        }
    }

    private func canShowResultAd(jobID: UUID) -> Bool {
        isActive(jobID) && isReview && isScreenVisible && rewardedAd.isReady && exportTask == nil
            && !showsPaywall && !AdMobService.hasPresentedContent
    }

    private func skipProcessingAdBreak() {
        processingAdTask?.cancel()
        processingAdTask = nil
        processingAdOverlay = nil
    }

    // MARK: - Helpers

    private func isActive(_ jobID: UUID) -> Bool {
        activeJobID == jobID && !Task.isCancelled
    }

    private var isWorking: Bool {
        if case .working = phase { return true }
        return false
    }

    private var isReview: Bool {
        if case .review = phase { return true }
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
            return viewError.message
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

private struct ViewFailure: Error {
    let message: String
    init(_ message: String) { self.message = message }
}

struct CutIntensityPicker: View {
    @Binding var selection: QuickSilenceEngine.CutIntensity
    let language: AppLanguage
    /// Replaces the preset description when set (e.g. an over-cutting warning).
    let hint: String?

    var body: some View {
        VStack(spacing: 8) {
            Picker(appText(language, "Kesim sertliği", "Cut intensity"), selection: $selection) {
                ForEach(QuickSilenceEngine.CutIntensity.allCases) { intensity in
                    Text(intensity.title(for: language)).tag(intensity)
                }
            }
            .pickerStyle(.segmented)

            Text(hint ?? selection.detail(for: language))
                .font(.caption)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .foregroundStyle(hint == nil ? .white.opacity(0.58) : .orange)
                .frame(minHeight: 18)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ProcessingAdCountdownView: View {
    let state: QuickSilenceView.ProcessingAdState
    let language: AppLanguage
    let onSkip: () -> Void
    /// Set only while Pro can be offered.
    let onRemoveAds: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
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
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if state.canSkip {
                    Button(action: onSkip) {
                        Text(appText(language, "Atla", "Skip"))
                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                            .lineLimit(1)
                            .fixedSize()
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.white.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityIdentifier("skipAdButton")
                }
            }
            if state.canSkip, let onRemoveAds {
                Button(action: onRemoveAds) {
                    Text(appText(language, "Reklamları kalıcı kaldır", "Remove ads forever"))
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(qsAccent, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .contentShape(Rectangle())
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(Color(red: 0.08, green: 0.09, blue: 0.11).opacity(0.96))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(.white.opacity(0.12)))
    }
}

struct QSPrimary: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline).padding(.vertical, 15)
            .frame(maxWidth: .infinity)
            .background(.white).foregroundStyle(.black)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

struct QSSecondary: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline).padding(.vertical, 14).frame(maxWidth: .infinity)
            .background(.white.opacity(0.08)).foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.14)))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}
