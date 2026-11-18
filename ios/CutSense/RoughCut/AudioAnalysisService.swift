import AVFoundation
import Accelerate

struct AudioSegment: Sendable {
    let startTime: Double
    let endTime: Double
    let type: AudioSegmentType
    let energy: Float
}

enum AudioSegmentType: String, Codable, Sendable {
    case speech
    case silence
    case lowEnergy
    case clipping
}

struct AudioAnalysisResult: Sendable {
    let segments: [AudioSegment]
    let silenceIntervals: [ClosedRange<Double>]
    let averageEnergy: Float
    let peakEnergy: Float
    let duration: Double
}

enum AudioAnalysisError: Error, LocalizedError, Sendable {
    case cannotAddAudioOutput
    case readerStartFailed(String)
    case readerFailed(String)
    case noSamplesRead(duration: Double)

    var errorDescription: String? {
        switch self {
        case .cannotAddAudioOutput:
            "Audio analyzer could not attach the asset reader output."
        case .readerStartFailed(let message):
            "Audio analyzer could not start reading samples: \(message)"
        case .readerFailed(let message):
            "Audio analyzer failed while reading samples: \(message)"
        case .noSamplesRead(let duration):
            "Audio analyzer read zero samples from an audio track with duration \(duration.formatted(.number.precision(.fractionLength(2))))s."
        }
    }
}

struct AudioAnalysisOptions: Sendable {
    var silenceThresholdDB: Float
    var minSilenceDuration: Double

    static let balanced = AudioAnalysisOptions(silenceThresholdDB: -30, minSilenceDuration: 0.35)
    static let tight = AudioAnalysisOptions(silenceThresholdDB: -35, minSilenceDuration: 0.3)
    static let hardcore = AudioAnalysisOptions(silenceThresholdDB: -40, minSilenceDuration: 0.2)
}

enum AudioAnalysisService {
    /// Base silence threshold in dB — used as fallback if adaptive detection fails
    private static let baseSilenceThresholdDB: Float = -35
    /// Minimum silence duration to consider (seconds) — shorter silences are natural pauses
    private static let minSilenceDuration: Double = 0.3
    /// Window size for energy analysis (seconds)
    private static let windowDuration: Double = 0.05
    /// Clipping threshold (0-1 range)
    private static let clippingThreshold: Float = 0.95

    static func analyze(url: URL) async throws -> AudioAnalysisResult {
        let asset = AVURLAsset(url: url)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)

        guard let audioTrack = audioTracks.first else {
            return AudioAnalysisResult(
                segments: [],
                silenceIntervals: [],
                averageEnergy: 0,
                peakEnergy: 0,
                duration: 0
            )
        }

        let duration = try await asset.load(.duration).seconds

        // Read audio samples
        let reader = try AVAssetReader(asset: asset)
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVNumberOfChannelsKey: 1,
            AVSampleRateKey: 16000
        ]

        let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
        guard reader.canAdd(output) else {
            throw AudioAnalysisError.cannotAddAudioOutput
        }
        reader.add(output)
        guard reader.startReading() else {
            throw AudioAnalysisError.readerStartFailed(reader.error?.localizedDescription ?? "unknown reader error")
        }

#error("RECON GAP: lines 101-123 of AudioAnalysisService.swift unrecoverable")
            throw AudioAnalysisError.readerFailed(reader.error?.localizedDescription ?? "\(reader.status)")
#error("RECON GAP: lines 125-127 of AudioAnalysisService.swift unrecoverable")
            throw AudioAnalysisError.noSamplesRead(duration: duration)
#error("RECON GAP: lines 129-255 of AudioAnalysisService.swift unrecoverable")
            throw AudioAnalysisError.cannotAddAudioOutput
#error("RECON GAP: lines 257-259 of AudioAnalysisService.swift unrecoverable")
            throw AudioAnalysisError.readerStartFailed(reader.error?.localizedDescription ?? "unknown reader error")
#error("RECON GAP: lines 261-287 of AudioAnalysisService.swift unrecoverable")
            throw AudioAnalysisError.readerFailed(reader.error?.localizedDescription ?? "\(reader.status)")
#error("RECON GAP: lines 289-291 of AudioAnalysisService.swift unrecoverable")
            throw AudioAnalysisError.noSamplesRead(duration: duration)
#error("RECON GAP: end of AudioAnalysisService.swift unknown (file may continue past line 292)")
