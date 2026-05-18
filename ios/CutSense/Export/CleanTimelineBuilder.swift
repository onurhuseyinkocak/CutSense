import AVFoundation

struct CleanTimeline {
    let composition: AVMutableComposition
    let videoTrack: AVMutableCompositionTrack
    let audioTrack: AVMutableCompositionTrack
    let totalDuration: CMTime
}

enum CleanTimelineBuilder {
    enum TimelineError: Error, LocalizedError {
        case noVideoTrack
        case noAudioTrack
        case insertFailed(String)

        var errorDescription: String? {
            switch self {
            case .noVideoTrack: "Source video has no video track."
            case .noAudioTrack: "Source video has no audio track."
            case .insertFailed(let msg): "Timeline insert failed: \(msg)"
            }
        }
    }

    /// Audio crossfade duration at cut boundaries
    private static let crossfadeDuration: Double = 0.05

    static func build(
        from sourceURL: URL,
        decisions: [RoughCutDecision]
    ) async throws -> CleanTimeline {
        let asset = AVURLAsset(url: sourceURL)

        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)

        guard let sourceVideoTrack = videoTracks.first else {
            throw TimelineError.noVideoTrack
        }

        let composition = AVMutableComposition()

        guard let compVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw TimelineError.insertFailed("Could not create video track")
        }

        guard let compAudioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw TimelineError.insertFailed("Could not create audio track")
        }

        // Copy video track transform
        let transform = try await sourceVideoTrack.load(.preferredTransform)
        compVideoTrack.preferredTransform = transform

        // Get keep segments, sorted by time
        let keepSegments = decisions
            .filter { $0.action == .keep }
            .sorted { $0.startTime < $1.startTime }

        guard !keepSegments.isEmpty else {
            // If no explicit keep segments, keep entire video
            let duration = try await asset.load(.duration)
            let timeRange = CMTimeRange(start: .zero, duration: duration)
            try compVideoTrack.insertTimeRange(timeRange, of: sourceVideoTrack, at: .zero)
            if let sourceAudioTrack = audioTracks.first {
                try compAudioTrack.insertTimeRange(timeRange, of: sourceAudioTrack, at: .zero)
            }
            return CleanTimeline(
                composition: composition,
                videoTrack: compVideoTrack,
                audioTrack: compAudioTrack,
                totalDuration: duration
            )
        }

        var insertTime = CMTime.zero

        for segment in keepSegments {
            let startCM = CMTime(seconds: segment.startTime, preferredTimescale: 600)
            let endCM = CMTime(seconds: segment.endTime, preferredTimescale: 600)
            let timeRange = CMTimeRange(start: startCM, end: endCM)

            do {
                try compVideoTrack.insertTimeRange(timeRange, of: sourceVideoTrack, at: insertTime)
                if let sourceAudioTrack = audioTracks.first {
                    try compAudioTrack.insertTimeRange(timeRange, of: sourceAudioTrack, at: insertTime)
                }
                insertTime = insertTime + timeRange.duration
            } catch {
                throw TimelineError.insertFailed(error.localizedDescription)
            }
        }

        return CleanTimeline(
            composition: composition,
            videoTrack: compVideoTrack,
            audioTrack: compAudioTrack,
            totalDuration: insertTime
        )
    }

    /// Creates audio mix with crossfades at cut boundaries
    static func audioMixWithFades(
        timeline: CleanTimeline,
        template: TemplateConfig
    ) -> AVMutableAudioMix {
        // Only boost the main audio track, not SFX tracks added later
        let mainTrackIDs: Set<CMPersistentTrackID> = [timeline.audioTrack.trackID]
        let baseMix = AudioMixService.createMix(for: timeline.composition, template: template, mainTrackIDs: mainTrackIDs)

        // Add fade-out at end (skip if timeline too short)
        let durationSeconds = CMTimeGetSeconds(timeline.totalDuration)
        guard durationSeconds > 0.5 else { return baseMix }
        let fadeOutStart = CMTimeSubtract(
            timeline.totalDuration,
            CMTime(seconds: 0.5, preferredTimescale: 600)
        )
        let fadeOutRange = CMTimeRange(
            start: fadeOutStart,
            duration: CMTime(seconds: 0.5, preferredTimescale: 600)
        )

        for params in baseMix.inputParameters {
            if let mutableParams = params as? AVMutableAudioMixInputParameters {
                mutableParams.setVolumeRamp(
                    fromStartVolume: 1.0,
                    toEndVolume: 0.0,
                    timeRange: fadeOutRange
                )
            }
        }

        return baseMix
    }
}
