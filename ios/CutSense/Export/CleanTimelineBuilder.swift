import AVFoundation
import CoreGraphics

struct CleanTimeline: @unchecked Sendable {
    let composition: AVMutableComposition
    let videoTrack: AVMutableCompositionTrack
    let audioTrack: AVMutableCompositionTrack
    let totalDuration: CMTime
    let sourceRanges: [TimelineRange]
    let sourceTransform: CGAffineTransform
}

enum CleanTimelineBuilder {
    enum TimelineError: Error, LocalizedError {
        case noVideoTrack
        case noAudioTrack
        case noIncludedRanges
        case insertFailed(String)

        var errorDescription: String? {
            switch self {
            case .noVideoTrack: "Source video has no video track."
            case .noAudioTrack: "Source video has no audio track."
            case .noIncludedRanges: "No timeline-included ranges were produced from rough cut decisions."
            case .insertFailed(let msg): "Timeline insert failed: \(msg)"
            }
        }
    }

    /// Audio crossfade duration at cut boundaries (increased from 0.05s to reduce stutter perception)
    private static let crossfadeDuration: Double = 0.15

    static func build(
        from sourceURL: URL,
        decisions: [RoughCutDecision]
    ) async throws -> CleanTimeline {
        let asset = AVURLAsset(url: sourceURL)

        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)

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

        let includedRanges = TimelineRangeNormalizer.includedRanges(
            from: decisions,
            assetDuration: durationSeconds
        )

        guard !includedRanges.isEmpty else {
            guard decisions.isEmpty else {
                throw TimelineError.noIncludedRanges
            }

            let timeRange = CMTimeRange(start: .zero, duration: duration)
            try compVideoTrack.insertTimeRange(timeRange, of: sourceVideoTrack, at: .zero)
            if let sourceAudioTrack = audioTracks.first {
                try compAudioTrack.insertTimeRange(timeRange, of: sourceAudioTrack, at: .zero)
            }
            let sourceRanges = durationSeconds.isFinite && durationSeconds > 0
                ? [TimelineRange(startTime: 0, endTime: durationSeconds)]
                : []
            return CleanTimeline(
                composition: composition,
                videoTrack: compVideoTrack,
                audioTrack: compAudioTrack,
                totalDuration: duration,
                sourceRanges: sourceRanges,
                sourceTransform: transform
            )
        }

        var insertTime = CMTime.zero

        for range in includedRanges {
            let startCM = CMTime(seconds: range.startTime, preferredTimescale: 600)
            let endCM = CMTime(seconds: range.endTime, preferredTimescale: 600)
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
            totalDuration: insertTime,
            sourceRanges: includedRanges,
            sourceTransform: transform
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

    /// Merge adjacent keep decisions whose gap is below `maxGap` seconds. Removes the tiny
    /// sample-boundary jolts that AVFoundation produces when inserting back-to-back ranges.
    /// Preserves all other metadata from the FIRST decision in each coalesced run.
    static func coalesceTinyGaps(_ keeps: [RoughCutDecision], maxGap: Double) -> [RoughCutDecision] {
        guard keeps.count > 1 else { return keeps }
        var result: [RoughCutDecision] = []
        var current = keeps[0]
        for next in keeps.dropFirst() {
            if next.startTime - current.endTime <= maxGap {
                // Extend current to absorb next (and any silence between)
                current = RoughCutDecision(
                    startTime: current.startTime,
                    endTime: max(current.endTime, next.endTime),
                    action: .keep,
                    reason: current.reason,
                    confidence: min(current.confidence, next.confidence),
                    linkedTranscriptText: current.linkedTranscriptText,
                    requiresReview: current.requiresReview || next.requiresReview
                )
            } else {
                result.append(current)
                current = next
            }
        }
        result.append(current)
        return result
    }
}
