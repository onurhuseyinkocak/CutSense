import PhotosUI
import SwiftUI
import AVFoundation

@MainActor
@Observable
final class VideoImportService {
    var selectedItem: PhotosPickerItem?
    var importedVideoURL: URL?
    var metadata: VideoMetadata?
    var isImporting = false
    var errorMessage: String?

    func importVideo(from item: PhotosPickerItem) async {
        isImporting = true
        errorMessage = nil
        defer { isImporting = false }

        do {
            guard let movie = try await item.loadTransferable(type: VideoTransferable.self) else {
                errorMessage = "Could not load video."
                return
            }
            importedVideoURL = movie.url
            metadata = await VideoMetadataService.extract(from: movie.url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct VideoTransferable: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("CutSense", isDirectory: true)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

            let destination = tempDir.appendingPathComponent(received.file.lastPathComponent)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: received.file, to: destination)
            return Self(url: destination)
        }
    }
}
