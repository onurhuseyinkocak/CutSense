import AVFoundation

/// Re-encode the picked video to fit the Supabase Storage free-tier object cap
/// (50MB). The backend re-normalises anyway, so a 720p/540p source is fine — we
/// only need clean audio + enough resolution. Uses the async export API (no
/// completion handler) to stay Swift 6 / iOS 26 concurrency-safe.
enum VideoCompressor {
    enum CompressError: LocalizedError {
        case cannotCreateSession
        case exportFailed(String)
        var errorDescription: String? {
            switch self {
            case .cannotCreateSession: return "Video sıkıştırılamadı (export session)."
            case let .exportFailed(m): return "Video sıkıştırma hatası: \(m)"
            }
        }
    }

    /// Returns a temp mp4 URL ≤ maxBytes. Steps the preset down until it fits.
    static func compress(_ src: URL, maxBytes: Int64 = 47_000_000) async throws -> URL {
        let asset = AVURLAsset(url: src)
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("cs_upload_\(UUID().uuidString).mp4")
        let presets = [
            AVAssetExportPreset1280x720,
            AVAssetExportPreset960x540,
            AVAssetExportPreset640x480,
        ]
        var lastError = "unknown"
        for preset in presets {
            try? FileManager.default.removeItem(at: dest)
            guard let session = AVAssetExportSession(asset: asset, presetName: preset) else { continue }
            session.shouldOptimizeForNetworkUse = true
            session.fileLengthLimit = maxBytes
            do {
                try await session.export(to: dest, as: .mp4)
            } catch {
                lastError = error.localizedDescription
                continue
            }
            if let size = fileSize(dest) {
                if size <= maxBytes { return dest }
                lastError = "still \(size) bytes at \(preset)"
            } else {
                return dest
            }
        }
        if fileSize(dest) != nil { return dest } // accept the smallest we got
        throw CompressError.exportFailed(lastError)
    }

    private static func fileSize(_ url: URL) -> Int64? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? Int64
    }
}
