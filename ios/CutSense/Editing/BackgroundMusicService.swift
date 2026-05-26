import AVFoundation
import Accelerate

/// Generates and inserts ambient background music into export compositions.
/// Each template maps to a mood that produces a distinct synthesized ambient pad.
/// Auto-ducks under voice segments for professional mixing.
enum BackgroundMusicService {

    enum Mood: String {
        case warmPad       // Premium Founder, Cinematic — warm low drone
        case energyPulse   // Viral Caption — rhythmic subtle pulse
        case cleanAmbient  // Clean Expert — airy, minimal texture
        case softDrone     // Podcast Highlights — barely-there hum
    }

    /// Map template to music mood
    static func mood(for template: TemplateConfig) -> Mood {
        switch template.id {
        case "tech_influencer", "viral_caption", "motivation_fire", "street_vlog": .energyPulse
        case "clean_expert", "beauty_lifestyle": .cleanAmbient
        case "podcast_highlights", "asmr_relaxing": .softDrone
        case "cinematic_storyteller", "tech_review": .warmPad
        default: .warmPad
        }
    }

    /// Generate ambient loop, insert into composition, return the BGM track for audio mix params.
    /// `voiceSegments` are (start, end) pairs in clean-timeline coordinates for auto-ducking.
    static func insertBackgroundMusic(
        into composition: AVMutableComposition,
        duration: CMTime,
        mood: Mood,
        volume: Float,
        voiceSegments: [(start: Double, end: Double)],
        packageSelection: EditPackageSelection? = nil
    ) async -> AVMutableCompositionTrack? {
        guard volume > 0.005 else { return nil }

        let loopURL: URL
        if let packageSelection,
           let item = AssetRegistry.musicItem(for: packageSelection),
           let url = AssetRegistry.bundleURL(for: item) {
            loopURL = url
        } else if let item = registryFallbackMusic(for: mood),
                  let url = AssetRegistry.bundleURL(for: item) {
            loopURL = url
        } else {
            do {
            loopURL = try await generateLoop(mood: mood, seconds: 10.0)
            } catch {
                #if DEBUG
                print("[BGM] Loop generation failed: \(error)")
                #endif
                return nil
            }
        }

        let loopAsset = AVURLAsset(url: loopURL)
        guard let loopAudioTrack = try? await loopAsset.loadTracks(withMediaType: .audio).first else {
            return nil
        }
        let loopDuration = try? await loopAsset.load(.duration)
        guard let loopDur = loopDuration, CMTimeGetSeconds(loopDur) > 0 else { return nil }

        guard let bgmTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else { return nil }

        // Loop the ambient pad to fill the entire composition duration
        let totalSeconds = CMTimeGetSeconds(duration)
        var insertTime = CMTime.zero
        let loopRange = CMTimeRange(start: .zero, duration: loopDur)

        while CMTimeGetSeconds(insertTime) < totalSeconds {
            let remaining = CMTimeSubtract(duration, insertTime)
            let insertRange: CMTimeRange
            if CMTimeCompare(remaining, loopDur) < 0 {
                insertRange = CMTimeRange(start: .zero, duration: remaining)
            } else {
                insertRange = loopRange
            }
            do {
                try bgmTrack.insertTimeRange(insertRange, of: loopAudioTrack, at: insertTime)
            } catch {
                #if DEBUG
                print("[BGM] Insert failed at \(CMTimeGetSeconds(insertTime))s: \(error)")
                #endif
                break
            }
            insertTime = CMTimeAdd(insertTime, loopDur)
        }

        return bgmTrack
    }

    private static func registryFallbackMusic(for mood: Mood) -> AssetRegistryItem? {
        let category: String = switch mood {
        case .warmPad:
            "cinematic"
        case .energyPulse:
            "tech"
        case .cleanAmbient:
            "minimal"
        case .softDrone:
            "minimal"
        }

        return AssetRegistry.items(type: .music, category: category).first
    }

