import PhotosUI
import SwiftUI
import AVFoundation

@MainActor
@Observable
final class VideoImportService {
    var selectedItem: PhotosPickerItem?
    var importedVideoURL: URL?
    var metadata: VideoMetadata?  // settable externally for resume
    var isImporting = false
    var errorMessage: String?

    enum ImportError: LocalizedError {
        case metadataUnavailable
        case unsupportedDuration(Double)
        case missingAudio

        var errorDescription: String? {
            switch self {
            case .metadataUnavailable:
                "Video bilgileri okunamadı. Lütfen farklı bir dosya deneyin."
            case .unsupportedDuration:
                "CutSense en fazla 5 dakikalık videoları analiz edebilir."
            case .missingAudio:
                "Bu videoda ses bulunamadı. Analiz için konuşma içeren bir video seçin."
            }
        }
    }

    func importVideo(from item: PhotosPickerItem) async {
        isImporting = true
        errorMessage = nil
        importedVideoURL = nil
        metadata = nil
        defer { isImporting = false }

        do {
            guard let movie = try await item.loadTransferable(type: VideoTransferable.self) else {
                errorMessage = "Could not load video."
                return
            }

            // Move from temp to persistent app documents
            let persistentURL = try Self.persistVideo(from: movie.url)
            guard let importedMetadata = await VideoMetadataService.extract(from: persistentURL) else {
                try? FileManager.default.removeItem(at: persistentURL)
                throw ImportError.metadataUnavailable
            }
            guard importedMetadata.isSupported else {
                try? FileManager.default.removeItem(at: persistentURL)
                throw ImportError.unsupportedDuration(importedMetadata.duration)
            }
            guard importedMetadata.hasAudio else {
                try? FileManager.default.removeItem(at: persistentURL)
                throw ImportError.missingAudio
            }

            importedVideoURL = persistentURL
            metadata = importedMetadata
        } catch {
            #if DEBUG
            print("[VideoImport] failed: \(error)")
            #endif
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "Video yüklenemedi. Lütfen başka bir dosya deneyin."
        }
    }

    /// Move video from temp directory to persistent app storage
    private static func persistVideo(from tempURL: URL) throws -> URL {
        let videosDir = URL.documentsDirectory
            .appending(path: "CutSense", directoryHint: .isDirectory)
            .appending(path: "videos", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: videosDir, withIntermediateDirectories: true)

        let fileExtension = tempURL.pathExtension.isEmpty ? "mov" : tempURL.pathExtension
        let destination = videosDir.appending(path: "\(UUID().uuidString).\(fileExtension)")
        try FileManager.default.moveItem(at: tempURL, to: destination)
        return destination
    }
}

struct VideoTransferable: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let tempDir = FileManager.default.temporaryDirectory
                .appending(path: "CutSense", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

            let fileExtension = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let destination = tempDir.appending(path: "\(UUID().uuidString).\(fileExtension)")
            try FileManager.default.copyItem(at: received.file, to: destination)
            return Self(url: destination)
        }
    }
}
