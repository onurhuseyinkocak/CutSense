import AVFoundation

enum SFXAssetManager {
    private static let trackReuseGuardGap: Double = 0.012

    enum SFXSound: String, CaseIterable, Hashable {
        case whoosh
        case impact
        case pop
        case confirm
        case riser
        case glitch
        case subHit = "sub_hit"
        case sweep
        case ping
        case typing
        case shutter

        var filename: String { rawValue }
    }

    /// Maps an EditDecision's reason to the appropriate SFX sound
    static func sound(for decision: EditDecision) -> SFXSound? {
        guard decision.type == .sfx else { return nil }

        let reason = decision.reason.lowercased()
        if reason.contains("riser") {
            return .riser
        } else if reason.contains("glitch") || reason.contains("digital") {
            return .glitch
        } else if reason.contains("sub hit") || reason.contains("sub") {
            return .subHit
        } else if reason.contains("sweep") {
            return .sweep
        } else if reason.contains("notification") || reason.contains("ping") {
            return .ping
        } else if reason.contains("typing") || reason.contains("keyboard") {
            return .typing
        } else if reason.contains("shutter") || reason.contains("camera flash") {
            return .shutter
        } else if reason.contains("whoosh") {
            return .whoosh
        } else if reason.contains("click") || reason.contains("ui") || reason.contains("pop") || reason.contains("tap") {
            return .pop
        } else if reason.contains("impact") || reason.contains("punch") {
            return .impact
        } else if reason.contains("keyword") {
            return .pop
        } else if reason.contains("transition") {
            return .whoosh
        } else if reason.contains("conclusion") || reason.contains("confirm") {
            return .confirm
        } else {
            return nil
        }
    }

    /// Template-specific SFX file (mixkit asset name without extension), per template id.
    /// Falls back to the generic 5-file set when no template-specific match is found.
    private static func mixkitName(for sound: SFXSound, templateId: String) -> (name: String, ext: String)? {
        switch (templateId, sound) {
        // ── premiumFounder: deep, calm, authoritative
        case ("premium_founder", .whoosh):   return ("mixkit_air_woosh_1489", "wav")
        case ("premium_founder", .impact):   return ("mixkit_cinematic_whoosh_deep_impact_1143", "mp3")
        case ("premium_founder", .pop):      return ("mixkit_select_click_1109", "wav")
        case ("premium_founder", .confirm):  return ("mixkit_select_click_1109", "wav")
        case ("premium_founder", .riser):    return ("mixkit_cinematic_trailer_riser_790", "wav")

        // ── viralCaption: fast, punchy, neon
        case ("viral_caption", .whoosh):     return ("mixkit_flying_fast_swoosh_1469", "wav")
        case ("viral_caption", .impact):     return ("mixkit_dramatic_metal_explosion_impact_1687", "wav")
        case ("viral_caption", .pop):        return ("mixkit_hard_pop_click_2364", "wav")
        case ("viral_caption", .confirm):    return ("mixkit_modern_technology_select_3124", "wav")
        case ("viral_caption", .riser):      return ("mixkit_short_space_stutter_intro_riser_1144", "mp3")

        // ── techInfluencer: crisp creator accents, less trailer-like than viral
        case ("tech_influencer", .whoosh):   return ("mixkit_cinematic_whoosh_fast_transition_1492", "wav")
        case ("tech_influencer", .impact):   return ("mixkit_cinematic_whoosh_deep_impact_1143", "mp3")
        case ("tech_influencer", .pop):      return ("mixkit_modern_technology_select_3124", "wav")
        case ("tech_influencer", .confirm):  return ("mixkit_select_click_1109", "wav")
        case ("tech_influencer", .riser):    return ("mixkit_short_space_stutter_intro_riser_1144", "mp3")
        case ("tech_influencer", .glitch):   return ("mixkit_glitch_static_1457", "wav")
        case ("tech_influencer", .subHit):   return ("mixkit_cinematic_whoosh_deep_impact_1143", "mp3")
        case ("tech_influencer", .sweep):    return ("mixkit_air_woosh_1489", "wav")
        case ("tech_influencer", .ping):     return ("mixkit_modern_technology_select_3124", "wav")
        case ("tech_influencer", .typing):   return ("mixkit_select_click_1109", "wav")
        case ("tech_influencer", .shutter):  return ("mixkit_camera_shutter_click_1133", "wav")

        // ── cleanExpert: minimal, educational
        case ("clean_expert", .whoosh):      return ("mixkit_arrow_whoosh_1714", "wav")
        case ("clean_expert", .impact):      return ("mixkit_movie_logo_intro_impact_2900", "wav")
        case ("clean_expert", .pop):         return ("mixkit_message_pop_alert_2354", "mp3")
        case ("clean_expert", .confirm):     return ("mixkit_select_click_1109", "wav")
        case ("clean_expert", .riser):       return ("mixkit_cinematic_trailer_riser_790", "wav")

        // ── cinematicStoryteller: warm, filmic, long sweeps
        case ("cinematic_storyteller", .whoosh):  return ("mixkit_cinematic_tunnel_reverb_woosh_1486", "wav")
        case ("cinematic_storyteller", .impact):  return ("mixkit_big_cinematic_impact_788", "mp3")
        case ("cinematic_storyteller", .pop):     return ("mixkit_message_pop_alert_2354", "mp3")
        case ("cinematic_storyteller", .confirm): return ("mixkit_select_click_1109", "wav")
        case ("cinematic_storyteller", .riser):   return ("mixkit_cinematic_horror_trailer_long_sweep_561", "wav")

        // ── podcastHighlights: voice-first, almost no SFX (only pop for quotes)
        case ("podcast_highlights", .pop):        return ("mixkit_message_pop_alert_2354", "mp3")
        case ("podcast_highlights", .confirm):    return ("mixkit_select_click_1109", "wav")
        // For podcast, whoosh/impact/riser intentionally fall back to defaults (or stay silent at quiet template volume)

        default: return nil
        }
    }

