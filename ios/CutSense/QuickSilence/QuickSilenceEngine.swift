import AVFoundation
import UIKit

/// The whole app: take a video, remove the silent parts, export the result.
/// Reuses the proven RMS/dB silence detection in `AudioAnalysisService`, then
/// rebuilds the video+audio keeping only the non-silent ranges.
enum QuickSilenceEngine {
    enum CutIntensity: String, CaseIterable, Identifiable, Sendable {
        case balanced
        case tight
        case hardcore

        var id: String { rawValue }

        var title: String {
            title(for: .tr)
        }

        var detail: String {
            detail(for: .tr)
        }

        func title(for language: AppLanguage) -> String {
            switch self {
            case .balanced:
                appText(language, "Dengeli", "Balanced")
            case .tight:
                appText(language, "Sıkı", "Tight")
            case .hardcore:
                appText(language, "Hardcore", "Hardcore")
            }
        }

        func detail(for language: AppLanguage) -> String {
            switch self {
            case .balanced:
                appText(language, "Önerilen. Konuşmanın etrafında doğal boşluk bırakır.", "Recommended. Keeps natural space around speech.")
            case .tight:
                appText(language, "Daha sıkı kesim, daha hızlı tempo.", "Tighter cut, faster pace.")
            case .hardcore:
                appText(language, "Nefes ve arka plan boşluğunu en agresif keser.", "Cuts breaths and background gaps most aggressively.")
            }
        }

        var analysisOptions: AudioAnalysisOptions {
            switch self {
            case .balanced: .balanced
            case .tight: .tight
            case .hardcore: .hardcore
            }
        }

        var padSeconds: Double {
            switch self {
            case .balanced: 0.16
            case .tight: 0.09
            case .hardcore: 0.06
            }
        }

        var mergeGap: Double {
            switch self {
            case .balanced: 0.28
            case .tight: 0.12
            case .hardcore: 0.06
            }
        }

        var finalMinimumRemovedGap: Double {
            switch self {
            case .balanced: 0.18
            case .tight: 0.10
            case .hardcore: 0.06
            }
        }
    }

    struct ProgressUpdate: Sendable {
        enum Stage: String, Sendable, Equatable {
            case importing
            case analyzingAudio
            case planningCuts
            case buildingTimeline
            case exporting
            case fallbackExport
            case verifying
            case done
        }

        let stage: Stage
        let fraction: Double
        let title: String
        let detail: String

        static func update(_ stage: Stage, _ fraction: Double, _ title: String, _ detail: String) -> ProgressUpdate {
            ProgressUpdate(stage: stage, fraction: min(max(fraction, 0), 1), title: title, detail: detail)
        }
    }

    struct Result: Sendable {
        let id = UUID()
        let outputURL: URL
        let originalDuration: Double
        let outputDuration: Double
        var removedDuration: Double { max(0, originalDuration - outputDuration) }
        var removedPercent: Int {
            guard originalDuration > 0 else { return 0 }
            return Int((removedDuration / originalDuration * 100).rounded())
        }
        let segmentsKept: Int
    }

    enum Failure: LocalizedError {
        case noVideoTrack
        case noAudioTrack
        case nothingToKeep
        case timelineInsertFailed(String)
        case outputEmpty(Int64)
        case exportFailed(String)
        var errorDescription: String? {
            message(for: .tr)
        }

        func message(for language: AppLanguage) -> String {
            switch self {
            case .noVideoTrack:
                appText(language, "Bu dosyada video bulunamadı.", "No video track was found in this file.")
            case .noAudioTrack:
                appText(language, "Bu videoda ses bulunamadı. Konuşma içeren bir video seç.", "This video has no audio. Choose a video with speech.")
            case .nothingToKeep:
                appText(language, "Konuşma bulunamadı. Video sessiz ya da sadece arka plan gürültüsü olabilir.", "No speech was found. The video may be silent or only background noise.")
            case .timelineInsertFailed(let message):
                String(format: appText(language, "Video zaman çizgisi kurulamadı: %@", "Could not build the video timeline: %@"), message)
            case .outputEmpty(let bytes):
                String(format: appText(language, "Video oluşturuldu ama dosya boş görünüyor (%lld bayt).", "The video was created, but the output file looks empty (%lld bytes)."), bytes)
            case .exportFailed:
                appText(
                    language,
                    "Dışa aktarım tamamlanamadı. Uzun video işlenirken iOS export motoru çıktı veremedi; aynı videoyu tekrar dene veya daha kısa bir video seç.",
                    "Export could not finish. The iOS export engine did not produce an output while processing this long video; try the same video again or choose a shorter video."
                )
            }
        }
    }

