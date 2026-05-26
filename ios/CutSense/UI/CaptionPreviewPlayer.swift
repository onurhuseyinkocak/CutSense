import SwiftUI
import AVFoundation
@preconcurrency import CoreImage

struct CaptionPreviewPlayer: View {
    let videoURL: URL
    let decisions: [RoughCutDecision]
    let captions: [CaptionSegment]
    let template: TemplateConfig
    @Binding var currentTime: Double
    var onSeek: ((Double) -> Void)?
    var onEditCaption: ((CaptionSegment) -> Void)?

    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var duration: Double = 0
    @State private var timeObserver: Any?
    @State private var lastExternalTime: Double = 0
    @State private var scrubThumbnails: [Double: UIImage] = [:]
    @State private var isScrubbing = false
    @State private var scrubPosition: CGFloat = 0 // x offset in timeline
    @State private var isBuffering = false
    @State private var playerStatusObserver: NSKeyValueObservation?
    @State private var bufferObserver: NSKeyValueObservation?
    @State private var selectedCaptionId: UUID?
    @State private var loopEnabled = false
    private static let semanticEmphasisTokens: Set<String> = [
        "ai", "free", "faster", "mistake", "launch", "automated", "tool", "problem",
        "fix", "money", "users", "mvp", "app", "build", "built", "result", "results",
        "generate", "generated", "click", "tap", "code", "coding", "vibe", "startup",
        "urun", "uygulama", "ucretsiz", "hizli", "hata", "yanlis", "sorun", "cozum",
        "sonuc", "cikti", "yorum", "takip", "kaydet"
    ]

    var body: some View {
        VStack(spacing: 0) {
            if let error = errorMessage {
                errorView(error)
            } else if isLoading {
                loadingView
            } else {
                playerWithOverlay
            }
        }
        .task { await buildPreview() }
        .onDisappear { cleanup() }
        .onChange(of: currentTime) { _, newTime in
            // External seek: if time jumps more than 0.5s from last known position, seek the player
            let delta = abs(newTime - lastExternalTime)
            if delta > 0.5, let player {
                let cmTime = CMTime(seconds: newTime, preferredTimescale: 600)
                player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
            }
            lastExternalTime = newTime
        }
    }

    // MARK: - Loading / Error

    private var loadingView: some View {
        VStack(spacing: 12) {
            // Skeleton video area
            SkeletonBlock(height: 180, radius: 8)
                .padding(.horizontal, 12)

            // Skeleton timeline
            SkeletonBlock(height: 6, radius: 3)
                .padding(.horizontal, 20)

            // Skeleton controls
            HStack(spacing: 20) {
                SkeletonBlock(width: 28, height: 28, radius: 14)
                SkeletonBlock(width: 28, height: 28, radius: 14)
                SkeletonBlock(width: 36, height: 36, radius: 18)
                SkeletonBlock(width: 28, height: 28, radius: 14)
                SkeletonBlock(width: 28, height: 28, radius: 14)
            }
        }
        .frame(height: 260)
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
        .frame(height: 260)
    }

    // MARK: - Player + Caption Overlay

    private var playerWithOverlay: some View {
        VStack(spacing: 8) {
            ZStack {
                // Video layer
                CaptionPlayerView(player: player)
                    .background(.black)

                // Live caption overlay (bottom)
                VStack {
                    Spacer()
                    captionOverlay
                }

                // Buffering indicator
                if isBuffering {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.8)
                }

                // Preview badge (top-right)
                VStack {
                    HStack {
                        Spacer()
                        Text("PREVIEW")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white.opacity(0.6))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.1))
                            .clipShape(Capsule())
                            .padding(8)
                    }
                    Spacer()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
            .onTapGesture { togglePlayback() }

            // Timeline scrubber
            if duration > 0 {
                timelineBar
            }

