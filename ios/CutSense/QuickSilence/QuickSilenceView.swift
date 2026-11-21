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
    @State private var auditioner = CutAuditioner()
    @State private var analysis: QuickSilenceEngine.Analysis?
    @State private var plan: QuickSilenceEngine.CutPlan?
    // Balanced by default: over-cutting is the top complaint about silence removers.
    @AppStorage("cut_intensity") private var cutIntensity: QuickSilenceEngine.CutIntensity = .balanced
    // Pro fine-tune survives new videos until the user picks a level again.
    @AppStorage("finetune_active") private var finetuneActive = false
    @AppStorage("finetune_min_silence") private var finetuneMinSilence = 0.0
    @AppStorage("finetune_pad") private var finetunePad = 0.0
    @State private var presetLengths: [QuickSilenceEngine.CutIntensity: Double] = [:]
    @State private var sourceInfo: ReviewSourceInfo?
    @State private var analysisStarted: Date?
    @State private var cutSettings = QuickSilenceEngine.CutSettings(.balanced)
    @State private var exportProgress: Double?
    @State private var exportTask: Task<Void, Never>?
    @State private var saved = false
    /// An error, not text: it is localized when shown, so a language change re-renders it.
    @State private var saveError: Error?
    /// Set when iOS ends the background grace period, which cancels the export like the user would.
    @State private var exportExpired = false
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
        case failed(Error)
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
        observers(screen
            .toolbar { toolbarContent }
            .sheet(isPresented: $showsPaywall) { ProSheet(language: appLanguage) })
    }

    /// Split out of `body`: one long modifier chain exceeded the type checker's time limit.
    private var screen: some View {
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
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
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
                // The pill needs both an active offer and its price; without either, keep the PRO entry.
                if isIdle && store.canOfferPro && !(offers.active != nil && store.offerPrices != nil) {
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

    /// Fine-tune sheet and state observers; split from `body` so it type-checks in time.
    private func observers(_ content: some View) -> some View {
        content
        .sheet(isPresented: $showsFineTune) {
            FineTuneSheet(settings: cutSettings, preset: QuickSilenceEngine.CutSettings(cutIntensity), language: appLanguage) { newSettings in
                cutSettings = newSettings
                finetuneMinSilence = newSettings.minSilence
                finetunePad = newSettings.pad
                finetuneActive = newSettings != QuickSilenceEngine.CutSettings(cutIntensity)
                replan()
            }
        }
        .onChange(of: showsPaywall) { _, shown in
            if shown { auditioner.stop(); preview.pause() }
        }
        .onAppear {
            isScreenVisible = true
            autoPresentFlashIfPossible()  // back from Settings
        }
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
        // Cold launch: the earlier triggers run before StoreKit products load, when no offer can be sold yet.
        .onChange(of: store.offerPrices != nil) { _, _ in autoPresentFlashIfPossible() }
        .onChange(of: phaseKey) { _, key in
            // Long analyses must not let the screen lock.
            UIApplication.shared.isIdleTimerDisabled = key == 1 || exportTask != nil
            if key == 0 { autoPresentFlashIfPossible() }
        }
        .onChange(of: cutIntensity) { _, intensity in
            finetuneActive = false
            cutSettings = QuickSilenceEngine.CutSettings(intensity)
            replan()
        }
        .task {
            cutSettings = QuickSilenceEngine.CutSettings(cutIntensity)
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
                    Text(percentText(state.progress))
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
                .accessibilityValue(percentText(state.progress))
                .accessibilityAddTraits(.updatesFrequently)
                .padding(.bottom, 8)

                Text(t("CutSense'i açık tut. Videon bu iPhone'dan çıkmaz.", "Keep CutSense open. Your video stays on this iPhone."))
                    .monoText(.caption)
                    .foregroundStyle(Mono.C.text3)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                // Height reserved so Cancel doesn't jump when the estimate appears.
                Text(timeLeftText(progress: state.progress) ?? "")
                    .monoText(.caption)
                    .foregroundStyle(Mono.C.text3)
                    .frame(minHeight: 16)
                    .padding(.bottom, 12)

                Button(t("İptal", "Cancel")) {
                    cancelActiveWork(returnToIdle: true)
                }
                .buttonStyle(MonoTertiaryButtonStyle())
                // 28 pt keeps the native ad clear of Cancel (AdMob accidental-click policy).
                .padding(.bottom, 28)

                // Below Cancel so a late-loading ad never shifts the button.
                if AdMobService.isEnabled && !store.isPro && !AdFreePass.isActive {
                    NativeAdCard()
                }
            }
            .frame(maxWidth: .infinity)
            .transition(phaseTransition)

        case .failed(let error):
            VStack(spacing: 0) {
                Text(t("Bu video işlenemedi", "This video couldn't be processed"))
                    .monoText(.title)
                    .foregroundStyle(Mono.C.text)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 8)
                Text(userFacingMessage(for: error))
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

            MonoIntensityControl(selection: intensityBinding, language: appLanguage,
                                 hint: store.isPro && finetuneActive ? fineTuneHint : nil)
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
            intensity: intensityBinding,
            usesPresetSettings: cutSettings == QuickSilenceEngine.CutSettings(cutIntensity),
            preview: preview,
            auditioner: auditioner,
            language: appLanguage,
            exportProgress: exportProgress,
            saved: saved,
            saveError: saveError.map { userFacingMessage(for: $0) },
            saveNeedsSettings: saveNeedsSettings,
            fineTune: store.isPro ? .unlocked : (store.canOfferPro ? .locked : .hidden),
            sourceInfo: sourceInfo,
            presetLengths: presetLengths,
            onOpenPhotos: { if let url = URL(string: "photos-redirect://") { UIApplication.shared.open(url) } },
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

    /// Re-tapping the selected level clears a custom fine-tune (onChange can't see that tap).
    private var intensityBinding: Binding<QuickSilenceEngine.CutIntensity> {
        Binding(get: { cutIntensity }, set: { level in
            if level != cutIntensity { cutIntensity = level } else { resetFineTune() }
        })
    }

    private var fineTuneHint: String {
        t("Özel ince ayar. Sıfırlamak için bir seviye seç.", "Custom fine-tune. Pick a level to reset.")
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
        applyProgress(0.02, t("Video hazırlanıyor", "Preparing video"), jobID: jobID)
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
            phase = .failed(ViewFailure.testVideoMissing)
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
            applyProgress(0.1 + max(0, update.fraction - 0.08) / 0.10 * 0.9, update.title, jobID: jobID)
        }
        guard isActive(jobID) else { return }
        let info = await Self.sourceInfo(of: inputURL)
        guard isActive(jobID) else { return }
        sourceInfo = info
        cutSettings = QuickSilenceEngine.CutSettings(cutIntensity)
        if store.isPro, finetuneActive {
            cutSettings.minSilence = finetuneMinSilence
            cutSettings.pad = finetunePad
        }
        plan = try QuickSilenceEngine.plan(result, settings: cutSettings)
        analysis = result
        presetLengths = Dictionary(uniqueKeysWithValues: QuickSilenceEngine.CutIntensity.allCases.compactMap { level in
            (try? QuickSilenceEngine.plan(result, settings: .init(level)).outputDuration).map { (level, $0) }
        })
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
        fail(error)
    }

    private func importVideo(_ item: PhotosPickerItem, jobID: UUID) async throws -> URL {
        let started = Date.now
        let tracker = Task { @MainActor in
            while !Task.isCancelled {
                let download = importService.downloadProgress
                // Photos reports progress for local copies too, so the title stays neutral (iCloud can't be proven).
                if download >= 0, download < 1, Date.now.timeIntervalSince(started) > 3 {
                    applyProgress(0.02 + download * 0.07, t("Video hazırlanıyor", "Preparing video"), jobID: jobID)
                } else {
                    applyProgress(0.04, t("Video hazırlanıyor", "Preparing video"), jobID: jobID)
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
            if error == .loadFailed, (1...300_000_000).contains(WorkFiles.availableBytes()) {
                throw ViewFailure.importNoSpace
            }
            throw error
        }
        guard let url = importService.importedVideoURL else {
            throw ViewFailure.loadFailed
        }
        return url
    }

    /// Import fills 0...0.1 of the bar, analysis (which reports 0.08...0.18) the rest.
    private func applyProgress(_ fraction: Double, _ title: String, jobID: UUID) {
        // Analysis posts progress through detached tasks that can land after review opened.
        guard isActive(jobID), !isReview else { return }
        if fraction >= 0.1, analysisStarted == nil { analysisStarted = .now }
        phase = .working(WorkingState(progress: min(max(fraction, 0), 1), title: title))
    }

    /// Linear estimate over the analysis share of the bar; nil until it is worth showing.
    private func timeLeftText(progress: Double) -> String? {
        guard let analysisStarted, progress > 0.11 else { return nil }
        let elapsed = Date.now.timeIntervalSince(analysisStarted)
        let left = elapsed * (1 - progress) / (progress - 0.1)
        guard elapsed > 3, left > 5, left.isFinite else { return nil }
        return String(format: t("Yaklaşık %@ kaldı", "About %@ left"), timeString(left))
    }

    // MARK: - Review

    /// Intensity or fine-tune change: re-plan from the cached scan (no new analysis, no export).
    private func replan() {
        guard let analysis, case .review = phase else { return }
        do {
            let fresh = try QuickSilenceEngine.plan(analysis, settings: cutSettings)
            plan = plan.map(fresh.carryingRestored) ?? fresh
        } catch {
            fail(error)
        }
    }

    private func resetFineTune() {
        let preset = QuickSilenceEngine.CutSettings(cutIntensity)
        finetuneActive = false
        guard cutSettings != preset else { return }
        cutSettings = preset
        replan()
    }

    private func startSave() {
        guard exportTask == nil else { return }
        // The permission alert is its own window, invisible to the ad gate: end the ad break first.
        skipProcessingAdBreak()
        Task {
            // Ask before exporting: a denial used to throw the finished export away.
            guard await PhotosSaveService.ensureAddAccess() else {
                saveError = ViewFailure.photosAccessOff
                saveNeedsSettings = true
                return
            }
            runExport(then: saveToPhotos)
        }
    }

    /// The output stays in the session so Share after Save reuses it.
    private func saveToPhotos(_ url: URL) async {
        let result = await PhotosSaveService.saveVideo(at: url)
        switch result {
        case .success:
            saved = true
            OfferCenter.shared.noteSave()
            scheduleReviewPrompt()
        case .failure(let error):
            // Keep the finished export: a retry or Share reuses it instead of exporting again.
            saveError = ViewFailure.saveFailed(error)
            saveNeedsSettings = (error as? PhotosSaveService.SaveError) == .permissionDenied
        }
    }

    private func startShare() {
        runExport { url in
            ShareSheet.present(url) {}
        }
    }

    /// Exports the current plan into the session's single output slot, then hands it to `finish`.
    /// No ads may appear meanwhile: leaving the app can kill the export.
    private func runExport(then finish: @escaping @MainActor (URL) async -> Void) {
        guard exportTask == nil, let plan, let inputURL = session.inputURL else { return }
        // Already exported for this plan (any plan change discards it): hand it over directly.
        if let url = session.outputURL, FileManager.default.fileExists(atPath: url.path) {
            saveError = nil
            saveNeedsSettings = false
            auditioner.stop()
            preview.pause()
            // Overlay locks the controls: a plan change mid-save would delete the file being copied.
            exportProgress = 1
            exportTask = Task {
                await finish(url)
                exportProgress = nil
                exportTask = nil
            }
            return
        }
        let size = (try? inputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let available = WorkFiles.availableBytes()  // 0 means the volume could not be read; don't block on that
        guard available == 0 || Double(available) >= Double(size) * 1.1 else {
            // Keep the review: the user can free space and retry without re-importing.
            saveError = ViewFailure.exportNoSpace
            saveNeedsSettings = false
            return
        }
        skipProcessingAdBreak()
        auditioner.stop()
        preview.pause()
        saveError = nil
        saveNeedsSettings = false
        exportExpired = false
        exportProgress = 0
        UIApplication.shared.isIdleTimerDisabled = true
        let language = appLanguage
        exportTask = Task {
            // Leaving the app no longer kills the export outright; iOS grants a short grace period.
            let bg = UIApplication.shared.beginBackgroundTask {
                exportExpired = true
                exportTask?.cancel()
            }
            defer {
                UIApplication.shared.endBackgroundTask(bg)
                UIApplication.shared.isIdleTimerDisabled = false
                exportProgress = nil
                exportTask = nil
            }
            do {
                let result = try await QuickSilenceEngine.export(url: inputURL, plan: plan, language: language) { update in
                    // Monotonic: the compatibility fallback restarts the engine's fraction lower.
                    if let current = exportProgress { exportProgress = max(current, (update.fraction - 0.28) / 0.72) }
                }
                // Register before any early return so the file can never be orphaned.
                session.setOutput(result.outputURL)
                guard !Task.isCancelled else {
                    session.discardOutput()
                    if exportExpired { saveError = ViewFailure.backgroundStopped }
                    return
                }
                // Dated name for AirDrop/Files; the "cutsense-" prefix keeps it a managed file.
                var outputURL = result.outputURL
                let named = FileManager.default.temporaryDirectory.appending(path: "cutsense-\(Self.exportStamp()).mp4")
                try? FileManager.default.removeItem(at: named)
                if (try? FileManager.default.moveItem(at: outputURL, to: named)) != nil {
                    outputURL = named
                    session.setOutput(named)
                }
                // Overlay stays up until `finish` returns so nothing can delete the file mid-save.
                await finish(outputURL)
            } catch {
                session.discardOutput()
                // Export failures stay on review so the user can retry or pick a softer setting.
                if exportExpired { saveError = ViewFailure.backgroundStopped }
                else if !(error is CancellationError) { saveError = error }
            }
        }
    }

    /// Pixel size and bytes for the review's size estimate. (VideoMetadataService isn't in this target.)
    private static func sourceInfo(of url: URL) async -> ReviewSourceInfo? {
        guard let track = try? await AVURLAsset(url: url).loadTracks(withMediaType: .video).first,
              let (size, transform) = try? await track.load(.naturalSize, .preferredTransform) else { return nil }
        let rect = CGRect(origin: .zero, size: size).applying(transform)
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return ReviewSourceInfo(pixelSize: CGSize(width: abs(rect.width), height: abs(rect.height)), fileBytes: Int64(bytes))
    }

        private static func exportStamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: .now)
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
        auditioner.stop()
        auditioner = CutAuditioner()  // drops the previous video's thumbnails and player item
        analysis = nil
        plan = nil
        presetLengths = [:]
        sourceInfo = nil
        analysisStarted = nil
        saved = false
        saveError = nil
        saveNeedsSettings = false
    }

    private func fail(_ error: Error) {
        cancelActiveWork(returnToIdle: false)
        endVideo()
        activeJobID = nil
        phase = .failed(error)
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
        // A pass with > 48 h left can't honour "24 h without banners" (it is capped at 72 h).
        let passLeft = AdFreePass.expiry?.timeIntervalSinceNow ?? 0
        guard AdMobService.isEnabled, passLeft <= 48 * 3600 else { preview.autoplayOnce(); return }
        processingAdTask?.cancel()
        processingAdTask = Task { @MainActor in
            defer {
                if !Task.isCancelled, isActive(jobID), isReview, isScreenVisible, !AdMobService.hasPresentedContent {
                    preview.autoplayOnce()
                }
            }
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
            auditioner.stop()
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
            && !auditioner.isShowingOriginal && auditioner.activeID == nil  // user is listening
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

    /// "%45" in Turkish, "45%" elsewhere (shared key with the review stats).
    private func percentText(_ fraction: Double) -> String {
        String(format: t("%%%d", "%d%%"), Int(fraction * 100))
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
            return message(for: viewError)
        }
        if let importError = error as? VideoImportService.ImportError {
            return importError.message(for: appLanguage)
        }
        // QA-FIX: a damaged/unreadable file used to get "try a softer cut setting", which can't help.
        let domain = (error as NSError).domain
        if domain == AVFoundationErrorDomain || domain == NSOSStatusErrorDomain {
            return t("Bu dosya okunamadı. Bozuk olabilir ya da iOS bu biçimi açamıyor. Başka bir video dene.",
                     "This file could not be read. It may be damaged or in a format iOS can't open. Try another video.")
        }
        return t("Video işlenemedi. Lütfen farklı bir video veya daha yumuşak kesim ayarı dene.", "Could not process this video. Try another video or a softer cut setting.")
    }

    private func message(for failure: ViewFailure) -> String {
        switch failure {
        case .testVideoMissing: t("Test videosu bulunamadı.", "Test video was not found.")
        case .importNoSpace: t("Bu videoyu içe aktarmak için yeterli boş alan yok. Biraz yer açıp tekrar dene.",
                               "Not enough free storage to import this video. Free up some space and try again.")
        case .loadFailed: t("Video yüklenemedi. Lütfen farklı bir dosya deneyin.", "Could not load the video. Try a different file.")
        case .photosAccessOff: t("Fotoğraflar izni kapalı. Kaydetmek için Ayarlar'dan izin ver.", "Photos access is off. Allow it in Settings to save.")
        case .exportNoSpace: t("Yeterli boş alan yok. Biraz yer açıp tekrar dene.", "Not enough free storage. Free up some space and try again.")
        case .backgroundStopped: t("Uygulama arka plandayken video oluşturma durdu. Tekrar dene.",
                                   "Creating the video stopped while the app was in the background. Try again.")
        case .saveFailed(let error): String(format: t("Kaydedilemedi: %@", "Could not save: %@"), saveErrorMessage(for: error))
        }
    }

    private func saveErrorMessage(for error: Error) -> String {
        guard let saveError = error as? PhotosSaveService.SaveError else {
            return error.localizedDescription
        }
        return saveError.message(for: appLanguage)
    }
}

/// Kinds, not text: `userFacingMessage` localizes them when shown.
private enum ViewFailure: Error {
    case testVideoMissing, importNoSpace, loadFailed, photosAccessOff, exportNoSpace, backgroundStopped
    case saveFailed(Error)
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
