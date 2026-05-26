import AVFoundation
import Accelerate

enum LoudnessNormalizer {
    /// Target integrated loudness — -14 LUFS (YouTube, IG, TikTok, Spotify standard)
    private static let targetLUFS: Float = -14.0
    /// Maximum gain to prevent over-amplification (dB)
    private static let maxGainDB: Float = 12.0
    /// Minimum gain (negative = attenuate loud sources)
    private static let minGainDB: Float = -6.0
    /// True-peak ceiling — -1 dBTP prevents inter-sample clipping on DACs
    private static let truePeakCeilingDB: Float = -1.0
    struct NormalizationResult: Sendable {
        let measuredLUFS: Float
        let gainDB: Float
        let gainLinear: Float
        /// Kept for API compatibility — always 1.0 now that VoiceEQProcessor handles real EQ
        let presenceBoostLinear: Float
        let wasNormalized: Bool
        /// Peak limiter attenuation (< 1.0 if gain would exceed true-peak ceiling)
        let peakLimiterGain: Float
    }

    /// Analyze source audio loudness and compute gain needed to reach -14 LUFS
    static func analyze(url: URL) async -> NormalizationResult {
        do {
            let samples = try await readAudioSamples(from: url)
            guard !samples.isEmpty else { return passthrough }

            let measuredLUFS = measureIntegratedLoudness(samples)

            // Compute gain needed
            var gainDB = targetLUFS - measuredLUFS
            gainDB = max(minGainDB, min(maxGainDB, gainDB))

            // Skip normalization if already close to target (within 1.5 dB)
            let needsNormalization = abs(gainDB) > 1.5

            let gainLinear = powf(10, gainDB / 20.0)

            // Peak limiter: measure peak, check if gain would exceed true-peak ceiling
            var peakLimiterGain: Float = 1.0
            if needsNormalization {
                var peak: Float = 0
                vDSP_maxmgv(samples, 1, &peak, vDSP_Length(samples.count))
                let peakAfterGain = peak * gainLinear
                let ceilingLinear = powf(10, truePeakCeilingDB / 20.0)
                if peakAfterGain > ceilingLinear {
                    peakLimiterGain = ceilingLinear / peakAfterGain
                }
            }

            return NormalizationResult(
                measuredLUFS: measuredLUFS,
                gainDB: gainDB,
                gainLinear: needsNormalization ? gainLinear : 1.0,
                presenceBoostLinear: 1.0,
                wasNormalized: needsNormalization,
                peakLimiterGain: peakLimiterGain
            )
        } catch {
            #if DEBUG
            print("[Loudness] Analysis failed: \(error)")
            #endif
            return passthrough
        }
    }

    /// Measure integrated loudness using ITU-R BS.1770 simplified (K-weighted RMS)
    /// Returns approximate LUFS value
    private static func measureIntegratedLoudness(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return -70.0 }

        // Step 1: K-weighting approximation
        // True K-weighting uses a pre-filter + RLB filter.
        // We approximate with a high-pass at ~100Hz (removes rumble) via first-order difference
        var kWeighted = [Float](repeating: 0, count: samples.count)
        kWeighted[0] = samples[0]
        for i in 1..<samples.count {
            // Simple high-pass: y[n] = 0.98 * (y[n-1] + x[n] - x[n-1])
            kWeighted[i] = 0.98 * (kWeighted[i - 1] + samples[i] - samples[i - 1])
        }

        // Step 2: Gated loudness measurement
        // Split into 400ms blocks, compute mean square, gate silent blocks
        let sampleRate: Int = 16000
        let blockSize = Int(0.4 * Double(sampleRate)) // 400ms blocks

        var blockLoudness: [Float] = []
        var offset = 0
        while offset + blockSize <= kWeighted.count {
            let blockSlice = Array(kWeighted[offset..<(offset + blockSize)])
            var meanSq: Float = 0
            vDSP_measqv(blockSlice, 1, &meanSq, vDSP_Length(blockSize))
            let blockLUFS = meanSq > 0 ? -0.691 + 10 * log10(meanSq) : -70.0
            blockLoudness.append(blockLUFS)
            offset += blockSize
        }

        guard !blockLoudness.isEmpty else { return -70.0 }

        // Step 3: Absolute gate at -70 LUFS
        let afterAbsGate = blockLoudness.filter { $0 > -70.0 }
        guard !afterAbsGate.isEmpty else { return -70.0 }

        // Ungated mean
        let ungatedMean = afterAbsGate.reduce(Float(0), +) / Float(afterAbsGate.count)

        // Step 4: Relative gate at -10 dB below ungated mean
        let relativeThreshold = ungatedMean - 10.0
        let afterRelGate = afterAbsGate.filter { $0 > relativeThreshold }
        guard !afterRelGate.isEmpty else { return ungatedMean }

        // Final integrated loudness
        return afterRelGate.reduce(Float(0), +) / Float(afterRelGate.count)
    }

    /// Read mono 16kHz audio samples from a URL
    private static func readAudioSamples(from url: URL) async throws -> [Float] {
        let asset = AVURLAsset(url: url)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard let track = audioTracks.first else { return [] }

        let reader = try AVAssetReader(asset: asset)
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVNumberOfChannelsKey: 1,
            AVSampleRateKey: 16000
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        reader.add(output)
        reader.startReading()

        var allSamples: [Float] = []
        // Cap at 5 minutes of audio — enough for accurate LUFS, prevents OOM on long videos
        let maxSamples = 16000 * 300
        allSamples.reserveCapacity(min(maxSamples, 16000 * 60))

        while allSamples.count < maxSamples,
              let buffer = output.copyNextSampleBuffer(),
              let blockBuffer = CMSampleBufferGetDataBuffer(buffer) {
            let length = CMBlockBufferGetDataLength(blockBuffer)
            var data = Data(count: length)
            data.withUnsafeMutableBytes { ptr in
                guard let base = ptr.baseAddress else { return }
                CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: base)
            }
            // Convert Int16 PCM to Float32 normalized
            let int16Count = length / 2
            let floats: [Float] = data.withUnsafeBytes { raw in
                let int16Ptr = raw.bindMemory(to: Int16.self)
                return (0..<int16Count).map { Float(int16Ptr[$0]) / 32768.0 }
            }
            allSamples.append(contentsOf: floats)
        }

        return allSamples
    }

    private static var passthrough: NormalizationResult {
        NormalizationResult(
            measuredLUFS: -14.0,
            gainDB: 0,
            gainLinear: 1.0,
            presenceBoostLinear: 1.0,
            wasNormalized: false,
            peakLimiterGain: 1.0
        )
    }
}