    private static func downloadedTechName(for sound: SFXSound, reason: String) -> (name: String, ext: String)? {
        let reason = reason.lowercased()
        switch sound {
        case .whoosh:
            if reason.contains("reveal") || reason.contains("cinematic") {
                return ("dragon-studio-whoosh-cinematic-376875", "mp3")
            }
            if reason.contains("sweep") || reason.contains("transition") {
                return ("lordsonny-cinematic-whoosh-reverse-161307", "mp3")
            }
            return ("dragon-studio-simple-whoosh-382724", "mp3")
        case .impact:
            if reason.contains("warning") || reason.contains("low impact") {
                return ("bryansantosbreton-biodynamic-impact-braam-tonal-dark-184276", "mp3")
            }
            return ("universfield-impact-cinematic-boom-352465", "mp3")
        case .pop:
            if reason.contains("ui") || reason.contains("click") || reason.contains("tap") {
                return ("dragon-studio-mouse-click-sfx-444806", "mp3")
            }
            return ("dragon-studio-pop-402324", "mp3")
        case .confirm:
            return ("dragon-studio-correct-472358", "mp3")
        case .riser:
            if reason.contains("hook") || reason.contains("hit") {
                return ("audiopapkin-riser-hit-sfx-001-289802", "mp3")
            }
            if reason.contains("cta") || reason.contains("music lift") {
                return ("soundreality-riser-hole-391174", "mp3")
            }
            return ("dragon-studio-cinematic-riser-03-414575", "mp3")
        case .glitch:
            return ("dragon-studio-glitch-effect-1-397982", "mp3")
        case .subHit:
            if reason.contains("bass") || reason.contains("sub") {
                return ("u_tmz2ks56ex-m3g-cinematic-bass-318310", "mp3")
            }
            return ("pwlpl-deep-bass-drop-sound-effect-521058", "mp3")
        case .sweep:
            return ("lordsonny-cinematic-whoosh-reverse-161307", "mp3")
        case .ping:
            return ("universfield-new-notification-057-494255", "mp3")
        case .typing:
            if reason.contains("asmr") || reason.contains("soft") {
                return ("dragon-studio-clicking-keyboard-asmr-sfx-356115", "mp3")
            }
            return ("virtualzero-mechanical-keyboard-typing-hd-372290", "mp3")
        case .shutter:
            return ("universfield-camera-shutter-199580", "mp3")
        }
    }