    /// Per-intensity knobs for `plan`. `minCutLength` folds the old `merged(gap:)` pass in,
    /// so every listed cut is one that is really removed.
    struct CutSettings: Sendable, Equatable {
        var minSilence: Double
        var pad: Double
        var minCutLength: Double
        var thresholdFallbackDB: Float

        init(_ intensity: CutIntensity) {
            minSilence = intensity.analysisOptions.minSilenceDuration
            pad = intensity.padSeconds
            minCutLength = max(intensity.finalMinimumRemovedGap, intensity.mergeGap)
            thresholdFallbackDB = intensity.analysisOptions.silenceThresholdDB
        }
    }

    /// Intensity-independent audio scan; re-planning with new settings needs no new scan.
    struct Analysis: Sendable {
        let windowRMS: [Float]
        let duration: Double
    }

    struct Cut: Identifiable, Sendable, Equatable {
        let id: Int
        let range: ClosedRange<Double>
        var isRestored: Bool
    }

    struct CutPlan: Sendable, Equatable {
        let duration: Double
        var cuts: [Cut]

        private var activeCuts: [ClosedRange<Double>] { cuts.filter { !$0.isRestored }.map(\.range) }

        var keepRanges: [ClosedRange<Double>] { QuickSilenceEngine.keepRanges(silence: activeCuts, duration: duration) }

        var outputDuration: Double { keepRanges.reduce(0) { $0 + $1.upperBound - $1.lowerBound } }

        var removedPercent: Int {
            guard duration > 0 else { return 0 }
            return Int(((duration - outputDuration) / duration * 100).rounded())
        }

        /// Where original time `t` lands in the cut output; a time inside a removed cut maps to the jump point.
        func outputTime(forOriginal t: Double) -> Double {
            let removedBefore = activeCuts.reduce(0) { sum, cut in
                sum + max(0, min(t, cut.upperBound) - cut.lowerBound)
            }
            return min(max(t, 0), duration) - removedBefore
        }
    }

    static func analyze(
        url: URL,
        language: AppLanguage,
        progress: @escaping @MainActor (ProgressUpdate) -> Void
    ) async throws -> Analysis {
        await progress(.update(
            .analyzingAudio,
            0.08,
            appText(language, "Ses haritası çıkarılıyor", "Mapping audio"),
            appText(language, "Konuşma ve sessizlik pencereleri cihaz üstünde taranıyor.", "Speech and silence windows are scanned on device.")
        ))
        let result = try await AudioAnalysisService.analyze(url: url) { processedSeconds, duration in
            let audioFraction = duration > 0 ? min(max(processedSeconds / duration, 0), 1) : 0
            Task { @MainActor in
                progress(.update(
                    .analyzingAudio,
                    0.08 + audioFraction * 0.10,
                    appText(language, "Ses taranıyor", "Scanning audio"),
                    String(
                        format: appText(language, "%@ / %@ ses penceresi işlendi.", "%@ / %@ of audio processed."),
                        compactTime(processedSeconds, language: language), compactTime(duration, language: language)
                    )
                ))
            }
        }
        return Analysis(windowRMS: result.segments.map(\.energy), duration: result.duration)
    }

    static func plan(_ analysis: Analysis, settings: CutSettings) throws -> CutPlan {
        let duration = analysis.duration
        let threshold = AudioAnalysisService.silenceThreshold(windowRMS: analysis.windowRMS, fallback: settings.thresholdFallbackDB)
        let classified = AudioAnalysisService.classify(
            windowRMS: analysis.windowRMS,
            thresholdDB: threshold,
            minSilence: settings.minSilence,
            duration: duration
        )
        guard classified.segments.contains(where: { $0.type == .speech || $0.type == .clipping }) else {
            throw Failure.nothingToKeep
        }
        let ranges = protectedCutRanges(
            silence: classified.silenceIntervals,
            pad: settings.pad,
            minimumRemovedGap: settings.minCutLength,
            duration: duration
        )
        let plan = CutPlan(
            duration: duration,
            cuts: ranges.enumerated().map { Cut(id: $0.offset, range: $0.element, isRestored: false) }
        )
        guard plan.outputDuration > 0.05 else { throw Failure.nothingToKeep }
        return plan
    }

    @MainActor
    static func makePreviewItem(url: URL, plan: CutPlan) async throws -> AVPlayerItem {
        AVPlayerItem(asset: try await makeComposition(url: url, plan: plan))
    }

