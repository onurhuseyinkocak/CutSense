import Foundation

public struct SFXEntry: Sendable, Identifiable, Decodable {
    public let id: String
    public let kind: String
    public let file: String
    public let durationSeconds: Double
}

public struct SFXLibrary: Sendable {
    private static let decoder = JSONDecoder()
    nonisolated(unsafe) private static var cachedEntries: [SFXEntry]?

    public static var all: [SFXEntry] {
        if let cached = cachedEntries {
            return cached
        }

        guard let url = Bundle.main.url(forResource: "sfx_library", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return []
        }

        struct Manifest: Decodable {
            let entries: [SFXEntry]
        }

        if let manifest = try? decoder.decode(Manifest.self, from: data) {
            cachedEntries = manifest.entries
            return manifest.entries
        }
        return []
    }

    public static func entry(forKind kind: String) -> SFXEntry? {
        all.first { $0.kind == kind }
    }

    public static func url(for entry: SFXEntry) -> URL? {
        let base = (entry.file as NSString).lastPathComponent
        let ext = (base as NSString).pathExtension
        let name = (base as NSString).deletingPathExtension
        return Bundle.main.url(forResource: name, withExtension: ext)
    }

    /// Find the best matching SFX file URL for a given category.
    static func bestFile(for category: AudioEvent.SFXCategory) -> URL? {
        let kind = category.rawValue
        if let entry = entry(forKind: kind),
           let url = url(for: entry) {
            return url
        }
        // Fallback: try to find any entry that partially matches the kind name
        return all.first(where: { $0.kind.contains(kind) }).flatMap { url(for: $0) }
    }
}
