import AVFoundation

enum AudioMixService {
    struct MixConfig: Sendable {
        let voiceBoostDB: Float
        let backgroundVolume: Float
        let sfxVolume: Float
        let fadeInDuration: Double
        let fadeOutDuration: Double
    }

    static func createMix(
        for composition: AVMutableComposition,
        template: TemplateConfig
    ) -> AVMutableAudioMix {
        let audioMix = AVMutableAudioMix()
        var params: [AVMutableAudioMixInputParameters] = []

        let audioTracks = composition.tracks(withMediaType: .audio)

        for track in audioTracks {
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
