import SwiftUI
import AVKit

let qsAccent = Color(red: 182 / 255, green: 243 / 255, blue: 92 / 255)

/// One player for the whole review. Plays the cut composition; if that item fails,
/// plays the original and seeks over every active cut (no extra file either way).
@MainActor @Observable
final class PreviewPlayer {
    @ObservationIgnored let player = AVPlayer()
    private(set) var usesFallback = false
    /// Counted, not a flag: a cancelled load can finish after its replacement started.
    private var activeLoads = 0
    var isLoading: Bool { activeLoads > 0 }
    @ObservationIgnored private var plan: QuickSilenceEngine.CutPlan?
    @ObservationIgnored private var fallbackURL: URL?
    @ObservationIgnored private var skipObserver: Any?
    /// Playhead in original-video seconds; only `PlayheadTimeline` reads it.
    private(set) var originalTime: Double = 0
    /// Keep ranges of the composition currently installed (not of a plan still loading).
    @ObservationIgnored private var installedKeepRanges: [ClosedRange<Double>] = []
    @ObservationIgnored private var clockObserver: Any?
    private var didAutoplay = false
    /// Autoplay asked for before the first item finished loading (Pro / no-ads path): play on install.
    private var autoplayPending = false

    init() {
        clockObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 20), queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated { self?.updateClock(time.seconds) }
        }
    }

    func load(url: URL, plan: QuickSilenceEngine.CutPlan, seekToOriginal: Double?) async {
        self.plan = plan
        activeLoads += 1
        defer { activeLoads -= 1 }
        if !usesFallback && !Self.forceFallback {
            if let item = try? await QuickSilenceEngine.makePreviewItem(url: url, plan: plan) {
                guard !Task.isCancelled else { return }
                player.replaceCurrentItem(with: item)
                installedKeepRanges = plan.keepRanges
                if await Self.becomesReady(item) {
                    if let seekToOriginal { seek(toOriginal: seekToOriginal) }
                    if autoplayPending { autoplayOnce() }
                    return
                }
            }
            guard !Task.isCancelled else { return }
        }
        usesFallback = true
        if fallbackURL != url {
            let pending = autoplayPending
            stop()
            autoplayPending = pending
            fallbackURL = url
            player.replaceCurrentItem(with: AVPlayerItem(url: url))
            skipObserver = player.addPeriodicTimeObserver(
                forInterval: CMTime(value: 1, timescale: 20), queue: .main
            ) { [weak self] time in
                MainActor.assumeIsolated { self?.skipActiveCut(at: time.seconds) }
            }
        }
        if let seekToOriginal { seek(toOriginal: seekToOriginal) }
        if autoplayPending { autoplayOnce() }
    }

    /// Row tap: one second before the cut, in whichever clock the player runs on.
    func seek(toOriginal t: Double) {
        guard let plan else { return }
        let target = usesFallback ? t : plan.outputTime(forOriginal: t)
        player.seek(to: CMTime(seconds: max(0, target - 1), preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero)
    }

    /// Waveform scrub: exact original time, in whichever clock the player runs on.
    func scrub(toOriginal t: Double) {
        guard let plan, !isLoading else { return }
        originalTime = t
        let target = usesFallback ? t : plan.outputTime(forOriginal: t)
        let tolerance = CMTime(seconds: 0.05, preferredTimescale: 600)
        player.seek(to: CMTime(seconds: max(0, target), preferredTimescale: 600),
                    toleranceBefore: tolerance, toleranceAfter: tolerance)
    }

    private func updateClock(_ t: Double) {
        guard t.isFinite, !isLoading else { return }
        let mapped = usesFallback ? t : Self.original(forOutput: t, keepRanges: installedKeepRanges)
        if abs(mapped - originalTime) > 0.01 { originalTime = mapped }
    }

    /// Composition clock → original clock: walk the keep ranges until `t` falls inside one.
    nonisolated static func original(forOutput t: Double, keepRanges: [ClosedRange<Double>]) -> Double {
        var elapsed = 0.0
        for range in keepRanges {
            let length = range.upperBound - range.lowerBound
            if t <= elapsed + length { return range.lowerBound + max(0, t - elapsed) }
            elapsed += length
        }
        return keepRanges.last?.upperBound ?? t
    }

    func pause() { player.pause() }

    /// Plays once per video, with sound, after the ad flow settled; replan reloads don't repeat it.
    func autoplayOnce() {
        guard !didAutoplay else { return }
        guard player.currentItem != nil else { autoplayPending = true; return }
        autoplayPending = false
        didAutoplay = true
        player.play()
    }

    /// Removes the observer and the item; the next video starts on the composition path again.
    func stop() {
        player.pause()
        didAutoplay = false
        autoplayPending = false
        if let skipObserver { player.removeTimeObserver(skipObserver) }
        skipObserver = nil
        fallbackURL = nil
        player.replaceCurrentItem(with: nil)
    }

    func reset() {
        stop()
        plan = nil
        usesFallback = false
    }

    private func skipActiveCut(at t: Double) {
        guard player.rate != 0, let plan,
              let cut = plan.cuts.first(where: { !$0.isRestored && t >= $0.range.lowerBound && t < $0.range.upperBound - 0.02 })
        else { return }
        player.seek(to: CMTime(seconds: cut.range.upperBound, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private static func becomesReady(_ item: AVPlayerItem) async -> Bool {
        for _ in 0..<100 where item.status == .unknown {
            try? await Task.sleep(for: .milliseconds(50))
        }
        return item.status == .readyToPlay
    }

    private static var forceFallback: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["CUTSENSE_FORCE_PREVIEW_FALLBACK"] == "1"
        #else
        false
        #endif
    }
}

/// Review before export: preview, waveform, stats, live intensity, cut list, Save/Share.
/// Cut list audition: Before plays the ORIGINAL around a cut on its own player (the edited
/// preview is never rebuilt); After plays the edited preview around the same point so the jump is heard.
@MainActor @Observable
final class CutAuditioner {
    enum Mode: Hashable { case before, after }

    @ObservationIgnored let original = AVPlayer()
    private(set) var activeID: Int?
    private(set) var mode: Mode = .before
    /// 0...1 through the audition window.
    private(set) var progress: Double = 0
    /// Original-clock playhead is inside the cut (Before only).
    private(set) var insideCut = false
    private(set) var thumbnails: [Int: CGImage] = [:]

    @ObservationIgnored private var url: URL?
    @ObservationIgnored private var observer: (player: AVPlayer, token: Any)?
    @ObservationIgnored private var window: ClosedRange<Double> = 0...0
    @ObservationIgnored private var cutRange: ClosedRange<Double> = 0...0

    var isShowingOriginal: Bool { activeID != nil && mode == .before }

    func prepare(url: URL) {
        guard self.url != url else { return }
        stop()
        self.url = url
        thumbnails = [:]
        original.replaceCurrentItem(with: AVPlayerItem(url: url))
    }

    func setMode(_ newMode: Mode, preview: PreviewPlayer) {
        guard newMode != mode else { return }
        stop(preview: preview)
        mode = newMode
    }

    /// Tap on a row: start, or stop when the same cut is already playing.
    func toggle(_ cut: QuickSilenceEngine.Cut, plan: QuickSilenceEngine.CutPlan, preview: PreviewPlayer) {
        if activeID == cut.id { stop(preview: preview); return }
        stop(preview: preview)
        cutRange = cut.range
        let player: AVPlayer
        switch mode {
        case .before:
            player = original
            window = max(0, cut.range.lowerBound - 1.5)...min(plan.duration, cut.range.upperBound + 1.0)
        case .after where preview.usesFallback:
            // Fallback preview runs on the original clock and skips active cuts itself.
            player = preview.player
            window = max(0, cut.range.lowerBound - 1.5)...min(plan.duration, cut.range.upperBound + 1.5)
        case .after:
            player = preview.player
            let jump = plan.outputTime(forOriginal: cut.range.lowerBound)
            // A kept pause still plays in the edit: hear all of it, then a beat.
            let kept = cut.isRestored ? cut.range.upperBound - cut.range.lowerBound : 0
            window = max(0, jump - 1.5)...min(plan.outputDuration, jump + kept + 1.5)
        }
        activeID = cut.id
        progress = 0
        insideCut = false
        preview.pause()
        original.pause()
        let token = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self] time in
            MainActor.assumeIsolated { self?.tick(time.seconds, preview: preview) }
        }
        observer = (player, token)
        player.seek(to: CMTime(seconds: window.lowerBound, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero) { finished in
            guard finished else { return }
            Task { @MainActor in player.play() }
        }
    }

    func stop(preview: PreviewPlayer? = nil) {
        if let observer {
            observer.player.removeTimeObserver(observer.token)
            observer.player.pause()
        }
        observer = nil
        original.pause()
        preview?.pause()
        activeID = nil
        progress = 0
        insideCut = false
    }

    private func tick(_ t: Double, preview: PreviewPlayer) {
        guard activeID != nil else { return }
        let span = max(window.upperBound - window.lowerBound, 0.01)
        progress = min(max((t - window.lowerBound) / span, 0), 1)
        insideCut = mode == .before && cutRange.contains(t)
        if t >= window.upperBound - 0.02 { stop(preview: preview) }
    }

    func thumbnail(for cut: QuickSilenceEngine.Cut) async {
        guard thumbnails[cut.id] == nil, let url else { return }
        guard let image = await Self.frame(url: url, at: cut.range.lowerBound), !Task.isCancelled else { return }
        thumbnails[cut.id] = image
    }

    /// Off the main actor; one small generator per row (rows load lazily, cancelled when scrolled away).
    nonisolated private static func frame(url: URL, at seconds: Double) async -> CGImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 168, height: 168)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)
        return try? await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image
    }
}

