#error("RECON GAP: lines 1-133 of UGCProcessor.swift unrecoverable")
        let supportedLocales = contentLanguage.recognitionLocales.filter {
#error("RECON GAP: lines 135-373 of UGCProcessor.swift unrecoverable")
            exportMetadata: exportMeta, faceResults: faceResults,
            silenceIntervals: audioAnalysis.silenceIntervals,
            transcriptResult: transcriptResult,
            detectedLanguageCode: languageCode
        )
    }

    private static func bestAutomaticTranscript(from candidates: [TranscriptionResult]) -> TranscriptionResult? {
        candidates.max { lhs, rhs in
            automaticTranscriptScore(lhs) < automaticTranscriptScore(rhs)
        }
    }

    private static func automaticTranscriptScore(_ result: TranscriptionResult) -> Double {
        let words = result.fullText.split(whereSeparator: { $0.isWhitespace }).count
        let coverage = min(Double(words), 160) / 160
#error("RECON GAP: lines 390-399 of UGCProcessor.swift unrecoverable")
    }

    /// Samples the lower caption-safe area in three source frames. We fail safe:
    /// a readable text hit in two frames means we preserve the source captions
    /// instead of burning a second layer into the export.
    private static func detectBurnedCaptions(url: URL) async -> Bool {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration).seconds, duration > 2 else { return false }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 720, height: 1280)
        var hits = 0
        for point in [duration * 0.18, duration * 0.52, duration * 0.82] {
            guard let cgImage = try? generator.copyCGImage(at: CMTime(seconds: point, preferredTimescale: 600), actualTime: nil) else { continue }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .fast
            request.usesLanguageCorrection = false
            request.regionOfInterest = CGRect(x: 0.04, y: 0.02, width: 0.92, height: 0.38)
            let handler = VNImageRequestHandler(cgImage: cgImage)
            try? handler.perform([request])
            let textCount = (request.results ?? []).reduce(0) { $0 + (($1.topCandidates(1).first?.string.count ?? 0) >= 3 ? 1 : 0) }
            if textCount > 0 { hits += 1 }
        }
        return hits >= 2
    }

    /// Re-renders the exact editable project state. This is deliberately separate
    /// from analysis so a text/style/timing change never re-transcribes the source.
    static func renderEdited(
        sourceURL: URL,
        editDecisions: [UGCEditDecision],
        captions: [CaptionSegment],
        intensity: UGCIntensity,
        language: AppLanguage,
        captionStyle: String,
        captionsEnabled: Bool,
        sfxEnabled: Bool,
        progress: @escaping @Sendable (Double, String) -> Void
    ) async throws -> (URL, ExportMetadata?) {
        // This path renders explicit user edits from the Studio. Do not reapply
        // automatic silence padding here: doing so silently changes a trim the
        // user has made on the timeline. Initial AI processing still applies its
        // pacing policy before opening the Studio; every subsequent Apply uses
        // the exact non-destructive EDL boundaries the user sees.
        let keepRanges = UGCEditDecisionEngine.keepRanges(from: editDecisions)
        guard !keepRanges.isEmpty else {
            throw ProcessingError.exportFailed(appText(language, "Dışa aktarılacak bir klip kalmadı.", "There are no clips left to export."))
        }
        let visibleCaptions = captionsEnabled ? captions.filter(\.isVisible) : []
        let transcript = TranscriptionResult(fullText: "", segments: [], language: language == .tr ? "tr" : "en", overallConfidence: 0)
        let result = try await exportWithFallback(
            url: sourceURL,
            keepRanges: keepRanges,
            transcript: transcript,
            languageCode: language == .tr ? "tr" : "en",
            captionStyle: captionStyle,
            captionsEnabled: captionsEnabled,
            captionOverride: visibleCaptions,
            sfxEnabled: sfxEnabled,
            progress: progress
        )
        return (result.outputURL, result.metadata)
    }

    // MARK: - Build Composition

    static func buildComposition(
        url: URL,
        keepRanges: [ClosedRange<Double>]
    ) async throws -> (AVMutableComposition, AVCompositionTrack, CMTime) {
        let asset = AVURLAsset(url: url)
        let srcVideo = try await asset.loadTracks(withMediaType: .video).first
        let srcAudio = try await asset.loadTracks(withMediaType: .audio).first

        guard let srcVideo else {
            throw ProcessingError.exportFailed("Video parçası bulunamadı / No video track found")
        }

        let composition = AVMutableComposition()
        guard let compVideo = composition.addMutableTrack(
            withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw ProcessingError.exportFailed("Video zaman çizgisi oluşturulamadı / Could not create video timeline")
        }

        let compAudio: AVMutableCompositionTrack?
        if srcAudio != nil {
            compAudio = composition.addMutableTrack(
                withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid
            )
        } else {
            compAudio = nil
        }

        compVideo.preferredTransform = try await srcVideo.load(.preferredTransform)
        let scale: CMTimeScale = 600
        var cursor = CMTime.zero

        for range in keepRanges {
            try Task.checkCancellation()
            let start = CMTime(seconds: max(0, range.lowerBound), preferredTimescale: scale)
            let end = CMTime(seconds: min(range.upperBound, 86400), preferredTimescale: scale)
            let timeRange = CMTimeRange(start: start, end: end)
            guard timeRange.duration.seconds > 0.05 else { continue }

            do {
                try compVideo.insertTimeRange(timeRange, of: srcVideo, at: cursor)
                if let compAudio, let srcAudio {
                    try compAudio.insertTimeRange(timeRange, of: srcAudio, at: cursor)
                }
                cursor = cursor + timeRange.duration
            } catch {
                throw ProcessingError.exportFailed("Zaman çizgisi oluşturulamadı: \(error.localizedDescription)")
            }
        }

        guard cursor.seconds > 0.05 else {
            throw ProcessingError.exportFailed("Oluşturulan video çok kısa / Output video is too short")
        }

        return (composition, compVideo, cursor)
    }

    // MARK: - Caption Segment Building

    /// Remap source-timeline captions to clean-timeline using keepRanges.
    private static func buildCaptionSegments(
        transcript: TranscriptionResult,
        keepRanges: [ClosedRange<Double>],
        cleanDuration: Double,
        captionStyle: String
#error("RECON GAP: lines 531-623 of UGCProcessor.swift unrecoverable")
        var cleanStart = 0.0
        for range in keepRanges {
            let duration = range.upperBound - range.lowerBound
            guard duration > 0.05 else { continue }
            ranges.append(SpeechRange(
                sourceStart: range.lowerBound,
                sourceEnd: range.upperBound,
                cleanStart: cleanStart
            ))
            cleanStart += duration
        }
        return ranges
    }

    // MARK: - SFX Plan Building

    private static func buildSFXPlan(
        keepRanges: [ClosedRange<Double>],
        cleanDuration: Double,
        languageCode: String
    ) async -> AudioPlan {
        let speechRanges = buildSpeechRanges(keepRanges: keepRanges)

        // Build a minimal CutSenseTranscript from the keep ranges
        let words: [CaptionWord] = speechRanges.enumerated().map { i, r in
            CaptionWord(text: "segment_\(i)", start: r.sourceStart, end: r.sourceEnd, confidence: 0.9)
        }
        let transcript = CutSenseTranscript(
            words: words, language: languageCode,
            fullText: "", durationSeconds: cleanDuration
        )

        return await AudioPlanBuilder.sfxOnlyPlan(
            transcript: transcript, speechRanges: speechRanges, cleanDuration: cleanDuration
        )
    }

    // MARK: - Video Composition Building

    private static func buildVideoComposition(
        composition: AVMutableComposition,
        compVideoTrack: AVCompositionTrack,
        captions: [CaptionSegment],
        keepRanges: [ClosedRange<Double>],
        cleanDuration: Double,
        renderSize: CGSize,
        sourceURL: URL,
        captionStyle: String
    ) -> AVVideoComposition? {
        var visualEffects = captions.compactMap { caption -> EditDecision? in
            switch caption.sceneBehavior {
            case .hookImpact, .punchIn:
                return EditDecision(time: caption.startTime, duration: min(0.72, max(0.45, caption.endTime - caption.startTime)), type: .zoom, reason: "Caption controlled punch", intensity: 0.24)
            case .subtleZoom, .conclusionHold:
                return EditDecision(time: caption.startTime, duration: max(2.8, caption.endTime - caption.startTime), type: .zoom, reason: "Caption slow push", intensity: 0.20)
            case .transitionWhoosh:
                return EditDecision(time: caption.startTime, duration: 0.32, type: .cutTransition, reason: "Caption transition", intensity: 0.55)
            case .focusBlur, .underlineReveal, .keywordLockOn:
                return EditDecision(time: caption.startTime, duration: min(0.45, caption.endTime - caption.startTime), type: .colorShift, reason: "Caption focus", intensity: 0.38)
            case .none: return nil
            }
        }
        // Make cuts feel intentional. Caption-only effect planning meant a
        // video with sparse text could contain no visual editorial cues at all.
        // Add short, restrained transitions only where the source actually had
        // a meaningful gap; never put a zoom on every sentence.
        var cleanCursor = 0.0
        for (index, range) in keepRanges.enumerated() {
            defer { cleanCursor += range.upperBound - range.lowerBound }
            guard index > 0 else { continue }
            let previous = keepRanges[index - 1]
            let sourceGap = range.lowerBound - previous.upperBound
            guard sourceGap >= 0.32 else { continue }
            visualEffects.append(EditDecision(
                time: max(0, cleanCursor - 0.12), duration: 0.24,
                type: .cutTransition, reason: "Timeline cut transition", intensity: 0.26
            ))
            if index.isMultiple(of: 2) {
                visualEffects.append(EditDecision(
                    time: cleanCursor, duration: 1.65,
                    type: .zoom, reason: "Timeline gentle push", intensity: 0.12
                ))
            }
        }
        guard !captions.isEmpty || !visualEffects.isEmpty else { return nil }

        let instruction = CaptionCompositionInstruction(
            timeRange: CMTimeRange(start: .zero, duration: CMTime(seconds: cleanDuration, preferredTimescale: 600)),
            sourceTrackID: compVideoTrack.trackID,
            captions: captions,
            editDecisions: visualEffects,
            colorGrade: .none,
            captionTheme: captionTheme(for: captionStyle),
            renderSize: renderSize,
            showWatermark: false,
            sourceTransform: .identity
        )

        let videoComposition = AVMutableVideoComposition()
        videoComposition.customVideoCompositorClass = CaptionOverlayCompositor.self
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.renderSize = renderSize
        videoComposition.instructions = [instruction]
        return videoComposition
    }

    private static func captionTheme(for style: String) -> TemplateConfig.CaptionTheme {
        switch style {
        case "karaoke", "techKinetic", "hookImpact":
            return .neonViral
        case "subtitleMinimal", "lowerThird":
            return .monoClean
        default:
            return .premiumGold
        }
    }

    private static func detectRenderSize(from url: URL) async -> CGSize {
        let asset = AVURLAsset(url: url)
        guard let track = (try? await asset.loadTracks(withMediaType: .video))?.first else {
            return CGSize(width: 1080, height: 1920)
        }
        let naturalSize = try? await track.load(.naturalSize)
        let transform = try? await track.load(.preferredTransform)
        guard let size = naturalSize else { return CGSize(width: 1080, height: 1920) }
        let isPortrait = transform?.a == 0 && (transform?.b == 1.0 || transform?.b == -1.0)
        return isPortrait
            ? CGSize(width: abs(size.height), height: abs(size.width))
            : size
    }

    // MARK: - Export With Fallback

    private static func exportWithFallback(
        url: URL,
        keepRanges: [ClosedRange<Double>],
        transcript: TranscriptionResult,
        languageCode: String,
        captionStyle: String,
        captionsEnabled: Bool,
        captionOverride: [CaptionSegment]? = nil,
        sfxEnabled: Bool,
        progress: @escaping @Sendable (Double, String) -> Void
    ) async throws -> (outputURL: URL, metadata: ExportMetadata?, captions: [CaptionSegment]) {
        let (composition, compVideo, cursor) = try await buildComposition(url: url, keepRanges: keepRanges)
        let cleanDuration = cursor.seconds

        let exportID = UUID().uuidString
        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ugc-\(exportID).mp4")

        var completedOutput = false
        defer {
            if !completedOutput {
                try? FileManager.default.removeItem(at: outURL)
            }
        }

        // Build caption segments
        let captions = captionOverride ?? (captionsEnabled
            ? buildCaptionSegments(
                transcript: transcript,
                keepRanges: keepRanges,
                cleanDuration: cleanDuration,
                captionStyle: captionStyle
            )
            : [])

        // Build video composition with captions
        let renderSize = await detectRenderSize(from: url)
        let videoComposition = buildVideoComposition(
            composition: composition,
            compVideoTrack: compVideo,
            captions: captions,
            keepRanges: keepRanges,
            cleanDuration: cleanDuration,
            renderSize: renderSize,
            sourceURL: url,
            captionStyle: captionStyle
        )

        // Build audio mix with SFX
        var audioMix: AVAudioMix?
        if sfxEnabled {
            let sfxPlan = await buildSFXPlan(
                keepRanges: keepRanges,
                cleanDuration: cleanDuration,
                languageCode: languageCode
            )
            guard !sfxPlan.sfxPlacements.isEmpty else {
                throw ProcessingError.exportFailed(appText(languageCode == "tr" ? .tr : .en,
                                                           "Ses efekti planı oluşturulamadı. Sessiz export yapılmadı.",
                                                           "Sound effects could not be planned. A silent export was not created."))
            }
            let mixOutput = try await AudioMixBuilder.build(
                composition: composition,
                sourceVoiceTrack: compVideo,
                plan: sfxPlan,
                cleanDuration: cleanDuration
            )
            guard !mixOutput.sfxTrackIDs.isEmpty else {
                throw ProcessingError.exportFailed(appText(languageCode == "tr" ? .tr : .en,
                                                           "Ses efektleri videoya eklenemedi. Sessiz export yapılmadı.",
                                                           "Sound effects could not be inserted. A silent export was not created."))
            }
            audioMix = mixOutput.audioMix
        }

        let outputDuration = cursor.seconds
        let coordinator = VideoExportCoordinator()
        let config = VideoExportCoordinator.Configuration.default(forOutputDuration: outputDuration)

        do {
            let result = try await coordinator.export(
                composition: composition,
                videoComposition: videoComposition,
                audioMix: audioMix,
                baseURL: outURL,
                configuration: config,
                progressHandler: { fraction, message in
                    progress(fraction, message)
                }
            )

            if result.outputURL != outURL {
                try? FileManager.default.removeItem(at: outURL)
                try FileManager.default.moveItem(at: result.outputURL, to: outURL)
            }

            completedOutput = true

            let meta = ExportMetadata(
                successfulPreset: result.successfulPreset,
                exportDuration: result.exportDuration,
                numberOfAttempts: result.numberOfAttempts,
                requiredFallback: result.requiredFallback,
                outputFileSize: result.outputFileSize
            )

            return (outURL, meta, captions)

        } catch let error as VideoExportCoordinator.ExportError {
            throw ProcessingError.exportFailed(errorDescription(for: error, language: .tr))
        } catch {
            throw ProcessingError.exportFailed(error.localizedDescription)
#error("RECON GAP: end of UGCProcessor.swift unknown (file may continue past line 868)")
