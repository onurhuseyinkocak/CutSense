import AVFoundation

struct VideoMetadata: Sendable {
    let duration: Double
    let resolution: CGSize
    let frameRate: Float
    let fileSize: Int64
    let orientation: VideoOrientation
    let hasAudio: Bool

    var isVertical: Bool { resolution.height > resolution.width }
    var isSupported: Bool { duration > 0 && duration <= 300 }

    var formattedDuration: String {
        let mins = Int(duration) / 60
        let secs = Int(duration) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    var formattedResolution: String {
        "\(Int(resolution.width))x\(Int(resolution.height))"
    }

    var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
}

enum VideoOrientation: String, Sendable {
    case portrait
    case landscape
    case square
}

enum VideoMetadataService {
    static func extract(from url: URL) async -> VideoMetadata? {
        let asset = AVURLAsset(url: url)

        async let durationValue = asset.load(.duration)
        async let tracksValue = asset.loadTracks(withMediaType: .video)
        async let audioTracksValue = asset.loadTracks(withMediaType: .audio)

        guard let duration = try? await durationValue,
              let videoTracks = try? await tracksValue,
              let videoTrack = videoTracks.first else {
            return nil
        }

        let audioTracks = (try? await audioTracksValue) ?? []

        guard let naturalSize = try? await videoTrack.load(.naturalSize),
              let transform = try? await videoTrack.load(.preferredTransform),
              let nominalFrameRate = try? await videoTrack.load(.nominalFrameRate) else {
            return nil
        }

        let transformedSize = naturalSize.applying(transform)
        let width = abs(transformedSize.width)
        let height = abs(transformedSize.height)
        let resolution = CGSize(width: width, height: height)

        let orientation: VideoOrientation
        if abs(width - height) < 10 {
            orientation = .square
        } else if height > width {
            orientation = .portrait
        } else {
            orientation = .landscape
        }

        let fileSize: Int64
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? Int64 {
            fileSize = size
        } else {
            fileSize = 0
        }

        return VideoMetadata(
            duration: duration.seconds,
            resolution: resolution,
            frameRate: nominalFrameRate,
            fileSize: fileSize,
            orientation: orientation,
            hasAudio: !audioTracks.isEmpty
        )
    }
}
