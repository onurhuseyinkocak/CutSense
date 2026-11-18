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
                "Hardcore"
            }
        }

        func detail(for language: AppLanguage) -> String {
            switch self {
            case .balanced:
                appText(language, "Konuşma uçlarını daha çok korur.", "Keeps more space around speech.")
            case .tight:
                appText(language, "Önerilen sert kesim.", "Recommended strong cut.")
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
                appText(language, "Video zaman çizgisi kurulamadı: \(message)", "Could not build the video timeline: \(message)")
            case .outputEmpty(let bytes):
                appText(language, "Video oluşturuldu ama dosya boş görünüyor (\(bytes) bayt).", "The video was created, but the output file looks empty (\(bytes) bytes).")
            case .exportFailed:
                appText(
                    language,
                    "Dışa aktarım tamamlanamadı. Uzun video işlenirken iOS export motoru çıktı veremedi; aynı videoyu tekrar dene veya daha kısa bir video seç.",
                    "Export could not finish. The iOS export engine did not produce an output while processing this long video; try the same video again or choose a shorter video."
                )
            }
        }
    }

    static func cut(
        url: URL,
        intensity: CutIntensity = .tight,
        language: AppLanguage = .tr,
        progress: @escaping @MainActor (ProgressUpdate) -> Void
    ) async throws -> Result {
        await progress(.update(
            .analyzingAudio,
            0.08,
            appText(language, "Ses haritası çıkarılıyor", "Mapping audio"),
            appText(language, "Konuşma ve sessizlik pencereleri cihaz üstünde taranıyor.", "Speech and silence windows are scanned on device.")
        ))
        let analysis = try await AudioAnalysisService.analyze(
            url: url,
            options: intensity.analysisOptions
        ) { processedSeconds, duration in
            let audioFraction = duration > 0 ? min(max(processedSeconds / duration, 0), 1) : 0
            progress(.update(
                .analyzingAudio,
                0.08 + audioFraction * 0.10,
                appText(language, "Ses taranıyor", "Scanning audio"),
                appText(
                    language,
                    "\(compactTime(processedSeconds, language: language)) / \(compactTime(duration, language: language)) ses penceresi işlendi.",
                    "\(compactTime(processedSeconds, language: language)) / \(compactTime(duration, language: language)) of audio processed."
                )
            ))
        }
        let duration = analysis.duration
        guard analysis.segments.contains(where: { $0.type == .speech || $0.type == .clipping }) else {
            throw Failure.nothingToKeep
        }

        await progress(.update(
            .planningCuts,
            0.18,
            appText(language, "Kesimler planlanıyor", "Planning cuts"),
            appText(
                language,
                "\(intensity.title(for: language)): \(analysis.silenceIntervals.count) kesilebilir aralık bulundu.",
                "\(intensity.title(for: language)): \(analysis.silenceIntervals.count) cuttable pause(s) found."
            )
        ))
        let cutRanges = protectedCutRanges(
            silence: analysis.silenceIntervals,
            pad: intensity.padSeconds,
            minimumRemovedGap: intensity.finalMinimumRemovedGap,
            duration: duration
        )
        var keep = keepRanges(silence: cutRanges, duration: duration)
        keep = merged(keep, gap: intensity.mergeGap)
        guard keep.contains(where: { $0.upperBound - $0.lowerBound > 0.05 }) else {
            throw Failure.nothingToKeep
        }

        await progress(.update(
            .buildingTimeline,
            0.28,
            appText(language, "Zaman çizgisi kuruluyor", "Building timeline"),
            appText(language, "\(keep.count) konuşma bölümü korunacak.", "\(keep.count) speech segment(s) will be kept.")
        ))
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
        var kept = 0
        for range in keep {
            let lower = min(max(range.lowerBound, 0), duration)
            let upper = min(max(range.upperBound, lower), duration)
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
                kept += 1
            } catch {
                throw Failure.timelineInsertFailed(error.localizedDescription)
            }
        }
        guard kept > 0, cursor.seconds > 0.05 else { throw Failure.nothingToKeep }

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
            try? FileManager.default.removeItem(at: fallbackURL)
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
            stallFallbackAfter: fastExportStallLimit(for: cursor.seconds),
            timeoutAfter: fastExportTimeout(for: cursor.seconds),
            language: language,
            progress: progress
        )
        if passthrough.completed {
            try replaceOutput(from: passthroughURL, to: outURL)
            try validateOutput(at: outURL)
            await progress(.update(.done, 1.0, appText(language, "Hazır", "Ready"), appText(language, "Video oluşturuldu.", "Video created.")))
            completedOutput = true
            return Result(outputURL: outURL, originalDuration: duration, outputDuration: cursor.seconds, segmentsKept: kept)
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
        return Result(outputURL: outURL, originalDuration: duration, outputDuration: cursor.seconds, segmentsKept: kept)
    }

    /// Runs one export pass with the given preset. Returns true only on a
    /// completed export, so the caller can fall back to a different preset.
    private struct ExportAttempt: Sendable {
        let completed: Bool
        let failureMessage: String?
        let outputURL: URL?

        init(completed: Bool, failureMessage: String?, outputURL: URL? = nil) {
#error("RECON GAP: lines 321-331 of QuickSilenceEngine.swift unrecoverable")
        init(_ session: AVAssetExportSession) {
#error("RECON GAP: end of QuickSilenceEngine.swift unknown (file may continue past line 332)")
