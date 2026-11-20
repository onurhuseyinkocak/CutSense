import PhotosUI
import SwiftUI
import AVFoundation

/// Copies a picked video into the app's caches, reporting iCloud download
/// progress, and rejects files without video or audio.
@MainActor
@Observable
final class VideoImportService {
    private(set) var importedVideoURL: URL?
    private(set) var isImporting = false
    private(set) var errorMessage: String?
    /// 0...1 while Photos is downloading the file, -1 when unknown.
    private(set) var downloadProgress: Double = -1

    private var loadProgress: Progress?

    enum ImportError: LocalizedError {
        case loadFailed
        case noVideo
        case missingAudio

        var errorDescription: String? {
            switch self {
            case .loadFailed: "Video yüklenemedi. Lütfen farklı bir dosya deneyin."
            case .noVideo: "Bu dosyada video bulunamadı."
            case .missingAudio: "Bu videoda ses bulunamadı. Konuşma içeren bir video seç."
            }
        }
    }

    func importVideo(from item: PhotosPickerItem) async {
        cancelImport()
        if let previous = importedVideoURL { try? FileManager.default.removeItem(at: previous) }
        importedVideoURL = nil
        errorMessage = nil
        downloadProgress = -1
        isImporting = true
        defer {
            isImporting = false
            loadProgress = nil
            downloadProgress = -1
        }

        do {
            let movie = try await loadMovie(item)
            try Task.checkCancellation()
            let asset = AVURLAsset(url: movie.url)
            guard try await !asset.loadTracks(withMediaType: .video).isEmpty else {
                try? FileManager.default.removeItem(at: movie.url)
                throw ImportError.noVideo
            }
            guard try await !asset.loadTracks(withMediaType: .audio).isEmpty else {
                try? FileManager.default.removeItem(at: movie.url)
                throw ImportError.missingAudio
            }
            importedVideoURL = movie.url
        } catch is CancellationError {
            return
        } catch {
            #if DEBUG
            print("[VideoImport] failed: \(error)")
            #endif
            errorMessage = (error as? ImportError)?.errorDescription ?? ImportError.loadFailed.errorDescription
        }
    }

    func cancelImport() {
        loadProgress?.cancel()
        loadProgress = nil
    }

    private func loadMovie(_ item: PhotosPickerItem) async throws -> VideoTransferable {
        let box = ProgressBox()
        let movie: VideoTransferable? = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let progress = item.loadTransferable(type: VideoTransferable.self) { result in
                    continuation.resume(with: result)
                }
                box.progress = progress
                loadProgress = progress
                Task { @MainActor [weak self] in
                    while !progress.isFinished && !progress.isCancelled {
                        self?.downloadProgress = progress.fractionCompleted
                        try? await Task.sleep(for: .milliseconds(250))
                    }
                }
            }
        } onCancel: {
            box.progress?.cancel()
        }
        guard let movie else { throw ImportError.loadFailed }
        return movie
    }
}

private final class ProgressBox: @unchecked Sendable {
    var progress: Progress?
}

struct VideoTransferable: Transferable, Sendable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let dir = URL.cachesDirectory.appending(path: "CutSense/imports", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let destination = dir.appending(path: "\(UUID().uuidString).\(ext)")
            try FileManager.default.copyItem(at: received.file, to: destination)
            return Self(url: destination)
        }
    }
}