struct ReviewScreen: View {
    let inputURL: URL
    @Binding var plan: QuickSilenceEngine.CutPlan
    let waveform: [Float]
    @Binding var intensity: QuickSilenceEngine.CutIntensity
    let usesPresetSettings: Bool
    let preview: PreviewPlayer
    let language: AppLanguage
    let exportProgress: Double?
    let saved: Bool
    let saveError: String?
    let saveNeedsSettings: Bool
    let fineTune: FineTuneAccess
    let onSave: () -> Void
    let onShare: () -> Void
    let onNewVideo: () -> Void
    let onCancelExport: () -> Void
    let onFineTune: () -> Void
    let onOpenSettings: () -> Void

    enum FineTuneAccess { case hidden, locked, unlocked }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsCuts = false
    @State private var pendingSeek: Double?
    /// Display bars, computed once per waveform (never in `body`).
    @State private var bars: [Float] = []
    @State private var counted = false
    @State private var compacted = false
    @State private var showsSeal = false
    @State private var auditioner = CutAuditioner()

    private var isExporting: Bool { exportProgress != nil }

    var body: some View {
        VStack(spacing: 0) {
            videoStage
                .padding(.bottom, 10)

            timeline
                .padding(.bottom, 12)

            stats
                .padding(.bottom, 12)

            MonoIntensityControl(selection: $intensity, language: language, hint: hint)
                .disabled(isExporting)
                .padding(.bottom, 10)

            HStack(spacing: 8) {
                Button { showsCuts = true } label: {
                    Label(String(format: appText(language, "Kesimleri incele (%d)", "Review cuts (%d)"), plan.cuts.count),
                          systemImage: "list.bullet")
                }
                .accessibilityIdentifier("reviewCutsButton")
                .buttonStyle(MonoSecondaryButtonStyle())

                if fineTune != .hidden {
                    Button(action: onFineTune) {
                        Label(appText(language, "İnce ayar", "Fine-tune"),
                              systemImage: fineTune == .locked ? "lock.fill" : "slider.horizontal.3")
                    }
                    .accessibilityIdentifier("fineTuneButton")
                    .buttonStyle(MonoSecondaryButtonStyle())
                }
            }
            .disabled(isExporting)
            .padding(.bottom, 10)

            if let saveError {
                MonoNotice(
                    text: saveError,
                    systemImage: "exclamationmark.triangle",
                    actionTitle: saveNeedsSettings ? appText(language, "Ayarları Aç", "Open Settings") : nil,
                    action: saveNeedsSettings ? onOpenSettings : nil
                )
                .padding(.bottom, 10)
                .transition(.opacity)
            }

            HStack(spacing: 8) {
                Button(action: onSave) {
                    MonoActionLabel(saved ? appText(language, "Galeriye Kaydedildi", "Saved to Photos") : appText(language, "Galeriye Kaydet", "Save to Photos"),
                                    systemImage: saved ? "checkmark" : "arrow.down")
                }
                .accessibilityIdentifier("saveButton")
                .buttonStyle(MonoPrimaryButtonStyle(outlined: saved))
                .disabled(saved || isExporting)

                Button(action: onShare) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 17, weight: .semibold))
                }
                .buttonStyle(MonoSecondaryButtonStyle(height: 56))
                .frame(width: 56)
                .accessibilityLabel(appText(language, "Paylaş", "Share"))
                .disabled(isExporting)
            }
            .animation(Mono.Motion.pick(Mono.Motion.smooth, reduce: reduceMotion), value: saved)
            .padding(.bottom, 6)

            Button(appText(language, "Yeni Video", "New Video"), action: onNewVideo)
                .accessibilityIdentifier("newVideoButton")
                .buttonStyle(MonoTertiaryButtonStyle(color: saved ? Mono.C.text : Mono.C.text2))
                .frame(height: 40)
                .disabled(isExporting)
        }
        .animation(Mono.Motion.pick(Mono.Motion.smooth, reduce: reduceMotion), value: saveError)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .overlay {
            if let exportProgress {
                ExportOverlay(progress: exportProgress, language: language, onCancel: onCancelExport)
                    .transition(.opacity)
            }
        }
        .animation(Mono.Motion.fade, value: isExporting)
        .onAppear {
            if bars.isEmpty { bars = MonoWave.bars(from: waveform) }
            withAnimation(Mono.Motion.pick(Mono.Motion.smooth, reduce: reduceMotion).delay(0.15)) { counted = true }
        }
        .onChange(of: waveform) { bars = MonoWave.bars(from: waveform) }
        .sensoryFeedback(.impact(flexibility: .soft), trigger: counted) { _, new in new }
        .sensoryFeedback(.success, trigger: saved) { _, new in new }
        .sensoryFeedback(.error, trigger: saveError) { old, new in old == nil && new != nil }
        .task(id: saved) { await savedMoment() }
        .task(id: plan) {
            let seek = pendingSeek
            pendingSeek = nil
            await preview.load(url: inputURL, plan: plan, seekToOriginal: seek)
        }
        .sheet(isPresented: $showsCuts, onDismiss: {
            auditioner.stop(preview: preview)
        }) {
            CutListSheet(plan: $plan, bars: bars, language: language, auditioner: auditioner, preview: preview) { cut in
                pendingSeek = cut.range.lowerBound
                // The edited preview is about to be rebuilt; an After audition on it would jump.
                if auditioner.mode == .after { auditioner.stop(preview: preview) }
            }
            // Leaves the video above the sheet visible on a 16e, so an audition can be watched.
            .presentationDetents([.fraction(0.55), .large])
            .monoSheet()
            .onAppear { auditioner.prepare(url: inputURL) }
        }
    }

    // MARK: Sections

    private var videoStage: some View {
        VideoPlayer(player: auditioner.isShowingOriginal ? auditioner.original : preview.player)
            .frame(maxWidth: .infinity, minHeight: 220, maxHeight: .infinity)
            .background(Mono.C.raised)
            .clipShape(RoundedRectangle(cornerRadius: Mono.Radius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Mono.Radius.card, style: .continuous)
                    .strokeBorder(Mono.C.hairline, lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .bottom) {
                if auditioner.activeID != nil {
                    AuditionBadge(auditioner: auditioner, plan: plan, language: language)
                        .padding(10)
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }
            }
            .animation(Mono.Motion.fade, value: auditioner.activeID)
            .overlay {
                if preview.isLoading {
                    ProgressView().tint(.white).controlSize(.large)
                }
            }
            .overlay {
                if showsSeal {
                    MonoCheckSeal()
                        .transition(.opacity.animation(.easeOut(duration: 0.25)))
                        .allowsHitTesting(false)
                }
            }
            .layoutPriority(-1)
    }

    private var timeline: some View {
        VStack(spacing: 0) {
            Group {
                if bars.isEmpty {
                    Color.clear
                } else {
                    PlayheadTimeline(preview: preview, bars: bars, plan: plan, compacted: compacted)
                        .accessibilityLabel(appText(language, "Zaman çizelgesi", "Timeline"))
                }
            }
            .frame(height: 44)

            HStack {
                Text(timeString(0))
                Spacer()
                Text(timeString(compacted ? plan.outputDuration : plan.duration))
                    .contentTransition(.numericText())
            }
            .monoText(.overline)
            .foregroundStyle(Mono.C.text3)
            .frame(height: 14)
            .accessibilityHidden(true)
        }
    }

    private var stats: some View {
        let removedPercent = counted ? plan.removedPercent : 0
        let silence = counted ? plan.duration - plan.outputDuration : 0
        let newLength = counted ? plan.outputDuration : 0
        return HStack(alignment: .center, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text(String(format: appText(language, "%%%d", "%d%%"), removedPercent))
                    .monoText(.numeralL)
                    .foregroundStyle(Mono.C.text)
                    .contentTransition(.numericText(value: Double(removedPercent)))
                Text(appText(language, "kesildi", "removed"))
                    .monoText(.caption)
                    .foregroundStyle(Mono.C.text2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            divider
            timeStat(silence, appText(language, "sessizlik", "silence"))
            divider
            timeStat(newLength, appText(language, "yeni süre", "new length"))
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .animation(Mono.Motion.pick(Mono.Motion.smooth, reduce: reduceMotion), value: plan)
    }

    private var divider: some View {
        Rectangle().fill(Mono.C.hairline).frame(width: 1, height: 28)
    }

    /// The value stays its own `Text` with a plain `m:ss` label; UI tests read it.
    private func timeStat(_ seconds: Double, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(timeString(seconds))
                .monoText(.numeralM)
                .foregroundStyle(Mono.C.text)
                .contentTransition(.numericText())
            Text(label)
                .monoText(.caption)
                .foregroundStyle(Mono.C.text2)
        }
        .padding(.leading, 14)
        .frame(width: 104, alignment: .leading)
    }

    /// Saved: compact the waveform, then seal in 0.25 s, hold 0.7 s, out 0.25 s (≤ 1.2 s total).
    private func savedMoment() async {
        let motion = Mono.Motion.pick(Mono.Motion.smooth, reduce: reduceMotion)
        guard saved else {
            showsSeal = false
            withAnimation(motion) { compacted = false }
            return
        }
        withAnimation(motion) { compacted = true }
        withAnimation(.easeOut(duration: 0.25)) { showsSeal = true }
        try? await Task.sleep(for: .milliseconds(950))
        withAnimation(.easeOut(duration: 0.25)) { showsSeal = false }
    }

    private var hint: String? {
        let lowSpeech = intensity == .balanced && usesPresetSettings && plan.removedPercent > 50
        if lowSpeech {
            return appText(language, "Bu videonun çoğunda konuşma yok. CutSense en iyi konuşmalı videolarda çalışır.", "Most of this video has no speech. CutSense works best on talking videos.")
        }
        guard plan.removedPercent > 60, intensity != .balanced else { return nil }
        return appText(language, "Çok mu kesildi? Dengeli'yi dene.", "Too much cut? Try Balanced.")
    }
}

/// The only view that reads `preview.originalTime`, so the screen body does not re-run at 20 Hz.
private struct PlayheadTimeline: View {
    let preview: PreviewPlayer
    let bars: [Float]
    let plan: QuickSilenceEngine.CutPlan
    let compacted: Bool

    @State private var lastScrub: Double?
    @State private var edgeCrossings = 0

    var body: some View {
        WaveformTimeline(bars: bars, plan: plan, playhead: preview.originalTime, compacted: compacted) { t in
            if let lastScrub, crossesCutEdge(from: lastScrub, to: t) { edgeCrossings += 1 }
            lastScrub = t
            preview.scrub(toOriginal: t)
        }
        .sensoryFeedback(.selection, trigger: edgeCrossings)
    }

    private func crossesCutEdge(from a: Double, to b: Double) -> Bool {
        let (lo, hi) = (min(a, b), max(a, b))
        return plan.cuts.contains { cut in
            !cut.isRestored && [cut.range.lowerBound, cut.range.upperBound].contains { $0 > lo && $0 <= hi }
        }
    }
}

func timeString(_ seconds: Double) -> String {
    let s = Int(seconds.rounded())
    return String(format: "%d:%02d", s / 60, s % 60)
}

private struct CutListSheet: View {
    @Binding var plan: QuickSilenceEngine.CutPlan
    let bars: [Float]
    let language: AppLanguage
    let auditioner: CutAuditioner
    let preview: PreviewPlayer
    let onToggle: (QuickSilenceEngine.Cut) -> Void

    @State private var toggles = 0
    @State private var bulkChanges = 0
    @State private var auditions = 0

    private var longest: Double { plan.cuts.map { $0.range.upperBound - $0.range.lowerBound }.max() ?? 1 }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(String(format: appText(language, "%d kesim", "%d cuts"), plan.cuts.count))
                    .monoText(.title, size: 22)
                    .foregroundStyle(Mono.C.text)
                Spacer(minLength: 8)
                Text(String(format: appText(language, "%@ kesiliyor", "Removing %@"), timeString(plan.duration - plan.outputDuration)))
                    .monoText(.overline)
                    .foregroundStyle(Mono.C.text2)
                    .contentTransition(.numericText())
            }
            .lineLimit(1)
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 6)

            if !plan.cuts.isEmpty {
                Text(appText(language, "Duymak için bir duraklamaya dokun. Tutmak için kapat.", "Tap a pause to hear it. Turn it off to keep it."))
                    .monoText(.caption)
                    .foregroundStyle(Mono.C.text2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
            }

            if !bars.isEmpty {
                WaveformTimeline(bars: bars, plan: plan)
                    .frame(height: 28)
                    .padding(.horizontal, 20)
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
            }

            if plan.cuts.isEmpty {
                Spacer()
                Text(appText(language, "Kesilecek duraklama bulunamadı.", "No pauses to cut were found."))
                    .monoText(.body)
                    .foregroundStyle(Mono.C.text2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                Spacer()
            } else {
                HStack(spacing: 8) {
                    BeforeAfterControl(mode: Binding(get: { auditioner.mode }, set: { auditioner.setMode($0, preview: preview) }),
                                       language: language)
                    let allKept = plan.cuts.allSatisfy(\.isRestored)
                    let allCut = !plan.cuts.contains(where: \.isRestored)
                    Button(appText(language, "Tümünü tut", "Keep all")) { setAll(restored: true) }
                        .buttonStyle(MonoSecondaryButtonStyle(height: 40))
                        .disabled(allKept)
                        .opacity(allKept ? 0.35 : 1)
                        .accessibilityIdentifier("keepAllCutsButton")
                    Button(appText(language, "Tümünü kes", "Cut all")) { setAll(restored: false) }
                        .buttonStyle(MonoSecondaryButtonStyle(height: 40))
                        .disabled(allCut)
                        .opacity(allCut ? 0.35 : 1)
                        .accessibilityIdentifier("cutAllButton")
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 8)

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array($plan.cuts.enumerated()), id: \.element.id) { index, $cut in
                            row(index: index, cut: $cut)
                        }
                    }
                    .padding(.bottom, 16)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .sensoryFeedback(.selection, trigger: toggles)
        .sensoryFeedback(.selection, trigger: auditions)
        .sensoryFeedback(.impact(weight: .medium), trigger: bulkChanges)
    }

    private func row(index: Int, cut: Binding<QuickSilenceEngine.Cut>) -> some View {
        let value = cut.wrappedValue
        let state = value.isRestored ? appText(language, "Kalsın", "Keep") : appText(language, "Kes", "Cut")
        let length = value.range.upperBound - value.range.lowerBound
        let isActive = auditioner.activeID == value.id
        return HStack(spacing: 12) {
            Button {
                if !isActive { auditions += 1 }
                auditioner.toggle(value, plan: plan, preview: preview)
            } label: {
                HStack(spacing: 12) {
                    thumbnail(value, isActive: isActive)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Text("\(timeString(value.range.lowerBound)) – \(timeString(value.range.upperBound))")
                                .font(.system(size: 15, design: .monospaced))
                                .foregroundStyle(value.isRestored ? Mono.C.text3 : Mono.C.text)
                            Text(String(format: appText(language, "%.1f sn", "%.1fs"), length))
                                .monoText(.caption)
                                .foregroundStyle(Mono.C.text3)
                        }
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        // Duration bar (relative to the longest cut); while auditioning, the live progress.
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Mono.C.hairline)
                                Capsule()
                                    .fill(isActive ? Mono.C.text : (value.isRestored ? Mono.C.strong : Mono.C.text2))
                                    .frame(width: geo.size.width * (isActive ? auditioner.progress : length / max(longest, 0.01)))
                            }
                        }
                        .frame(height: 3)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(rowTitle(value))
            .accessibilityHint(isActive ? appText(language, "Durdurmak için dokun", "Tap to stop")
                                        : appText(language, "Dinlemek için dokun", "Tap to listen"))
            .accessibilityIdentifier("cutRow_\(value.id)")

            Toggle(isOn: Binding(
                get: { !cut.wrappedValue.isRestored },
                set: { cut.wrappedValue.isRestored = !$0; toggles += 1; onToggle(cut.wrappedValue) }
            )) {
                Text(state)
                    .monoText(.label)
                    .foregroundStyle(value.isRestored ? Mono.C.text2 : Mono.C.text)
            }
            .toggleStyle(MonoToggleStyle())
            .fixedSize()
            .accessibilityLabel(rowTitle(value))
            .accessibilityValue(state)
            .accessibilityIdentifier("cutToggle_\(value.id)")
        }
        .padding(.horizontal, 20)
        .frame(height: 76)
        .background(isActive ? Mono.C.raised : Color.clear)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Mono.C.hairline).frame(height: 1).padding(.horizontal, 20)
        }
    }

    private func thumbnail(_ cut: QuickSilenceEngine.Cut, isActive: Bool) -> some View {
        ZStack {
            Mono.C.raised
            if let image = auditioner.thumbnails[cut.id] {
                Image(decorative: image, scale: 3)
                    .resizable()
                    .scaledToFill()
                    .opacity(cut.isRestored ? 0.5 : 1)
            }
            if isActive {
                Color.black.opacity(0.45)
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Mono.C.text)
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Mono.C.hairline, lineWidth: 1))
        .task(id: cut.id) { await auditioner.thumbnail(for: cut) }
    }

    private func setAll(restored: Bool) {
        for index in plan.cuts.indices { plan.cuts[index].isRestored = restored }
        bulkChanges += 1
    }

    private func rowTitle(_ cut: QuickSilenceEngine.Cut) -> String {
        let length = cut.range.upperBound - cut.range.lowerBound
        return String(format: appText(language, "%@ – %@ · %.1f sn", "%@ – %@ · %.1fs"),
                      timeString(cut.range.lowerBound), timeString(cut.range.upperBound), length)
    }
}

