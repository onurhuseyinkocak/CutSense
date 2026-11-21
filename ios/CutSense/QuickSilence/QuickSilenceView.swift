import SwiftUI
import PhotosUI
import StoreKit
import UIKit
import AVFoundation

/// The entire app, one screen: pick a video → analyze → review the cuts → save or share.
/// Export runs only on Save/Share; no output file exists while reviewing.
struct QuickSilenceView: View {
    @State private var phase: Phase = .idle
    @State private var pickerItem: PhotosPickerItem?
    @State private var importService = VideoImportService()
    @StateObject private var rewardedAd = RewardedInterstitialAdController()
    @State private var store = ProStore.shared
    @State private var offers = OfferCenter.shared
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

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
            Mono.C.bg.ignoresSafeArea()

            if case .review = phase, let current = plan, let inputURL = session.inputURL {
                // Not Binding($plan): its force-unwrap crashes when New Video clears the plan while
                // the review screen is still updating on the way out.
                review(plan: Binding(get: { plan ?? current }, set: { if plan != nil { plan = $0 } }), inputURL: inputURL)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                    .transition(phaseTransition)
            } else {
                VStack(spacing: 0) {
                    Spacer(minLength: 8)
                    // Outside the phase switch so its identity (and animatable progress) survives updates.
                    SignalField(mode: signalMode)
                        .frame(minHeight: isIdle ? 96 : 64, maxHeight: isIdle ? 220 : 64)
                        .animation(.easeOut(duration: 0.4), value: workingProgress)
                        .monoEntrance(0)
                        .padding(.bottom, isIdle ? 28 : 12)
                    content
                    if !isIdle { Spacer(minLength: 0) }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .padding(.bottom, showsPersistentBanner ? AdBannerSlot.height + 8 : 0)
                .transition(phaseTransition)
            }

            if showsPersistentBanner {
                AdBannerSlot()
                    .background(Mono.C.bg)
                    .overlay(alignment: .top) {
                        Rectangle().fill(Mono.C.hairline).frame(height: 1)
                    }
            }
        }
        .animation(Mono.Motion.pick(Mono.Motion.smooth, reduce: reduceMotion), value: phaseKey)
        .sensoryFeedback(.impact(weight: .medium), trigger: pickerItem) { _, new in new != nil }
        .sensoryFeedback(.error, trigger: phaseKey) { _, new in new == 3 }
        // QA-FIX: same cap as the review screen; at AX sizes the home hero, hint and CTA clipped.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .preferredColorScheme(.dark)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                OfferPill(language: appLanguage) { showsPaywall = true }
                    .disabled(exportTask != nil)
            }
            ToolbarItem(placement: .topBarLeading) {
                if privacyOptionsRequired && !store.isPro {
                    privacyOptionsToolbarButton
                }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                if isIdle && store.canOfferPro && offers.active == nil {
                    Button { showsPaywall = true } label: {
                        proCapsuleLabel
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("CutSense Pro")
                    .accessibilityIdentifier("proCapsule")
                }
                NavigationLink {
                    SettingsScreen(urlsInUse: session.urlsInUse)
                } label: {
                    toolbarGlyph("gearshape")
                }
                .disabled(isWorking || exportTask != nil)
                .accessibilityLabel(t("Ayarlar", "Settings"))
                .accessibilityIdentifier("settingsButton")
            }
        }
        .sheet(isPresented: $showsPaywall) {
            ProSheet(language: appLanguage)
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
        // Flash offer: one automatic presentation per install, only on home/review when nothing else is up.
        .onChange(of: offers.active, initial: true) { _, _ in autoPresentFlashIfPossible() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { autoPresentFlashIfPossible() } }
        .onChange(of: phaseKey) { _, key in if key == 0 { autoPresentFlashIfPossible() } }
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

    /// `Phase` is not Equatable; this drives phase animations and the failed haptic.
    private var phaseKey: Int {
        switch phase {
        case .idle: 0
        case .working: 1
        case .review: 2
        case .failed: 3
        }
    }

    private var phaseTransition: AnyTransition {
        reduceMotion ? .opacity : AnyTransition(.blurReplace)
    }

    private var workingProgress: Double {
        if case .working(let state) = phase { return state.progress }
        return 0
    }

    private var signalMode: SignalField.Mode {
        switch phase {
        case .idle, .review: .demo
        case .working(let state): .scanning(progress: state.progress)
        case .failed: .flat
        }
    }

    private func toolbarGlyph(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(Mono.C.text)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }

    @ViewBuilder
    private var proCapsuleLabel: some View {
        let text = Text("PRO").monoText(.overline).bold().foregroundStyle(Mono.C.text)
        // iOS 26 already wraps toolbar items in a glass capsule; earlier versions need our own.
        if #available(iOS 26.0, *) {
            text
        } else {
            text
                .padding(.horizontal, 10)
                .frame(height: 26)
                .overlay(Capsule().strokeBorder(Mono.C.strong, lineWidth: 1))
        }
    }

    private var privacyOptionsToolbarButton: some View {
        Button {
            Task {
                await AdMobService.presentPrivacyOptions()
                privacyOptionsRequired = AdMobService.isPrivacyOptionsRequired
            }
        } label: {
            toolbarGlyph("hand.raised")
        }
        .accessibilityLabel(t("Gizlilik seçenekleri", "Privacy options"))
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .idle, .review:
            home
                .transition(phaseTransition)

        case .working(let state):
            VStack(spacing: 0) {
                VStack(spacing: 4) {
                    Text("\(Int(state.progress * 100))%")
                        .monoText(.numeralXL)
                        .foregroundStyle(Mono.C.text)
                        .contentTransition(.numericText(value: state.progress))
                        .animation(Mono.Motion.pick(Mono.Motion.smooth, reduce: reduceMotion), value: state.progress)
                    Text(state.title)
                        .monoText(.headline)
                        .foregroundStyle(Mono.C.text2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(state.title)
                .accessibilityValue("\(Int(state.progress * 100))%")
                .accessibilityAddTraits(.updatesFrequently)
                .padding(.bottom, 12)

                Button(t("İptal", "Cancel")) {
                    cancelActiveWork(returnToIdle: true)
                }
                .buttonStyle(MonoTertiaryButtonStyle())
                .padding(.bottom, 16)

                // Below Cancel so a late-loading ad never shifts the button.
                if AdMobService.isEnabled && !store.isPro && !AdFreePass.isActive {
                    NativeAdCard()
                }
            }
            .frame(maxWidth: .infinity)
            .transition(phaseTransition)

        case .failed(let message):
            VStack(spacing: 0) {
                Text(t("Bu video işlenemedi", "This video couldn't be processed"))
                    .monoText(.title)
                    .foregroundStyle(Mono.C.text)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 8)
                Text(message)
                    .monoText(.body)
                    .foregroundStyle(Mono.C.text2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 32)
                Button { reset() } label: {
                    MonoActionLabel(t("Tekrar Dene", "Try Again"), systemImage: "arrow.clockwise")
                }
                .buttonStyle(MonoPrimaryButtonStyle())
            }
            .frame(maxWidth: .infinity)
            .transition(phaseTransition)
        }
    }

    /// A Group, so its parts become siblings of the hero and the two Spacers split the free height.
    private var home: some View {
        Group {
            VStack(alignment: .leading, spacing: 0) {
                Text("CutSense")
                    .monoText(.overline)
                    .foregroundStyle(Mono.C.text3)
                    .padding(.bottom, 8)
                    .monoEntrance(1)
                Text(t("Sessizlik Kes", "Cut Silence"))
                    .monoText(.display)
                    .foregroundStyle(Mono.C.text)
                    .padding(.bottom, 8)
                    .monoEntrance(2)
                Text(t("Videondaki sessizlikleri ve duraklamaları otomatik kes.", "Automatically remove silence and long pauses from your video."))
                    .monoText(.body)
                    .foregroundStyle(Mono.C.text2)
                    .fixedSize(horizontal: false, vertical: true)
                    .monoEntrance(3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Color.clear.frame(height: 24)

            MonoIntensityControl(selection: $cutIntensity, language: appLanguage, hint: nil)
                .padding(.bottom, 16)
                .monoEntrance(4)

            VStack(spacing: 12) {
                // QA-FIX: .current hands over the original file; no Photos transcode (which failed intermittently).
                PhotosPicker(selection: $pickerItem, matching: .videos, preferredItemEncoding: .current, photoLibrary: .shared()) {
                    MonoActionLabel(t("Video Seç", "Choose Video"), systemImage: "plus")
                }
                .buttonStyle(MonoPrimaryButtonStyle())
                .accessibilityIdentifier("chooseVideoButton")

                Text(t("Ücretsiz · Filigransız · Cihazda", "Free · No watermark · On-device"))
                    .monoText(.overline)
                    .foregroundStyle(Mono.C.text3)
                    .frame(maxWidth: .infinity)
            }
            .monoEntrance(5)
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
                .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(Mono.Motion.pick(Mono.Motion.smooth, reduce: reduceMotion), value: processingAdOverlay)
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
                OfferCenter.shared.noteSave()
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
        guard AdMobService.isEnabled else { preview.autoplayOnce(); return }
        processingAdTask?.cancel()
        processingAdTask = Task { @MainActor in
            defer { if !Task.isCancelled, isActive(jobID), isReview, !AdMobService.hasPresentedContent { preview.autoplayOnce() } }
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

    private func autoPresentFlashIfPossible() {
        guard scenePhase == .active, isScreenVisible, isIdle || isReview, offers.active?.kind == .flash,
              !showsPaywall, !showsFineTune, exportTask == nil, processingAdOverlay == nil,
              !AdMobService.hasPresentedContent else { return }
        if offers.takeAutoPresent() { showsPaywall = true }  // ProSheet shows OfferPanel(.flash) while active
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
        // QA-FIX: a damaged/unreadable file used to get "try a softer cut setting", which can't help.
        let domain = (error as NSError).domain
        if domain == AVFoundationErrorDomain || domain == NSOSStatusErrorDomain {
            return t("Bu dosya okunamadı. Bozuk olabilir ya da iOS bu biçimi açamıyor. Başka bir video dene.",
                     "This file could not be read. It may be damaged or in a format iOS can't open. Try another video.")
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var thanksBounce = 0

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                ring

                VStack(alignment: .leading, spacing: 4) {
                    Text(appText(language, "Reklam arası", "Ad break"))
                        .monoText(.overline)
                        .foregroundStyle(Mono.C.text)
                    Text(state.status)
                        .monoText(.caption)
                        .foregroundStyle(Mono.C.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if state.canSkip {
                    Button(action: onSkip) {
                        // Visual 36 pt capsule inside a 44 pt hit area.
                        Text(appText(language, "Atla", "Skip"))
                            .font(.system(size: 15, weight: .semibold))
                            .lineLimit(1)
                            .fixedSize()
                            .foregroundStyle(Mono.C.text)
                            .padding(.horizontal, 16)
                            .frame(height: 36)
                            .background(Capsule().fill(Mono.C.elevated))
                            .overlay(Capsule().strokeBorder(Mono.C.hairline, lineWidth: 1))
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("skipAdButton")
                }
            }
            if state.canSkip, let onRemoveAds {
                Button(action: onRemoveAds) {
                    Text(appText(language, "Reklamları kalıcı kaldır", "Remove ads forever"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Capsule().fill(Mono.C.text))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Mono.C.raised.opacity(0.97), in: RoundedRectangle(cornerRadius: Mono.Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Mono.Radius.card, style: .continuous).strokeBorder(Mono.C.hairline, lineWidth: 1))
    }

    private var ring: some View {
        ZStack {
            Circle().strokeBorder(Mono.C.hairline, lineWidth: 2)
            if let countdown = state.countdown, countdown > 0 {
                // Re-keyed per tick so each second drains a fresh ring.
                CountdownTrim(animated: !reduceMotion).id(countdown)
                Text("\(countdown)")
                    .monoText(.numeralM)
                    .foregroundStyle(Mono.C.text)
                    .contentTransition(.numericText(countsDown: true))
            } else if state.isOpening {
                ProgressView().tint(Mono.C.text)
            } else {
                Image(systemName: "checkmark")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Mono.C.text)
                    .symbolEffect(.bounce, value: thanksBounce)
                    .onAppear { if !reduceMotion { thanksBounce += 1 } }
            }
        }
        .frame(width: 48, height: 48)
        .accessibilityHidden(state.countdown == nil)
    }

    private struct CountdownTrim: View {
        let animated: Bool
        @State private var remaining: CGFloat = 1

        var body: some View {
            Circle()
                .inset(by: 1)
                .trim(from: 0, to: remaining)
                .stroke(Mono.C.text, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .onAppear {
                    guard animated else { return }
                    withAnimation(.linear(duration: 1)) { remaining = 0 }
                }
        }
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
