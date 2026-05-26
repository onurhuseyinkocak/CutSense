import AVFoundation
import Accelerate

/// Offline parametric EQ processor for voice clarity.
/// Applies frequency-domain processing via cascaded biquad filters:
/// - High-pass at 80Hz (removes rumble/room noise)
/// - Warmth peak +1.5dB at 250Hz (body/presence for thin voices)
/// - Presence boost +5.5dB at 3.5kHz (voice clarity/presence zone)
/// - Air boost +2.5dB at 5kHz (articulation/consonants)
/// - De-ess peaks: -3.5dB at 7kHz + -2dB at 9kHz (thorough sibilance control)
/// - Noise gate + compressor with makeup gain
/// - Soft-clip limiter at 0.95 (transparent peak protection)
/// - Normalization to -1dBFS
enum VoiceEQProcessor {
    private static let processSampleRate: Double = 44100

    struct EQResult: Sendable {
        let processedAudioURL: URL
        let sampleRate: Double
        let channelCount: Int
    }

    /// Process source video's audio track with parametric voice EQ.
    /// Returns URL of processed .caf audio file.
    static func process(sourceURL: URL) async throws -> EQResult {
        let (samples, channels) = try await readAudioSamples(from: sourceURL)
        guard !samples.isEmpty else {
            throw EQError.noAudioData
        }

        // Apply cascaded biquad EQ
        let processed = applyEQ(to: samples, sampleRate: Float(processSampleRate))

        // Write to temp .caf file
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CutSense/eq", isDirectory: true)
            .appendingPathComponent("voice_eq_\(UUID().uuidString.prefix(8)).caf")
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        try writeAudio(samples: processed, to: outputURL, sampleRate: processSampleRate, channels: channels)

        return EQResult(
            processedAudioURL: outputURL,
            sampleRate: processSampleRate,
            channelCount: channels
        )
    }

    /// Clean up processed audio temp files
    static func cleanup() {
        let eqDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CutSense/eq", isDirectory: true)
        try? FileManager.default.removeItem(at: eqDir)
    }

    // MARK: - EQ Core

    private static func applyEQ(to samples: [Float], sampleRate: Float) -> [Float] {
        var output = samples

        // High-pass: remove rumble/room noise below 80Hz
        let hp = biquadHighPass(freq: 80, q: 0.707, sampleRate: sampleRate)
        applyBiquadInPlace(hp, to: &output)

        // Warmth: gentle +1.5dB peak at 250Hz for body (fixes thin voices)
        let warmth = biquadPeak(freq: 250, gainDB: 1.5, q: 1.2, sampleRate: sampleRate)
        applyBiquadInPlace(warmth, to: &output)

        // Presence: +5.5dB peak at 3.5kHz for clarity
        let presence = biquadPeak(freq: 3500, gainDB: 5.5, q: 2.0, sampleRate: sampleRate)
        applyBiquadInPlace(presence, to: &output)

        // Air: +2.5dB peak at 5kHz for articulation
        let air = biquadPeak(freq: 5000, gainDB: 2.5, q: 2.0, sampleRate: sampleRate)
        applyBiquadInPlace(air, to: &output)

        // De-ess: primary peak at 7kHz -3.5dB
        let deess = biquadPeak(freq: 7000, gainDB: -3.5, q: 3.0, sampleRate: sampleRate)
        applyBiquadInPlace(deess, to: &output)

        // De-ess: secondary peak at 9kHz -2dB for wider sibilance control
        let deess2 = biquadPeak(freq: 9000, gainDB: -2.0, q: 2.5, sampleRate: sampleRate)
        applyBiquadInPlace(deess2, to: &output)

        // Noise gate: attenuate quiet parts
        applyNoiseGateInPlace(to: &output, sampleRate: sampleRate)

        // Dynamics compressor with makeup gain: even out loud/quiet + restore level
        applyCompressorWithMakeupGainInPlace(to: &output, sampleRate: sampleRate)

        // Soft-clip limiter: transparent peak protection above 0.98
        applySoftClipLimiter(to: &output, threshold: 0.98)

        // Normalize to -0.5dBFS (0.944 linear) for more headroom
        var peak: Float = 0
        vDSP_maxmgv(output, 1, &peak, vDSP_Length(output.count))
        if peak > 0.944 {
            let target: Float = 0.944
            var scale = target / peak
            vDSP_vsmul(output, 1, &scale, &output, 1, vDSP_Length(output.count))
        }

        return output
    }

    // MARK: - Noise Gate