            // Playback controls
            controlsBar
        }
    }

    private var captionOverlay: some View {
        let active = captions.first { caption in
            currentTime >= caption.startTime && currentTime < caption.endTime
        }

        return Group {
            if let caption = active {
                VStack(spacing: 4) {
                    captionView(caption)
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                        .id(caption.id)
                        .onTapGesture {
                            selectedCaptionId = caption.id
                            onEditCaption?(caption)
                        }

                    if selectedCaptionId == caption.id {
                        Text("Tap again to edit")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.15), value: active?.id)
        .padding(.horizontal, 12)
        .padding(.bottom, 16)
    }

    private func captionView(_ caption: CaptionSegment) -> some View {
        let theme = template.captionTheme
        let isHook = caption.role == .hook

        return VStack(spacing: 0) {
            if isHook {
                hookCaptionView(caption, theme: theme)
            } else {
                karaokeCaptionView(caption, theme: theme)
            }
        }
    }

    private func hookCaptionView(_ caption: CaptionSegment, theme: TemplateConfig.CaptionTheme) -> some View {
        Text(caption.text.uppercased())
            .font(.system(size: 18, weight: .black))
            .foregroundStyle(Color(theme.hookTextColor.uiColor))
            .multilineTextAlignment(.center)
            .lineLimit(3)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(theme.hookBgColor.uiColor))
            )
            .shadow(color: .black.opacity(0.5), radius: 4, y: 2)
    }

    private func karaokeCaptionView(_ caption: CaptionSegment, theme: TemplateConfig.CaptionTheme) -> some View {
        let words = caption.text.split(separator: " ").map(String.init)
        let activeIndex = CaptionTextLayout.activeWordIndex(
            displayWords: words,
            timeInCaption: currentTime - caption.startTime,
            captionDuration: caption.endTime - caption.startTime,
            currentTime: currentTime,
            wordTimings: caption.wordTimings
        )

        return HStack(spacing: 4) {
            ForEach(words.indices, id: \.self) { index in
                let word = words[index]
                let isRevealed = index < activeIndex
                let isActive = index == activeIndex
                let isSemanticEmphasis = Self.isSemanticEmphasisWord(word)
                let highlightColor = Color(theme.karaokeHighlight.uiColor)
                let dimColor = Color(theme.karaokeDim.uiColor)

                Text(word)
                    .font(styleFont(caption.style, weight: isSemanticEmphasis && (isRevealed || isActive) ? .black : .bold, size: 16))
                    .foregroundStyle(isActive || (isSemanticEmphasis && isRevealed) ? highlightColor : (isRevealed ? .white : dimColor))
                    .scaleEffect(isActive ? 1.08 : 1.0)
                    .animation(.easeOut(duration: 0.12), value: isActive)
                    .background(
                        isActive ?
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color(theme.wordHighlightBg.uiColor))
                                .padding(.horizontal, -3)
                                .padding(.vertical, -1)
                            : nil
                    )
                    .overlay(
                        (theme.glowEnabled || isSemanticEmphasis) && isActive ?
                            Text(word)
                                .font(styleFont(caption.style, weight: .black, size: 16))
                                .foregroundStyle(highlightColor.opacity(0.4))
                                .blur(radius: 6)
                            : nil
                    )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(styledBackground(caption.style, theme: theme))
        .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
    }

    private static func isSemanticEmphasisWord(_ word: String) -> Bool {
        semanticEmphasisTokens.contains(normalizedEmphasisToken(word))
    }

    private static func normalizedEmphasisToken(_ word: String) -> String {
        word
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "tr_TR"))
            .filter { $0.isLetter || $0.isNumber }
    }

    @ViewBuilder
    private func styledBackground(_ style: CaptionStyle, theme: TemplateConfig.CaptionTheme) -> some View {
        switch style {
        case .neonGlow:
            RoundedRectangle(cornerRadius: 6)
                .fill(.black.opacity(0.7))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(theme.karaokeHighlight.uiColor).opacity(0.4), lineWidth: 1)
                )
        case .glitchBold:
            RoundedRectangle(cornerRadius: 2)
                .fill(.black.opacity(0.65))
        case .minimalWellness:
            RoundedRectangle(cornerRadius: 4)
                .fill(.black.opacity(0.35))
        case .typewriterClean:
            RoundedRectangle(cornerRadius: 0)
                .fill(.black.opacity(0.5))
        case .elegantSerif:
            RoundedRectangle(cornerRadius: 8)
                .fill(.black.opacity(0.4))
        case .retroVHS:
            RoundedRectangle(cornerRadius: 0)
                .fill(.black.opacity(0.7))
        default:
            RoundedRectangle(cornerRadius: 6)
                .fill(.black.opacity(0.55))
        }
    }

    private func styleFont(_ style: CaptionStyle, weight: Font.Weight, size: CGFloat) -> Font {
        switch style {
        case .elegantSerif:
            return .system(size: size, weight: weight, design: .default)
        case .typewriterClean:
            return .system(size: size, weight: weight, design: .monospaced)
        case .glitchBold:
            return .system(size: size * 1.05, weight: .black)
        case .neonGlow:
            return .system(size: size, weight: .bold)
        default:
            return .system(size: size, weight: weight)
        }
    }

    // MARK: - Timeline

    private var timelineBar: some View {
        VStack(spacing: 8) {
            // Caption timeline with segments
            captionTimelineSegments

            // Scrub bar
            GeometryReader { geo in
                let width = geo.size.width
                ZStack(alignment: .leading) {
                    // Track background
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.1))
                        .frame(height: 6)

                    // Playhead fill
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white)
                        .frame(width: max(width * (currentTime / duration), 2), height: 6)

                    // Scrub thumbnail popup
                    if isScrubbing, duration > 0 {
                        let thumbTime = (scrubPosition / width) * duration
                        scrubThumbnailPopup(time: thumbTime)
                            .offset(x: min(max(scrubPosition - 40, 0), width - 80), y: -72)
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isScrubbing = true
                            scrubPosition = min(max(value.location.x, 0), width)
                            let frac = scrubPosition / width
                            let seekTime = frac * duration
                            currentTime = seekTime
                            let time = CMTime(seconds: seekTime, preferredTimescale: 600)
                            player?.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
                        }
                        .onEnded { _ in
                            isScrubbing = false
                        }
                )
            }
            .frame(height: 6)

            HStack {
                Text(formatTime(currentTime))
                Spacer()
                Text(formatTime(duration))
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.gray)
        }
        .padding(.horizontal, 8)
    }

    private var captionTimelineSegments: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .leading) {
                // Background track
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.05))

                // Caption segments with different colors per role
                HStack(spacing: 0) {
                    ForEach(captions) { caption in
                        let startFrac = caption.startTime / duration
                        let endFrac = caption.endTime / duration
                        let segmentWidth = max((endFrac - startFrac) * width, 1)

                        VStack {
                            RoundedRectangle(cornerRadius: 1)
                                .fill(colorForRole(caption.role, theme: template.captionTheme))
                                .frame(width: segmentWidth)
                        }
                        .frame(width: segmentWidth)
                        .onTapGesture {
                            let seekTime = (startFrac + (endFrac - startFrac) / 2) * duration
                            currentTime = seekTime
                            let cmTime = CMTime(seconds: seekTime, preferredTimescale: 600)
                            player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
                        }

                        if caption.id != captions.last?.id {
                            Spacer()
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                .frame(height: 12)

                // Current time indicator
                VStack {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.white)
                        .frame(width: 2, height: 14)
                        .offset(x: (currentTime / duration) * width - 1)
                }
                .frame(height: 12)
            }
        }
        .frame(height: 12)
        .padding(.horizontal, 0)
    }

    private func colorForRole(_ role: CaptionRole, theme: TemplateConfig.CaptionTheme) -> Color {
        let highlight = Color(theme.karaokeHighlight.uiColor)
        let base = Color(theme.defaultTextColor.uiColor)

        switch role {
        case .hook:
            return Color(theme.hookBgColor.uiColor)
        case .warning:
            return Color.red.opacity(0.6)
        case .reveal:
            return highlight.opacity(0.7)
        case .keyword:
            return highlight
        case .transition:
            return Color.white.opacity(0.3)
        case .conclusion:
            return highlight.opacity(0.5)
        case .regular:
            return base.opacity(0.4)
        }
    }

    private func scrubThumbnailPopup(time: Double) -> some View {
        let snappedTime = snapToThumbnailTime(time)
        let thumb = scrubThumbnails[snappedTime]

        return VStack(spacing: 2) {
            Group {
                if let thumb {
                    Image(uiImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Rectangle().fill(Color.white.opacity(0.1))
                }
            }
            .frame(width: 80, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.white.opacity(0.5), lineWidth: 1)
            )

            Text(formatTime(time))
                .font(.caption2.weight(.medium).monospacedDigit())
                .foregroundStyle(.white)
        }
        .shadow(color: .black.opacity(0.6), radius: 4, y: 2)
    }

    /// Snap time to nearest thumbnail interval for cache lookup.
    private func snapToThumbnailTime(_ time: Double) -> Double {
        guard duration > 0 else { return 0 }
        let interval = thumbnailInterval
        return (time / interval).rounded() * interval
    }

    private var thumbnailInterval: Double {
        // ~20 thumbnails across the video, min 0.5s interval
        max(duration / 20.0, 0.5)
    }

    // MARK: - Controls

    private var controlsBar: some View {
        HStack(spacing: 16) {
            // Loop toggle
            Button { loopEnabled.toggle() } label: {
                Image(systemName: loopEnabled ? "repeat.1" : "repeat")
                    .foregroundStyle(loopEnabled ? .white : .white.opacity(0.5))
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("Loop playback")

            // Frame step back
            Button { stepFrame(forward: false) } label: {
                Image(systemName: "chevron.left.2")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("Previous frame")

            // Skip back 2s
            Button {
                let target = max(currentTime - 2, 0)
                currentTime = target
                player?.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
            } label: {
                Image(systemName: "gobackward.2")
                    .foregroundStyle(.white)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("Skip back 2 seconds")

            Button { togglePlayback() } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel(isPlaying ? "Pause" : "Play")

            // Skip forward 2s
            Button {
                let target = min(currentTime + 2, duration)
                currentTime = target
                player?.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
            } label: {
                Image(systemName: "goforward.2")
                    .foregroundStyle(.white)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("Skip forward 2 seconds")

            // Frame step forward
            Button { stepFrame(forward: true) } label: {
                Image(systemName: "chevron.right.2")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("Next frame")
        }
    }

    /// Step exactly one frame forward or backward (1/30s)
    private func stepFrame(forward: Bool) {
        guard let player else { return }
        if isPlaying { player.pause(); isPlaying = false }
        let frameDuration = 1.0 / 30.0
        let target = forward
            ? min(currentTime + frameDuration, duration)
            : max(currentTime - frameDuration, 0)
        currentTime = target
        let cmTime = CMTime(seconds: target, preferredTimescale: 600)
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    // MARK: - Build

    private func buildPreview() async {
        do {
            let timeline = try await CleanTimelineBuilder.build(
                from: videoURL,
                decisions: decisions
            )

            let playerItem = AVPlayerItem(asset: timeline.composition)

            // Apply live color grade preview via CIFilter video composition
            let grade = template.colorGrade
            if Self.needsGrading(grade) {
                playerItem.videoComposition = try await Self.buildGradeComposition(
                    for: timeline.composition, grade: grade
                )
            }

            let avPlayer = AVPlayer(playerItem: playerItem)

            let dur = try await timeline.composition.load(.duration)
            duration = dur.seconds

            let observer = avPlayer.addPeriodicTimeObserver(
                forInterval: CMTime(seconds: 1.0 / 10.0, preferredTimescale: 600),
                queue: .main
            ) { time in
                MainActor.assumeIsolated {
                    let secs = time.seconds
                    currentTime = secs
                    lastExternalTime = secs
                    if secs >= duration - 0.05 {
                        if loopEnabled {
                            avPlayer.seek(to: .zero)
                            avPlayer.play()
                        } else {
                            isPlaying = false
                        }
                    }
                }
            }

            // Buffer monitoring via KVO
            guard let item = avPlayer.currentItem else { return }
            playerStatusObserver = item.observe(\.status, options: [.new]) { item, _ in
                if item.status == .failed {
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated {
                            errorMessage = item.error?.localizedDescription ?? "Playback failed"
                        }
                    }
                }
            }
            bufferObserver = item.observe(\.isPlaybackBufferEmpty, options: [.new]) { item, _ in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        isBuffering = item.isPlaybackBufferEmpty
                    }
                }
            }

            player = avPlayer
            timeObserver = observer
            isLoading = false

            // Generate scrub thumbnails in background
            Task.detached(priority: .utility) {
                let thumbs = await Self.generateScrubThumbnails(
                    asset: timeline.composition,
                    duration: dur.seconds
                )
                await MainActor.run { scrubThumbnails = thumbs }
            }
        } catch {
            #if DEBUG
            print("[CaptionPreviewPlayer] load failed: \(error)")
            #endif
            errorMessage = "Önizleme yüklenemedi."
            isLoading = false
        }
    }

    /// Pre-generate ~20 thumbnails evenly across the composition.
    nonisolated private static func generateScrubThumbnails(
        asset: AVAsset,
        duration: Double
    ) async -> [Double: UIImage] {
        let interval = max(duration / 20.0, 0.5)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 160, height: 120)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)

        var times: [NSValue] = []
        var time: Double = 0
        while time <= duration {
            times.append(NSValue(time: CMTime(seconds: time, preferredTimescale: 600)))
            time += interval
        }

        var thumbnails: [Double: UIImage] = [:]
        // Use batch API (callback-based, no Sendable issue)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            var remaining = times.count
            guard remaining > 0 else {
                continuation.resume()
                return
            }
            generator.generateCGImagesAsynchronously(forTimes: times) { requestedTime, cgImage, _, _, _ in
                Task { @MainActor in
                    if let cgImage {
                        let snapped = (requestedTime.seconds / interval).rounded() * interval
                        thumbnails[snapped] = UIImage(cgImage: cgImage)
                    }
                    remaining -= 1
                    if remaining == 0 {
                        continuation.resume()
                    }
                }
            }
        }
        return thumbnails
    }

    // MARK: - Live Color Grade

    private static func needsGrading(_ grade: TemplateConfig.ColorGrade) -> Bool {
        let ht = grade.highlightsTint
        let st = grade.shadowsTint
        return grade.saturation != 1.0 || grade.brightness != 0.0 ||
               grade.contrast != 1.0 || abs(grade.warmth) > 0.01 ||
               grade.vignetteIntensity > 0.01 || grade.fade > 0.01 ||
               grade.sharpen > 0.01 ||
               abs(ht.r) > 0.005 || abs(ht.g) > 0.005 || abs(ht.b) > 0.005 ||
               abs(st.r) > 0.005 || abs(st.g) > 0.005 || abs(st.b) > 0.005
    }

    nonisolated private static func buildGradeComposition(
        for asset: AVAsset,
        grade: TemplateConfig.ColorGrade
    ) async throws -> AVVideoComposition {
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = tracks.first else {
            throw NSError(domain: "CaptionPreviewPlayer", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "No video track"])
        }
        let size = try await videoTrack.load(.naturalSize)
        let transform = try await videoTrack.load(.preferredTransform)
        let isPortrait = transform.a == 0 && transform.d == 0
        let renderSize = isPortrait ? CGSize(width: size.height, height: size.width) : size

        let duration = try await asset.load(.duration)
        let instruction = PreviewGradeInstruction(
            timeRange: CMTimeRange(start: .zero, duration: duration),
            grade: grade,
            sourceTrackID: videoTrack.trackID
        )

        let configuration = AVVideoComposition.Configuration(
            customVideoCompositorClass: PreviewGradeCompositor.self,
            frameDuration: CMTime(value: 1, timescale: 30),
            instructions: [instruction],
            renderSize: renderSize
        )
        return AVVideoComposition(configuration: configuration)
    }

    private func togglePlayback() {
        guard let player else { return }
        if isPlaying {
            player.pause()
        } else {
            if currentTime >= duration - 0.2 {
                player.seek(to: .zero)
                currentTime = 0
            }
            player.play()
        }
        isPlaying.toggle()
    }

    private func cleanup() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        playerStatusObserver?.invalidate()
        playerStatusObserver = nil
        bufferObserver?.invalidate()
        bufferObserver = nil
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