    /// Build audio mix parameters for the BGM track with auto-ducking around voice.
    static func duckingParams(
        for track: AVMutableCompositionTrack,
        duration: CMTime,
        baseVolume: Float,
        voiceSegments: [(start: Double, end: Double)]
    ) -> AVMutableAudioMixInputParameters {
        let params = AVMutableAudioMixInputParameters(track: track)
        let duckedVolume = baseVolume * 0.68
        let rampDuration = 0.14
        let totalDuration = max(0, CMTimeGetSeconds(duration))

        // Merge overlapping/adjacent voice segments to prevent conflicting ramps.
        let sorted = voiceSegments
            .map { (start: max(0, $0.start), end: min(totalDuration, $0.end)) }
            .filter { $0.end > $0.start }
            .sorted { $0.start < $1.start }
        var merged: [(start: Double, end: Double)] = []
        for seg in sorted {
            if let last = merged.last, seg.start <= last.end + rampDuration * 2.5 {
                merged[merged.count - 1] = (start: last.start, end: max(last.end, seg.end))
            } else {
                merged.append(seg)
            }
        }

        var lastRampEnd = 0.0
        func addRamp(from startVolume: Float, to endVolume: Float, start: Double, duration: Double) {
            let clampedStart = max(start, lastRampEnd)
            let clampedEnd = min(totalDuration, clampedStart + duration)
            guard clampedEnd - clampedStart > 0.01 else { return }
            params.setVolumeRamp(
                fromStartVolume: startVolume,
                toEndVolume: endVolume,
                timeRange: CMTimeRange(
                    start: CMTime(seconds: clampedStart, preferredTimescale: 600),
                    duration: CMTime(seconds: clampedEnd - clampedStart, preferredTimescale: 600)
                )
            )
            lastRampEnd = clampedEnd
        }

        let startsUnderSpeech = merged.first.map { $0.start <= 0.5 } ?? false
        if startsUnderSpeech {
            params.setVolume(duckedVolume, at: .zero)
        } else {
            addRamp(from: 0, to: baseVolume, start: 0, duration: min(0.5, totalDuration))
        }

        // Duck under each voice segment
        for seg in merged {
            // Ramp down before voice starts
            let duckStart = max(0, seg.start - rampDuration)
            if duckStart >= lastRampEnd + 0.01 {
                addRamp(
                    from: baseVolume,
                    to: duckedVolume,
                    start: duckStart,
                    duration: min(rampDuration, max(0, seg.start - duckStart))
                )
            }

            // Ramp back up after voice ends
            addRamp(
                from: duckedVolume,
                to: baseVolume,
                start: max(seg.end, lastRampEnd),
                duration: rampDuration
            )
        }

        // Fade out at end
        addRamp(
            from: baseVolume,
            to: 0,
            start: max(0, totalDuration - 1.0),
            duration: 1.0
        )

        return params
    }

    // MARK: - Ambient Loop Synthesis

    private static let sampleRate: Double = 44100
    private static let channels: Int = 1

    /// Generate a loopable ambient pad as a .caf file, cached per mood.
    private static func generateLoop(mood: Mood, seconds: Double) async throws -> URL {
        let cacheDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CutSense/bgm", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        let cacheURL = cacheDir.appendingPathComponent("\(mood.rawValue)_v2.caf")

        // Return cached if exists
        if FileManager.default.fileExists(atPath: cacheURL.path) {
            return cacheURL
        }

        let totalSamples = Int(sampleRate * seconds)
        var samples = [Float](repeating: 0, count: totalSamples)

        switch mood {
        case .warmPad:
            synthesizeWarmPad(&samples, count: totalSamples)
        case .energyPulse:
            synthesizeEnergyPulse(&samples, count: totalSamples)
        case .cleanAmbient:
            synthesizeCleanAmbient(&samples, count: totalSamples)
        case .softDrone:
            synthesizeSoftDrone(&samples, count: totalSamples)
        }

        // Apply loop-friendly crossfade (first/last 500ms)
        let crossfadeSamples = min(Int(0.5 * sampleRate), totalSamples / 4)
        for i in 0..<crossfadeSamples {
            let fade = Float(i) / Float(crossfadeSamples)
            samples[i] *= fade
            samples[totalSamples - 1 - i] *= fade
        }

        // Normalize peak to -6dB
        var peak: Float = 0
        vDSP_maxmgv(samples, 1, &peak, vDSP_Length(totalSamples))
        if peak > 0 {
            let targetPeak: Float = 0.5 // -6dB
            var scale = targetPeak / peak
            vDSP_vsmul(samples, 1, &scale, &samples, 1, vDSP_Length(totalSamples))
        }

        try writeCAF(samples: samples, to: cacheURL)
        return cacheURL
    }

