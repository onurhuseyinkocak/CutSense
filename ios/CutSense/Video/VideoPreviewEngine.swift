import AVFoundation
import AVKit
import SwiftUI

struct VideoPlayerView: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = Self.configuredPlayer(for: url)
        controller.showsPlaybackControls = true
        controller.allowsPictureInPicturePlayback = false
        controller.view.backgroundColor = .black
        context.coordinator.currentURL = url
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        guard context.coordinator.currentURL != url else { return }
        context.coordinator.currentURL = url
        controller.player = Self.configuredPlayer(for: url)
    }

    private static func configuredPlayer(for url: URL) -> AVPlayer {
        activatePlaybackSession()
        let player = AVPlayer(url: url)
        player.isMuted = false
        player.volume = 1
        return player
    }

    private static func activatePlaybackSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback)
            try session.setActive(true)
        } catch {
            #if DEBUG
            print("[CutSense] Preview audio session failed: \(error.localizedDescription)")
            #endif
        }
    }

    final class Coordinator {
        var currentURL: URL?
    }
}

struct VideoThumbnailView: View {
    let url: URL
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(Color.white.opacity(0.05))
                    .overlay {
                        ProgressView().tint(.gray)
                    }
            }
        }
        .task {
            image = await generateThumbnail()
        }
    }

    private func generateThumbnail() async -> UIImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 400, height: 400)

        let time = CMTime(seconds: 0.5, preferredTimescale: 600)
        guard let cgImage = try? await generator.image(at: time).image else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}
