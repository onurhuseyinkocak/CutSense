#error("RECON GAP: lines 1-18 of ProExportPipeline.swift unrecoverable")
///   7. AVAssetExportSession render to mp4
#error("RECON GAP: lines 20-41 of ProExportPipeline.swift unrecoverable")
    func export(
#error("RECON GAP: lines 43-59 of ProExportPipeline.swift unrecoverable")
        progress(.init(stage: .planningCuts, fraction: 0.30, message: "Kesimler planlanıyor…"))
#error("RECON GAP: lines 61-62 of ProExportPipeline.swift unrecoverable")
        let speechRanges = buildSpeechRanges(
#error("RECON GAP: lines 64-229 of ProExportPipeline.swift unrecoverable")
        // No ducking, no extra tracks. AVAssetExportSession will use the
#error("RECON GAP: lines 231-231 of ProExportPipeline.swift unrecoverable")
        let audioMix: AVMutableAudioMix? = nil
#error("RECON GAP: lines 233-237 of ProExportPipeline.swift unrecoverable")
        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
#error("RECON GAP: lines 239-243 of ProExportPipeline.swift unrecoverable")
        if let audioMix { session.audioMix = audioMix }
        try await session.export(to: outputURL, as: .mp4)
#error("RECON GAP: lines 246-260 of ProExportPipeline.swift unrecoverable")
    private struct SpeechRange {
#error("RECON GAP: lines 262-268 of ProExportPipeline.swift unrecoverable")
    private func buildSpeechRanges(
#error("RECON GAP: lines 270-273 of ProExportPipeline.swift unrecoverable")
    ) -> [SpeechRange] {
#error("RECON GAP: lines 275-275 of ProExportPipeline.swift unrecoverable")
            return [SpeechRange(start: 0, end: totalDuration)]
#error("RECON GAP: lines 277-278 of ProExportPipeline.swift unrecoverable")
        var out: [SpeechRange] = []
#error("RECON GAP: lines 280-284 of ProExportPipeline.swift unrecoverable")
                last = SpeechRange(start: last.start, end: max(last.end, e))
#error("RECON GAP: lines 286-288 of ProExportPipeline.swift unrecoverable")
                out.append(SpeechRange(start: s, end: e))
#error("RECON GAP: lines 290-303 of ProExportPipeline.swift unrecoverable")
        speechRanges: [SpeechRange]
#error("RECON GAP: lines 305-339 of ProExportPipeline.swift unrecoverable")
        speechRanges: [SpeechRange]
#error("RECON GAP: lines 341-372 of ProExportPipeline.swift unrecoverable")
    private func offsetMapBack(for caption: MappedCaption, speechRanges: [SpeechRange]) -> Double {
#error("RECON GAP: end of ProExportPipeline.swift unknown (file may continue past line 373)")
