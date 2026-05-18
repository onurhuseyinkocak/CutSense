import AVFoundation
import Photos

@MainActor
@Observable
final class ExportService {
    var progress: Float = 0
    var isExporting = false
    var errorMessage: String?
    var exportedURL: URL?
    var currentStepLabel = ""

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
        let outputURL = exportOutputURL()
        defer {
            isExporting = false
            stopProgressTracking()
            exportSession = nil
        }

        do {
            // Step 1: Build clean timeline
            progress = 0.1
            currentStepLabel = "Building clean timeline..."
            let timeline = try await CleanTimelineBuilder.build(
                from: sourceURL,
                decisions: decisions
            )

            // Detect source video dimensions for correct render size
            let renderSize = await detectRenderSize(from: sourceURL)
            #if DEBUG
            print("[Export] Step 1: Clean timeline built — duration=\(CMTimeGetSeconds(timeline.totalDuration))s, keepSegments=\(decisions.filter { $0.action == .keep }.count), renderSize=\(renderSize)")
            #endif

            // Step 2: Remap captions + edit decisions from source to clean timeline
            progress = 0.2
            currentStepLabel = "Remapping captions..."
            let mapping = TimelineMapper.buildMapping(from: decisions)
            let remappedCaptions = TimelineMapper.resolveOverlaps(
                TimelineMapper.remapCaptions(captions, mapping: mapping)
            )
            let allEditDecisions = editPlan?.decisions ?? []
            let remappedEdits = TimelineMapper.remapEditDecisions(allEditDecisions, mapping: mapping)
            #if DEBUG
            print("[Export] Step 2: Remapped — captions=\(captions.count)→\(remappedCaptions.count), effects=\(allEditDecisions.count)→\(remappedEdits.count)")
            if let first = remappedCaptions.first {
                print("[Export]   First caption: \"\(first.text.prefix(30))\" at \(String(format: "%.2f", first.startTime))-\(String(format: "%.2f", first.endTime))s role=\(first.role)")
            }
            #endif

            // Step 3: Insert SFX audio tracks BEFORE building audio mix
            progress = 0.25
            currentStepLabel = "Adding sound effects..."
            let sfxResult = await SFXAssetManager.insertSFX(
                into: timeline.composition,
                decisions: remappedEdits,
                sfxVolume: template.sfxVolume
            )
            let sfxTracks = sfxResult.tracks
            if sfxResult.failedCount > 0 {
                currentStepLabel = "Some sound effects unavailable (\(sfxResult.failedCount) skipped)"
            }
            #if DEBUG
            let sfxCount = remappedEdits.filter { $0.type == .sfx }.count
            print("[Export] Step 3: SFX — \(sfxCount) decisions, \(sfxTracks.count) tracks inserted, \(sfxResult.failedCount) failed, volume=\(template.sfxVolume)")
            #endif

            // Step 4: Build audio mix AFTER SFX tracks are in composition
            let audioMix = CleanTimelineBuilder.audioMixWithFades(
                timeline: timeline,
                template: template
            )
            // Override SFX track volumes (audioMixWithFades applies voice boost to all tracks)
            for track in sfxTracks {
                let sfxParams = AVMutableAudioMixInputParameters(track: track)
                sfxParams.setVolume(template.sfxVolume, at: CMTime.zero)
                audioMix.inputParameters = audioMix.inputParameters + [sfxParams]
            }

            // Step 5: Create video composition with caption overlay + visual effects
            let showWatermark = !SubscriptionManager.shared.isPro
            let videoComposition = buildVideoComposition(
                timeline: timeline,
                captions: remappedCaptions,
                editDecisions: remappedEdits,
                colorGrade: template.colorGrade,
                captionTheme: template.captionTheme,
                renderSize: renderSize,
                showWatermark: showWatermark
            )
            #if DEBUG
            print("[Export] Step 5: VideoComposition=\(videoComposition != nil ? "CREATED" : "NIL") renderSize=\(videoComposition?.renderSize ?? .zero)")
            #endif

            // Step 6: Export
            progress = 0.3
            currentStepLabel = "Encoding video..."
            guard let session = AVAssetExportSession(
                asset: timeline.composition,
                presetName: AVAssetExportPresetHighestQuality
            ) else {
                errorMessage = "Could not create export session."
                return nil
            }

            exportSession = session
            session.videoComposition = videoComposition
            session.audioMix = audioMix
            #if DEBUG
            print("[Export] Step 6: Exporting — preset=HighestQuality, videoComposition=\(session.videoComposition != nil), audioMix=\(session.audioMix != nil)")
            #endif

            startProgressTracking(baseProgress: 0.3)
            try await session.export(to: outputURL, as: .mp4)
            progress = 1.0
            exportedURL = outputURL
            #if DEBUG
            print("[Export] DONE — output=\(outputURL.lastPathComponent)")
            #endif
            return outputURL
        } catch {
            progress = 0
            errorMessage = error.localizedDescription
            cleanupPartialExport(outputURL)
            #if DEBUG
            print("[Export] FAILED: \(error)")
            #endif
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
            exportSession = nil
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
            cleanupPartialExport(outputURL)
            return nil
        }
    }

    func saveToPhotos(url: URL) async -> Bool {
        // Verify file exists before attempting save
        guard FileManager.default.fileExists(atPath: url.path) else {
            errorMessage = "Export file not found."
            return false
        }

        // Perform Photos save off @MainActor to avoid Swift 6 dispatch_assert_queue crash
        // on physical devices (iOS 26). PHPhotoLibrary.performChanges uses background queues.
        let filePath = url.path
        let result = await Task.detached { () -> Result<Void, Error> in
            do {
                let authStatus = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
                guard authStatus == .authorized || authStatus == .limited else {
                    return .failure(NSError(domain: "CutSense", code: -1, userInfo: [
                        NSLocalizedDescriptionKey: "Photos access denied. Enable in Settings > CutSense > Photos."
                    ]))
                }
                let fileURL = URL(fileURLWithPath: filePath)
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: fileURL)
                }
                return .success(())
            } catch {
                return .failure(error)
            }
        }.value

        switch result {
        case .success:
            return true
        case .failure(let error):
            errorMessage = "Failed to save: \(error.localizedDescription)"
            #if DEBUG
            print("[Export] Photos save failed: \(error)")
            #endif
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

    private func cleanupPartialExport(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private func exportOutputURL() -> URL {
        let outputDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CutSense/exports", isDirectory: true)
        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        return outputDir.appendingPathComponent("export_\(UUID().uuidString.prefix(8)).mp4")
    }

    /// Detect the natural render size from source video, defaulting to 1080x1920 (portrait)
    private func detectRenderSize(from sourceURL: URL) async -> CGSize {
        let asset = AVURLAsset(url: sourceURL)
        do {
            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            guard let track = videoTracks.first else { return CGSize(width: 1080, height: 1920) }
            let naturalSize = try await track.load(.naturalSize)
            let transform = try await track.load(.preferredTransform)
            // Apply transform to get actual pixel dimensions (handles rotation)
            let transformedSize = naturalSize.applying(transform)
            let w = abs(transformedSize.width)
            let h = abs(transformedSize.height)
            // Ensure portrait orientation for social media
            if w > h {
                // Landscape source — scale to fit 1080x1920 (pillarbox or crop)
                return CGSize(width: 1080, height: 1920)
            }
            // Portrait or square — use actual dimensions rounded to even
            let roundedW = CGFloat(Int(w / 2) * 2)
            let roundedH = CGFloat(Int(h / 2) * 2)
            return CGSize(width: roundedW, height: roundedH)
        } catch {
            return CGSize(width: 1080, height: 1920)
        }
    }

    private func buildVideoComposition(
        timeline: CleanTimeline,
        captions: [CaptionSegment],
        editDecisions: [EditDecision] = [],
        colorGrade: TemplateConfig.ColorGrade = .none,
        captionTheme: TemplateConfig.CaptionTheme = .premiumGold,
        renderSize: CGSize = CGSize(width: 1080, height: 1920),
        showWatermark: Bool = false
    ) -> AVMutableVideoComposition? {
        let hasContent = !captions.isEmpty || !editDecisions.isEmpty
        let hasGrade = colorGrade.saturation != 1.0 || colorGrade.brightness != 0.0 ||
                       colorGrade.contrast != 1.0 || abs(colorGrade.warmth) > 0.01 ||
                       colorGrade.vignetteIntensity > 0.01
        guard hasContent || hasGrade || showWatermark else { return nil }

        // Filter to visual-only decisions (SFX handled in audio mix)
        let visualDecisions = editDecisions.filter { $0.type != .sfx }

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.customVideoCompositorClass = CaptionOverlayCompositor.self

        let instruction = CaptionCompositionInstruction(
            timeRange: CMTimeRange(start: .zero, duration: timeline.totalDuration),
            sourceTrackID: timeline.videoTrack.trackID,
            captions: captions,
            editDecisions: visualDecisions,
            colorGrade: colorGrade,
            captionTheme: captionTheme,
            renderSize: renderSize,
            showWatermark: showWatermark
        )

        videoComposition.instructions = [instruction]
        return videoComposition
    }
}