    /// Load the SFX audio asset from the bundle, preferring template-specific mixkit file.
    static func asset(for sfx: SFXSound, templateId: String = "") -> AVURLAsset? {
        // Template-specific first
        if !templateId.isEmpty, let info = mixkitName(for: sfx, templateId: templateId),
           let url = Bundle.main.url(forResource: info.name, withExtension: info.ext) {
            return AVURLAsset(url: url)
        }
        // Generic fallback
        for ext in ["mp3", "wav"] {
            if let url = Bundle.main.url(forResource: sfx.filename, withExtension: ext) {
                return AVURLAsset(url: url)
            }
        }
        return nil
    }

    static func asset(for decision: EditDecision, sound: SFXSound, templateId: String = "") -> AVURLAsset? {
        let reason = decision.reason.lowercased()
        if templateId == "tech_influencer",
           let info = downloadedTechName(for: sound, reason: reason) {
            guard let url = Bundle.main.url(forResource: info.name, withExtension: info.ext) else {
                return nil
            }
            return AVURLAsset(url: url)
        }
        if sound == .impact,
           reason.contains("punch")
            || reason.contains("keyword")
            || reason.contains("cut impact")
            || reason.contains("transition impact")
            || reason.contains("hook impact") {
            return asset(for: sound, templateId: "")
        }
        return asset(for: sound, templateId: templateId)
    }

    struct InsertResult {
        let tracks: [AVMutableCompositionTrack]
        let volumeEvents: [VolumeEvent]
        let insertedCount: Int
        let failedCount: Int
    }

    struct VolumeEvent {
        let trackID: CMPersistentTrackID
        let startTime: Double
        let endTime: Double
        let volume: Float
    }

