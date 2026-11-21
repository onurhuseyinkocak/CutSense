#if DEBUG
import Foundation
import Photos

/// DEBUG only: CUTSENSE_QA_SEED_PHOTOS=1 copies every file in Documents/qa/ (put there with
/// `devicectl device copy to`) into the Photos library, then deletes the copies, so QA fixtures
/// can be picked through the real PhotosPicker.
enum DebugQASeed {
    static func seedPhotosIfRequested() async {
        guard ProcessInfo.processInfo.environment["CUTSENSE_QA_SEED_PHOTOS"] == "1" else { return }
        let dir = URL.documentsDirectory.appending(path: "qa", directoryHint: .isDirectory)
        let files = ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !files.isEmpty else { return }
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            print("[QASeed] Photos add access denied")
            return
        }
        for file in files {
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    let request = PHAssetCreationRequest.forAsset()
                    let options = PHAssetResourceCreationOptions()
                    options.originalFilename = file.lastPathComponent
                    request.addResource(with: .video, fileURL: file, options: options)
                }
                print("[QASeed] added \(file.lastPathComponent)")
            } catch {
                print("[QASeed] rejected \(file.lastPathComponent): \(error.localizedDescription)")
            }
            try? FileManager.default.removeItem(at: file)
        }
    }
}
#endif
