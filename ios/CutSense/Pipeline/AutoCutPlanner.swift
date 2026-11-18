#error("RECON GAP: lines 1-3 of AutoCutPlanner.swift unrecoverable")
/// `SpeechRange[]` that drives auto-cutting. Silences ≥ `minSilenceGap`
#error("RECON GAP: lines 5-12 of AutoCutPlanner.swift unrecoverable")
    ) -> [SpeechRange] {
#error("RECON GAP: lines 14-23 of AutoCutPlanner.swift unrecoverable")
    static func planAutomaticEdit(
#error("RECON GAP: lines 25-26 of AutoCutPlanner.swift unrecoverable")
    ) -> [SpeechRange] {
#error("RECON GAP: lines 28-41 of AutoCutPlanner.swift unrecoverable")
    ) -> [SpeechRange] {
#error("RECON GAP: lines 43-53 of AutoCutPlanner.swift unrecoverable")
        let audioRanges = audioSpeechRanges(
#error("RECON GAP: lines 55-59 of AutoCutPlanner.swift unrecoverable")
        let baseRanges: [SpeechRange]
#error("RECON GAP: lines 61-94 of AutoCutPlanner.swift unrecoverable")
    ) -> [SpeechRange] {
#error("RECON GAP: lines 96-105 of AutoCutPlanner.swift unrecoverable")
            return SpeechRange(sourceStart: start, sourceEnd: end, cleanStart: cleanCursor)
#error("RECON GAP: lines 107-117 of AutoCutPlanner.swift unrecoverable")
    ) -> [SpeechRange] {
#error("RECON GAP: lines 119-121 of AutoCutPlanner.swift unrecoverable")
            return [SpeechRange(sourceStart: 0, sourceEnd: totalSourceDuration, cleanStart: 0)]
#error("RECON GAP: lines 123-143 of AutoCutPlanner.swift unrecoverable")
        var ranges: [SpeechRange] = []
#error("RECON GAP: lines 145-147 of AutoCutPlanner.swift unrecoverable")
            ranges.append(SpeechRange(sourceStart: p.startTime, sourceEnd: p.endTime, cleanStart: cleanCursor))
#error("RECON GAP: lines 149-151 of AutoCutPlanner.swift unrecoverable")
            ranges.append(SpeechRange(sourceStart: 0, sourceEnd: totalSourceDuration, cleanStart: 0))
#error("RECON GAP: lines 153-177 of AutoCutPlanner.swift unrecoverable")
        wordRanges: [SpeechRange],
        audioRanges: [SpeechRange],
#error("RECON GAP: lines 180-198 of AutoCutPlanner.swift unrecoverable")
        let audioClearlyHasMoreSpeech = audioCleanDuration > max(wordCleanDuration * 2.5, wordCleanDuration + 6)
#error("RECON GAP: lines 200-200 of AutoCutPlanner.swift unrecoverable")
        return transcriptEndsEarly && transcriptTooShortForSource && audioClearlyHasMoreSpeech
#error("RECON GAP: lines 202-204 of AutoCutPlanner.swift unrecoverable")
        to ranges: [SpeechRange],
#error("RECON GAP: lines 206-208 of AutoCutPlanner.swift unrecoverable")
    ) -> [SpeechRange] {
#error("RECON GAP: lines 210-396 of AutoCutPlanner.swift unrecoverable")
    private static func audioSpeechRanges(
#error("RECON GAP: lines 398-400 of AutoCutPlanner.swift unrecoverable")
    ) -> [SpeechRange]? {
#error("RECON GAP: end of AutoCutPlanner.swift unknown (file may continue past line 401)")