    /// Insert SFX audio into the composition at EditDecision times.
    /// Keeps separate track pools per SFX lane so whoosh/impact/riser accents can combine
    /// without one lane suppressing another at the same edit point.
    /// Returns tracks added and count of failures (for user feedback).
    @MainActor
    static func insertSFX(
        into composition: AVMutableComposition,
        decisions: [EditDecision],
        sfxVolume: Float,
        templateId: String = ""
    ) async -> InsertResult {
        let sfxDecisions = decisions.filter { $0.type == .sfx }.sorted { $0.time < $1.time }
        guard !sfxDecisions.isEmpty else { return InsertResult(tracks: [], volumeEvents: [], insertedCount: 0, failedCount: 0) }

        var tracksBySound: [SFXSound: [AVMutableCompositionTrack]] = [:]
        var trackOccupiedEnd: [CMPersistentTrackID: Double] = [:]
        var sfxTracks: [AVMutableCompositionTrack] = []
        var volumeEvents: [VolumeEvent] = []
        var failedCount = 0

        let compositionDuration = composition.duration.seconds

        func makeTrack(for sound: SFXSound) -> AVMutableCompositionTrack? {
            guard let track = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else {
                return nil
            }
            tracksBySound[sound, default: []].append(track)
            trackOccupiedEnd[track.trackID] = 0
            sfxTracks.append(track)
            return track
        }

        func targetTrack(for sound: SFXSound, at time: Double) -> AVMutableCompositionTrack? {
            if let availableTrack = tracksBySound[sound]?.first(where: { track in
                time >= (trackOccupiedEnd[track.trackID] ?? 0) + Self.trackReuseGuardGap
            }) {
                return availableTrack
            }
            return makeTrack(for: sound)
        }

        for decision in sfxDecisions {
            guard let sfxSound = sound(for: decision),
                  let sfxAsset = asset(for: decision, sound: sfxSound, templateId: templateId) else {
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

            // Honor the edit plan duration instead of letting long asset tails cover dialogue.
            let plannedDurationSeconds = if decision.duration.isFinite, decision.duration > 0 {
                decision.duration
            } else {
                CMTimeGetSeconds(sfxDuration)
            }
            let plannedDuration = CMTime(seconds: plannedDurationSeconds, preferredTimescale: 600)

            // Clip SFX duration so it doesn't extend past the requested plan or composition end.
            let maxDuration = CMTime(seconds: max(0, compositionDuration - decision.time), preferredTimescale: 600)
            let clippedDuration = CMTimeMinimum(CMTimeMinimum(sfxDuration, plannedDuration), maxDuration)
            guard CMTimeGetSeconds(clippedDuration) > 0 else { continue }

            let sfxRangeStart = sourceRangeStart(
                for: sfxSound,
                assetDuration: sfxDuration,
                clippedDuration: clippedDuration
            )
            let timeRange = CMTimeRange(start: sfxRangeStart, duration: clippedDuration)

            guard let targetTrack = targetTrack(for: sfxSound, at: decision.time) else {
                failedCount += 1
                continue
            }

            do {
                try targetTrack.insertTimeRange(timeRange, of: sfxAudioTrack, at: insertTime)
                let endTime = decision.time + CMTimeGetSeconds(clippedDuration)
                trackOccupiedEnd[targetTrack.trackID] = max(trackOccupiedEnd[targetTrack.trackID] ?? 0, endTime)
                let volume = outputVolume(
                    for: sfxSound,
                    decision: decision,
                    templateSFXVolume: sfxVolume
                )
                volumeEvents.append(VolumeEvent(
                    trackID: targetTrack.trackID,
                    startTime: decision.time,
                    endTime: endTime,
                    volume: volume
                ))
            } catch {
                failedCount += 1
                #if DEBUG
                print("[SFX] Failed to insert \(sfxSound.rawValue) at \(decision.time)s: \(error)")
                #endif
            }
        }

        return InsertResult(tracks: sfxTracks, volumeEvents: volumeEvents, insertedCount: volumeEvents.count, failedCount: failedCount)
    }

    static func outputVolume(
        for sound: SFXSound,
        decision: EditDecision,
        templateSFXVolume: Float
    ) -> Float {
        outputVolume(
            for: sound,
            decisionIntensity: decision.intensity,
            templateSFXVolume: templateSFXVolume,
            reason: decision.reason
        )
    }

    static func outputVolume(
        for sound: SFXSound,
        decisionIntensity: Float,
        templateSFXVolume: Float
    ) -> Float {
        outputVolume(
            for: sound,
            decisionIntensity: decisionIntensity,
            templateSFXVolume: templateSFXVolume,
            reason: ""
        )
    }

    private static func outputVolume(
        for sound: SFXSound,
        decisionIntensity: Float,
        templateSFXVolume: Float,
        reason: String
    ) -> Float {
        var base = min(max(max(decisionIntensity, templateSFXVolume), 0), 1)
        let lowerReason = reason.lowercased()
        if sound == .impact {
            if lowerReason.contains("punch") {
                base = max(base, 0.45)
            } else if lowerReason.contains("hook")
                        || lowerReason.contains("keyword")
                        || lowerReason.contains("cut impact")
                        || lowerReason.contains("transition impact") {
                base = max(base, 0.40)
            }
        }
        let boost: Float = switch sound {
        case .whoosh:
            1.25
        case .impact:
            1.45
        case .pop:
            1.15
        case .confirm:
            1.0
        case .riser:
            1.30
        case .glitch:
            1.05
        case .subHit:
            1.35
        case .sweep:
            1.10
        case .ping:
            1.05
        case .typing:
            0.90
        case .shutter:
            1.05
        }
        return min(base * boost, 0.95)
    }

    static func sourceRangeStart(
        for sound: SFXSound,
        assetDuration: CMTime,
        clippedDuration: CMTime
    ) -> CMTime {
        guard CMTimeCompare(assetDuration, clippedDuration) > 0 else { return .zero }

        let assetSeconds = CMTimeGetSeconds(assetDuration)
        let clipSeconds = CMTimeGetSeconds(clippedDuration)
        let latestStart = max(0, assetSeconds - clipSeconds)
        let startSeconds: Double

        switch sound {
        case .riser:
            startSeconds = latestStart
        case .whoosh:
            // Several whoosh assets have a quiet lead-in. Start near the transient so a
            // 0.25-0.35s planned cue is actually audible in the final mix.
            startSeconds = min(latestStart, max(0.18, assetSeconds * 0.30))
        case .impact, .subHit:
            startSeconds = min(latestStart, 0.04)
        case .sweep:
            startSeconds = min(latestStart, max(0.12, assetSeconds * 0.24))
        case .pop, .confirm, .glitch, .ping, .typing, .shutter:
            startSeconds = .zero
        }

        return CMTime(seconds: startSeconds, preferredTimescale: 600)
    }
}
