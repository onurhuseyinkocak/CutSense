#error("RECON GAP: lines 1-5 of SilenceCutEngine.swift unrecoverable")
/// How aggressively silence is removed. Speech is never auto-removed; only the
#error("RECON GAP: lines 7-62 of SilenceCutEngine.swift unrecoverable")
    /// Speech is kept by default; silence is removed by default when it is
#error("RECON GAP: lines 64-84 of SilenceCutEngine.swift unrecoverable")
        struct Run { var start: Double; var end: Double; var isSpeech: Bool }
#error("RECON GAP: lines 86-87 of SilenceCutEngine.swift unrecoverable")
            let isSpeech: Bool
#error("RECON GAP: lines 89-89 of SilenceCutEngine.swift unrecoverable")
            case .speech, .clipping: isSpeech = true
            case .silence, .lowEnergy: isSpeech = false
#error("RECON GAP: lines 92-92 of SilenceCutEngine.swift unrecoverable")
            if var last = runs.last, last.isSpeech == isSpeech, seg.startTime - last.end < 0.06 {
#error("RECON GAP: lines 94-96 of SilenceCutEngine.swift unrecoverable")
                runs.append(Run(start: seg.startTime, end: seg.endTime, isSpeech: isSpeech))
#error("RECON GAP: lines 98-119 of SilenceCutEngine.swift unrecoverable")
            if !run.isSpeech, run.end - run.start < 0.12, var last = merged.last, last.isSpeech {
#error("RECON GAP: lines 121-122 of SilenceCutEngine.swift unrecoverable")
            } else if let last = merged.last, last.isSpeech == run.isSpeech {
#error("RECON GAP: lines 124-131 of SilenceCutEngine.swift unrecoverable")
            if run.isSpeech {
#error("RECON GAP: lines 133-143 of SilenceCutEngine.swift unrecoverable")
    static func keptSpeechRanges(blocks: [CutBlock], pad: Double, duration: Double) -> [SpeechRange] {
#error("RECON GAP: lines 145-175 of SilenceCutEngine.swift unrecoverable")
        var ranges: [SpeechRange] = []
#error("RECON GAP: lines 177-178 of SilenceCutEngine.swift unrecoverable")
            ranges.append(SpeechRange(sourceStart: iv.start, sourceEnd: iv.end, cleanStart: cleanCursor))
#error("RECON GAP: lines 180-229 of SilenceCutEngine.swift unrecoverable")
    var keptRanges: [SpeechRange] {
        SilenceCutPlanner.keptSpeechRanges(blocks: blocks, pad: pacing.pad, duration: originalDuration)
#error("RECON GAP: lines 232-310 of SilenceCutEngine.swift unrecoverable")
    func export() async {
#error("RECON GAP: lines 312-313 of SilenceCutEngine.swift unrecoverable")
            phase = .failed("Kesilecek konuşma kalmadı. En az bir sahne tut.")
#error("RECON GAP: lines 315-325 of SilenceCutEngine.swift unrecoverable")
            let result = try await CutSensePipeline().export(
#error("RECON GAP: lines 327-329 of SilenceCutEngine.swift unrecoverable")
                preplannedSpeechRanges: ranges,
#error("RECON GAP: lines 331-337 of SilenceCutEngine.swift unrecoverable")
            savedToPhotos = await exporter.saveToPhotos(url: result.outputURL)
#error("RECON GAP: end of SilenceCutEngine.swift unknown (file may continue past line 338)")