/// Before = original around the cut, After = the edit around the same point.
private struct BeforeAfterControl: View {
    @Binding var mode: CutAuditioner.Mode
    let language: AppLanguage
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 2) {
            segment(.before, appText(language, "Önce", "Before"))
            segment(.after, appText(language, "Sonra", "After"))
        }
        .padding(2)
        .background(Capsule().strokeBorder(Mono.C.strong, lineWidth: 1))
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(appText(language, "Dinleme modu", "Listening mode"))
    }

    private func segment(_ value: CutAuditioner.Mode, _ title: String) -> some View {
        let selected = mode == value
        return Button {
            withAnimation(Mono.Motion.pick(Mono.Motion.snappy, reduce: reduceMotion)) { mode = value }
        } label: {
            Text(title)
                .monoText(.label)
                .foregroundStyle(selected ? Color.black : Mono.C.text2)
                .padding(.horizontal, 12)
                .frame(minWidth: 44, minHeight: 36)
                .background(Capsule().fill(selected ? Mono.C.text : Color.clear))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(value == .before ? "auditionBefore" : "auditionAfter")
    }
}

/// Over the video while auditioning: what happens to the pause being heard.
private struct AuditionBadge: View {
    let auditioner: CutAuditioner
    let plan: QuickSilenceEngine.CutPlan
    let language: AppLanguage

