import AVFoundation
import Photos

@MainActor
@Observable
final class ExportService {
    var progress: Float = 0
    var isExporting = false
    var errorMessage: String?
    var exportedURL: URL?

    private var exportSession: AVAssetExportSession?

    /// Full pipeline export: clean timeline + captions + audio mix
    @discardableResult
    func exportWithPipeline(
        sourceURL: URL,
        decisions: [RoughCutDecision],
        captions: [CaptionSegment],
        template: TemplateConfig
    ) async -> URL? {
        isExporting = true
        progress = 0
        errorMessage = nil
        exportedURL = nil
        defer { isExporting = false }

        do {
            // Step 1: Build clean timeline
            progress = 0.1
            let timeline = try await CleanTimelineBuilder.build(
                from: sourceURL,
                decisions: decisions
            )

            // Step 2: Create video composition with caption overlay
            progress = 0.3
            let videoComposition = buildVideoComposition(
                timeline: timeline,
                captions: captions
            )

            // Step 3: Create audio mix
            progress = 0.4
            let audioMix = CleanTimelineBuilder.audioMixWithFades(
                timeline: timeline,
                template: template
            )

            // Step 4: Export
            progress = 0.5
            guard let session = AVAssetExportSession(
                asset: timeline.composition,
                presetName: AVAssetExportPreset1920x1080
            ) else {
                errorMessage = "Could not create export session."
                return nil
            }

            let outputURL = exportOutputURL()
            exportSession = session
            session.videoComposition = videoComposition
            session.audioMix = audioMix

            try await session.export(to: outputURL, as: .mp4)
            progress = 1.0
            exportedURL = outputURL
            return outputURL
        } catch {
            progress = 0
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// Simple export without editing pipeline (fallback)
    @discardableResult
    func exportNormalized(from sourceURL: URL) async -> URL? {
        isExporting = true
        progress = 0
        errorMessage = nil
        exportedURL = nil
        defer { isExporting = false }

        let asset = AVURLAsset(url: sourceURL)

        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset1920x1080) else {
            errorMessage = "Could not create export session."
            return nil
        }

        let outputURL = exportOutputURL()
        exportSession = session

        do {
            try await session.export(to: outputURL, as: .mp4)
            progress = 1.0
            exportedURL = outputURL
            return outputURL
        } catch {
            progress = 0
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func saveToPhotos(url: URL) async -> Bool {
        do {
            let authStatus = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard authStatus == .authorized || authStatus == .limited else {
                errorMessage = "Photos access denied."
                return false
            }

            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func cancelExport() {
        exportSession?.cancelExport()
    }

    // MARK: - Private

    private func exportOutputURL() -> URL {
        let outputDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CutSense/exports", isDirectory: true)
        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        return outputDir.appendingPathComponent("export_\(UUID().uuidString.prefix(8)).mp4")
    }

    private func buildVideoComposition(
        timeline: CleanTimeline,
        captions: [CaptionSegment]
    ) -> AVMutableVideoComposition? {
        guard !captions.isEmpty else { return nil }

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = CGSize(width: 1080, height: 1920)
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.customVideoCompositorClass = CaptionOverlayCompositor.self

        let instruction = CaptionCompositionInstruction(
            timeRange: CMTimeRange(start: .zero, duration: timeline.totalDuration),
            sourceTrackID: timeline.videoTrack.trackID,
            captions: captions,
            renderSize: CGSize(width: 1080, height: 1920)
        )

        videoComposition.instructions = [instruction]
        return videoComposition
    }
}
