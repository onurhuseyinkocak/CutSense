import AVFoundation
import Photos

@MainActor
@Observable
final class ExportService {
    var progress: Float = 0
    var isExporting = false
    var errorMessage: String?
    var exportedURL: URL?

    private var exportSession: AVAssetExportSession?

    @discardableResult
    func exportNormalized(from sourceURL: URL) async -> URL? {
        isExporting = true
        progress = 0
        errorMessage = nil
        exportedURL = nil
        defer { isExporting = false }

        let asset = AVURLAsset(url: sourceURL)

        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset1920x1080) else {
            errorMessage = "Could not create export session."
            return nil
        }

        let outputDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CutSense/exports", isDirectory: true)
        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        let outputURL = outputDir.appendingPathComponent("export_\(UUID().uuidString.prefix(8)).mp4")
        exportSession = session

        do {
            try await session.export(to: outputURL, as: .mp4)
            progress = 1.0
            exportedURL = outputURL
            return outputURL
        } catch {
            progress = 0
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func saveToPhotos(url: URL) async -> Bool {
        do {
            let authStatus = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard authStatus == .authorized || authStatus == .limited else {
                errorMessage = "Photos access denied."
                return false
            }

            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func cancelExport() {
        exportSession?.cancelExport()
    }
}