    var body: some View {
        let restored = plan.cuts.first { $0.id == auditioner.activeID }?.isRestored ?? false
        let text: String = {
            if auditioner.mode == .after { return appText(language, "Kesilmiş hâli", "Edited version") }
            if auditioner.insideCut {
                return restored ? appText(language, "Bu duraklama kalıyor", "This pause is kept")
                                : appText(language, "Bu duraklama kesilecek", "This pause will be cut")
            }
            return appText(language, "Orijinal", "Original")
        }()
        VStack(alignment: .leading, spacing: 6) {
            Text(text)
                .monoText(.label)
                .foregroundStyle(auditioner.insideCut ? Color.black : Mono.C.text)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill((auditioner.insideCut ? Color.black : Mono.C.text).opacity(0.25))
                    Capsule().fill(auditioner.insideCut ? Color.black : Mono.C.text)
                        .frame(width: geo.size.width * auditioner.progress)
                }
            }
            .frame(height: 2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: 240, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(auditioner.insideCut ? Mono.C.text : Color.black.opacity(0.7)))
        .accessibilityElement(children: .combine)
    }
}

/// Pro-only sliders; values apply when a drag ends so the preview rebuilds once.
struct FineTuneSheet: View {
    let settings: QuickSilenceEngine.CutSettings
    let language: AppLanguage
    let onCommit: (QuickSilenceEngine.CutSettings) -> Void