    // MARK: - Synthesis

    private static func synthesizeWarmPad(_ samples: inout [Float], count: Int) {
        // Warm pad with midrange harmonics so it remains audible on phone speakers.
        let freqs: [Float] = [130.81, 196.0, 261.63, 392.0, 523.25]
        let amps: [Float] = [0.34, 0.22, 0.16, 0.10, 0.06]
        let lfoRate: Float = 0.3 // Hz

        for i in 0..<count {
            let t = Float(i) / Float(sampleRate)
            let lfo = 1.0 + 0.15 * sinf(2 * .pi * lfoRate * t)
            var sample: Float = 0
            for (f, a) in zip(freqs, amps) {
                sample += a * sinf(2 * .pi * f * t) * lfo
            }
            samples[i] = sample
        }
    }

    private static func synthesizeEnergyPulse(_ samples: inout [Float], count: Int) {
        // Subtle rhythmic pulse: bass plus mid harmonic for small speakers.
        let baseFreq: Float = 164.81 // E3
        let pulseRate: Float = 2.0   // 120 BPM feel

        for i in 0..<count {
            let t = Float(i) / Float(sampleRate)
            // Pulse envelope (smooth sine-shaped)
            let pulse = 0.5 + 0.5 * sinf(2 * .pi * pulseRate * t)
            let envelope = pulse * pulse // Sharper pulse
            let tone = 0.28 * sinf(2 * .pi * baseFreq * t) + 0.18 * sinf(2 * .pi * baseFreq * 2 * t)
            samples[i] = tone * envelope
        }
    }

    private static func synthesizeCleanAmbient(_ samples: inout [Float], count: Int) {
        // Airy texture: high shimmer with slow detuned oscillators
        let freqs: [Float] = [523.25, 659.26, 783.99] // C5, E5, G5 (major chord)
        let detune: [Float] = [0.0, 0.5, -0.3] // Slight detuning for width

        for i in 0..<count {
            let t = Float(i) / Float(sampleRate)
            let lfo = 1.0 + 0.1 * sinf(2 * .pi * 0.15 * t)
            var sample: Float = 0
            for (f, d) in zip(freqs, detune) {
                sample += 0.12 * sinf(2 * .pi * (f + d) * t) * lfo
            }
            samples[i] = sample
        }
    }

    private static func synthesizeSoftDrone(_ samples: inout [Float], count: Int) {
        // Barely-there drone with a soft mid harmonic for phone playback.
        let freq: Float = 110.0 // A2
        let breathRate: Float = 0.08 // Very slow

        for i in 0..<count {
            let t = Float(i) / Float(sampleRate)
            let breath = 0.6 + 0.4 * sinf(2 * .pi * breathRate * t)
            let tone = 0.22 * sinf(2 * .pi * freq * t) + 0.12 * sinf(2 * .pi * freq * 2 * t)
            samples[i] = tone * breath
        }
    }

    // MARK: - File Writing

    private static func writeCAF(samples: [Float], to url: URL) throws {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: AVAudioChannelCount(channels),
            interleaved: false
        ) else {
            throw NSError(domain: "BGM", code: 2, userInfo: [NSLocalizedDescriptionKey: "Audio format creation failed"])
        }

        let frameCount = AVAudioFrameCount(samples.count)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw NSError(domain: "BGM", code: 1, userInfo: [NSLocalizedDescriptionKey: "Buffer creation failed"])
        }
        buffer.frameLength = frameCount

        guard let channelData = buffer.floatChannelData?[0] else {
            throw NSError(domain: "BGM", code: 3, userInfo: [NSLocalizedDescriptionKey: "Channel data unavailable"])
        }
        samples.withUnsafeBufferPointer { src in
            guard let srcBase = src.baseAddress else { return }
            channelData.update(from: srcBase, count: samples.count)
        }

        let file = try AVAudioFile(
            forWriting: url,
            settings: format.settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        try file.write(from: buffer)
    }
}
