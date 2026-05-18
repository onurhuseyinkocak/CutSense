import AVFoundation
import SwiftUI

struct VideoPlayerView: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = AVPlayer(url: url)
        controller.showsPlaybackControls = true
        controller.allowsPictureInPicturePlayback = false
        controller.view.backgroundColor = .black
        context.coordinator.currentURL = url
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        guard context.coordinator.currentURL != url else { return }
        context.coordinator.currentURL = url
        controller.player = AVPlayer(url: url)
    }

    final class Coordinator {
        var currentURL: URL?
    }
}

import AVKit

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
