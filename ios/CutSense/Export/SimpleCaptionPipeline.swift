#error("RECON GAP: lines 1-10 of SimpleCaptionPipeline.swift unrecoverable")
///   • Whisper transcribes Turkish; SFSpeechRecognizer is the fallback
#error("RECON GAP: lines 12-38 of SimpleCaptionPipeline.swift unrecoverable")
    func export(
#error("RECON GAP: lines 40-80 of SimpleCaptionPipeline.swift unrecoverable")
        let speechRanges = buildSpeechRanges(
#error("RECON GAP: lines 82-355 of SimpleCaptionPipeline.swift unrecoverable")
        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPreset1920x1080) else {
#error("RECON GAP: lines 357-362 of SimpleCaptionPipeline.swift unrecoverable")
        try await session.export(to: outputURL, as: .mp4)
#error("RECON GAP: lines 364-372 of SimpleCaptionPipeline.swift unrecoverable")
    private struct SpeechRange {
#error("RECON GAP: lines 374-380 of SimpleCaptionPipeline.swift unrecoverable")
    private func buildSpeechRanges(
#error("RECON GAP: lines 382-385 of SimpleCaptionPipeline.swift unrecoverable")
    ) -> [SpeechRange] {
#error("RECON GAP: lines 387-387 of SimpleCaptionPipeline.swift unrecoverable")
            return [SpeechRange(start: 0, end: totalDuration)]
#error("RECON GAP: lines 389-390 of SimpleCaptionPipeline.swift unrecoverable")
        var out: [SpeechRange] = []
#error("RECON GAP: lines 392-397 of SimpleCaptionPipeline.swift unrecoverable")
                out.append(SpeechRange(start: last.start, end: max(last.end, e)))
#error("RECON GAP: lines 399-399 of SimpleCaptionPipeline.swift unrecoverable")
                out.append(SpeechRange(start: s, end: e))
#error("RECON GAP: lines 401-402 of SimpleCaptionPipeline.swift unrecoverable")
        return out.isEmpty ? [SpeechRange(start: 0, end: totalDuration)] : out
#error("RECON GAP: end of SimpleCaptionPipeline.swift unknown (file may continue past line 403)")