    @State private var draft: QuickSilenceEngine.CutSettings
    @State private var commits = 0

    init(settings: QuickSilenceEngine.CutSettings, language: AppLanguage, onCommit: @escaping (QuickSilenceEngine.CutSettings) -> Void) {
        self.settings = settings
        self.language = language
        self.onCommit = onCommit
        _draft = State(initialValue: settings)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(appText(language, "İnce ayar", "Fine-tune"))
                .monoText(.title, size: 22)
            slider(appText(language, "En kısa duraklama", "Minimum pause"),
                   caption: appText(language, "Bundan kısa duraklamalar kalır.", "Pauses shorter than this are kept."),
                   value: $draft.minSilence, range: 0.15...1.5)
            slider(appText(language, "Nefes payı", "Breathing room"),
                   caption: appText(language, "Her cümlenin etrafında bırakılan sessizlik.", "Silence left around each sentence."),
                   value: $draft.pad, range: 0.03...0.40)
            Spacer(minLength: 0)
        }
        .foregroundStyle(Mono.C.text)
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .sensoryFeedback(.impact(weight: .light), trigger: commits)
        .presentationDetents([.height(300)])
        .monoSheet()
    }

    private func slider(_ title: String, caption: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.system(size: 15, weight: .semibold))
                Spacer()
                Text(String(format: appText(language, "%.2f sn", "%.2fs"), value.wrappedValue))
                    .monoText(.numeralM)
                    .contentTransition(.numericText(value: value.wrappedValue))
                    .animation(Mono.Motion.snappy, value: value.wrappedValue)
            }
            Slider(value: value, in: range) { editing in
                if !editing { onCommit(draft); commits += 1 }
            }
            .tint(.white)
            Text(caption)
                .monoText(.caption)
                .foregroundStyle(Mono.C.text3)
                .lineLimit(2)
        }
    }
}

