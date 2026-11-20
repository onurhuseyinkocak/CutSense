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
    case noAudioTrack
    case cannotAddAudioOutput
    case readerStartFailed(String)
    case readerFailed(String)
    case noSamplesRead(duration: Double)

    var errorDescription: String? {
        switch self {
        case .noAudioTrack:
            "This video has no audio track."
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
    /// Used when the clip is too short to estimate a noise floor.
    var silenceThresholdDB: Float
    var minSilenceDuration: Double

    static let balanced = AudioAnalysisOptions(silenceThresholdDB: -30, minSilenceDuration: 0.35)
    static let tight = AudioAnalysisOptions(silenceThresholdDB: -35, minSilenceDuration: 0.3)
    static let hardcore = AudioAnalysisOptions(silenceThresholdDB: -40, minSilenceDuration: 0.2)
}

enum AudioAnalysisService {
    private static let sampleRate = 16_000.0
    private static let windowDuration = 0.05
    private static let clippingThreshold: Float = 0.95
    /// Report progress roughly every 5 s of audio.
    private static let progressStepSeconds = 5.0

    /// Streams the audio track once, computes RMS per 50 ms window, then
    /// classifies windows against an adaptive threshold (noise floor + 6 dB).
    static func analyze(
        url: URL,
        options: AudioAnalysisOptions = .tight,
        progress: (@Sendable (_ processedSeconds: Double, _ duration: Double) -> Void)? = nil
    ) async throws -> AudioAnalysisResult {
        let asset = AVURLAsset(url: url)
        guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            throw AudioAnalysisError.noAudioTrack
        }
        let duration = try await asset.load(.duration).seconds

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVNumberOfChannelsKey: 1,
            AVSampleRateKey: sampleRate
        ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw AudioAnalysisError.cannotAddAudioOutput }
        reader.add(output)
        guard reader.startReading() else {
            throw AudioAnalysisError.readerStartFailed(reader.error?.localizedDescription ?? "unknown reader error")
        }

        let windowSamples = Int(windowDuration * sampleRate)
        var windowRMS: [Float] = []
        windowRMS.reserveCapacity(Int(duration / windowDuration) + 1)
        var pending: [Float] = []
        pending.reserveCapacity(windowSamples * 2)
        var totalSamples = 0
        var nextProgressAt = progressStepSeconds

        while let sampleBuffer = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }
            let length = CMBlockBufferGetDataLength(blockBuffer)
            let count = length / MemoryLayout<Int16>.size
            guard count > 0 else { continue }
            var ints = [Int16](repeating: 0, count: count)
            let status = ints.withUnsafeMutableBytes { raw -> OSStatus in
                guard let base = raw.baseAddress else { return kCMBlockBufferBadPointerParameterErr }
                return CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: count * MemoryLayout<Int16>.size, destination: base)
            }
            guard status == kCMBlockBufferNoErr else { continue }
            var floats = [Float](repeating: 0, count: count)
            vDSP_vflt16(ints, 1, &floats, 1, vDSP_Length(count))
            var scale: Float = 1.0 / 32768.0
            vDSP_vsmul(floats, 1, &scale, &floats, 1, vDSP_Length(count))
            pending.append(contentsOf: floats)
            totalSamples += count

            var offset = 0
            while pending.count - offset >= windowSamples {
                windowRMS.append(rms(pending[offset..<(offset + windowSamples)]))
                offset += windowSamples
            }
            pending.removeFirst(offset)

            let processed = Double(totalSamples) / sampleRate
            if processed >= nextProgressAt {
                progress?(processed, duration)
                nextProgressAt = processed + progressStepSeconds
            }
        }
        if !pending.isEmpty { windowRMS.append(rms(pending[...])) }

        if reader.status == .failed || reader.status == .cancelled {
            throw AudioAnalysisError.readerFailed(reader.error?.localizedDescription ?? "\(reader.status.rawValue)")
        }
        guard totalSamples > 0 else { throw AudioAnalysisError.noSamplesRead(duration: duration) }
        progress?(duration, duration)

        let threshold = silenceThreshold(windowRMS: windowRMS, fallback: options.silenceThresholdDB)
        return classify(windowRMS: windowRMS, thresholdDB: threshold, minSilence: options.minSilenceDuration, duration: duration)
    }

    /// Noise floor = 10th-percentile window RMS; silence = floor + 6 dB, clamped to [-50, -20] dB.
    static func silenceThreshold(windowRMS: [Float], fallback: Float) -> Float {
        guard windowRMS.count > 20 else { return fallback }
        let sorted = windowRMS.sorted()
        let floorRMS = sorted[min(sorted.count / 10, sorted.count - 1)]
        let floorDB: Float = floorRMS > 0 ? 20 * log10(floorRMS) : -100
        return max(min(floorDB + 6, -20), -50)
    }

    static func classify(windowRMS: [Float], thresholdDB: Float, minSilence: Double, duration: Double) -> AudioAnalysisResult {
        var segments: [AudioSegment] = []
        segments.reserveCapacity(windowRMS.count)
        var silenceIntervals: [ClosedRange<Double>] = []
        var energySum: Float = 0
        var peak: Float = 0
        var silenceStart: Double?

        for (i, value) in windowRMS.enumerated() {
            let dB: Float = value > 0 ? 20 * log10(value) : -100
            energySum += value
            peak = max(peak, value)
            let start = Double(i) * windowDuration
            let end = min(start + windowDuration, max(duration, start + windowDuration))

            let type: AudioSegmentType
            if value > clippingThreshold {
                type = .clipping
            } else if dB < thresholdDB {
                type = .silence
            } else if dB < thresholdDB + 8 {
                type = .lowEnergy
            } else {
                type = .speech
            }
            segments.append(AudioSegment(startTime: start, endTime: end, type: type, energy: value))

            if type == .silence {
                if silenceStart == nil { silenceStart = start }
            } else if let s = silenceStart {
                if start - s >= minSilence { silenceIntervals.append(s...start) }
                silenceStart = nil
            }
        }
        if let s = silenceStart {
            let end = Double(windowRMS.count) * windowDuration
            if end - s >= minSilence { silenceIntervals.append(s...end) }
        }

        return AudioAnalysisResult(
            segments: segments,
            silenceIntervals: silenceIntervals,
            averageEnergy: windowRMS.isEmpty ? 0 : energySum / Float(windowRMS.count),
            peakEnergy: peak,
            duration: duration
        )
    }

    private static func rms(_ slice: ArraySlice<Float>) -> Float {
        var value: Float = 0
        slice.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress, !buffer.isEmpty else { return }
            vDSP_rmsqv(base, 1, &value, vDSP_Length(buffer.count))
        }
        return value
    }
}
