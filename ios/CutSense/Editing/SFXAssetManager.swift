import AVFoundation

enum SFXAssetManager {
    enum SFXSound: String, CaseIterable {
        case whoosh
        case impact
        case pop
        case confirm
        case riser

        var filename: String { rawValue }
    }

    /// Maps an EditDecision's reason to the appropriate SFX sound
    static func sound(for decision: EditDecision) -> SFXSound? {
        guard decision.type == .sfx else { return nil }

        let reason = decision.reason.lowercased()
        if reason.contains("hook") {
            return .impact
        } else if reason.contains("whoosh") || reason.contains("transition") {
            return .whoosh
        } else if reason.contains("keyword") {
            return .pop
        } else if reason.contains("conclusion") || reason.contains("confirm") {
            return .confirm
        } else {
            return .riser
        }
    }

    /// Load the SFX audio asset from the bundle
    static func asset(for sfx: SFXSound) -> AVURLAsset? {
        guard let url = Bundle.main.url(forResource: sfx.filename, withExtension: "mp3") else {
            return nil
        }
        return AVURLAsset(url: url)
    }

    struct InsertResult {
        let tracks: [AVMutableCompositionTrack]
        let failedCount: Int
    }

    /// Insert SFX audio into the composition at EditDecision times.
    /// Reuses a single audio track for non-overlapping SFX to avoid track count issues.
    /// Returns tracks added and count of failures (for user feedback).
    @MainActor
    static func insertSFX(
        into composition: AVMutableComposition,
        decisions: [EditDecision],
        sfxVolume: Float
    ) async -> InsertResult {
        let sfxDecisions = decisions.filter { $0.type == .sfx }.sorted { $0.time < $1.time }
        guard !sfxDecisions.isEmpty else { return InsertResult(tracks: [], failedCount: 0) }

        // Use a single shared SFX track — all SFX are short and rarely overlap
        guard let sfxTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            return InsertResult(tracks: [], failedCount: sfxDecisions.count)
        }

        // Track occupied time ranges per track to detect overlaps
        var trackOccupiedEnd: [CMPersistentTrackID: Double] = [sfxTrack.trackID: 0]
        var overflowTrack: AVMutableCompositionTrack?
        var sfxTracks: [AVMutableCompositionTrack] = [sfxTrack]
        var failedCount = 0

        let compositionDuration = composition.duration.seconds

        for decision in sfxDecisions {
            guard let sfxSound = sound(for: decision),
                  let sfxAsset = asset(for: sfxSound) else {
                failedCount += 1
                #if DEBUG
                print("[SFX] Missing asset for decision: \(decision.reason)")
                #endif
                continue
            }

            guard let sfxAudioTrack = try? await sfxAsset.loadTracks(withMediaType: .audio).first else {
                failedCount += 1
                continue
            }

            let sfxDuration = (try? await sfxAsset.load(.duration)) ?? CMTime(seconds: 1.0, preferredTimescale: 600)
            let insertTime = CMTime(seconds: decision.time, preferredTimescale: 600)

            // Clip SFX duration so it doesn't extend past composition end
            let maxDuration = CMTime(seconds: max(0, compositionDuration - decision.time), preferredTimescale: 600)
            let clippedDuration = CMTimeMinimum(sfxDuration, maxDuration)
            guard CMTimeGetSeconds(clippedDuration) > 0 else { continue }

            let timeRange = CMTimeRange(start: .zero, duration: clippedDuration)

            // Pick target track: primary if no overlap, overflow if overlapping
            let primaryEnd = trackOccupiedEnd[sfxTrack.trackID] ?? 0
            let targetTrack: AVMutableCompositionTrack
            if decision.time >= primaryEnd {
                targetTrack = sfxTrack
            } else {
                // Check overflow track occupancy too
                let overflowEnd = overflowTrack.flatMap { trackOccupiedEnd[$0.trackID] } ?? 0
                if let existing = overflowTrack, decision.time >= overflowEnd {
                    targetTrack = existing
                } else {
                    // Need new overflow track
                    let newTrack = composition.addMutableTrack(
                        withMediaType: .audio,
                        preferredTrackID: kCMPersistentTrackID_Invalid
                    )
                    guard let t = newTrack else {
                        failedCount += 1
                        continue
                    }
                    overflowTrack = t
                    sfxTracks.append(t)
                    trackOccupiedEnd[t.trackID] = 0
                    targetTrack = t
                }
            }

            do {
                try targetTrack.insertTimeRange(timeRange, of: sfxAudioTrack, at: insertTime)
                let endTime = decision.time + CMTimeGetSeconds(clippedDuration)
                trackOccupiedEnd[targetTrack.trackID] = max(trackOccupiedEnd[targetTrack.trackID] ?? 0, endTime)
            } catch {
                failedCount += 1
                #if DEBUG
                print("[SFX] Failed to insert \(sfxSound.rawValue) at \(decision.time)s: \(error)")
                #endif
            }
        }

        return InsertResult(tracks: sfxTracks, failedCount: failedCount)
    }
}
