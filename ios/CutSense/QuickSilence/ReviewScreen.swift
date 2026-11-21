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

    func load(url: URL, plan: QuickSilenceEngine.CutPlan, seekToOriginal: Double?) async {
        self.plan = plan
        activeLoads += 1
        defer { activeLoads -= 1 }
        if !usesFallback && !Self.forceFallback {
            if let item = try? await QuickSilenceEngine.makePreviewItem(url: url, plan: plan) {
                guard !Task.isCancelled else { return }
                player.replaceCurrentItem(with: item)
                if await Self.becomesReady(item) {
                    if let seekToOriginal { seek(toOriginal: seekToOriginal) }
                    return
                }
            }
            guard !Task.isCancelled else { return }
        }
        usesFallback = true
        if fallbackURL != url {
            stop()
            fallbackURL = url
            player.replaceCurrentItem(with: AVPlayerItem(url: url))
            skipObserver = player.addPeriodicTimeObserver(
                forInterval: CMTime(value: 1, timescale: 20), queue: .main
            ) { [weak self] time in
                MainActor.assumeIsolated { self?.skipActiveCut(at: time.seconds) }
            }
        }
        if let seekToOriginal { seek(toOriginal: seekToOriginal) }
    }

    /// Row tap: one second before the cut, in whichever clock the player runs on.
    func seek(toOriginal t: Double) {
        guard let plan else { return }
        let target = usesFallback ? t : plan.outputTime(forOriginal: t)
        player.seek(to: CMTime(seconds: max(0, target - 1), preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func pause() { player.pause() }

    /// Removes the observer and the item; the next video starts on the composition path again.
    func stop() {
        player.pause()
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

/// Review before export: preview, stats, live intensity, cut list, Save/Share.
struct ReviewScreen: View {
    let inputURL: URL
    @Binding var plan: QuickSilenceEngine.CutPlan
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

    @State private var showsCuts = false
    @State private var pendingSeek: Double?

    private var isExporting: Bool { exportProgress != nil }

    var body: some View {
        VStack(spacing: 14) {
            VideoPlayer(player: preview.player)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay {
                    if preview.isLoading {
                        ProgressView().tint(.white).controlSize(.large)
                    }
                }
                .layoutPriority(-1)

            CutStrip(plan: plan)
                .frame(height: 8)

            HStack(spacing: 0) {
                stat(String(format: appText(language, "%%%d", "%d%%"), plan.removedPercent), appText(language, "kesildi", "removed"))
                stat(timeString(plan.duration - plan.outputDuration), appText(language, "sessizlik", "silence"))
                stat(timeString(plan.outputDuration), appText(language, "yeni süre", "new length"))
            }

            CutIntensityPicker(selection: $intensity, language: language, hint: hint)
                .disabled(isExporting)

            HStack(spacing: 10) {
                Button { showsCuts = true } label: {
                    Label(String(format: appText(language, "Kesimleri incele (%d)", "Review cuts (%d)"), plan.cuts.count),
                          systemImage: "list.bullet")
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
                .accessibilityIdentifier("reviewCutsButton")
                .buttonStyle(QSSecondary())

                if fineTune != .hidden {
                    Button(action: onFineTune) {
                        Label(appText(language, "İnce ayar", "Fine-tune"),
                              systemImage: fineTune == .locked ? "lock.fill" : "slider.horizontal.3")
                            .lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .accessibilityIdentifier("fineTuneButton")
                    .buttonStyle(QSSecondary())
                }
            }
            .disabled(isExporting)

            if let saveError {
                HStack(spacing: 10) {
                    Text(saveError).font(.caption).foregroundStyle(.orange).lineLimit(2)
                    if saveNeedsSettings {
                        Button(appText(language, "Ayarları Aç", "Open Settings"), action: onOpenSettings)
                            .font(.caption.weight(.bold)).foregroundStyle(.white)
                    }
                }
            }

            Button(action: onSave) {
                Label(saved ? appText(language, "Galeriye Kaydedildi", "Saved to Photos") : appText(language, "Galeriye Kaydet", "Save to Photos"),
                      systemImage: saved ? "checkmark.circle.fill" : "square.and.arrow.down")
            }
            .accessibilityIdentifier("saveButton")
            .buttonStyle(QSPrimary())
            .disabled(saved || isExporting)

            HStack(spacing: 10) {
                Button(action: onShare) {
                    Label(appText(language, "Paylaş", "Share"), systemImage: "square.and.arrow.up")
                }
                .buttonStyle(QSSecondary())
                Button(appText(language, "Yeni Video", "New Video"), action: onNewVideo)
                    .accessibilityIdentifier("newVideoButton")
                    .buttonStyle(QSSecondary())
            }
            .disabled(isExporting)
        }
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .overlay {
            if let exportProgress {
                ExportOverlay(progress: exportProgress, language: language, onCancel: onCancelExport)
            }
        }
        .task(id: plan) {
            let seek = pendingSeek
            pendingSeek = nil
            await preview.load(url: inputURL, plan: plan, seekToOriginal: seek)
        }
        .sheet(isPresented: $showsCuts) {
            CutListSheet(plan: $plan, language: language) { cut in
                preview.seek(toOriginal: cut.range.lowerBound)
            } onToggle: { cut in
                pendingSeek = cut.range.lowerBound
            }
            .presentationDetents([.medium, .large])
        }
    }

    private var hint: String? {
        let lowSpeech = intensity == .balanced && usesPresetSettings && plan.removedPercent > 50
        if lowSpeech {
            return appText(language, "Bu videonun çoğunda konuşma yok. CutSense en iyi konuşmalı videolarda çalışır.", "Most of this video has no speech. CutSense works best on talking videos.")
        }
        guard plan.removedPercent > 60, intensity != .balanced else { return nil }
        return appText(language, "Çok mu kesildi? Dengeli'yi dene.", "Too much cut? Try Balanced.")
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(.title3, design: .rounded).weight(.bold)).foregroundStyle(.white)
                .monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity)
    }
}

func timeString(_ seconds: Double) -> String {
    let s = Int(seconds.rounded())
    return String(format: "%d:%02d", s / 60, s % 60)
}

/// Passive bar: kept time bright, removed time dark.
private struct CutStrip: View {
    let plan: QuickSilenceEngine.CutPlan

    var body: some View {
        GeometryReader { geo in
            let scale = plan.duration > 0 ? geo.size.width / plan.duration : 0
            ZStack(alignment: .leading) {
                Capsule().fill(qsAccent)
                ForEach(plan.cuts.filter { !$0.isRestored }) { cut in
                    Rectangle()
                        .fill(Color(white: 0.16))
                        .frame(width: max(1, (cut.range.upperBound - cut.range.lowerBound) * scale))
                        .offset(x: cut.range.lowerBound * scale)
                }
            }
            .clipShape(Capsule())
        }
        .accessibilityHidden(true)
    }
}

private struct CutListSheet: View {
    @Binding var plan: QuickSilenceEngine.CutPlan
    let language: AppLanguage
    let onSelect: (QuickSilenceEngine.Cut) -> Void
    let onToggle: (QuickSilenceEngine.Cut) -> Void

    var body: some View {
        NavigationStack {
            List($plan.cuts) { $cut in
                HStack {
                    Button { onSelect(cut) } label: {
                        Text(rowTitle(cut))
                            .monospacedDigit()
                            .foregroundStyle(cut.isRestored ? .white.opacity(0.5) : .white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Toggle(isOn: Binding(
                        get: { !cut.isRestored },
                        set: { cut.isRestored = !$0; onToggle(cut) }
                    )) {
                        Text(cut.isRestored ? appText(language, "Kalsın", "Keep") : appText(language, "Kes", "Cut"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(cut.isRestored ? .white.opacity(0.6) : qsAccent)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .tint(qsAccent)
                    .fixedSize()
                    .accessibilityLabel(rowTitle(cut))
                    .accessibilityValue(cut.isRestored ? appText(language, "Kalsın", "Keep") : appText(language, "Kes", "Cut"))
                    .accessibilityIdentifier("cutToggle_\(cut.id)")
                }
            }
            .overlay {
                if plan.cuts.isEmpty {
                    Text(appText(language, "Kesilecek duraklama bulunamadı.", "No pauses to cut were found."))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .navigationTitle(String(format: appText(language, "%d kesim", "%d cuts"), plan.cuts.count))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !plan.cuts.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(appText(language, "Tümünü tut", "Keep all")) { setAll(restored: true) }
                            .disabled(plan.cuts.allSatisfy(\.isRestored))
                            .accessibilityIdentifier("keepAllCutsButton")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(appText(language, "Tümünü kes", "Cut all")) { setAll(restored: false) }
                            .disabled(!plan.cuts.contains(where: \.isRestored))
                            .accessibilityIdentifier("cutAllButton")
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func setAll(restored: Bool) {
        for index in plan.cuts.indices { plan.cuts[index].isRestored = restored }
    }

    private func rowTitle(_ cut: QuickSilenceEngine.Cut) -> String {
        let length = cut.range.upperBound - cut.range.lowerBound
        return String(format: appText(language, "%@ – %@ · %.1f sn", "%@ – %@ · %.1fs"),
                      timeString(cut.range.lowerBound), timeString(cut.range.upperBound), length)
    }
}

/// Pro-only sliders; values apply when a drag ends so the preview rebuilds once.
struct FineTuneSheet: View {
    let settings: QuickSilenceEngine.CutSettings
    let language: AppLanguage
    let onCommit: (QuickSilenceEngine.CutSettings) -> Void

    @State private var draft: QuickSilenceEngine.CutSettings

    init(settings: QuickSilenceEngine.CutSettings, language: AppLanguage, onCommit: @escaping (QuickSilenceEngine.CutSettings) -> Void) {
        self.settings = settings
        self.language = language
        self.onCommit = onCommit
        _draft = State(initialValue: settings)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(appText(language, "İnce ayar", "Fine-tune"))
                .font(.system(.title3, design: .rounded).weight(.bold))
            slider(appText(language, "En kısa duraklama", "Minimum pause"), value: $draft.minSilence, range: 0.15...1.5)
            slider(appText(language, "Nefes payı", "Breathing room"), value: $draft.pad, range: 0.03...0.40)
        }
        .padding(24)
        .preferredColorScheme(.dark)
        .presentationDetents([.height(240)])
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.subheadline.weight(.semibold))
                Spacer()
                Text(String(format: appText(language, "%.2f sn", "%.2fs"), value.wrappedValue))
                    .font(.subheadline).monospacedDigit().foregroundStyle(.white.opacity(0.7))
            }
            Slider(value: value, in: range) { editing in
                if !editing { onCommit(draft) }
            }
            .tint(qsAccent)
        }
    }
}

private struct ExportOverlay: View {
    let progress: Double
    let language: AppLanguage
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.78).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView(value: progress).tint(qsAccent).frame(maxWidth: 240)
                Text(appText(language, "Video oluşturuluyor", "Creating video"))
                    .font(.system(.headline, design: .rounded).weight(.bold))
                Text("\(Int(progress * 100))%")
                    .font(.system(.title3, design: .rounded).weight(.semibold)).monospacedDigit()
                Text(appText(language, "Uygulamayı açık tut.", "Keep the app open."))
                    .font(.footnote).foregroundStyle(.white.opacity(0.6))
                Button(appText(language, "İptal", "Cancel"), action: onCancel)
                    .buttonStyle(QSSecondary())
                    .frame(maxWidth: 200)
            }
            .foregroundStyle(.white)
        }
    }
}
