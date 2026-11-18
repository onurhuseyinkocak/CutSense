import Foundation
@preconcurrency import AVFoundation
import Speech
import NaturalLanguage

/// Main orchestrator for the Auto UGC Editor pipeline.
/// Runs all analysis locally on device using Apple frameworks.
actor UGCProcessor {
    /// Cap on the best-effort AI transcript analysis so the core edit
    /// pipeline is never blocked for long on a network call.
    private static let aiAnalysisTimeoutNanos: UInt64 = 15_000_000_000

    enum ProcessingError: Error, LocalizedError {
        case noAudioTrack
        case speechRecognitionUnavailable(String)
        case noSpeechDetected
        case transcriptionFailed(String)
        case exportFailed(String)
        case cancelled

        var errorDescription: String? {
            switch self {
            case .noAudioTrack:
                return "Bu videoda ses bulunamadı. / This video has no audio track."
            case .speechRecognitionUnavailable(let detail):
                return "Konuşma tanıma kullanılamıyor: \(detail) / Speech recognition unavailable: \(detail)"
            case .noSpeechDetected:
                return "Videoda konuşma tespit edilemedi. / No speech detected in this video."
            case .transcriptionFailed(let msg):
                return "Transkripsiyon başarısız: \(msg) / Transcription failed: \(msg)"
            case .exportFailed(let msg):
                return "Dışa aktarım başarısız: \(msg) / Export failed: \(msg)"
            case .cancelled:
                return "İşlem iptal edildi. / Process was cancelled."
            }
        }
    }

    struct ProcessingResult: Sendable {
        let takeGroups: [UGCTakeGroup]
        let editDecisions: [UGCEditDecision]
        let timelineSegments: [TimelineSegment]
        let outputURL: URL
        let originalDuration: Double
        let editedDuration: Double
        let exportMetadata: ExportMetadata?
        let faceResults: [UUID: FacePresenceAnalysisService.FacePresenceResult]
        let silenceIntervals: [ClosedRange<Double>]
    }

    struct ExportMetadata: Sendable {
        let successfulPreset: String
        let exportDuration: TimeInterval
        let numberOfAttempts: Int
        let requiredFallback: Bool
        let outputFileSize: Int64
    }

    enum Stage: String, Sendable {
        case preparing
        case analyzingAudio
        case transcribing
        case segmentingTakes
        case findingRepeats
        case checkingFraming
        case scoring
        case buildingEdit
        case exporting
        case done
    }

    struct ProgressUpdate: Sendable {
        let stage: Stage
        let fraction: Double
        let title: String
        let detail: String
    }

    // MARK: - Main Processing Pipeline

    static func process(
        url: URL,
        intensity: UGCIntensity = .conservative,
        language: AppLanguage = .tr,
        captionStyle: String = "techKinetic",
        sfxEnabled: Bool = true,
        progress: @escaping @Sendable (ProgressUpdate) -> Void
    ) async throws -> ProcessingResult {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        let languageCode = language == .tr ? "tr" : "en"

        progress(ProgressUpdate(
            stage: .preparing,
            fraction: 0.02,
            title: appText(language, "Video hazırlanıyor", "Preparing video"),
            detail: appText(language, "Video doğrulanıyor ve ses parçası kontrol ediliyor.", "Validating video and checking audio track.")
        ))

        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard !audioTracks.isEmpty else { throw ProcessingError.noAudioTrack }

        try Task.checkCancellation()

        // Step 1: Analyze audio
        progress(ProgressUpdate(
            stage: .analyzingAudio,
            fraction: 0.05,
            title: appText(language, "Ses analiz ediliyor", "Analyzing audio"),
            detail: appText(language, "Sessizlik ve konuşma bölgeleri tespit ediliyor.", "Detecting silence and speech regions.")
        ))

        let audioAnalysis = try await AudioAnalysisService.analyze(url: url)

        try Task.checkCancellation()

        // Step 2: Speech Recognition
        progress(ProgressUpdate(
            stage: .transcribing, fraction: 0.18,
            title: appText(language, "Konuşma tanınıyor", "Transcribing speech"),
            detail: appText(language, "Apple Speech ile cihaz üstünde transkripsiyon yapılıyor.", "On-device transcription using Apple Speech.")
        ))

        let recognizer = SFSpeechRecognizer(locale: language == .tr ? Locale(identifier: "tr-TR") : Locale(identifier: "en-US"))
        let isOnDeviceSupported = recognizer?.supportsOnDeviceRecognition ?? false
        if !isOnDeviceSupported {
            throw ProcessingError.speechRecognitionUnavailable(
                appText(language,
                       "Cihaz üstü konuşma tanıma bu dil için kullanılamıyor. Lütfen farklı bir dil seçin veya Silence Cutter modunu kullanın.",
                       "On-device speech recognition is not available for this language. Please try a different language or use Silence Cutter mode.")
            )
        }

        let transcriptionService = SpeechTranscriptionService()
        let locale = language == .tr ? Locale(identifier: "tr-TR") : Locale(identifier: "en-US")

        let transcriptResult: TranscriptionResult
        do {
            transcriptResult = try await transcriptionService.transcribe(url: url, locale: locale)
        } catch {
            if let transcriptError = error as? SpeechTranscriptionService.TranscriptionError {
                switch transcriptError {
                case .notAuthorized:
                    throw ProcessingError.speechRecognitionUnavailable("Konuşma tanıma izni gerekli / Speech recognition authorization required")
                case .noRecognizer:
                    throw ProcessingError.speechRecognitionUnavailable("Konuşma tanıyıcı kullanılamıyor / Speech recognizer not available")
                case .emptyTranscript, .noUsableSpeech:
                    throw ProcessingError.noSpeechDetected
                default:
                    throw ProcessingError.transcriptionFailed(error.localizedDescription)
                }
            }
            throw ProcessingError.transcriptionFailed(error.localizedDescription)
        }

        try Task.checkCancellation()

        // Step 3: Segment into takes
        progress(ProgressUpdate(
            stage: .segmentingTakes, fraction: 0.55,
            title: appText(language, "Çekimler bölünüyor", "Segmenting takes"),
            detail: appText(language, "Cümleler ve çekimler belirleniyor.", "Identifying sentences and takes.")
        ))

        let takes = TranscriptSegmentationService.segmentIntoTakes(
            transcriptSegments: transcriptResult.segments,
            audioSegments: audioAnalysis.segments,
            language: languageCode
        )

        guard !takes.isEmpty else { throw ProcessingError.noSpeechDetected }

        try Task.checkCancellation()

        // Step 4: Find repeated takes
        progress(ProgressUpdate(
            stage: .findingRepeats, fraction: 0.62,
            title: appText(language, "Tekrarlar bulunuyor", "Finding repeats"),
            detail: appText(language, "Tekrarlanan çekimler gruplandırılıyor.", "Grouping repeated takes.")
        ))

        let groups = TakeSimilarityService.groupRepeatedTakes(
            takes, language: languageCode, threshold: intensity.similarityThreshold
        )

        try Task.checkCancellation()

        // Step 4.5: Face presence analysis
        progress(ProgressUpdate(
            stage: .checkingFraming, fraction: 0.66,
            title: appText(language, "Kadraj kontrol ediliyor", "Checking framing"),
            detail: appText(language, "Yüz görünürlüğü taranıyor.", "Scanning face visibility.")
        ))

        let faceService = FacePresenceAnalysisService()
        var faceResults: [UUID: FacePresenceAnalysisService.FacePresenceResult] = [:]
        let allTakes = groups.flatMap(\.takes).sorted { $0.startTime < $1.startTime }

        let batchSize = 5
        for batchStart in stride(from: 0, to: allTakes.count, by: batchSize) {
            try Task.checkCancellation()
            let batch = allTakes[batchStart..<min(batchStart + batchSize, allTakes.count)]
            for take in batch {
                let result = await faceService.analyzeFacePresence(asset: asset, startTime: take.startTime, endTime: take.endTime)
                faceResults[take.id] = result
                let takeIndex = allTakes.firstIndex(where: { $0.id == take.id }) ?? 0
                let overallFraction = 0.66 + (Double(takeIndex + 1) / Double(allTakes.count)) * 0.04
                progress(ProgressUpdate(
                    stage: .checkingFraming, fraction: overallFraction,
                    title: appText(language, "Kadraj kontrol ediliyor", "Checking framing"),
                    detail: appText(language, "Çekim \(takeIndex + 1)/\(allTakes.count) yüz tarandı.", "Take \(takeIndex + 1)/\(allTakes.count) face scanned.")
                ))
            }
        }

        try Task.checkCancellation()

        // Step 5: Score takes
        progress(ProgressUpdate(
            stage: .scoring, fraction: 0.70,
            title: appText(language, "Çekimler puanlanıyor", "Scoring takes"),
            detail: appText(language, "Her çekim yedi faktöre göre değerlendiriliyor.", "Each take is scored across seven factors.")
        ))

        let audioQuality = audioAnalysis.averageEnergy > 0
            ? min(Float(audioAnalysis.averageEnergy * 5), 1.0) : 0.7

        // AI-assisted transcript analysis (runs on best available provider)
        // Best-effort: ~15s cap so a slow/dead network never stalls the core
        // edit pipeline. AI failure must never stop the edit.
        let aiRouter = AIProviderRouter()
        let transcriptAnalysis = await withTaskGroup(of: AIProviderRouter.TranscriptAnalysis?.self) { group in
            group.addTask {
                await aiRouter.analyzeTranscript(
                    transcript: transcriptResult.fullText,
                    language: languageCode
                )
            }
            // Timeout task returns nil after ~15s; first result wins, then cancel all
            group.addTask {
#error("RECON GAP: lines 241-284 of UGCProcessor.swift unrecoverable")
        let editDecisions = UGCEditDecisionEngine.buildEditDecisions(
            groups: scoredGroups, originalDuration: duration,
            silenceIntervals: audioAnalysis.silenceIntervals, intensity: intensity
        )

        let timelineSegments = UGCEditDecisionEngine.buildTimelineSegments(from: editDecisions)

        let paddedRanges = UGCEditDecisionEngine.paddedKeepRanges(
            from: editDecisions, padStart: intensity.silencePadStart, padEnd: intensity.silencePadEnd
        )

        try Task.checkCancellation()

        // Step 7: Build composition for export
        progress(ProgressUpdate(
            stage: .exporting, fraction: 0.85,
            title: appText(language, "Video oluşturuluyor", "Creating video"),
            detail: appText(language, "Düzenlenmiş video dışa aktarılıyor.", "Exporting the edited video.")
        ))

        let keepRanges = paddedRanges
        guard !keepRanges.isEmpty else {
            throw ProcessingError.exportFailed(appText(language, "Korunacak bölüm bulunamadı.", "No segments to keep found."))
        }

        let (outputURL, exportMeta) = try await exportWithFallback(
            url: url, keepRanges: keepRanges,
            transcript: transcriptResult, languageCode: languageCode,
            captionStyle: captionStyle, sfxEnabled: sfxEnabled,
            progress: { fraction, message in
                let mapped = 0.85 + fraction * 0.14
                progress(ProgressUpdate(
                    stage: .exporting, fraction: mapped,
                    title: appText(language, "Video oluşturuluyor", "Creating video"), detail: message
                ))
            }
        )

        try Task.checkCancellation()

        progress(ProgressUpdate(
            stage: .done, fraction: 1.0,
            title: appText(language, "Hazır", "Ready"),
            detail: appText(language, "Video düzenlendi.", "Video edited.")
        ))

        let editedDuration = keepRanges.reduce(0) { $0 + ($1.upperBound - $1.lowerBound) }

        return ProcessingResult(
            takeGroups: scoredGroups, editDecisions: editDecisions,
            timelineSegments: timelineSegments, outputURL: outputURL,
            originalDuration: duration, editedDuration: editedDuration,
            exportMetadata: exportMeta, faceResults: faceResults,
            silenceIntervals: audioAnalysis.silenceIntervals
        )
    }

    // MARK: - Build Composition

    static func buildComposition(
        url: URL,
        keepRanges: [ClosedRange<Double>]
    ) async throws -> (AVMutableComposition, AVCompositionTrack, CMTime) {
        let asset = AVURLAsset(url: url)
        let srcVideo = try await asset.loadTracks(withMediaType: .video).first
        let srcAudio = try await asset.loadTracks(withMediaType: .audio).first
#error("RECON GAP: lines 351-499 of UGCProcessor.swift unrecoverable")

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
        cleanDuration: Double,
        renderSize: CGSize,
        sourceURL: URL
    ) -> AVVideoComposition? {
        guard !captions.isEmpty else { return nil }

        let instruction = CaptionCompositionInstruction(
            timeRange: CMTimeRange(start: .zero, duration: CMTime(seconds: cleanDuration, preferredTimescale: 600)),
            sourceTrackID: compVideoTrack.trackID,
            captions: captions,
            editDecisions: [],
            colorGrade: .none,
            captionTheme: .premiumGold,
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
        sfxEnabled: Bool,
        progress: @escaping @Sendable (Double, String) -> Void
    ) async throws -> (outputURL: URL, metadata: ExportMetadata?) {
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
        let captions = buildCaptionSegments(
            transcript: transcript,
            keepRanges: keepRanges,
            cleanDuration: cleanDuration,
            captionStyle: captionStyle
        )

        // Build video composition with captions
        let renderSize = await detectRenderSize(from: url)
        let videoComposition = buildVideoComposition(
            composition: composition,
            compVideoTrack: compVideo,
            captions: captions,
            cleanDuration: cleanDuration,
            renderSize: renderSize,
            sourceURL: url
        )

        // Build audio mix with SFX
        var audioMix: AVAudioMix?
        if sfxEnabled {
            let sfxPlan = await buildSFXPlan(
                keepRanges: keepRanges,
                cleanDuration: cleanDuration,
                languageCode: languageCode
            )
            if !sfxPlan.sfxPlacements.isEmpty {
                do {
                    let mixOutput = try await AudioMixBuilder.build(
                        composition: composition,
                        sourceVoiceTrack: compVideo,
                        plan: sfxPlan,
                        cleanDuration: cleanDuration
                    )
                    audioMix = mixOutput.audioMix
                } catch {
                    #if DEBUG
                    print("[UGC] AudioMixBuilder failed: \(error), exporting without SFX")
                    #endif
                }
            }
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

            return (outURL, meta)

        } catch let error as VideoExportCoordinator.ExportError {
            throw ProcessingError.exportFailed(errorDescription(for: error, language: .tr))
        } catch {
            throw ProcessingError.exportFailed(error.localizedDescription)
        }
    }

    // MARK: - Error Display

    private static func errorDescription(for error: VideoExportCoordinator.ExportError, language: AppLanguage) -> String {
        switch error {
        case .noCompatiblePreset:
            return appText(language, "Bu video için uyumlu dışa aktarım formatı bulunamadı.", "No compatible export format was found for this video.")
        case .allPresetsFailed:
            return appText(language, "Dışa aktarım tüm formatlarda başarısız oldu. Lütfen videoyu kısaltıp tekrar deneyin.", "Export failed on all formats. Please try a shorter video.")
        case .sessionCreationFailed:
            return appText(language, "Dışa aktarım oturumu oluşturulamadı.", "Could not create an export session.")
        case .outputEmpty:
            return appText(language, "Oluşturulan dosya boş görünüyor.", "The exported file appears to be empty.")
        case .validationFailed:
            return appText(language, "Dışa aktarılan video doğrulanamadı.", "The exported video could not be validated.")
        case .notEnoughStorage:
            return appText(language, "Yeterli depolama alanı yok.", "Not enough free storage space.")
        case .cancelled:
            return appText(language, "Dışa aktarım iptal edildi.", "Export was cancelled.")
        case .unsupportedFormat(let detail):
            return appText(language, "Desteklenmeyen format: \(detail)", "Unsupported format: \(detail)")
        case .noVideoTrack:
            return appText(language, "Düzenlenen video hiç video parçası içermiyor.", "The edited video contains no video track.")
#error("RECON GAP: end of UGCProcessor.swift unknown (file may continue past line 700)")
