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
    private var progressTimer: Timer?

    /// Full pipeline export: clean timeline + captions + visual effects + audio mix
    @discardableResult
    func exportWithPipeline(
        sourceURL: URL,
        decisions: [RoughCutDecision],
        captions: [CaptionSegment],
        template: TemplateConfig,
        editPlan: EditPlan? = nil
    ) async -> URL? {
        isExporting = true
        progress = 0
        errorMessage = nil
        exportedURL = nil
        defer {
            isExporting = false
            stopProgressTracking()
        }

        do {
            // Step 1: Build clean timeline
            progress = 0.1
            let timeline = try await CleanTimelineBuilder.build(
                from: sourceURL,
                decisions: decisions
            )

            // Step 2: Remap captions + edit decisions from source to clean timeline
            progress = 0.2
            let mapping = TimelineMapper.buildMapping(from: decisions)
            let remappedCaptions = TimelineMapper.remapCaptions(captions, mapping: mapping)
            let allEditDecisions = editPlan?.decisions ?? []
            let remappedEdits = TimelineMapper.remapEditDecisions(allEditDecisions, mapping: mapping)

            // Step 3: Create video composition with caption overlay + visual effects
            let videoComposition = buildVideoComposition(
                timeline: timeline,
                captions: remappedCaptions,
                editDecisions: remappedEdits,
                colorGrade: template.colorGrade
            )

            // Step 4: Build audio mix for voice track BEFORE adding SFX tracks
            let audioMix = CleanTimelineBuilder.audioMixWithFades(
                timeline: timeline,
                template: template
            )

            // Step 5: Insert SFX audio tracks into composition (after audio mix so voice boost doesn't hit SFX)
            progress = 0.25
            let remappedSfxEdits = remappedEdits
            let sfxTracks = await SFXAssetManager.insertSFX(
                into: timeline.composition,
                decisions: remappedSfxEdits,
                sfxVolume: template.sfxVolume
            )
            // Set SFX track volumes separately
            for track in sfxTracks {
                let sfxParams = AVMutableAudioMixInputParameters(track: track)
                sfxParams.setVolume(template.sfxVolume, at: CMTime.zero)
                audioMix.inputParameters = audioMix.inputParameters + [sfxParams]
            }

            // Step 6: Export
            progress = 0.3
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

            startProgressTracking(baseProgress: 0.3)
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
        defer {
            isExporting = false
            stopProgressTracking()
        }

        let asset = AVURLAsset(url: sourceURL)

        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset1920x1080) else {
            errorMessage = "Could not create export session."
            return nil
        }

        let outputURL = exportOutputURL()
        exportSession = session

        do {
            startProgressTracking(baseProgress: 0.0)
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

    // MARK: - Progress Tracking

    private func startProgressTracking(baseProgress: Float) {
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let session = self.exportSession else { return }
                // Map session progress (0-1) to remaining range (baseProgress to 0.95)
                let sessionProgress = session.progress
                self.progress = baseProgress + (0.95 - baseProgress) * sessionProgress
            }
        }
    }

    private func stopProgressTracking() {
        progressTimer?.invalidate()
        progressTimer = nil
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
        captions: [CaptionSegment],
        editDecisions: [EditDecision] = [],
        colorGrade: TemplateConfig.ColorGrade = .none
    ) -> AVMutableVideoComposition? {
        let hasContent = !captions.isEmpty || !editDecisions.isEmpty
        let hasGrade = colorGrade.saturation != 1.0 || colorGrade.brightness != 0.0 ||
                       colorGrade.contrast != 1.0 || abs(colorGrade.warmth) > 0.01 ||
                       colorGrade.vignetteIntensity > 0.01
        guard hasContent || hasGrade else { return nil }

        // Filter to visual-only decisions (SFX handled in audio mix)
        let visualDecisions = editDecisions.filter { $0.type != .sfx }

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = CGSize(width: 1080, height: 1920)
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.customVideoCompositorClass = CaptionOverlayCompositor.self

        let instruction = CaptionCompositionInstruction(
            timeRange: CMTimeRange(start: .zero, duration: timeline.totalDuration),
            sourceTrackID: timeline.videoTrack.trackID,
            captions: captions,
            editDecisions: visualDecisions,
            colorGrade: colorGrade,
            renderSize: CGSize(width: 1080, height: 1920)
        )

        videoComposition.instructions = [instruction]
        return videoComposition
    }
}
