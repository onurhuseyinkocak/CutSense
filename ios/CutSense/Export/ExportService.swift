import AVFoundation
import CoreGraphics
import Photos

@MainActor
@Observable
final class ExportService {
    nonisolated static let socialExportRenderSize = CGSize(width: 1080, height: 1920)

    var progress: Float = 0
    var isExporting = false
    var errorMessage: String?
    var exportedURL: URL?
    var lastVerificationReport: ExportVerificationReport?
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
        editPlan: EditPlan? = nil,
        isProEntitled: Bool? = nil
    ) async -> URL? {
        isExporting = true
        progress = 0
        errorMessage = nil
        exportedURL = nil
        lastVerificationReport = nil
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

            // Social exports are always rendered to the product target canvas. Source frames are
            // aspect-filled inside this canvas by the custom compositor.
            let renderSize = await detectRenderSize(from: sourceURL)
            let sourceFPS = await Self.detectSourceFrameRate(from: sourceURL)
            #if DEBUG
            print("[Export] Step 1: Clean timeline built — duration=\(CMTimeGetSeconds(timeline.totalDuration))s, sourceRanges=\(timeline.sourceRanges.count), renderSize=\(renderSize), sourceFPS=\(sourceFPS)")
            #endif

            // Step 2: Remap captions + edit decisions from source to clean timeline
            progress = 0.2
            currentStepLabel = "Remapping captions..."
            let mapping = TimelineMapper.buildMapping(from: timeline.sourceRanges)
            let remappedCaptions = TimelineMapper.exportReadyCaptions(
                TimelineMapper.remapCaptions(captions, mapping: mapping),
                totalDuration: timeline.totalDuration.seconds
            )
            let allEditDecisions = editPlan?.decisions ?? []
            let sourceTimedEdits = allEditDecisions.filter { !Self.isCleanTimelineDecision($0) }
            let cleanTimedEdits = allEditDecisions.filter { Self.isCleanTimelineDecision($0) }
            let remappedEdits = TimelineMapper.remapEditDecisions(sourceTimedEdits, mapping: mapping) + cleanTimedEdits
            let exportReadyEdits = TechInfluencerEditDecisionNormalizer.exportReadyDecisions(
                remappedEdits,
                templateId: template.id
            )
            #if DEBUG
            print("[Export] Step 2: Remapped — captions=\(captions.count)→\(remappedCaptions.count), effects=\(allEditDecisions.count)→\(exportReadyEdits.count)")
            if let first = remappedCaptions.first {
                print("[Export]   First caption: \"\(first.text.prefix(30))\" at \(String(format: "%.2f", first.startTime))-\(String(format: "%.2f", first.endTime))s role=\(first.role)")
            }
            #endif

            // Step 3: Insert SFX audio tracks BEFORE building audio mix
            progress = 0.25
            currentStepLabel = "Adding sound effects..."
            let sfxResult = await SFXAssetManager.insertSFX(
                into: timeline.composition,
                decisions: exportReadyEdits,
                sfxVolume: template.sfxVolume,
                templateId: template.id
            )
            let sfxTracks = sfxResult.tracks
            let expectedSFXCount = exportReadyEdits.filter { $0.type == .sfx }.count
            if sfxResult.failedCount > 0 {
                currentStepLabel = "Some sound effects unavailable (\(sfxResult.failedCount) skipped)"
            }
            if template.id == "tech_influencer", sfxResult.failedCount > 0 {
                errorMessage = "Required sound effects unavailable: \(sfxResult.failedCount) failed."
                cleanupPartialExport(outputURL)
                return nil
            }
            if template.id == "tech_influencer", expectedSFXCount > 0, sfxResult.insertedCount == 0 {
                errorMessage = "Required sound effects were not inserted."
                cleanupPartialExport(outputURL)
                return nil
            }
            #if DEBUG
            print("[Export] Step 3: SFX — \(expectedSFXCount) decisions, \(sfxResult.insertedCount) clips inserted on \(sfxTracks.count) track(s), \(sfxResult.failedCount) failed, templateVolume=\(template.sfxVolume)")
            #endif

            let voiceSegments = remappedCaptions.isEmpty
                ? [(start: 0.0, end: max(0, timeline.totalDuration.seconds))]
                : remappedCaptions.map { (start: $0.startTime, end: $0.endTime) }
            let bgmTrack = await BackgroundMusicService.insertBackgroundMusic(
                into: timeline.composition,
                duration: timeline.totalDuration,
                mood: BackgroundMusicService.mood(for: template),
                volume: template.backgroundMusicVolume,
                voiceSegments: voiceSegments
            )

            // Step 4: Build audio mix AFTER SFX/BGM tracks are in composition
            let audioMix = CleanTimelineBuilder.audioMixWithFades(
                timeline: timeline,
                template: template
            )
            if let bgmTrack {
                let bgmParams = BackgroundMusicService.duckingParams(
                    for: bgmTrack,
                    duration: timeline.totalDuration,
                    baseVolume: template.backgroundMusicVolume,
                    voiceSegments: voiceSegments
                )
                audioMix.inputParameters = audioMix.inputParameters + [bgmParams]
            }
            // Override SFX track volumes per inserted decision.
            for track in sfxTracks {
                let sfxParams = AVMutableAudioMixInputParameters(track: track)
                sfxParams.setVolume(0, at: .zero)
                let events = sfxResult.volumeEvents.filter { $0.trackID == track.trackID }
                for event in events {
                    let start = CMTime(seconds: event.startTime, preferredTimescale: 600)
                    let end = CMTime(seconds: event.endTime, preferredTimescale: 600)
                    sfxParams.setVolume(event.volume, at: start)
                    sfxParams.setVolume(event.volume, at: end)
                    sfxParams.setVolume(0, at: CMTimeAdd(end, CMTime(seconds: 0.01, preferredTimescale: 600)))
                }
                audioMix.inputParameters = audioMix.inputParameters + [sfxParams]
            }

            // Step 5: Create video composition with caption overlay + visual effects
            let showWatermark = !(isProEntitled ?? SubscriptionManager.shared.isPro)
            let videoComposition = buildVideoComposition(
                timeline: timeline,
                captions: remappedCaptions,
                editDecisions: exportReadyEdits,
                colorGrade: template.colorGrade,
                captionTheme: template.captionTheme,
                renderSize: renderSize,
                showWatermark: showWatermark,
                sourceFrameRate: sourceFPS,
                sourceTransform: timeline.sourceTransform
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
            progress = 0.97
            currentStepLabel = "Verifying export..."
            let expectedDuration = timeline.totalDuration.seconds
            let verification = await ExportVerifier.verify(
                outputURL: outputURL,
                expectedDuration: expectedDuration.isFinite ? expectedDuration : nil,
                expectedResolution: Self.resolutionString(for: renderSize)
            )
            lastVerificationReport = verification
            verification.save()
            guard verification.passed else {
                errorMessage = "Post-export verification failed: \(verification.failureSummary)"
                cleanupPartialExport(outputURL)
                #if DEBUG
                print("[Export] VERIFICATION FAILED: \(verification.failureSummary)")
                #endif
                return nil
            }
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
        lastVerificationReport = nil
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

    nonisolated static func isCleanTimelineDecision(_ decision: EditDecision) -> Bool {
        decision.reason == "Cut boundary"
            || decision.reason == "Cut whoosh"
            || decision.reason == "Cut impact SFX"
    }

    private func exportOutputURL() -> URL {
        let outputDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CutSense/exports", isDirectory: true)
        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        return outputDir.appendingPathComponent("export_\(UUID().uuidString.prefix(8)).mp4")
    }

    /// Pipeline exports target a fixed vertical social canvas regardless of source dimensions.
    /// The source frame is normalized and aspect-filled by `VideoFrameRenderer`.
    private func detectRenderSize(from sourceURL: URL) async -> CGSize {
        let asset = AVURLAsset(url: sourceURL)
        do {
            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            guard !videoTracks.isEmpty else { return Self.socialExportRenderSize }
            return Self.socialExportRenderSize
        } catch {
            return Self.socialExportRenderSize
        }
    }

    private func buildVideoComposition(
        timeline: CleanTimeline,
        captions: [CaptionSegment],
        editDecisions: [EditDecision] = [],
        colorGrade: TemplateConfig.ColorGrade = .none,
        captionTheme: TemplateConfig.CaptionTheme = .premiumGold,
        renderSize: CGSize = CGSize(width: 1080, height: 1920),
        showWatermark: Bool = false,
        sourceFrameRate: Float = 30,
        sourceTransform: CGAffineTransform = .identity
    ) -> AVVideoComposition? {
        let hasContent = !captions.isEmpty || !editDecisions.isEmpty
        let hasGrade = colorGrade.saturation != 1.0 || colorGrade.brightness != 0.0 ||
                       colorGrade.contrast != 1.0 || abs(colorGrade.warmth) > 0.01 ||
                       colorGrade.vignetteIntensity > 0.01
        guard hasContent || hasGrade || showWatermark else { return nil }

        // Filter to visual-only decisions (SFX handled in audio mix)
        let visualDecisions = editDecisions.filter { $0.type != .sfx }

        let instruction = CaptionCompositionInstruction(
            timeRange: CMTimeRange(start: .zero, duration: timeline.totalDuration),
            sourceTrackID: timeline.videoTrack.trackID,
            captions: captions,
            editDecisions: visualDecisions,
            colorGrade: colorGrade,
            captionTheme: captionTheme,
            renderSize: renderSize,
            showWatermark: showWatermark,
            sourceTransform: sourceTransform
        )

        // Match the source framerate so we never re-time and judder.
        // Common sources: 30, 29.97 (1001/30000), 24 (1001/24000), 60, 25.
        let configuration = AVVideoComposition.Configuration(
            customVideoCompositorClass: CaptionOverlayCompositor.self,
            frameDuration: Self.frameDuration(for: sourceFrameRate),
            instructions: [instruction],
            renderSize: renderSize
        )
        return AVVideoComposition(configuration: configuration)
    }

    /// Map a source framerate to the nearest common CMTime that AVFoundation handles cleanly.
    /// Round to the well-known broadcast rates to avoid any sample-time drift.
    nonisolated static func frameDuration(for fps: Float) -> CMTime {
        guard fps.isFinite, fps > 0 else {
            return CMTime(value: 1, timescale: 30)
        }

        let candidates: [(fps: Float, duration: CMTime)] = [
            (20, CMTime(value: 1, timescale: 20)),
            (23.976, CMTime(value: 1001, timescale: 24000)),
            (24, CMTime(value: 1, timescale: 24)),
            (25, CMTime(value: 1, timescale: 25)),
            (29.97, CMTime(value: 1001, timescale: 30000)),
            (30, CMTime(value: 1, timescale: 30)),
            (48, CMTime(value: 1, timescale: 48)),
            (50, CMTime(value: 1, timescale: 50)),
            (59.94, CMTime(value: 1001, timescale: 60000)),
            (60, CMTime(value: 1, timescale: 60)),
            (120, CMTime(value: 1, timescale: 120)),
        ]

        return candidates.min { left, right in
            abs(left.fps - fps) < abs(right.fps - fps)
        }?.duration ?? CMTime(value: 1, timescale: 30)
    }

    private static func resolutionString(for size: CGSize) -> String {
        "\(Int(abs(size.width).rounded()))x\(Int(abs(size.height).rounded()))"
    }

    /// Read source framerate from the first video track. Fallback to 30 fps when unknown.
    nonisolated private static func detectSourceFrameRate(from sourceURL: URL) async -> Float {
        let asset = AVURLAsset(url: sourceURL)
        guard let track = (try? await asset.loadTracks(withMediaType: .video))?.first else {
            return 30
        }
        if let nominal = try? await track.load(.nominalFrameRate), nominal > 0 {
            return nominal
        }
        return 30
    }
}
