import Foundation
import AVFoundation

/// Reusable multi-preset export coordinator with stall detection, timeout management,
/// file validation, and automatic fallback to compatible presets.
///
/// Pattern extracted from QuickSilenceEngine and generalized for both Silence Cutter
/// and Auto UGC Editor use. No external APIs — all export logic uses AVFoundation.
actor VideoExportCoordinator {
    // MARK: - Export Attempt Model

    struct ExportAttemptResult: Sendable {
        let presetName: String
        let attemptIndex: Int
        let startDate: Date
        let lastProgressUpdate: Date
        let lastProgressValue: Float
        let outputURL: URL
        let status: AttemptStatus
        let failureError: String?
        let elapsedDuration: TimeInterval

        enum AttemptStatus: String, Sendable {
            case pending
            case exporting
            case completed
            case failed
            case stalled
            case cancelled
            case timedOut
        }
    }

    struct ExportResult: Sendable {
        let outputURL: URL
        let successfulPreset: String
        let exportDuration: TimeInterval
        let numberOfAttempts: Int
        let requiredFallback: Bool
        let outputResolution: CGSize?
        let outputFileSize: Int64
    }

    // MARK: - Errors

    enum ExportError: LocalizedError, Sendable {
        case noCompatiblePreset
        case allPresetsFailed([String])
        case sessionCreationFailed(String)
        case outputEmpty(Int64)
        case validationFailed(String)
        case notEnoughStorage
        case cancelled
        case unsupportedFormat(String)
        case noVideoTrack

        var errorDescription: String? {
            switch self {
            case .noCompatiblePreset:
                return "No compatible export preset was found for this video."
            case .allPresetsFailed(let failures):
                return "Export failed on all available formats: \(failures.joined(separator: ", "))"
            case .sessionCreationFailed(let preset):
                return "Could not create an export session for preset: \(preset)"
            case .outputEmpty(let size):
                return "The exported file is empty (\(size) bytes)."
            case .validationFailed(let detail):
                return "Export validation failed: \(detail)"
            case .notEnoughStorage:
                return "Not enough free storage space to export this video."
            case .cancelled:
                return "Export was cancelled."
            case .unsupportedFormat(let detail):
                return "Unsupported source format: \(detail)"
            case .noVideoTrack:
                return "The edited composition contains no valid video track."
            }
        }

        var technicalDescription: String {
            switch self {
            case .allPresetsFailed(let failures):
                return failures.joined(separator: " | ")
            case .sessionCreationFailed(let preset):
                return "session_creation_failed:\(preset)"
            case .outputEmpty(let size):
                return "output_empty:\(size)"
            case .validationFailed(let detail):
                return "validation_failed:\(detail)"
            default:
                return errorDescription ?? "unknown_error"
            }
        }
    }

    // MARK: - Configuration

    struct Configuration: Sendable {
        /// Presets to attempt, in order. Each is checked for compatibility before use.
        var preferredPresets: [String]

        /// Stall threshold for initial startup (seconds without any progress).
        var initialStallTimeout: TimeInterval

        /// Stall threshold for mid-export (seconds without progress increase).
        var midExportStallTimeout: TimeInterval

        /// Maximum total export duration before timeout.
        var maxExportDuration: TimeInterval

        /// Minimum output file size in bytes.
        var minimumFileSize: Int64

        /// Progress polling interval.
        var pollInterval: TimeInterval

        static func `default`(forOutputDuration outputDuration: Double) -> Configuration {
            let scaled = max(outputDuration, 60)
            return Configuration(
                preferredPresets: [
                    AVAssetExportPresetHEVCHighestQuality,
                    AVAssetExportPresetHighestQuality,
                    AVAssetExportPreset1920x1080,
                    AVAssetExportPreset1280x720,
                    AVAssetExportPresetMediumQuality
                ],
                initialStallTimeout: min(max(30, scaled * 0.10), 60),
                midExportStallTimeout: min(max(15, scaled * 0.05), 60),
                maxExportDuration: min(max(scaled * 2.5 + 90, 180), 3600),
                minimumFileSize: 4096,
                pollInterval: 0.25
            )
        }
    }

    // MARK: - Export

    /// Run a reliable export with automatic fallback across compatible presets.
    /// - Parameters:
    ///   - composition: The composition to export.
    ///   - baseURL: Base URL for temporary output files.
    ///   - configuration: Export configuration (presets, timeouts).
    ///   - progressHandler: Called with progress fraction (0-1) and a status message.
    /// - Returns: ExportResult with the final output URL and metadata.
    func export(
        composition: AVComposition,
        videoComposition: AVVideoComposition? = nil,
        audioMix: AVAudioMix? = nil,
        baseURL: URL,
        configuration: Configuration,
        progressHandler: @escaping @Sendable (Double, String) -> Void
    ) async throws -> ExportResult {
        try Task.checkCancellation()

        let outputDuration = stableSeconds(composition.duration)
        let presets = try await compatiblePresets(
            for: composition,
            preferred: configuration.preferredPresets
        )

        guard !presets.isEmpty else {
            throw ExportError.noCompatiblePreset
        }

        var lastFailureMessages: [String] = []
        let startTime = Date()
        var totalAttempts = 0
        var outputResolution: CGSize?
        var outputFileSize: Int64 = 0

        for (index, preset) in presets.enumerated() {
            try Task.checkCancellation()

            let attemptURL = attemptURL(baseURL: baseURL, index: index, preset: preset)
            try? FileManager.default.removeItem(at: attemptURL)

            let message: String
            if index == 0 {
                message = "Optimizing export…"
            } else {
                message = "Retrying with a compatible format…"
            }
            progressHandler(Double(index) / Double(presets.count), message)

            let result = try await runSingleExport(
                composition: composition,
                videoComposition: videoComposition,
                audioMix: audioMix,
                outputURL: attemptURL,
                preset: preset,
                attemptIndex: index,
                outputDuration: outputDuration,
                configuration: configuration,
                progressHandler: progressHandler
            )

            totalAttempts += 1

            switch result.status {
            case .completed:
                // Validate the output
                try await validateOutput(at: attemptURL, minimumSize: configuration.minimumFileSize, expectedDuration: outputDuration)

                outputFileSize = (try? FileManager.default.attributesOfItem(atPath: attemptURL.path))?[.size] as? Int64 ?? 0
                outputResolution = try? await resolveOutputResolution(url: attemptURL)

                let elapsed = Date().timeIntervalSince(startTime)
                progressHandler(1.0, "Export completed.")

                return ExportResult(
                    outputURL: attemptURL,
                    successfulPreset: preset,
                    exportDuration: elapsed,
                    numberOfAttempts: totalAttempts,
                    requiredFallback: index > 0,
                    outputResolution: outputResolution,
                    outputFileSize: outputFileSize
                )

            case .failed, .stalled, .timedOut:
                lastFailureMessages.append(result.failureError ?? "\(preset) failed")
                try? FileManager.default.removeItem(at: attemptURL)

            case .cancelled:
                try? FileManager.default.removeItem(at: attemptURL)
                throw ExportError.cancelled

            default:
                lastFailureMessages.append("\(preset) unexpected status: \(result.status.rawValue)")
                try? FileManager.default.removeItem(at: attemptURL)
            }
        }

        throw ExportError.allPresetsFailed(lastFailureMessages)
    }

    // MARK: - Single Export Attempt

    private func runSingleExport(
        composition: AVComposition,
        videoComposition: AVVideoComposition? = nil,
        audioMix: AVAudioMix? = nil,
        outputURL: URL,
        preset: String,
        attemptIndex: Int,
        outputDuration: Double,
        configuration: Configuration,
        progressHandler: @escaping @Sendable (Double, String) -> Void
    ) async throws -> ExportAttemptResult {
        guard let session = AVAssetExportSession(asset: composition, presetName: preset) else {
            return ExportAttemptResult(
                presetName: preset,
                attemptIndex: attemptIndex,
                startDate: Date(),
                lastProgressUpdate: Date(),
                lastProgressValue: 0,
                outputURL: outputURL,
                status: .failed,
                failureError: "Could not create export session for \(preset)",
                elapsedDuration: 0
            )
        }

        guard session.supportedFileTypes.contains(.mp4) else {
            return ExportAttemptResult(
                presetName: preset,
                attemptIndex: attemptIndex,
                startDate: Date(),
                lastProgressUpdate: Date(),
                lastProgressValue: 0,
                outputURL: outputURL,
                status: .failed,
                failureError: "\(preset) does not support MP4 export",
                elapsedDuration: 0
            )
        }

        session.outputURL = outputURL
        session.outputFileType = .mp4
        session.timeRange = CMTimeRange(start: .zero, duration: composition.duration)
        session.shouldOptimizeForNetworkUse = true
        session.videoComposition = videoComposition
        session.audioMix = audioMix

        let startDate = Date()
        var lastMovement = startDate
        var lastProgress: Float = -1
        var hasMadeInitialProgress = false
        let initialStallDeadline = startDate.addingTimeInterval(configuration.initialStallTimeout)

        session.exportAsynchronously {}

        while true {
            try Task.checkCancellation()

            let status = session.status
            let now = Date()
            let elapsed = now.timeIntervalSince(startDate)

            switch status {
            case .completed:
                return ExportAttemptResult(
                    presetName: preset,
                    attemptIndex: attemptIndex,
                    startDate: startDate,
                    lastProgressUpdate: now,
                    lastProgressValue: session.progress,
                    outputURL: outputURL,
                    status: .completed,
                    failureError: nil,
                    elapsedDuration: elapsed
                )

            case .failed:
                let errorDesc = session.error?.localizedDescription ?? "unknown error"
                return ExportAttemptResult(
                    presetName: preset,
                    attemptIndex: attemptIndex,
                    startDate: startDate,
                    lastProgressUpdate: now,
                    lastProgressValue: session.progress,
                    outputURL: outputURL,
                    status: .failed,
                    failureError: errorDesc,
                    elapsedDuration: elapsed
                )

            case .cancelled:
                return ExportAttemptResult(
                    presetName: preset,
                    attemptIndex: attemptIndex,
                    startDate: startDate,
                    lastProgressUpdate: now,
                    lastProgressValue: session.progress,
                    outputURL: outputURL,
                    status: .cancelled,
                    failureError: "Export was cancelled",
                    elapsedDuration: elapsed
                )

            default:
                break
            }

            // Track progress movement
            let currentProgress = session.progress
            if currentProgress > lastProgress + 0.001 {
                lastProgress = currentProgress
                lastMovement = now
                if !hasMadeInitialProgress && currentProgress > 0.01 {
                    hasMadeInitialProgress = true
                }
            }

            // Stall detection
            if !hasMadeInitialProgress {
                // Initial startup stall: hasn't begun exporting yet
                if now >= initialStallDeadline {
                    session.cancelExport()
                    return ExportAttemptResult(
                        presetName: preset,
                        attemptIndex: attemptIndex,
                        startDate: startDate,
                        lastProgressUpdate: now,
                        lastProgressValue: currentProgress,
                        outputURL: outputURL,
                        status: .stalled,
                        failureError: "Export did not start within \(Int(configuration.initialStallTimeout))s",
                        elapsedDuration: elapsed
                    )
                }
            } else {
                // Mid-export stall: progress has stopped advancing
                let stallDuration = now.timeIntervalSince(lastMovement)
                if stallDuration >= configuration.midExportStallTimeout {
                    session.cancelExport()
                    return ExportAttemptResult(
                        presetName: preset,
                        attemptIndex: attemptIndex,
                        startDate: startDate,
                        lastProgressUpdate: now,
                        lastProgressValue: currentProgress,
                        outputURL: outputURL,
                        status: .stalled,
                        failureError: "Export stalled at \(Int((currentProgress * 100).rounded()))% for \(Int(stallDuration))s",
                        elapsedDuration: elapsed
                    )
                }
            }

            // Total timeout
            if elapsed >= configuration.maxExportDuration {
                session.cancelExport()
                return ExportAttemptResult(
                    presetName: preset,
                    attemptIndex: attemptIndex,
                    startDate: startDate,
                    lastProgressUpdate: now,
                    lastProgressValue: currentProgress,
                    outputURL: outputURL,
                    status: .timedOut,
                    failureError: "Export exceeded maximum duration of \(Int(configuration.maxExportDuration))s",
                    elapsedDuration: elapsed
                )
            }

            // Report progress
            let mappedProgress = Double(currentProgress)
            progressHandler(mappedProgress, "Exporting (\(Int(mappedProgress * 100))%)")

            try await Task.sleep(for: .milliseconds(Int(configuration.pollInterval * 1000)))
        }
    }

    // MARK: - Compatibility

    private func compatiblePresets(
        for composition: AVComposition,
        preferred: [String]
    ) async throws -> [String] {
        var compatible: [String] = []
        for preset in preferred {
            if await AVAssetExportSession.compatibility(ofExportPreset: preset, with: composition, outputFileType: .mp4) {
                compatible.append(preset)
            }
        }
        if compatible.isEmpty {
            // Last resort: medium quality
            compatible = [AVAssetExportPresetMediumQuality]
        }
        return compatible
    }

    // MARK: - Validation

    private func validateOutput(at url: URL, minimumSize: Int64, expectedDuration: Double) async throws {
        let attrs = (try? FileManager.default.attributesOfItem(atPath: url.path)) ?? [:]
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        guard size >= minimumSize else {
            try? FileManager.default.removeItem(at: url)
            throw ExportError.outputEmpty(size)
        }

        // Verify the asset is readable and has a video track
        let asset = AVURLAsset(url: url)
        let assetTracks = try? await asset.loadTracks(withMediaType: .video)
        guard let tracks = assetTracks, !tracks.isEmpty else {
            try? FileManager.default.removeItem(at: url)
            throw ExportError.validationFailed("Output file contains no video track")
        }

        // Check duration is reasonable
        let actualDuration = try? await asset.load(.duration).seconds
        if let actual = actualDuration, actual > 0, expectedDuration > 0 {
            let ratio = actual / expectedDuration
            // For very short edits (<5s), use wider tolerance
            let tolerance: Double = expectedDuration < 5 ? 0.3 : 0.4
            if ratio < tolerance || ratio > (1.0 + (1.0 - tolerance)) {
                try? FileManager.default.removeItem(at: url)
                #if DEBUG
                print("[VideoExportCoordinator] Duration mismatch rejected: expected \(String(format: "%.2f", expectedDuration))s, got \(String(format: "%.2f", actual))s (ratio \(String(format: "%.2f", ratio)))")
                #endif
                throw ExportError.validationFailed("Duration mismatch: expected \(String(format: "%.1f", expectedDuration))s, got \(String(format: "%.1f", actual))s")
            }
        }
    }

    private func resolveOutputResolution(url: URL) async throws -> CGSize? {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            return nil
        }
        let naturalSize = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let isPortrait = transform.a == 0 && (transform.b == 1.0 || transform.b == -1.0)
        return isPortrait
            ? CGSize(width: abs(naturalSize.height), height: abs(naturalSize.width))
            : naturalSize
    }

    // MARK: - Helpers

    private func stableSeconds(_ time: CMTime) -> Double {
        let seconds = time.seconds
        return seconds.isFinite && seconds > 0 ? seconds : 0
    }

    private func attemptURL(baseURL: URL, index: Int, preset: String) -> URL {
        let safePreset = preset
            .replacingOccurrences(of: "AVAssetExportPreset", with: "")
            .replacingOccurrences(of: "/", with: "-")
        let baseName = baseURL.deletingPathExtension().lastPathComponent
        return baseURL
            .deletingLastPathComponent()
            .appendingPathComponent("\(baseName)-\(index)-\(safePreset).mp4")
    }
}
