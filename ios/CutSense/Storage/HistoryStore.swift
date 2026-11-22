import AVFoundation
import Foundation
import Observation
import UIKit

/// One saved-to-Photos edit. Only numbers and a tiny preview; the video itself stays in Photos.
struct HistoryEntry: Codable, Identifiable, Equatable {
    var id: UUID
    var date: Date
    var originalDuration: Double
    var outputDuration: Double
    var removedPercent: Int
    /// `CutIntensity.rawValue`.
    var intensity: String
    var isCustom: Bool
    var resolution: String?
    var hasThumbnail: Bool
}

/// Edit history in Application Support/CutSense/History (history.json + thumbs/<uuid>.jpg), excluded from backup.
/// Not a WorkFiles managed location, so launch sweeps and Settings > Clear never touch it.
@MainActor @Observable
final class HistoryStore {
    static let cap = 200
    static let maxThumbnailBytes = 24_000

    static let shared: HistoryStore = {
        let store = HistoryStore(directory: URL.applicationSupportDirectory.appending(path: "CutSense/History", directoryHint: .isDirectory))
        #if DEBUG
        if let raw = ProcessInfo.processInfo.environment["CUTSENSE_SEED_HISTORY"], let count = Int(raw) {
            store.seed(count)
        }
        #endif
        return store
    }()

    private struct File: Codable {
        var version: Int
        var entries: [HistoryEntry]
    }

    /// Newest first.
    private(set) var entries: [HistoryEntry] = []

    var removedSeconds: Double {
        entries.reduce(0) { $0 + max(0, $1.originalDuration - $1.outputDuration) }
    }

    private let directory: URL
    private var fileURL: URL { directory.appending(path: "history.json") }
    private var thumbsURL: URL { directory.appending(path: "thumbs", directoryHint: .isDirectory) }

    init(directory: URL) {
        self.directory = directory
        prepareDirectory()
        load()
    }

    func thumbnailURL(for id: UUID) -> URL {
        thumbsURL.appending(path: "\(id.uuidString).jpg")
    }

    func add(_ entry: HistoryEntry, thumbnail: Data?) {
        var entry = entry
        entry.hasThumbnail = false
        if let thumbnail, thumbnail.count <= Self.maxThumbnailBytes {
            entry.hasThumbnail = write(thumbnail, to: thumbnailURL(for: entry.id))
        }
        entries.insert(entry, at: 0)
        if entries.count > Self.cap {
            for dropped in entries[Self.cap...] { removeThumbnail(dropped.id) }
            entries.removeSubrange(Self.cap...)
        }
        save()
    }

    func delete(id: UUID) {
        entries.removeAll { $0.id == id }
        removeThumbnail(id)
        save()
    }

    func clear() {
        entries = []
        try? FileManager.default.removeItem(at: thumbsURL)
        prepareDirectory()
        save()
    }

    /// A small JPEG of the frame at 25% of the output; nil when the frame can't be read.
    nonisolated static func thumbnail(of url: URL, outputDuration: Double) async -> Data? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true // portrait video would come out sideways
        generator.maximumSize = CGSize(width: 160, height: 160)
        guard let (image, _) = try? await generator.image(at: CMTime(seconds: outputDuration * 0.25, preferredTimescale: 600)) else {
            return nil
        }
        return UIImage(cgImage: image).jpegData(compressionQuality: 0.7)
    }

    // MARK: - Disk

    private func prepareDirectory() {
        let manager = FileManager.default
        guard !manager.fileExists(atPath: thumbsURL.path) else { return }
        do {
            try manager.createDirectory(at: thumbsURL, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var dir = directory
            try dir.setResourceValues(values)
        } catch {
            log("history dir", error)
        }
    }

    /// A missing, corrupt or unknown-version file starts empty; the next write replaces it.
    private func load() {
        if let data = try? Data(contentsOf: fileURL),
           let file = try? JSONDecoder().decode(File.self, from: data),
           file.version == 1 {
            entries = file.entries
        }
        let referenced = Set(entries.filter(\.hasThumbnail).map { thumbnailURL(for: $0.id).lastPathComponent })
        let files = (try? FileManager.default.contentsOfDirectory(at: thumbsURL, includingPropertiesForKeys: nil)) ?? []
        for url in files where !referenced.contains(url.lastPathComponent) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(File(version: 1, entries: entries))
            try data.write(to: fileURL, options: .atomic)
        } catch {
            log("history save", error)
        }
    }

    private func write(_ data: Data, to url: URL) -> Bool {
        do {
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            log("thumbnail save", error)
            return false
        }
    }

    private func removeThumbnail(_ id: UUID) {
        try? FileManager.default.removeItem(at: thumbnailURL(for: id))
    }

    private func log(_ what: String, _ error: Error) {
        #if DEBUG
        print("[HistoryStore] \(what) failed: \(error)")
        #endif
    }

    #if DEBUG
    /// Replaces the store with `count` fake entries (0 clears): one custom, one without a thumbnail.
    private func seed(_ count: Int) {
        clear()
        let intensities = QuickSilenceEngine.CutIntensity.allCases
        let resolutions: [String?] = ["1080p", "4K", "720p", nil]
        let thumb = UIGraphicsImageRenderer(size: CGSize(width: 160, height: 160)).jpegData(withCompressionQuality: 0.7) { context in
            let colors = [UIColor(white: 0.35, alpha: 1).cgColor, UIColor(white: 0.1, alpha: 1).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceGray(), colors: colors, locations: [0, 1]) {
                context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 160, y: 160), options: [])
            }
        }
        // Oldest first so the newest ends on top.
        for index in (0..<count).reversed() {
            let original = Double(45 + index * 37 % 400)
            let percent = 12 + index * 17 % 55
            let entry = HistoryEntry(
                id: UUID(),
                date: Date().addingTimeInterval(-Double(index) * 86_400 * 1.3 - 3_600),
                originalDuration: original,
                outputDuration: original * Double(100 - percent) / 100,
                removedPercent: percent,
                intensity: intensities[index % intensities.count].rawValue,
                isCustom: index == 1,
                resolution: resolutions[index % resolutions.count],
                hasThumbnail: true)
            add(entry, thumbnail: index == 2 ? nil : thumb)
        }
    }
    #endif
}