private struct ExportOverlay: View {
    let progress: Double
    let language: AppLanguage
    let onCancel: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false
    @State private var cancels = 0

    var body: some View {
        let percent = Int(progress * 100)
        ZStack {
            Mono.C.scrim.ignoresSafeArea()
            VStack(spacing: 0) {
                MonoProgressRing(progress: progress)
                    .overlay {
                        Text("\(percent)%")
                            .monoText(.numeralL)
                            .contentTransition(.numericText(value: Double(percent)))
                            .animation(Mono.Motion.smooth, value: percent)
                    }
                    .scaleEffect(shown || reduceMotion ? 1 : 0.92)
                    .opacity(shown ? 1 : 0)
                    .padding(.bottom, 24)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(appText(language, "Video oluşturuluyor", "Creating video"))
                    .accessibilityValue("\(percent)%")
                    .accessibilityAddTraits(.updatesFrequently)
                Text(appText(language, "Video oluşturuluyor", "Creating video"))
                    .monoText(.headline)
                    .padding(.bottom, 4)
                    .accessibilityHidden(true)
                Text(appText(language, "Uygulamayı açık tut.", "Keep the app open."))
                    .monoText(.caption)
                    .foregroundStyle(Mono.C.text2)
                    .padding(.bottom, 16)
                Button(appText(language, "İptal", "Cancel")) {
                    cancels += 1
                    onCancel()
                }
                .buttonStyle(MonoTertiaryButtonStyle())
            }
            .foregroundStyle(Mono.C.text)
        }
        .sensoryFeedback(.impact(weight: .light), trigger: cancels)
        .onAppear {
            withAnimation(Mono.Motion.pick(Mono.Motion.smooth, reduce: reduceMotion)) { shown = true }
        }
    }
}
