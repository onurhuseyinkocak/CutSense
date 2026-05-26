import SwiftUI
import AVFoundation

/// Split-screen A/B comparison: original source vs clean-cut with captions.
/// Both players sync to the same playback position.
struct ABComparisonPlayer: View {
    let videoURL: URL
    let decisions: [RoughCutDecision]
    let captions: [CaptionSegment]
    let template: TemplateConfig
    @Binding var currentTime: Double
    @Binding var isComparing: Bool

    @State private var originalPlayer: AVPlayer?
    @State private var editedPlayer: AVPlayer?
    @State private var isPlaying = false
    @State private var isLoading = true
    @State private var duration: Double = 0
    @State private var editedDuration: Double = 0
    @State private var timeObserver: Any?
    @State private var lastSyncTime: Double = -1
    @State private var sourceTimeForCleanTime: [Double: Double] = [:]
    @State private var splitPosition: CGFloat = 0.5 // 0.5 = 50/50, 0.0 = all original, 1.0 = all edited
    @State private var isDraggingDivider = false
    @State private var viewMode: ViewMode = .split // .split, .original, .edited

    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                loadingView
            } else {
                switch viewMode {
                case .split:
                    splitScreenView
                case .original:
                    singleView(label: "ORIGINAL", player: originalPlayer, isOriginal: true)
                case .edited:
                    singleView(label: "EDITED", player: editedPlayer, isOriginal: false)
                }
            }
        }
        .task { await buildPlayers() }
        .onDisappear { cleanup() }
        .onChange(of: currentTime) { _, newTime in
            syncOriginalToEdited(cleanTime: newTime)
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 12) {
            HStack(spacing: 2) {
                SkeletonBlock(height: 200, radius: 6)
                SkeletonBlock(height: 200, radius: 6)
            }
            .padding(.horizontal, 4)
            HStack(spacing: 16) {
                SkeletonBlock(width: 24, height: 24, radius: 12)
                SkeletonBlock(width: 24, height: 24, radius: 12)
                SkeletonBlock(width: 36, height: 36, radius: 18)
                SkeletonBlock(width: 24, height: 24, radius: 12)
                SkeletonBlock(width: 24, height: 24, radius: 12)
            }
        }
        .frame(height: 340)
    }

    // MARK: - Split Screen View

    private var splitScreenView: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                ZStack {
                    HStack(spacing: 0) {
                        // Original side (left)
                        ZStack {
                            if let player = originalPlayer {
                                ABPlayerView(player: player)
                            }
                            // Original label
                            VStack {
                                HStack {
                                    Text("ORIGINAL")
                                        .font(.caption2.weight(.heavy))
                                        .foregroundStyle(.white.opacity(0.8))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.red.opacity(0.6))
                                        .clipShape(Capsule())
                                        .padding(6)
                                    Spacer()
                                }
                                Spacer()
                            }
                        }
                        .frame(width: geo.size.width * splitPosition)

                        // Edited side (right)
                        ZStack {
                            if let player = editedPlayer {
                                ABPlayerView(player: player)
                            }
                            // Caption overlay
                            VStack {
                                Spacer()
                                captionOverlay
                            }
                            // Edited label
                            VStack {
                                HStack {
                                    Spacer()
                                    Text("EDITED")
                                        .font(.caption2.weight(.heavy))
                                        .foregroundStyle(.black)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.green.opacity(0.8))
                                        .clipShape(Capsule())
                                        .padding(6)
                                }
                                Spacer()
                            }
                        }
                        .frame(width: geo.size.width * (1 - splitPosition))
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                    // Draggable divider
                    VStack(spacing: 0) {
                        HStack(spacing: 0) {
                            Spacer()
                                .frame(width: geo.size.width * splitPosition)
                            // Divider handle
                            VStack {
                                Circle()
                                    .fill(Color.white)
                                    .frame(width: 10, height: 10)
                                    .padding(4)
                                    .background(Color.white.opacity(0.8))
                                    .clipShape(Circle())
                            }
                            .frame(width: 20)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        isDraggingDivider = true
                                        let newPosition = max(0.1, min(0.9, value.location.x / geo.size.width))
                                        splitPosition = newPosition
                                    }
                                    .onEnded { _ in
                                        isDraggingDivider = false
                                    }
                            )
                            Spacer()
                        }
                        Spacer()
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { togglePlayback() }
                .accessibilityLabel("Video comparison")
                .accessibilityHint("Tap to \(isPlaying ? "pause" : "play")")
            }
            .frame(height: 260)

            // Unified controls
            HStack(spacing: 16) {
                // Back to single view
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { isComparing = false }
                } label: {
                    Image(systemName: "rectangle.on.rectangle.slash")
                        .font(.caption)
                        .foregroundStyle(.gray)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Exit comparison view")

                Spacer()

                Button { skip(-2) } label: {
                    Image(systemName: "gobackward.2")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Skip back 2 seconds")

                Button { togglePlayback() } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(isPlaying ? "Pause" : "Play")

                Button { skip(2) } label: {
                    Image(systemName: "goforward.2")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Skip forward 2 seconds")

                Spacer()

                // Time display
                Text(formatTime(currentTime))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.gray)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .gesture(
            DragGesture()
                .onEnded { value in
                    let translation = value.translation.width
                    if translation < -50 {
                        // Swiped left → show edited
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewMode = .edited
                        }
                    } else if translation > 50 {
                        // Swiped right → show original
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewMode = .original
                        }
                    }
                }
        )
    }

    // MARK: - Single View (Original or Edited)

    private func singleView(label: String, player: AVPlayer?, isOriginal: Bool) -> some View {
        VStack(spacing: 0) {
            ZStack {
                if let player = player {
                    ABPlayerView(player: player)
                }

                // Caption overlay (only for edited view)
                if !isOriginal {
                    VStack {
                        Spacer()
                        captionOverlay
                    }
                }

                // Label
                VStack {
                    HStack {
                        if isOriginal {
                            Text(label)
                                .font(.caption2.weight(.heavy))
                                .foregroundStyle(.white.opacity(0.8))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.red.opacity(0.6))
                                .clipShape(Capsule())
                                .padding(6)
                            Spacer()
                        } else {
                            Spacer()
                            Text(label)
                                .font(.caption2.weight(.heavy))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.8))
                                .clipShape(Capsule())
                                .padding(6)
                        }
                    }
                    Spacer()
                }
            }
            .frame(height: 260)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
            .onTapGesture { togglePlayback() }
            .accessibilityLabel("Video player")
            .accessibilityHint("Tap to \(isPlaying ? "pause" : "play")")

            // Unified controls
            HStack(spacing: 16) {
                // Back to comparison
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { viewMode = .split }
                } label: {
                    Image(systemName: "rectangle.on.rectangle")
                        .font(.caption)
                        .foregroundStyle(.gray)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Back to split view")

                Spacer()

                Button { skip(-2) } label: {
                    Image(systemName: "gobackward.2")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Skip back 2 seconds")

                Button { togglePlayback() } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(isPlaying ? "Pause" : "Play")

                Button { skip(2) } label: {
                    Image(systemName: "goforward.2")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Skip forward 2 seconds")

                Spacer()

                // Time display
                Text(formatTime(currentTime))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.gray)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .gesture(
            DragGesture()
                .onEnded { value in
                    let translation = value.translation.width
                    if translation < -50 || translation > 50 {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewMode = .split
                        }
                    }
                }
        )
    }

    // MARK: - Caption Overlay (edited side)

    private var captionOverlay: some View {
        let active = captions.first { caption in
            currentTime >= caption.startTime && currentTime < caption.endTime
        }

        return Group {
            if let caption = active {
                miniCaptionView(caption)
                    .transition(.opacity)
                    .id(caption.id)
            }
        }
        .animation(.easeInOut(duration: 0.12), value: active?.id)
        .padding(.horizontal, 6)
        .padding(.bottom, 8)
    }

    private func miniCaptionView(_ caption: CaptionSegment) -> some View {
        let theme = template.captionTheme
        let progress = min(max((currentTime - caption.startTime) / (caption.endTime - caption.startTime), 0), 1)
        let words = caption.text.split(separator: " ").map(String.init)
        let revealedCount = max(1, Int(ceil(Double(words.count) * progress)))

        return HStack(spacing: 0) {
            ForEach(Array(words.enumerated()), id: \.offset) { idx, word in
                let isRevealed = idx < revealedCount
                Text(word + (idx < words.count - 1 ? " " : ""))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(isRevealed
                        ? Color(theme.karaokeHighlight.uiColor)
                        : Color(theme.karaokeDim.uiColor))
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color.black.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    // MARK: - Build

    private func buildPlayers() async {
        do {
            // Original: straight from source
            let sourceAsset = AVURLAsset(url: videoURL)
            let sourceDur = try await sourceAsset.load(.duration)
            let origPlayer = AVPlayer(playerItem: AVPlayerItem(asset: sourceAsset))
            origPlayer.isMuted = true // only edited side has audio

            // Edited: clean timeline
            let timeline = try await CleanTimelineBuilder.build(
                from: videoURL,
                decisions: decisions
            )
            let editedItem = AVPlayerItem(asset: timeline.composition)
            let edPlayer = AVPlayer(playerItem: editedItem)

            let editDur = try await timeline.composition.load(.duration)

            // Build source→clean time mapping from decisions
            buildTimeMapping()

            // Time observer on edited player (drives both)
            let observer = edPlayer.addPeriodicTimeObserver(
                forInterval: CMTime(seconds: 1.0 / 30.0, preferredTimescale: 600),
                queue: .main
            ) { time in
                MainActor.assumeIsolated {
                    let secs = time.seconds
                    currentTime = secs
                    syncOriginalToEdited(cleanTime: secs)
                    if secs >= editDur.seconds - 0.05 {
                        isPlaying = false
                    }
                }
            }

            originalPlayer = origPlayer
            editedPlayer = edPlayer
            duration = sourceDur.seconds
            editedDuration = editDur.seconds
            timeObserver = observer
            isLoading = false
        } catch {
            isLoading = false
        }
    }

    /// Build a mapping from clean-timeline seconds to source-timeline seconds.
    private func buildTimeMapping() {
        let keepSegments = decisions
            .filter { $0.action == .keep }
            .sorted { $0.startTime < $1.startTime }

        // Store the mapping for quick lookup
        var cleanOffset: Double = 0
        var mapping: [(cleanStart: Double, sourceStart: Double, duration: Double)] = []

        for seg in keepSegments {
            let segDuration = seg.endTime - seg.startTime
            mapping.append((cleanStart: cleanOffset, sourceStart: seg.startTime, duration: segDuration))
            cleanOffset += segDuration
        }

        // Store as instance property won't work (let me use a different approach)
        // Instead, we'll compute inline in syncOriginalToEdited
    }

    /// Seek the original player to the source timestamp that corresponds to cleanTime.
    private func syncOriginalToEdited(cleanTime: Double) {
        guard let origPlayer = originalPlayer, abs(cleanTime - lastSyncTime) > 0.016 else { return }
        lastSyncTime = cleanTime

        let keepSegments = decisions
            .filter { $0.action == .keep }
            .sorted { $0.startTime < $1.startTime }

        var cleanOffset: Double = 0
        for seg in keepSegments {
            let segDuration = seg.endTime - seg.startTime
            if cleanTime >= cleanOffset && cleanTime < cleanOffset + segDuration {
                let offsetInSegment = cleanTime - cleanOffset
                let sourceTime = seg.startTime + offsetInSegment
                let cmTime = CMTime(seconds: sourceTime, preferredTimescale: 600)
                origPlayer.seek(to: cmTime, toleranceBefore: CMTime(seconds: 0.016, preferredTimescale: 600),
                               toleranceAfter: CMTime(seconds: 0.016, preferredTimescale: 600))
                return
            }
            cleanOffset += segDuration
        }
    }

    // MARK: - Controls

    private func togglePlayback() {
        guard let edited = editedPlayer, let original = originalPlayer else { return }
        if isPlaying {
            edited.pause()
            original.pause()
        } else {
            if currentTime >= editedDuration - 0.2 {
                edited.seek(to: .zero)
                original.seek(to: .zero)
                currentTime = 0
            }
            edited.play()
            original.play()
        }
        isPlaying.toggle()
    }

    private func skip(_ seconds: Double) {
        guard let edited = editedPlayer else { return }
        let target = min(max(currentTime + seconds, 0), editedDuration)
        let cmTime = CMTime(seconds: target, preferredTimescale: 600)
        edited.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = target
        syncOriginalToEdited(cleanTime: target)
    }

    private func cleanup() {
        if let observer = timeObserver {
            editedPlayer?.removeTimeObserver(observer)
            timeObserver = nil
        }
        editedPlayer?.pause()
        originalPlayer?.pause()
        editedPlayer = nil
        originalPlayer = nil
    }

    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - View Mode Enum

enum ViewMode {
    case split
    case original
    case edited
}

// MARK: - Player UIView

private struct ABPlayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> ABPlayerUIView {
        let view = ABPlayerUIView()
        view.player = player
        return view
    }

    func updateUIView(_ uiView: ABPlayerUIView, context: Context) {
        uiView.player = player
    }
}

private class ABPlayerUIView: UIView {
    var player: AVPlayer? {
        didSet { playerLayer.player = player }
    }

    override class var layerClass: AnyClass { AVPlayerLayer.self }

    private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    override init(frame: CGRect) {
        super.init(frame: frame)
        playerLayer.videoGravity = .resizeAspectFill
        backgroundColor = .black
    }

    required init?(coder: NSCoder) { fatalError() }
}
