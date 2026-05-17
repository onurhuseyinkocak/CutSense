import AVFoundation

enum AudioMixService {
    struct MixConfig: Sendable {
        let voiceBoostDB: Float
        let backgroundVolume: Float
        let sfxVolume: Float
        let fadeInDuration: Double
        let fadeOutDuration: Double
    }

    /// Create audio mix for the main voice track(s) only.
    /// SFX tracks should NOT get voice boost — they get separate volume params.
    /// Pass `mainTrackIDs` to limit boost to only the original voice track.
    static func createMix(
        for composition: AVMutableComposition,
        template: TemplateConfig,
        mainTrackIDs: Set<CMPersistentTrackID>? = nil
    ) -> AVMutableAudioMix {
        let audioMix = AVMutableAudioMix()
        var params: [AVMutableAudioMixInputParameters] = []

        let audioTracks = composition.tracks(withMediaType: .audio)

        for track in audioTracks {
            // Only apply voice boost to main tracks, not SFX
            if let mainIDs = mainTrackIDs, !mainIDs.contains(track.trackID) {
                continue
            }

            let inputParams = AVMutableAudioMixInputParameters(track: track)

            // Apply voice boost via volume ramp
            let boostLinear = powf(10, template.voiceBoostDB / 20.0)
            inputParams.setVolume(min(boostLinear, 2.0), at: .zero)

            // Fade in at start
            inputParams.setVolumeRamp(
                fromStartVolume: 0,
                toEndVolume: min(boostLinear, 2.0),
                timeRange: CMTimeRange(
                    start: .zero,
                    duration: CMTime(seconds: 0.3, preferredTimescale: 600)
                )
            )

            params.append(inputParams)
        }

        audioMix.inputParameters = params
        return audioMix
    }

    static func mixConfigFrom(template: TemplateConfig) -> MixConfig {
        MixConfig(
            voiceBoostDB: template.voiceBoostDB,
            backgroundVolume: template.backgroundMusicVolume,
            sfxVolume: template.sfxVolume,
            fadeInDuration: 0.3,
            fadeOutDuration: 0.5
        )
    }
}
