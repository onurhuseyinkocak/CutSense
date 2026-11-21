import Foundation

/// App-owned scratch files: imports in Caches/CutSense/imports and exports in tmp
/// named "cutsense-*". Anything else (the user's own files, DEBUG fixtures) is never touched.
enum WorkFiles {
    static let importsDirectory = URL.cachesDirectory.appending(path: "CutSense/imports", directoryHint: .isDirectory)

    private static var tmp: URL { FileManager.default.temporaryDirectory }

    private static func canonical(_ url: URL) -> URL { url.resolvingSymlinksInPath().standardizedFileURL }

    static func isManaged(_ url: URL) -> Bool {
        let file = canonical(url)
        let parent = file.deletingLastPathComponent()
        if parent == canonical(importsDirectory) { return true }
        return parent == canonical(tmp) && file.lastPathComponent.hasPrefix("cutsense-")
    }

    static func delete(_ url: URL?) {
        guard let url, isManaged(url) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    static func sweepAtLaunch() {
        for url in managedFiles() { try? FileManager.default.removeItem(at: url) }
        for url in contents(of: tmp) where isLegacyInput(url) { try? FileManager.default.removeItem(at: url) }
    }

    static func usageBytes() -> Int64 {
        managedFiles().reduce(0) { $0 + size(of: $1) }
    }

    /// Deletes managed files not in `keeping`; returns bytes freed.
    static func clearUnused(keeping: Set<URL>) -> Int64 {
        let kept = Set(keeping.map(canonical))
        var freed: Int64 = 0
        for url in managedFiles() where !kept.contains(canonical(url)) {
            let bytes = size(of: url)
            if (try? FileManager.default.removeItem(at: url)) != nil { freed += bytes }
        }
        return freed
    }

    static func availableBytes() -> Int64 {
        let values = try? URL.cachesDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? 0
    }

    private static func isLegacyInput(_ url: URL) -> Bool {
        url.lastPathComponent.hasPrefix("input-") && url.pathExtension.lowercased() == "mov"
    }

    private static func managedFiles() -> [URL] {
        contents(of: importsDirectory) + contents(of: tmp).filter { $0.lastPathComponent.hasPrefix("cutsense-") }
    }

    private static func contents(of dir: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
    }

    private static func size(of url: URL) -> Int64 {
        var total: Int64 = 0
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileSizeKey, .isRegularFileKey]
        let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys)
        let urls = [url] + (walker?.allObjects as? [URL] ?? [])
        for item in urls {
            guard let v = try? item.resourceValues(forKeys: Set(keys)), v.isRegularFile == true else { continue }
            total += Int64(v.fileSize ?? v.totalFileAllocatedSize ?? 0)
        }
        return total
    }
}

/// Owns the files of one edit: the imported input and at most one export output.
@MainActor
final class WorkSession {
    private(set) var inputURL: URL?
    private(set) var outputURL: URL?

    var urlsInUse: Set<URL> { Set([inputURL, outputURL].compactMap { $0 }) }

    func begin(input: URL) {
        end()
        inputURL = input
    }

    func setOutput(_ url: URL) {
        if outputURL != url { WorkFiles.delete(outputURL) }
        outputURL = url
    }

    func discardOutput() {
        WorkFiles.delete(outputURL)
        outputURL = nil
    }

    func end() {
        discardOutput()
        WorkFiles.delete(inputURL)
        inputURL = nil
    }
}