    /// Noise gate in-place: attenuate samples in windows where RMS is below threshold.
    private static func applyNoiseGateInPlace(to output: inout [Float], sampleRate: Float) {
        let windowSize = Int(0.02 * sampleRate)
        guard windowSize > 0, output.count > windowSize else { return }

        let thresholdLinear = powf(10, -40.0 / 20.0)
        let attenuation: Float = 0.05
        var gateGain: Float = 1.0
        let attackRate: Float = 1.0 / Float(max(Int(0.005 * sampleRate), 1))
        let releaseRate: Float = 1.0 / Float(max(Int(0.05 * sampleRate), 1))

        var windowIdx = 0
        while windowIdx < output.count {
            let end = min(windowIdx + windowSize, output.count)
            // Compute RMS directly from output buffer (no slice copy)
            var rms: Float = 0
            output.withUnsafeBufferPointer { buf in
                guard let base = buf.baseAddress else { return }
                vDSP_rmsqv(base + windowIdx, 1, &rms, vDSP_Length(end - windowIdx))
            }

            let targetGain: Float = rms > thresholdLinear ? 1.0 : attenuation
            let rate = targetGain > gateGain ? attackRate : releaseRate

            for i in windowIdx..<end {
                if gateGain < targetGain {
                    gateGain = min(gateGain + rate, targetGain)
                } else {
                    gateGain = max(gateGain - rate, targetGain)
                }
                output[i] *= gateGain
            }
            windowIdx = end
        }
    }

    // MARK: - Dynamics Compressor with Makeup Gain

    /// Soft-knee compressor for voice: evens out loud/quiet passages.
    /// Threshold -18 dBFS, ratio 3:1, 5ms attack, 50ms release.
    /// Includes makeup gain to restore perceived loudness after compression.
    private static func applyCompressorWithMakeupGainInPlace(to output: inout [Float], sampleRate: Float) {
        let count = output.count
        guard count > 0 else { return }

        let thresholdDB: Float = -18.0
        let thresholdLinear = powf(10, thresholdDB / 20.0)
        let ratio: Float = 3.0 // 3:1 compression above threshold
        let attackSamples = max(Int(0.005 * sampleRate), 1) // 5ms attack
        let releaseSamples = max(Int(0.050 * sampleRate), 1) // 50ms release
        let attackCoeff: Float = 1.0 / Float(attackSamples)
        let releaseCoeff: Float = 1.0 / Float(releaseSamples)

        var envelope: Float = 0
        var totalGainReductionDB: Float = 0
        var gainReductionSamples: Int = 0

        for i in 0..<count {
            let absVal = abs(output[i])

            // Smooth envelope follower
            if absVal > envelope {
                envelope += attackCoeff * (absVal - envelope)
            } else {
                envelope += releaseCoeff * (absVal - envelope)
            }

            // Compute gain reduction above threshold
            if envelope > thresholdLinear {
                let overDB = 20 * log10(envelope / thresholdLinear)
                let reducedDB = overDB / ratio
                let gainDB = reducedDB - overDB
                let gainLinear = powf(10, gainDB / 20.0)
                output[i] *= gainLinear
                totalGainReductionDB += -gainDB // accumulate positive reduction
                gainReductionSamples += 1
            }
        }

        // Calculate average gain reduction and apply makeup gain
        // Typical: 3dB reduction at -18dB threshold → +2.5 to +3.5dB makeup
        let avgGainReductionDB = gainReductionSamples > 0
            ? totalGainReductionDB / Float(gainReductionSamples)
            : 0.0

        // Apply makeup gain: restore 90% of average reduction to avoid over-leveling
        let makeupGainDB = avgGainReductionDB * 0.9
        let makeupGainLinear = powf(10, makeupGainDB / 20.0)
        var scale = makeupGainLinear
        vDSP_vsmul(output, 1, &scale, &output, 1, vDSP_Length(count))
    }

    // MARK: - Soft-Clip Limiter

    /// Soft-clip limiter using tanh for transparent peak protection.
    /// Samples above threshold are soft-clipped to prevent harsh digital clipping.
    private static func applySoftClipLimiter(to output: inout [Float], threshold: Float) {
        let count = output.count
        guard count > 0 else { return }

        for i in 0..<count {
            let sample = output[i]
            let absVal = abs(sample)

            if absVal > threshold {
                // Soft-clip using tanh: smooth knee above threshold
                let clipped = threshold * tanh(sample / threshold)
                output[i] = clipped
            }
        }
    }

    // MARK: - Biquad Filter Coefficients

    /// 5-element array: [b0, b1, b2, a1, a2] (a0 normalized to 1)
    private typealias BiquadCoeffs = [Double]

    private static func biquadHighPass(freq: Float, q: Float, sampleRate: Float) -> BiquadCoeffs {
        let w0 = 2.0 * Double.pi * Double(freq) / Double(sampleRate)
        let alpha = sin(w0) / (2.0 * Double(q))
        let cosW0 = cos(w0)

        let b0 = (1.0 + cosW0) / 2.0
        let b1 = -(1.0 + cosW0)
        let b2 = (1.0 + cosW0) / 2.0
        let a0 = 1.0 + alpha
        let a1 = -2.0 * cosW0
        let a2 = 1.0 - alpha

        return [b0/a0, b1/a0, b2/a0, a1/a0, a2/a0]
    }

