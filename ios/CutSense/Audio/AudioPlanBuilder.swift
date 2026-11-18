import Foundation

/// Builds an `AudioPlan` from a transcript. Phase 1 uses deterministic
/// rules; Phase 2 can replace the mood classifier with an on-device LLM.
public struct AudioPlanBuilder {

    public static func plan(
        transcript: CutSenseTranscript,
        speechRanges: [SpeechRange],
        cleanDuration: Double
    ) async -> AudioPlan {

        let mood = classifyMood(transcript: transcript)
        let track = MusicLibrary.track(forMood: mood.rawValue, minDuration: cleanDuration * 0.6)
        let musicURL = track.flatMap { MusicLibrary.url(for: $0) }
        let bpm: Double = track.map { Double($0.bpm) } ?? defaultBPM(for: mood)

        // Beat detection only when we actually have music (saves CPU).
        var beats: [Double] = []
        if let url = musicURL {
            beats = (try? await BeatDetector.detect(audioURL: url)) ?? []
        }

        // Ducking windows = every Whisper word + tiny pad
        let ducking = buildDuckingRanges(
            transcript: transcript,
            speechRanges: speechRanges,
            cleanDuration: cleanDuration
        )

        // SFX placements: a whoosh on each speech-range boundary, a
        // riser before the first phrase. Skipped silently if the SFX
        // library is empty.
        var sfx: [SFXPlacement] = []
        if let riser = SFXLibrary.entry(forKind: SFXKind.riser.rawValue),
           let riserURL = SFXLibrary.url(for: riser),
           let firstRange = speechRanges.first {
            let placeAt = max(0, firstRange.cleanStart - 0.20)
            sfx.append(SFXPlacement(url: riserURL, cleanTime: placeAt, gain: 0.65, kind: .riser))
        }
        if let whoosh = SFXLibrary.entry(forKind: SFXKind.whoosh.rawValue),
           let whooshURL = SFXLibrary.url(for: whoosh),
           speechRanges.count > 1 {
            for r in speechRanges.dropFirst() {
                sfx.append(SFXPlacement(
                    url: whooshURL,
                    cleanTime: max(0, r.cleanStart - 0.05),
                    gain: 0.55,
                    kind: .whoosh
                ))
            }
        }

        return AudioPlan(
            musicURL: musicURL,
            mood: mood,
            bpm: bpm,
            beats: beats,
            sfxPlacements: sfx,
            duckingRanges: ducking
        )
    }

    public static func sfxOnlyPlan(
        transcript: CutSenseTranscript,
        speechRanges: [SpeechRange],
        cleanDuration: Double
    ) async -> AudioPlan {
        AudioPlan(
            musicURL: nil,
            mood: .subtle,
            bpm: defaultBPM(for: .subtle),
            beats: [],
            sfxPlacements: buildStandaloneSFXPlacements(
                transcript: transcript,
                speechRanges: speechRanges,
                cleanDuration: cleanDuration
            ),
            duckingRanges: []
        )
    }

    private static func buildStandaloneSFXPlacements(
        transcript: CutSenseTranscript,
        speechRanges: [SpeechRange],
        cleanDuration: Double
    ) -> [SFXPlacement] {
        guard cleanDuration > 0.30 else { return [] }

        var placements: [SFXPlacement] = []
        var lastPlacementTime = -Double.infinity

        func append(kind: SFXKind, at time: Double, gain: Float, minimumGap: Double = 0.65) {
            let clamped = min(max(0, time), max(0, cleanDuration - 0.05))
            guard clamped - lastPlacementTime >= minimumGap,
                  let placement = sfxPlacement(kind: kind, at: clamped, gain: gain) else { return }
            placements.append(placement)
            lastPlacementTime = clamped
        }

        if cleanDuration > 1.40 {
            append(kind: .riser, at: 0.05, gain: 0.34, minimumGap: 0.30)
        }

        for range in speechRanges.dropFirst().prefix(6) {
            append(kind: .whoosh, at: range.cleanStart - 0.04, gain: 0.34, minimumGap: 0.80)
        }

        let accentTokens: Set<String> = [
            "ai", "yapay", "zeka", "otomatik", "edit", "uygulama", "app",
            "mvp", "kod", "coding", "vibe", "video", "sistem", "problem",
            "cozum", "sonuc", "bugun", "onemli", "fikir", "urun", "tool",
            "launch", "export", "caption", "sfx", "cut"
        ]
        var accentCount = 0
        for word in transcript.words {
            guard accentCount < 8,
                  accentTokens.contains(normalizedToken(word.text)),
                  let cleanTime = speechRanges.cleanTime(forSource: word.start) else { continue }
            let kind: SFXKind
            switch accentCount % 4 {
            case 0: kind = .ding
            case 1: kind = .pop
            case 2: kind = .impact
            default: kind = .pop
            }
            append(kind: kind, at: cleanTime, gain: kind == .impact ? 0.26 : 0.30, minimumGap: 1.15)
            accentCount += 1
        }

        if placements.isEmpty {
            append(kind: .pop, at: min(0.45, cleanDuration * 0.25), gain: 0.28, minimumGap: 0.20)
        }
        if placements.count == 1, cleanDuration > 2.0 {
            append(kind: .transition, at: min(cleanDuration - 0.45, 1.40), gain: 0.24, minimumGap: 0.80)
        }

        return placements.sorted { $0.cleanTime < $1.cleanTime }
    }

    private static func sfxPlacement(kind: SFXKind, at time: Double, gain: Float) -> SFXPlacement? {
        guard let entry = SFXLibrary.entry(forKind: kind.rawValue),
              let url = SFXLibrary.url(for: entry) else { return nil }
        return SFXPlacement(url: url, cleanTime: time, gain: gain, kind: kind)
    }

    private static func defaultBPM(for mood: Mood) -> Double {
        switch mood {
        case .energetic: return 128
        case .chill: return 90
        case .dramatic: return 100
        case .comedic: return 115
        case .emotional: return 78
        case .subtle: return 95
        }
    }

    private static func classifyMood(transcript: CutSenseTranscript) -> Mood {
        let lower = transcript.fullText.lowercased()

        // Cheap signal counts.
        let exclamCount = transcript.fullText.filter { $0 == "!" }.count
        let capsRatio = ratioOfAllCapsWords(in: transcript.fullText)
        let chillHints = ["rahatla", "sakin", "derin", "nefes", "huzur", "uyku", "calm"]
        let dramaticHints = ["kriz", "tehdit", "şok", "büyük tehlike", "tarihte", "büyük"]
        let comedicHints = ["şaka", "komik", "gülmek", "lol", "haha", "ironik"]
        let emotionalHints = ["ağla", "kalp", "duygu", "umut", "anı", "sev"]
        let educationalHints = ["öğret", "anlat", "ders", "kurs", "eğit", "nasıl"]

        if chillHints.contains(where: lower.contains) { return .chill }
        if emotionalHints.contains(where: lower.contains) { return .emotional }
        if dramaticHints.contains(where: lower.contains) { return .dramatic }
        if comedicHints.contains(where: lower.contains) { return .comedic }
        if exclamCount >= 3 || capsRatio > 0.20 { return .energetic }
        if educationalHints.contains(where: lower.contains) { return .subtle }
        return .subtle
    }

    private static func ratioOfAllCapsWords(in text: String) -> Double {
        let words = text.split(separator: " ").map(String.init)
#error("RECON GAP: lines 181-196 of AudioPlanBuilder.swift unrecoverable")
        speechRanges: [SpeechRange],
#error("RECON GAP: end of AudioPlanBuilder.swift unknown (file may continue past line 197)")