private struct CaptionPlayerView: UIViewRepresentable {
    let player: AVPlayer?

    func makeUIView(context: Context) -> CaptionPlayerUIView {
        let view = CaptionPlayerUIView()
        view.player = player
        return view
    }

    func updateUIView(_ uiView: CaptionPlayerUIView, context: Context) {
        uiView.player = player
    }
}

class CaptionPlayerUIView: UIView {
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

// MARK: - Preview Grade Compositor (lightweight, color grade only)

private final class PreviewGradeInstruction: NSObject, AVVideoCompositionInstructionProtocol, @unchecked Sendable {
    let timeRange: CMTimeRange
    let enablePostProcessing: Bool = false
    let containsTweening: Bool = false
    let requiredSourceTrackIDs: [NSValue]?
    let passthroughTrackID: CMPersistentTrackID = kCMPersistentTrackID_Invalid

    let grade: TemplateConfig.ColorGrade

    init(timeRange: CMTimeRange, grade: TemplateConfig.ColorGrade, sourceTrackID: CMPersistentTrackID) {
        self.timeRange = timeRange
        self.grade = grade
        self.requiredSourceTrackIDs = [NSNumber(value: sourceTrackID)]
        super.init()
    }
}

private final class PreviewGradeCompositor: NSObject, AVVideoCompositing, @unchecked Sendable {
    var sourcePixelBufferAttributes: [String: any Sendable]? {
        [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
    }

    var requiredPixelBufferAttributesForRenderContext: [String: any Sendable] {
        [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
    }

    private var renderContext: AVVideoCompositionRenderContext?
    private let ciContext = FilterEngine.sharedCIContext

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {
        renderContext = newRenderContext
    }

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        guard let instruction = request.videoCompositionInstruction as? PreviewGradeInstruction else {
            request.finish(with: NSError(domain: "PreviewGrade", code: -1))
            return
        }

        let trackID: CMPersistentTrackID
        if let ids = instruction.requiredSourceTrackIDs,
           let first = ids.first as? NSNumber {
            trackID = first.int32Value
        } else {
            trackID = request.sourceTrackIDs.first?.int32Value ?? 1
        }

        guard let sourceBuffer = request.sourceFrame(byTrackID: trackID) else {
            request.finish(with: NSError(domain: "PreviewGrade", code: -2))
            return
        }

        guard let outputBuffer = renderContext?.newPixelBuffer() else {
            request.finish(withComposedVideoFrame: sourceBuffer)
            return
        }

        let sourceImage = CIImage(cvPixelBuffer: sourceBuffer)
        let graded = FilterEngine.applyGrade(instruction.grade, to: sourceImage)
        ciContext.render(graded, to: outputBuffer)
        request.finish(withComposedVideoFrame: outputBuffer)
    }
}
