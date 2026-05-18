import AVFoundation
import Accelerate

struct AudioSegment: Sendable {
    let startTime: Double
    let endTime: Double
    let type: AudioSegmentType
    let energy: Float
}

enum AudioSegmentType: String, Sendable {
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
        reader.add(output)
        reader.startReading()

        let sampleRate = 16000.0
        let windowSamples = Int(windowDuration * sampleRate)
        var allSamples: [Float] = []

        while let sampleBuffer = output.copyNextSampleBuffer() {
            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }
            let length = CMBlockBufferGetDataLength(blockBuffer)
            var data = Data(count: length)
            data.withUnsafeMutableBytes { ptr in
                CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: ptr.baseAddress!)
            }

            // Convert Int16 to Float
            let int16Count = length / 2
            let floatSamples = data.withUnsafeBytes { rawPtr -> [Float] in
                let int16Ptr = rawPtr.bindMemory(to: Int16.self)
                return (0..<int16Count).map { Float(int16Ptr[$0]) / 32768.0 }
            }
            allSamples.append(contentsOf: floatSamples)
        }

        guard !allSamples.isEmpty else {
            return AudioAnalysisResult(
                segments: [], silenceIntervals: [], averageEnergy: 0, peakEnergy: 0, duration: duration
            )
        }

        // First pass: compute RMS per window to find adaptive noise floor
        let totalWindows = allSamples.count / windowSamples
        var windowRMS: [Float] = []
        windowRMS.reserveCapacity(totalWindows)

        for i in 0..<totalWindows {
            let start = i * windowSamples
            let end = min(start + windowSamples, allSamples.count)
            let window = Array(allSamples[start..<end])
            var rms: Float = 0
            vDSP_rmsqv(window, 1, &rms, vDSP_Length(window.count))
            windowRMS.append(rms)
        }

        // Adaptive silence threshold: find the noise floor from quietest 10% of windows
        let silenceThresholdDB: Float
        if totalWindows > 20 {
            let sortedRMS = windowRMS.sorted()
            let percentile10Index = min(totalWindows / 10, sortedRMS.count - 1)
            let noiseFloorRMS = sortedRMS[percentile10Index]
            let noiseFloorDB = noiseFloorRMS > 0 ? 20 * log10(noiseFloorRMS) : -100
            // Set threshold 6dB above noise floor (2x amplitude), clamped to reasonable range
            silenceThresholdDB = max(min(noiseFloorDB + 6, -20), -50)
            #if DEBUG
            print("[AudioAnalysis] Adaptive threshold: noiseFloor=\(String(format: "%.1f", noiseFloorDB))dB → silence threshold=\(String(format: "%.1f", silenceThresholdDB))dB")
            #endif
        } else {
            silenceThresholdDB = baseSilenceThresholdDB
        }

        // Second pass: classify segments using adaptive threshold
        var segments: [AudioSegment] = []
        var silenceIntervals: [ClosedRange<Double>] = []
        var energySum: Float = 0
        var peakEnergy: Float = 0
        var silenceStart: Double?

        for i in 0..<totalWindows {
            let rms = windowRMS[i]
            let dB = rms > 0 ? 20 * log10(rms) : -100
            energySum += rms
            peakEnergy = max(peakEnergy, rms)

            let startTime = Double(i) * windowDuration
            let endTime = startTime + windowDuration

            let segmentType: AudioSegmentType
            if rms > clippingThreshold {
                segmentType = .clipping
            } else if dB < silenceThresholdDB {
                segmentType = .silence
            } else if dB < silenceThresholdDB + 8 {
                segmentType = .lowEnergy
            } else {
                segmentType = .speech
            }

            segments.append(AudioSegment(
                startTime: startTime,
                endTime: endTime,
                type: segmentType,
                energy: rms
            ))

            // Track silence intervals
            if segmentType == .silence {
                if silenceStart == nil {
                    silenceStart = startTime
                }
            } else {
                if let start = silenceStart {
                    let silenceDuration = startTime - start
                    if silenceDuration >= minSilenceDuration {
                        silenceIntervals.append(start...startTime)
                    }
                    silenceStart = nil
                }
            }
        }

        // Close any trailing silence
        if let start = silenceStart {
            let end = Double(totalWindows) * windowDuration
            if end - start >= minSilenceDuration {
                silenceIntervals.append(start...end)
            }
        }

        let avgEnergy = totalWindows > 0 ? energySum / Float(totalWindows) : 0

        return AudioAnalysisResult(
            segments: segments,
            silenceIntervals: silenceIntervals,
            averageEnergy: avgEnergy,
            peakEnergy: peakEnergy,
            duration: duration
        )
    }
}
