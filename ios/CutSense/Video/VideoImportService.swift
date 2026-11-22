import PhotosUI
import SwiftUI
import AVFoundation
import os

/// Copies a picked video into the app's caches, reporting iCloud download
/// progress, and rejects files without video or audio.
@MainActor
@Observable
final class VideoImportService {
    private(set) var importedVideoURL: URL?
    private(set) var isImporting = false
    private(set) var error: ImportError?
    /// 0...1 while Photos is downloading the file, -1 when unknown.
    private(set) var downloadProgress: Double = -1

    private var loadProgress: Progress?

    enum ImportError: Error {
        case loadFailed
        case noVideo
        case missingAudio
        case photosExportFailed

        func message(for language: AppLanguage) -> String {
            switch self {
            case .loadFailed: appText(language, "Video yüklenemedi. Lütfen farklı bir dosya deneyin.", "The video could not be loaded. Try a different file.")
            case .noVideo: appText(language, "Bu dosyada video bulunamadı.", "No video was found in this file.")
            case .missingAudio: appText(language, "Bu videoda ses bulunamadı. Konuşma içeren bir video seç.", "This video has no audio. Choose a video with speech.")
            case .photosExportFailed: appText(language, "Fotoğraflar bu videoyu veremedi. Tekrar dene.", "Photos couldn't hand over this video. Try again.")
            }
        }
    }

    private var importToken = UUID()

    func importVideo(from item: PhotosPickerItem) async {
        cancelImport()
        let token = UUID()
        importToken = token
        discardImport()
        error = nil
        downloadProgress = -1
        isImporting = true
        defer {
            // A superseded import must not touch the newer import's state.
            if importToken == token {
                isImporting = false
                loadProgress = nil
                downloadProgress = -1
            }
        }

        var copiedURL: URL?
        do {
            let movie: VideoTransferable
            do {
                movie = try await loadMovie(item)
            } catch where Self.isTransientExportFailure(error) {
                // Photos' export helper fails intermittently (4:34 clip: failed after a 2.5 min transcode).
                try Task.checkCancellation()
                guard importToken == token else { throw CancellationError() }
                Logger(subsystem: "com.cutsense.app", category: "import").notice("retrying import after Photos export failure")
                movie = try await loadMovie(item)
            }
            copiedURL = movie.url
            try Task.checkCancellation()
            guard importToken == token else { throw CancellationError() }
            let asset = AVURLAsset(url: movie.url)
            guard try await !asset.loadTracks(withMediaType: .video).isEmpty else { throw ImportError.noVideo }
            guard try await !asset.loadTracks(withMediaType: .audio).isEmpty else { throw ImportError.missingAudio }
            guard importToken == token, !Task.isCancelled else { throw CancellationError() }
            importedVideoURL = movie.url
        } catch {
            WorkFiles.delete(copiedURL)
            guard importToken == token, !(error is CancellationError) else { return }
            let ns = error as NSError
            let underlying = (ns.userInfo[NSUnderlyingErrorKey] as? NSError).map { "\($0.domain) \($0.code)" } ?? "-"
            Logger(subsystem: "com.cutsense.app", category: "import").error("import failed: \(ns.domain, privacy: .public) \(ns.code) underlying: \(underlying, privacy: .public)")
            self.error = (error as? ImportError) ?? (Self.isTransientExportFailure(error) ? .photosExportFailed : .loadFailed)
        }
    }

    /// Photos' export helper failing: NSItemProvider -1000 / Cocoa 4101 ("couldn't communicate with a
    /// helper application"). CoreTransferable surfaces it as a bare TransferableSupportError (no
    /// underlying error, seen on device), so that domain counts too. Worth one retry.
    nonisolated static func isTransientExportFailure(_ error: Error) -> Bool {
        var current: NSError? = error as NSError
        while let ns = current {
            if (ns.domain == NSItemProvider.errorDomain && ns.code == -1000)
                || (ns.domain == NSCocoaErrorDomain && ns.code == 4101)
                || ns.domain == "PHAssetExportRequestErrorDomain"
                || ns.domain.hasSuffix("TransferableSupportError") { return true }
            current = ns.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return false
    }

    /// Deletes the imported copy (managed files only) and forgets it.
    func discardImport() {
        WorkFiles.delete(importedVideoURL)
        importedVideoURL = nil
    }

    func cancelImport() {
        loadProgress?.cancel()
        loadProgress = nil
    }

    private func loadMovie(_ item: PhotosPickerItem) async throws -> VideoTransferable {
        let box = ProgressBox()
        // The poller must end with the load: a failed load's Progress may never report finished,
        // and a stale poller would overwrite the retry's (or next import's) downloadProgress.
        defer { box.poller?.cancel() }
        let movie: VideoTransferable? = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let progress = item.loadTransferable(type: VideoTransferable.self) { result in
                    // PhotosUI can call back twice (an error after a cancel); a second resume traps (crash 2026-11-21-203348).
                    if box.claimResume() { continuation.resume(with: result) }
                }
                box.progress = progress
                loadProgress = progress
                box.poller = Task { @MainActor [weak self] in
                    while !Task.isCancelled && !progress.isFinished && !progress.isCancelled {
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
    var poller: Task<Void, Never>?
    private let lock = NSLock()
    private var resumed = false

    /// True exactly once per load.
    func claimResume() -> Bool {
        lock.withLock {
            defer { resumed = true }
            return !resumed
        }
    }
}

struct VideoTransferable: Transferable, Sendable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let dir = WorkFiles.importsDirectory
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let destination = dir.appending(path: "\(UUID().uuidString).\(ext)")
            // Move first: copying would briefly double a multi-GB file on disk.
            do { try FileManager.default.moveItem(at: received.file, to: destination) }
            catch { try FileManager.default.copyItem(at: received.file, to: destination) }
            return Self(url: destination)
        }
    }
}
