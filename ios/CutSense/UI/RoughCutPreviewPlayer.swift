import SwiftUI
import AVFoundation

struct RoughCutPreviewPlayer: View {
    let videoURL: URL
    let decisions: [RoughCutDecision]
    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var timeObserver: Any?

    var body: some View {
        VStack(spacing: 0) {
            if let error = errorMessage {
                errorView(error)
            } else if isLoading {
                loadingView
            } else {
                playerView
            }
        }
        .task { await buildPreview() }
        .onDisappear { cleanup() }
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(.white)
            Text("Building preview...")
                .font(.caption)
                .foregroundStyle(.gray)
        }
        .frame(height: 220)
    }

    private func errorView(_ error: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            Text(error)
                .font(.caption)
                .foregroundStyle(.gray)
                .multilineTextAlignment(.center)
        }
        .frame(height: 220)
    }

    private var playerView: some View {
        VStack(spacing: 12) {
            // Video
            RoughCutPlayerView(player: player)
                .aspectRatio(9/16, contentMode: .fit)
                .frame(maxHeight: 300)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            // Timeline bar
            if duration > 0 {
                VStack(spacing: 4) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            // Background
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.white.opacity(0.1))
                                .frame(height: 4)

                            // Progress
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.white)
                                .frame(width: geo.size.width * (currentTime / duration), height: 4)
                        }
                    }
                    .frame(height: 4)

                    HStack {
                        Text(formatTime(currentTime))
                        Spacer()
                        Text(formatTime(duration))
                    }
                    .font(.caption2.monospaced())
                    .foregroundStyle(.gray)
                }
            }

            // Controls
            HStack(spacing: 24) {
                Button {
                    player?.seek(to: .zero)
                    currentTime = 0
                } label: {
                    Image(systemName: "backward.end.fill")
                        .foregroundStyle(.white)
                }

                Button {
                    togglePlayback()
                } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                }

                Button {
                    player?.seek(to: CMTime(seconds: duration, preferredTimescale: 600))
                } label: {
                    Image(systemName: "forward.end.fill")
                        .foregroundStyle(.white)
                }
            }
        }
        .padding(.horizontal)
    }

    private func buildPreview() async {
        do {
            let timeline = try await CleanTimelineBuilder.build(
                from: videoURL,
                decisions: decisions
            )

            let playerItem = AVPlayerItem(asset: timeline.composition)
            let avPlayer = AVPlayer(playerItem: playerItem)

            let dur = try await timeline.composition.load(.duration)
            duration = dur.seconds

            // Time observer
            let observer = avPlayer.addPeriodicTimeObserver(
                forInterval: CMTime(seconds: 0.1, preferredTimescale: 600),
                queue: .main
            ) { time in
                currentTime = time.seconds
                if time.seconds >= duration - 0.1 {
                    isPlaying = false
                }
            }

            player = avPlayer
            timeObserver = observer
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    private func togglePlayback() {
        guard let player else { return }
        if isPlaying {
            player.pause()
        } else {
            if currentTime >= duration - 0.2 {
                player.seek(to: .zero)
            }
            player.play()
        }
        isPlaying.toggle()
    }

    private func cleanup() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
        }
        player?.pause()
        player = nil
    }

    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - AVPlayer UIViewRepresentable

private struct RoughCutPlayerView: UIViewRepresentable {
    let player: AVPlayer?

    func makeUIView(context: Context) -> PlayerUIView {
        let view = PlayerUIView()
        view.player = player
        return view
    }

    func updateUIView(_ uiView: PlayerUIView, context: Context) {
        uiView.player = player
    }
}

private class PlayerUIView: UIView {
    var player: AVPlayer? {
        didSet { playerLayer.player = player }
    }

    private var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }

    override class var layerClass: AnyClass { AVPlayerLayer.self }

    override init(frame: CGRect) {
        super.init(frame: frame)
        playerLayer.videoGravity = .resizeAspect
        backgroundColor = .black
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}
