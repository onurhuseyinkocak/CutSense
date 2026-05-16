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

    /// Insert SFX audio tracks into the composition at EditDecision times.
    /// Returns the SFX tracks added (for audio mix volume control).
    @MainActor @discardableResult
    static func insertSFX(
        into composition: AVMutableComposition,
        decisions: [EditDecision],
        sfxVolume: Float
    ) async -> [AVMutableCompositionTrack] {
        let sfxDecisions = decisions.filter { $0.type == .sfx }
        guard !sfxDecisions.isEmpty else { return [] }

        var sfxTracks: [AVMutableCompositionTrack] = []

        for decision in sfxDecisions {
            guard let sfxSound = sound(for: decision),
                  let sfxAsset = asset(for: sfxSound) else { continue }

            guard let sfxAudioTrack = try? await sfxAsset.loadTracks(withMediaType: .audio).first,
                  let compTrack = composition.addMutableTrack(
                      withMediaType: .audio,
                      preferredTrackID: kCMPersistentTrackID_Invalid
                  ) else { continue }

            let sfxDuration = (try? await sfxAsset.load(.duration)) ?? CMTime(seconds: 1.0, preferredTimescale: 600)
            let insertTime = CMTime(seconds: decision.time, preferredTimescale: 600)
            let timeRange = CMTimeRange(start: .zero, duration: sfxDuration)

            do {
                try compTrack.insertTimeRange(timeRange, of: sfxAudioTrack, at: insertTime)
                sfxTracks.append(compTrack)
            } catch {
                #if DEBUG
                print("[SFX] Failed to insert \(sfxSound.rawValue) at \(decision.time)s: \(error)")
                #endif
            }
        }

        return sfxTracks
    }
}