    static func cut(
        url: URL,
        intensity: CutIntensity = .tight,
        language: AppLanguage = .tr,
        progress: @escaping @MainActor (ProgressUpdate) -> Void
    ) async throws -> Result {
        let analysis = try await analyze(url: url, language: language, progress: progress)
        let plan = try Self.plan(analysis, settings: CutSettings(intensity))
        await progress(.update(
            .planningCuts,
            0.18,
            appText(language, "Kesimler planlanıyor", "Planning cuts"),
            String(
                format: appText(language, "%@: %d kesilebilir aralık bulundu.", "%@: %d cuttable pause(s) found."),
                intensity.title(for: language), plan.cuts.count
            )
        ))
        return try await export(url: url, plan: plan, language: language, progress: progress)
    }

    /// Single place that turns a plan into a timeline; preview and export must match.
    private static func makeComposition(url: URL, plan: CutPlan) async throws -> sending AVMutableComposition {
        let asset = AVURLAsset(url: url)
        let composition = AVMutableComposition()
        guard
            let srcVideo = try await asset.loadTracks(withMediaType: .video).first,
            let compVideo = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw Failure.noVideoTrack }
        let srcAudio = try await asset.loadTracks(withMediaType: .audio).first
        let compAudio = srcAudio == nil ? nil : composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)

        compVideo.preferredTransform = try await srcVideo.load(.preferredTransform)

        let scale: CMTimeScale = 600
        var cursor = CMTime.zero
        for range in plan.keepRanges {
            let lower = min(max(range.lowerBound, 0), plan.duration)
            let upper = min(max(range.upperBound, lower), plan.duration)
            let start = CMTime(seconds: lower, preferredTimescale: scale)
            let end = CMTime(seconds: upper, preferredTimescale: scale)
            guard end > start else { continue }
            let timeRange = CMTimeRange(start: start, end: end)
            do {
                try compVideo.insertTimeRange(timeRange, of: srcVideo, at: cursor)
                if let compAudio, let srcAudio {
                    try compAudio.insertTimeRange(timeRange, of: srcAudio, at: cursor)
                }
                cursor = cursor + timeRange.duration
            } catch {
                throw Failure.timelineInsertFailed(error.localizedDescription)
            }
        }
        guard cursor.seconds > 0.05 else { throw Failure.nothingToKeep }
        return composition
    }

    static func export(
        url: URL,
        plan: CutPlan,
        language: AppLanguage,
        progress: @escaping @MainActor (ProgressUpdate) -> Void
    ) async throws -> Result {
        let segmentsKept = plan.keepRanges.count
        await progress(.update(
            .buildingTimeline,
            0.28,
            appText(language, "Zaman çizgisi kuruluyor", "Building timeline"),
            String(format: appText(language, "%d konuşma bölümü korunacak.", "%d speech segment(s) will be kept."), segmentsKept)
        ))
        let composition = try await makeComposition(url: url, plan: plan)
        let outputSeconds = composition.duration.seconds

        await progress(.update(
            .exporting,
            0.40,
            appText(language, "Video oluşturuluyor", "Creating video"),
            appText(language, "Hızlı dışa aktarım hazırlanıyor.", "Preparing fast export.")
        ))
        let exportID = UUID().uuidString
        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cutsense-\(exportID).mp4")
        let passthroughURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cutsense-passthrough-\(exportID).mp4")
        let fallbackURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cutsense-fallback-\(exportID).mp4")
        try? FileManager.default.removeItem(at: outURL)
        var completedOutput = false
        defer {
            if !completedOutput {
                try? FileManager.default.removeItem(at: outURL)
            }
            try? FileManager.default.removeItem(at: passthroughURL)
            for index in 0..<fallbackPresetCount {
                try? FileManager.default.removeItem(at: Self.fallbackURL(base: fallbackURL, index: index))
            }
        }

        let passthrough = try await runExport(
            composition,
            to: passthroughURL,
            preset: AVAssetExportPresetPassthrough,
            stage: .exporting,
            progressBase: 0.42,
            progressCeiling: 0.88,
            title: appText(language, "Video oluşturuluyor", "Creating video"),
            detail: appText(language, "Hızlı dışa aktarım sürüyor.", "Fast export is running."),
            stallFallbackAfter: fastExportStallLimit(for: outputSeconds),
            timeoutAfter: fastExportTimeout(for: outputSeconds),
            language: language,
            progress: progress
        )
        if passthrough.completed {
            try replaceOutput(from: passthroughURL, to: outURL)
            try validateOutput(at: outURL)
            await progress(.update(.done, 1.0, appText(language, "Hazır", "Ready"), appText(language, "Video oluşturuldu.", "Video created.")))
            completedOutput = true
            return Result(outputURL: outURL, originalDuration: plan.duration, outputDuration: outputSeconds, segmentsKept: segmentsKept)
        }

        await progress(.update(
            .fallbackExport,
            0.50,
            appText(language, "Uyumluluk modu", "Compatibility mode"),
            appText(language, "Hızlı dışa aktarım yanıt vermedi; güvenli MP4 oluşturuluyor.", "Fast export did not respond; creating a safe MP4.")
        ))
        let fallback = try await runFallbackExports(
            composition,
            baseURL: fallbackURL,
            language: language,
            progress: progress
        )
        guard fallback.completed else {
            let reason = fallback.failureMessage ?? passthrough.failureMessage ?? appText(language, "dışa aktarma tamamlanamadı", "export could not finish")
            throw Failure.exportFailed(reason)
        }
        guard let fallbackOutputURL = fallback.outputURL else {
            throw Failure.exportFailed(appText(language, "uyumluluk çıktısı bulunamadı", "compatibility output was not found"))
        }
        try replaceOutput(from: fallbackOutputURL, to: outURL)
        await progress(.update(.verifying, 0.96, appText(language, "Çıktı kontrol ediliyor", "Checking output"), appText(language, "Dosya boyutu ve export durumu doğrulanıyor.", "File size and export status are being verified.")))
        try validateOutput(at: outURL)
        await progress(.update(.done, 1.0, appText(language, "Hazır", "Ready"), appText(language, "Video oluşturuldu.", "Video created.")))
        completedOutput = true
        return Result(outputURL: outURL, originalDuration: plan.duration, outputDuration: outputSeconds, segmentsKept: segmentsKept)
    }

    // MARK: - Cut planning

    /// Shrinks every detected silence by `pad` on each side so speech keeps a
    /// little air, then drops pauses too short to be worth a jump cut.
    /// Silence touching the start or end of the clip is cut all the way to the edge.
    static func protectedCutRanges(
        silence: [ClosedRange<Double>],
        pad: Double,
        minimumRemovedGap: Double,
        duration: Double
    ) -> [ClosedRange<Double>] {
        silence.sorted { $0.lowerBound < $1.lowerBound }.compactMap { range in
            let lower = range.lowerBound <= 0.001 ? 0 : range.lowerBound + pad
            let upper = range.upperBound >= duration - 0.001 ? duration : range.upperBound - pad
            guard upper - lower >= minimumRemovedGap else { return nil }
            return lower...upper
        }
    }

    /// Complement of the cut ranges inside `0...duration`.
    static func keepRanges(silence cuts: [ClosedRange<Double>], duration: Double) -> [ClosedRange<Double>] {
        guard duration > 0 else { return [] }
        var keep: [ClosedRange<Double>] = []
        var cursor = 0.0
        for cut in cuts.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            let lower = max(cut.lowerBound, 0)
            if lower > cursor { keep.append(cursor...lower) }
            cursor = max(cursor, min(cut.upperBound, duration))
        }
        if duration > cursor { keep.append(cursor...duration) }
        return keep
    }

    /// Joins kept ranges separated by less than `gap`, so tiny removals don't
    /// produce stuttering jump cuts.
    static func merged(_ ranges: [ClosedRange<Double>], gap: Double) -> [ClosedRange<Double>] {
        var result: [ClosedRange<Double>] = []
        for range in ranges.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if let last = result.last, range.lowerBound - last.upperBound < gap {
                result[result.count - 1] = last.lowerBound...max(last.upperBound, range.upperBound)
            } else {
                result.append(range)
            }
        }
        return result
    }

    static func compactTime(_ seconds: Double, language: AppLanguage) -> String {
        let total = max(0, Int(seconds.rounded()))
        if total < 60 { return String(format: appText(language, "%d sn", "%ds"), total) }
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    // MARK: - Export

    private struct ExportAttempt: Sendable {
        let completed: Bool
        let failureMessage: String?
        let outputURL: URL?

        init(completed: Bool, failureMessage: String?, outputURL: URL? = nil) {
            self.completed = completed
            self.failureMessage = failureMessage
            self.outputURL = outputURL
        }
    }

    /// Passthrough export should finish in a fraction of real time; if progress
    /// stops moving this long, give up and re-encode instead.
    static func fastExportStallLimit(for seconds: Double) -> Duration {
        .seconds(max(20, min(90, seconds * 0.5)))
    }

    static func fastExportTimeout(for seconds: Double) -> Duration {
        .seconds(max(60, min(900, seconds * 3)))
    }

    /// Runs one export pass and polls its progress. Cancels and reports failure
    /// on stall or timeout so the caller can try another preset.
    private static func runExport(
        _ composition: AVComposition,
        to url: URL,
        preset: String,
        stage: ProgressUpdate.Stage,
        progressBase: Double,
        progressCeiling: Double,
        title: String,
        detail: String,
        stallFallbackAfter: Duration,
        timeoutAfter: Duration,
        language: AppLanguage,
        progress: @escaping @MainActor (ProgressUpdate) -> Void
    ) async throws -> ExportAttempt {
        try? FileManager.default.removeItem(at: url)
        guard let session = AVAssetExportSession(asset: composition, presetName: preset) else {
            return ExportAttempt(completed: false, failureMessage: appText(language, "\(preset) kullanılamıyor", "\(preset) is unavailable"))
        }
        guard session.supportedFileTypes.contains(.mp4) else {
            return ExportAttempt(completed: false, failureMessage: appText(language, "\(preset) MP4 desteklemiyor", "\(preset) does not support MP4"))
        }
        session.outputURL = url
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true
        session.exportAsynchronously {}

        let clock = ContinuousClock()
        let started = clock.now
        var lastChange = started
        var lastProgress: Float = -1

        while session.status == .waiting || session.status == .exporting || session.status == .unknown {
            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch {
                await cancelAndSettle(session)
                throw error
            }
            let now = clock.now
            let current = session.progress
            if current > lastProgress + 0.001 {
                lastProgress = current
                lastChange = now
                let fraction = progressBase + Double(current) * (progressCeiling - progressBase)
                // Percent is shown by the view; keep `detail` stable so the event log doesn't flood.
                await progress(.update(stage, fraction, title, detail))
            }
            if now - lastChange > stallFallbackAfter {
                await cancelAndSettle(session)
                return ExportAttempt(completed: false, failureMessage: appText(language, "dışa aktarım ilerlemedi", "export stopped progressing"))
            }
            if now - started > timeoutAfter {
                await cancelAndSettle(session)
                return ExportAttempt(completed: false, failureMessage: appText(language, "dışa aktarım zaman aşımına uğradı", "export timed out"))
            }
        }

        guard session.status == .completed else {
            let reason = session.error?.localizedDescription ?? "status \(session.status.rawValue)"
            return ExportAttempt(completed: false, failureMessage: reason)
        }
        return ExportAttempt(completed: true, failureMessage: nil, outputURL: url)
    }

    /// Cancels and waits (max 3 s) until the session stops writing, so the next
    /// preset never races a still-running export.
    private static func cancelAndSettle(_ session: AVAssetExportSession) async {
        session.cancelExport()
        for _ in 0..<30 where session.status == .waiting || session.status == .exporting {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    /// Output path for fallback attempt `index`; also used for cleanup.
    static func fallbackURL(base: URL, index: Int) -> URL {
        base.deletingPathExtension().appendingPathExtension("\(index).mp4")
    }

    static let fallbackPresetCount = 3

    /// Re-encodes with progressively more conservative presets until one finishes.
    private static func runFallbackExports(
        _ composition: AVComposition,
        baseURL: URL,
        language: AppLanguage,
        progress: @escaping @MainActor (ProgressUpdate) -> Void
    ) async throws -> ExportAttempt {
        let presets = [AVAssetExportPresetHighestQuality, AVAssetExportPreset1920x1080, AVAssetExportPreset1280x720]
        assert(presets.count == fallbackPresetCount)
        let seconds = composition.duration.seconds
        var lastFailure: String?
        for (index, preset) in presets.enumerated() {
            let url = fallbackURL(base: baseURL, index: index)
            let attempt = try await runExport(
                composition,
                to: url,
                preset: preset,
                stage: .fallbackExport,
                progressBase: 0.50,
                progressCeiling: 0.94,
                title: appText(language, "Uyumluluk modu", "Compatibility mode"),
                detail: appText(language, "Güvenli MP4 oluşturuluyor.", "Creating a safe MP4."),
                stallFallbackAfter: .seconds(60),
                timeoutAfter: .seconds(max(120, min(1800, seconds * 6))),
                language: language,
                progress: progress
            )
            if attempt.completed { return attempt }
            try? FileManager.default.removeItem(at: url)
            lastFailure = attempt.failureMessage
        }
        return ExportAttempt(completed: false, failureMessage: lastFailure)
    }

    private static func replaceOutput(from source: URL, to destination: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
        try fm.moveItem(at: source, to: destination)
    }

    /// A completed export can still be an empty container; reject anything under 1 KB.
    private static func validateOutput(at url: URL) throws {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        guard size >= 1024 else { throw Failure.outputEmpty(size) }
    }
}
