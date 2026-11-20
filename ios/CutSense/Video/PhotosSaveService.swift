import Photos

/// Saves an exported video to the user's Photos library (add-only permission).
enum PhotosSaveService {
    enum SaveError: Error, Equatable {
        case fileMissing
        case permissionDenied
        case assetCreationFailed
    }

    static func saveVideo(at url: URL) async -> Result<Void, Error> {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .failure(SaveError.fileMissing)
        }
        var status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if status == .notDetermined {
            status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        }
        guard status == .authorized || status == .limited else {
            return .failure(SaveError.permissionDenied)
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }
            return .success(())
        } catch {
            #if DEBUG
            print("[PhotosSave] failed: \(error.localizedDescription)")
            #endif
            return .failure(SaveError.assetCreationFailed)
        }
    }
}