    private static func biquadPeak(freq: Float, gainDB: Float, q: Float, sampleRate: Float) -> BiquadCoeffs {
        let A = pow(10.0, Double(gainDB) / 40.0)
        let w0 = 2.0 * Double.pi * Double(freq) / Double(sampleRate)
        let alpha = sin(w0) / (2.0 * Double(q))
        let cosW0 = cos(w0)

        let b0 = 1.0 + alpha * A
        let b1 = -2.0 * cosW0
        let b2 = 1.0 - alpha * A
        let a0 = 1.0 + alpha / A
        let a1 = -2.0 * cosW0
        let a2 = 1.0 - alpha / A

        return [b0/a0, b1/a0, b2/a0, a1/a0, a2/a0]
    }

    private static func applyBiquadInPlace(_ coeffs: BiquadCoeffs, to buffer: inout [Float]) {
        let count = buffer.count
        guard count > 0 else { return }

        let b0 = Float(coeffs[0])
        let b1 = Float(coeffs[1])
        let b2 = Float(coeffs[2])
        let a1 = Float(coeffs[3])
        let a2 = Float(coeffs[4])

        var xn1: Float = 0, xn2: Float = 0
        var yn1: Float = 0, yn2: Float = 0

        for i in 0..<count {
            let x = buffer[i]
            let y = b0 * x + b1 * xn1 + b2 * xn2 - a1 * yn1 - a2 * yn2
            buffer[i] = y
            xn2 = xn1; xn1 = x
            yn2 = yn1; yn1 = y
        }
    }

    // MARK: - Audio I/O

    private static func readAudioSamples(from url: URL) async throws -> ([Float], Int) {
        let asset = AVURLAsset(url: url)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard let track = audioTracks.first else {
            throw EQError.noAudioTrack
        }

        let reader = try AVAssetReader(asset: asset)
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVNumberOfChannelsKey: 1,
            AVSampleRateKey: processSampleRate
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        reader.add(output)
        reader.startReading()

        var allSamples: [Float] = []
        allSamples.reserveCapacity(Int(processSampleRate) * 120) // ~2 min pre-alloc

        while let buffer = output.copyNextSampleBuffer(),
              let blockBuffer = CMSampleBufferGetDataBuffer(buffer) {
            let length = CMBlockBufferGetDataLength(blockBuffer)
            var data = Data(count: length)
            data.withUnsafeMutableBytes { ptr in
                guard let base = ptr.baseAddress else { return }
                CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: base)
            }
            let floatCount = length / MemoryLayout<Float>.size
            let floats: [Float] = data.withUnsafeBytes { raw in
                let floatPtr = raw.bindMemory(to: Float.self)
                return Array(UnsafeBufferPointer(start: floatPtr.baseAddress, count: floatCount))
            }
            allSamples.append(contentsOf: floats)
        }

        // Detect original channel count for output
        let origChannels: Int
        if let formatDesc = try? await track.load(.formatDescriptions).first {
            let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)
            origChannels = Int(asbd?.pointee.mChannelsPerFrame ?? 1)
        } else {
            origChannels = 1
        }

        return (allSamples, min(origChannels, 2))
    }

    private static func writeAudio(samples: [Float], to url: URL, sampleRate: Double, channels: Int) throws {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: AVAudioChannelCount(1), // mono processed
            interleaved: false
        ) else {
            throw EQError.bufferCreationFailed
        }

        let frameCount = AVAudioFrameCount(samples.count)
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw EQError.bufferCreationFailed
        }
        pcmBuffer.frameLength = frameCount

        // Copy samples into buffer
        guard let channelData = pcmBuffer.floatChannelData?[0] else {
            throw EQError.bufferCreationFailed
        }
        samples.withUnsafeBufferPointer { src in
            guard let srcBase = src.baseAddress else { return }
            channelData.update(from: srcBase, count: samples.count)
        }

        // Write as .caf
        let audioFile = try AVAudioFile(
            forWriting: url,
            settings: format.settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        try audioFile.write(from: pcmBuffer)
    }

    enum EQError: Error, LocalizedError {
        case noAudioTrack
        case noAudioData
        case bufferCreationFailed

        var errorDescription: String? {
            switch self {
            case .noAudioTrack: "Source has no audio track for EQ processing."
            case .noAudioData: "Could not read audio data for EQ processing."
            case .bufferCreationFailed: "Failed to create audio buffer for EQ output."
            }
        }
    }
}
