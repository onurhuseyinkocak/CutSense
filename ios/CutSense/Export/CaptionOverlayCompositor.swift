import AVFoundation
import CoreImage
import UIKit

enum CaptionTextLayout {
    static func words(in text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    static func wordRanges(in text: String) -> [NSRange] {
        var ranges: [NSRange] = []
        var cursor = text.startIndex

        while cursor < text.endIndex {
            while cursor < text.endIndex, text[cursor].isWhitespace {
                cursor = text.index(after: cursor)
            }
            guard cursor < text.endIndex else { break }

            let wordStart = cursor
            while cursor < text.endIndex, !text[cursor].isWhitespace {
                cursor = text.index(after: cursor)
            }
            ranges.append(NSRange(wordStart..<cursor, in: text))
        }

        return ranges
    }

    static func canUseWordTimings(
        displayWords: [String],
        wordTimings: [(word: String, start: Double, duration: Double)]
    ) -> Bool {
        guard !displayWords.isEmpty, displayWords.count == wordTimings.count else { return false }
        return zip(displayWords, wordTimings).allSatisfy { displayWord, timing in
            normalizedToken(displayWord) == normalizedToken(timing.word)
        }
    }

    static func activeWordIndex(
        displayWords: [String],
        timeInCaption: Double,
        captionDuration: Double,
        currentTime: Double,
        wordTimings: [(word: String, start: Double, duration: Double)]
    ) -> Int {
        let wordCount = displayWords.count
        guard wordCount > 0 else { return 0 }

        if canUseWordTimings(displayWords: displayWords, wordTimings: wordTimings) {
            return wordTimings.firstIndex { timing in
                currentTime >= timing.start && currentTime < timing.start + timing.duration
            } ?? uniformActiveWordIndex(timeInCaption: timeInCaption, captionDuration: captionDuration, wordCount: wordCount)
        }

        return uniformActiveWordIndex(timeInCaption: timeInCaption, captionDuration: captionDuration, wordCount: wordCount)
    }

    private static func uniformActiveWordIndex(
        timeInCaption: Double,
        captionDuration: Double,
        wordCount: Int
    ) -> Int {
        let wordDuration = max(0.001, captionDuration / Double(max(wordCount, 1)))
        return min(Int(max(0, timeInCaption) / wordDuration), max(wordCount - 1, 0))
    }

    private static func normalizedToken(_ word: String) -> String {
        word
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }
}

enum CaptionLayoutTuning {
    static func baseYRatio(for caption: CaptionSegment) -> Double {
        let baseRatio: Double = switch caption.style {
        case .premiumLowerThird:
            0.72
        case .hookImpact, .boldCenterViral, .glitchBold:
            0.64
        case .focusStatement, .neonGlow:
            0.68
        case .minimalWellness, .elegantSerif, .typewriterClean, .retroVHS:
            0.72
        }

        let variant = max(0, Int((caption.startTime / 2.7).rounded(.down))) % 4
        let offsetRatio: Double = switch caption.role {
        case .hook:
            [0.00, 0.025, -0.015, 0.035][variant]
        case .reveal, .warning, .keyword:
            [-0.015, 0.025, 0.045, 0.00][variant]
        case .transition, .regular:
            [0.025, 0.055, -0.005, 0.040][variant]
        case .conclusion:
            [0.055, 0.025, 0.070, 0.040][variant]
        }

        return min(max(baseRatio + offsetRatio, 0.60), 0.77)
    }

    static func verticalBandKey(for caption: CaptionSegment) -> Int {
        Int((baseYRatio(for: caption) * 100).rounded())
    }
}

enum VisualEffectTuning {
    static func zoomPeakScale(for effect: EditDecision) -> Double {
        guard effect.type == .zoom else { return 1.0 }
        return 1.0 + Double(max(0, effect.intensity)) * zoomAmplitude(for: effect)
    }

    static func zoomAmplitude(for effect: EditDecision) -> Double {
        let reason = effect.reason.lowercased()
        if reason.contains("push-back") {
            return 0.20
        }
        if reason.contains("hook slow push-in") || reason.contains("hook sentence back") {
            return 0.22
        }
        if reason.contains("slow push") {
            return 0.22
        }
        if reason.contains("ui focus") {
            return 0.30
        }
        if reason.contains("reveal") {
            return 0.34
        }
        if reason.contains("controlled") || reason.contains("keyword") {
            return 0.18
        }
        if reason.contains("hook") || reason.contains("push-pull") {
            return 0.24
        }
        if reason.contains("punch") || reason.contains("impact") || reason.contains("snap") {
            return 0.24
        }
        if reason.contains("transition") || reason.contains("whip") {
            return 0.20
        }
        if reason.contains("conclusion") || reason.contains("slow") {
            return 0.18
        }
        return 0.12
    }
}

final class CaptionOverlayCompositor: NSObject, AVVideoCompositing, @unchecked Sendable {
    var sourcePixelBufferAttributes: [String: any Sendable]? {
        [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
    }

    var requiredPixelBufferAttributesForRenderContext: [String: any Sendable] {
        [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
    }

    var supportsHDRSourceFrames: Bool { false }

    private var renderContext: AVVideoCompositionRenderContext?
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private var frameCount = 0
    private var captionHitCount = 0
    private var effectHitCount = 0
    private static let semanticEmphasisTokens: Set<String> = [
        "ai", "free", "faster", "mistake", "launch", "automated", "tool", "problem",
        "fix", "money", "users", "mvp", "app", "build", "built", "result", "results",
        "generate", "generated", "click", "tap", "code", "coding", "vibe", "startup",
        "urun", "uygulama", "ucretsiz", "hizli", "hata", "yanlis", "sorun", "cozum",
        "sonuc", "cikti", "yorum", "takip", "kaydet"
    ]

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {
        renderContext = newRenderContext
        #if DEBUG
        print("[Compositor] renderContextChanged — size: \(newRenderContext.size)")
        #endif
    }

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        guard let instruction = request.videoCompositionInstruction as? CaptionCompositionInstruction else {
            #if DEBUG
            print("[Compositor] ERROR: instruction cast failed")
            #endif
            request.finish(with: NSError(domain: "CaptionOverlay", code: -1))
            return
        }

        // Try all source track IDs, not just the first
        let trackID: CMPersistentTrackID
        if let ids = instruction.requiredSourceTrackIDs,
           let first = ids.first as? NSNumber {
            trackID = first.int32Value
        } else {
            // Fallback: try all available source tracks
            let availableIDs = request.sourceTrackIDs
            trackID = availableIDs.first?.int32Value ?? 1
        }

        guard let sourceBuffer = request.sourceFrame(byTrackID: trackID) else {
            #if DEBUG
            print("[Compositor] ERROR: no source frame for trackID \(trackID), available=\(request.sourceTrackIDs)")
            #endif
            request.finish(with: NSError(domain: "CaptionOverlay", code: -2))
            return
        }

        let currentTime = request.compositionTime.seconds
        let grade = instruction.colorGrade

        // Find active caption
        let activeCaption = instruction.captions.first { caption in
            currentTime >= caption.startTime && currentTime < caption.endTime
        }

        // Find active edit decisions (non-SFX visual effects)
        let activeEffects = instruction.editDecisions.filter { decision in
            decision.type != .sfx &&
            currentTime >= decision.time &&
            currentTime < decision.time + decision.duration
        }

        let hasGrade = grade.saturation != 1.0 || grade.brightness != 0.0 ||
                       grade.contrast != 1.0 || abs(grade.warmth) > 0.01 ||
                       grade.vignetteIntensity > 0.01
        let needsOverlayPass = activeCaption != nil || !activeEffects.isEmpty || instruction.showWatermark

        #if DEBUG
        frameCount += 1
        if activeCaption != nil { captionHitCount += 1 }
        if !activeEffects.isEmpty { effectHitCount += 1 }
        if frameCount == 1 || frameCount % 120 == 0 {
            print("[Compositor] frame=\(frameCount) t=\(String(format: "%.2f", currentTime))s captions=\(instruction.captions.count) captionHits=\(captionHitCount) effectHits=\(effectHitCount) hasGrade=\(hasGrade)")
        }
        #endif

        // Get output buffer from AVFoundation's managed pool
        guard let outputBuffer = request.renderContext.newPixelBuffer() else {
            #if DEBUG
            print("[Compositor] ERROR: newPixelBuffer() nil at frame \(frameCount)")
            #endif
            request.finish(with: NSError(domain: "CaptionOverlay", code: -3, userInfo: [
                NSLocalizedDescriptionKey: "Could not allocate export render buffer."
            ]))
            return
        }

        let outputSize = CGSize(
            width: CVPixelBufferGetWidth(outputBuffer),
            height: CVPixelBufferGetHeight(outputBuffer)
        )
        let outputRect = CGRect(origin: .zero, size: outputSize)
        let orientedSource = VideoFrameRenderer.orientedAspectFillImage(
            from: sourceBuffer,
            sourceTransform: instruction.sourceTransform,
            renderSize: outputSize
        )
        let renderedFrame = hasGrade
            ? FilterEngine.applyGrade(grade, to: orientedSource)
            : orientedSource
        let compositedFrame = VideoFrameRenderer.compositedOverBlack(renderedFrame, renderSize: outputSize)
        ciContext.render(
            compositedFrame,
            to: outputBuffer,
            bounds: outputRect,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )

        if needsOverlayPass {
            drawOverlay(
                on: outputBuffer,
                caption: activeCaption,
                effects: activeEffects,
                currentTime: currentTime,
                renderSize: outputSize,
                captionTheme: instruction.captionTheme,
                sourceIsAlreadyDrawn: true,
                showWatermark: instruction.showWatermark
            )
        }

        request.finish(withComposedVideoFrame: outputBuffer)
    }

    func cancelAllPendingVideoCompositionRequests() {}

    // MARK: - Overlay Drawing

    private func drawOverlay(
        on outputBuffer: CVPixelBuffer,
        caption: CaptionSegment?,
        effects: [EditDecision],
        currentTime: Double,
        renderSize: CGSize,
        captionTheme: TemplateConfig.CaptionTheme = .premiumGold,
        sourceIsAlreadyDrawn: Bool,
        sourceBuffer: CVPixelBuffer? = nil,
        showWatermark: Bool = false
    ) {
        let width = CVPixelBufferGetWidth(outputBuffer)
        let height = CVPixelBufferGetHeight(outputBuffer)
        let frameRect = CGRect(x: 0, y: 0, width: width, height: height)

        CVPixelBufferLockBaseAddress(outputBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(outputBuffer, []) }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue

        guard let outputBase = CVPixelBufferGetBaseAddress(outputBuffer),
              let context = CGContext(
                  data: outputBase,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: CVPixelBufferGetBytesPerRow(outputBuffer),
                  space: colorSpace,
                  bitmapInfo: bitmapInfo
              ) else { return }

        // If source not yet drawn (no grade applied), copy source frame first
        if !sourceIsAlreadyDrawn, let sourceBuffer {
            CVPixelBufferLockBaseAddress(sourceBuffer, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(sourceBuffer, .readOnly) }

            guard let srcBase = CVPixelBufferGetBaseAddress(sourceBuffer),
                  let srcCtx = CGContext(
                      data: srcBase,
                      width: CVPixelBufferGetWidth(sourceBuffer),
                      height: CVPixelBufferGetHeight(sourceBuffer),
                      bitsPerComponent: 8,
                      bytesPerRow: CVPixelBufferGetBytesPerRow(sourceBuffer),
                      space: colorSpace,
                      bitmapInfo: bitmapInfo
                  ),
                  let srcImage = srcCtx.makeImage()
            else { return }

            context.saveGState()
            applyVisualEffects(effects, context: context, width: width, height: height, currentTime: currentTime)
            context.draw(srcImage, in: frameRect)
            context.restoreGState()
        } else if sourceIsAlreadyDrawn && !effects.isEmpty {
            // Buffer already has graded frame. Re-draw with effects.
            if let existingImage = context.makeImage() {
                context.clear(frameRect)
                context.saveGState()
                applyVisualEffects(effects, context: context, width: width, height: height, currentTime: currentTime)
                context.draw(existingImage, in: frameRect)
                context.restoreGState()
            }
        }

        // Flash effect: white overlay
        drawFlashEffect(effects, context: context, frameRect: frameRect, currentTime: currentTime)

        // Color shift effect: warm tint overlay
        drawColorShiftEffect(effects, context: context, frameRect: frameRect, currentTime: currentTime)

        // Cut transition effect: brief black dip + zoom punch
        drawCutTransitionEffect(effects, context: context, frameRect: frameRect, currentTime: currentTime)

        // Draw caption on top — uses flipped context for correct UIKit text rendering
        if let caption {
            drawCaption(caption, in: context, width: CGFloat(width), height: CGFloat(height), currentTime: currentTime, theme: captionTheme)
        }

        // Draw watermark for free tier
        if showWatermark {
            drawWatermark(in: context, width: CGFloat(width), height: CGFloat(height))
        }
    }

    // MARK: - Watermark

    private func drawWatermark(in context: CGContext, width: CGFloat, height: CGFloat) {
        context.saveGState()
        // Flip for UIKit text drawing
        context.translateBy(x: 0, y: height)
        context.scaleBy(x: 1, y: -1)

        UIGraphicsPushContext(context)

        let text = "Made with CutSense" as NSString
        let fontSize = max(width * 0.028, 14)
        let padding = width * 0.03
        let font = UIFont.systemFont(ofSize: fontSize, weight: .semibold)

        let shadowAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.black.withAlphaComponent(0.5)
        ]
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.white.withAlphaComponent(0.7)
        ]

        let textSize = text.size(withAttributes: attrs)
        let x = width - textSize.width - padding
        let y = height - textSize.height - padding

        // Shadow
        text.draw(at: CGPoint(x: x + 1, y: y + 1), withAttributes: shadowAttrs)
        // Text
        text.draw(at: CGPoint(x: x, y: y), withAttributes: attrs)

        UIGraphicsPopContext()
        context.restoreGState()
    }

    // MARK: - Visual Effects

    private func applyVisualEffects(_ effects: [EditDecision], context: CGContext, width: Int, height: Int, currentTime: Double) {
        // Zoom effect: visible creator-style punch without losing framing.
        if let zoom = effects
            .filter({ $0.type == .zoom })
            .max(by: { $0.intensity < $1.intensity }) {
            let progress = effectProgress(zoom, at: currentTime)
            let curve = zoomCurve(for: zoom, progress: progress)
            let scale = 1.0 + CGFloat(zoom.intensity) * CGFloat(VisualEffectTuning.zoomAmplitude(for: zoom)) * curve
            let cx = CGFloat(width) / 2
            let cy = CGFloat(height) / 2
            context.translateBy(x: cx, y: cy)
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: -cx, y: -cy)
        }

        // Cut transitions get actual camera motion, not just a black dip.
        if let cut = effects.first(where: { $0.type == .cutTransition }) {
            let progress = effectProgress(cut, at: currentTime)
            let curve = sin(progress * .pi)
            let scale = 1.0 + CGFloat(cut.intensity) * 0.11 * curve
            let pan = CGFloat(cut.intensity) * 30 * (0.5 - progress)
            let cx = CGFloat(width) / 2
            let cy = CGFloat(height) / 2
            context.translateBy(x: cx + pan, y: cy)
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: -cx, y: -cy)
        }

        // Shake effect: short motion accent for impact moments.
        if let shake = effects.first(where: { $0.type == .shake }) {
            let progress = effectProgress(shake, at: currentTime)
            let envelope = max(0, 1 - progress)
            let magnitude = CGFloat(shake.intensity) * 8.0 * envelope
            let phase = progress * .pi * 8
            let dx = sin(phase) * magnitude
            let dy = cos(phase * 1.3) * magnitude
            context.translateBy(x: dx, y: dy)
        }
    }

    private func drawFlashEffect(_ effects: [EditDecision], context: CGContext, frameRect: CGRect, currentTime: Double) {
        guard let flash = effects.first(where: { $0.type == .flash }) else { return }
        let progress = effectProgress(flash, at: currentTime)
        let envelope: CGFloat
        if progress < 0.28 {
            envelope = smoothstep(progress / 0.28)
        } else {
            envelope = max(0, 1 - smoothstep((progress - 0.28) / 0.72))
        }
        let alpha = min(0.22, CGFloat(flash.intensity) * 0.32 * envelope)
        if alpha > 0.01 {
            context.saveGState()
            context.setBlendMode(.screen)
            context.setFillColor(UIColor(red: 1.0, green: 0.88, blue: 0.58, alpha: alpha).cgColor)
            context.fill(frameRect)
            context.restoreGState()
        }
    }

    private func drawColorShiftEffect(_ effects: [EditDecision], context: CGContext, frameRect: CGRect, currentTime: Double) {
        guard let color = effects.first(where: { $0.type == .colorShift }) else { return }
        let progress = effectProgress(color, at: currentTime)
        let eased = smoothstep(progress)
        let reason = color.reason.lowercased()
        let alpha = CGFloat(color.intensity) * (reason.contains("ui") ? 0.26 : 0.2) * eased
        if alpha > 0.01 {
            let accent = if reason.contains("warning") {
                UIColor(red: 1.0, green: 0.42, blue: 0.18, alpha: alpha)
            } else if reason.contains("ui") {
                UIColor(red: 0.26, green: 0.82, blue: 1.0, alpha: alpha)
            } else {
                UIColor(red: 1.0, green: 0.85, blue: 0.5, alpha: alpha)
            }
            context.setFillColor(accent.cgColor)
            context.setBlendMode(.overlay)
            context.fill(frameRect)
            context.setBlendMode(.normal)
        }
    }

    private func drawCutTransitionEffect(_ effects: [EditDecision], context: CGContext, frameRect: CGRect, currentTime: Double) {
        guard let cut = effects.first(where: { $0.type == .cutTransition }) else { return }
        let progress = effectProgress(cut, at: currentTime)
        // V-shaped opacity: peaks at midpoint then fades out (brief black dip)
        let midAlpha = CGFloat(cut.intensity) * 0.34
        let alpha: CGFloat
        if progress < 0.5 {
            alpha = midAlpha * (progress * 2.0)
        } else {
            alpha = midAlpha * ((1.0 - progress) * 2.0)
        }
        if alpha > 0.01 {
            context.setFillColor(UIColor.black.withAlphaComponent(alpha).cgColor)
            context.fill(frameRect)
        }
    }

    // MARK: - Effect Helpers

    private func effectProgress(_ effect: EditDecision, at time: Double) -> CGFloat {
        let elapsed = time - effect.time
        return CGFloat(min(max(elapsed / effect.duration, 0), 1))
    }

    private func smoothstep(_ t: CGFloat) -> CGFloat {
        let clamped = min(max(t, 0), 1)
        return clamped * clamped * (3 - 2 * clamped)
    }

    private func captionMetricScale(width: CGFloat, height: CGFloat) -> CGFloat {
        min(1.0, max(0.72, min(width / 1080, height / 1920)))
    }

    private func zoomCurve(for effect: EditDecision, progress: CGFloat) -> CGFloat {
        let reason = effect.reason.lowercased()
        if reason.contains("push-back") {
            return max(0, sin(progress * .pi))
        }
        if reason.contains("hook slow push-in") {
            return smoothstep(progress)
        }
        if reason.contains("hook sentence back") {
            return max(0, 1 - smoothstep(progress))
        }
        if reason.contains("slow push") {
            return smoothstep(progress)
        }
        if reason.contains("controlled") || reason.contains("ui focus") {
            return max(0, sin(progress * .pi))
        }
        if reason.contains("reveal") {
            if progress < 0.34 {
                return easeOutCubic(progress / 0.34)
            }
            return max(0, 1 - smoothstep((progress - 0.34) / 0.66))
        }
        if reason.contains("hook") || reason.contains("push-pull") || reason.contains("transition") || reason.contains("whip") {
            return max(0, sin(progress * .pi))
        }
        if reason.contains("punch") || reason.contains("impact") || reason.contains("snap") {
            if progress < 0.22 {
                return smoothstep(progress / 0.22)
            }
            return max(0, 1 - smoothstep((progress - 0.22) / 0.78))
        }
        if reason.contains("conclusion") || reason.contains("slow") {
            return smoothstep(progress)
        }
        return smoothstep(progress)
    }

    private func easeOutCubic(_ t: CGFloat) -> CGFloat {
        let clamped = min(max(t, 0), 1)
        let inverse = 1 - clamped
        return 1 - inverse * inverse * inverse
    }

    private func clampedCaptionY(
        _ desiredY: CGFloat,
        textHeight: CGFloat,
        canvasHeight: CGFloat
    ) -> CGFloat {
        let topLimit = max(CaptionSafeArea.topInset, canvasHeight * 0.58)
        let bottomLimit = max(topLimit, canvasHeight - CaptionSafeArea.bottomInset - textHeight)
        return min(max(desiredY, topLimit), bottomLimit)
    }

    private func captionBaseYPosition(for caption: CaptionSegment, canvasHeight height: CGFloat) -> CGFloat {
        height * CGFloat(CaptionLayoutTuning.baseYRatio(for: caption))
    }

    // MARK: - Caption Drawing

    private func drawCaption(_ caption: CaptionSegment, in context: CGContext, width: CGFloat, height: CGFloat, currentTime: Double = 0, theme: TemplateConfig.CaptionTheme = .premiumGold) {
        let config = styleConfig(for: caption.style, theme: theme)

        // Caption entrance animation: fade-in + slight scale-up over 0.2s
        let entranceDuration: Double = 0.2
        let elapsed = currentTime - caption.startTime
        let entranceProgress = min(max(elapsed / entranceDuration, 0), 1)
        let easedEntrance = CGFloat(entranceProgress * entranceProgress * (3 - 2 * entranceProgress)) // smoothstep

        // Skip drawing if fully transparent
        guard easedEntrance > 0.01 else { return }

        // Flip context for UIKit text drawing (y=0 at top, y increases downward)
        context.saveGState()
        context.translateBy(x: 0, y: height)
        context.scaleBy(x: 1, y: -1)

        // Apply entrance scale (1.08 → 1.0) from center
        if easedEntrance < 1.0 {
            let entranceScale = 1.0 + (1.0 - easedEntrance) * 0.08
            context.translateBy(x: width / 2, y: height / 2)
            context.scaleBy(x: entranceScale, y: entranceScale)
            context.translateBy(x: -width / 2, y: -height / 2)
        }

        // Apply entrance opacity
        context.setAlpha(easedEntrance)

        let metricScale = captionMetricScale(width: width, height: height)
        let maxWidth = width * CaptionSafeArea.maxWidthRatio
        let horizontalInset = (width - maxWidth) / 2

        // Positions in UIKit coordinates (y=0 at top). Talking-head content usually keeps
        // the face in the upper/middle region, so captions vary only inside the lower safe band.
        let baseYPosition = captionBaseYPosition(for: caption, canvasHeight: height)

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = config.alignment
        paragraphStyle.lineSpacing = max(2, 4 * metricScale)

        let font = UIFont.systemFont(ofSize: max(28, config.fontSize * metricScale), weight: config.fontWeight)

        let text = caption.text as NSString
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: config.textColor,
            .paragraphStyle: paragraphStyle
        ]

        let textSize = text.boundingRect(
            with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: textAttributes,
            context: nil
        )
        let yPosition = clampedCaptionY(
            baseYPosition,
            textHeight: textSize.height,
            canvasHeight: height
        )

        let textRect = CGRect(
            x: horizontalInset,
            y: yPosition,
            width: maxWidth,
            height: height * 0.2
        )

        if config.hasBackground {
            let bgPadH: CGFloat = 20 * metricScale
            let bgPadV: CGFloat = 12 * metricScale
            let bgRect: CGRect
            if config.alignment == .center {
                // Center the background behind text
                let bgWidth = min(textSize.width + bgPadH * 2, maxWidth + bgPadH * 2)
                let bgX = (width - bgWidth) / 2
                bgRect = CGRect(
                    x: bgX,
                    y: yPosition - bgPadV,
                    width: bgWidth,
                    height: textSize.height + bgPadV * 2
                )
            } else {
                bgRect = CGRect(
                    x: horizontalInset - bgPadH,
                    y: yPosition - bgPadV,
                    width: textSize.width + bgPadH * 2,
                    height: textSize.height + bgPadV * 2
                )
            }

            // Draw rounded background — use UIKit drawing for correct flipped coordinates
            UIGraphicsPushContext(context)
            let bgPath = UIBezierPath(roundedRect: bgRect, cornerRadius: max(2, config.cornerRadius * metricScale))
            config.backgroundColor.setFill()
            bgPath.fill()
            UIGraphicsPopContext()
        }

        // Draw text with word-by-word karaoke reveal
        UIGraphicsPushContext(context)

        let words = caption.text.split(whereSeparator: \.isWhitespace).map(String.init)
        let captionDuration = caption.endTime - caption.startTime
        let timeInCaption = currentTime - caption.startTime

        if words.count > 1 && captionDuration > 0.3 {
            // Karaoke mode: highlight words progressively
            drawKaraokeText(
                displayText: caption.text,
                words: words,
                font: font,
                config: config,
                paragraphStyle: paragraphStyle,
                textRect: textRect,
                timeInCaption: timeInCaption,
                captionDuration: captionDuration,
                maxWidth: maxWidth,
                theme: theme,
                context: context,
                currentTime: currentTime,
                wordTimings: caption.wordTimings
            )
        } else {
            // Single word or very short caption — draw normally with shadow
            let shadowAttributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: theme.shadowColor.uiColor,
                .paragraphStyle: paragraphStyle
            ]
            let shadowOffset: CGFloat = 2
            let shadowRect = textRect.offsetBy(dx: shadowOffset, dy: shadowOffset)
            text.draw(in: shadowRect, withAttributes: shadowAttributes)
            text.draw(in: textRect, withAttributes: textAttributes)
        }

        UIGraphicsPopContext()

        context.restoreGState()
    }

    // MARK: - Karaoke Word-by-Word Reveal

    private func drawKaraokeText(
        displayText: String,
        words: [String],
        font: UIFont,
        config: StyleConfig,
        paragraphStyle: NSMutableParagraphStyle,
        textRect: CGRect,
        timeInCaption: Double,
        captionDuration: Double,
        maxWidth: CGFloat,
        theme: TemplateConfig.CaptionTheme,
        context: CGContext,
        currentTime: Double,
        wordTimings: [(word: String, start: Double, duration: Double)] = []
    ) {
        let wordCount = words.count
        let wordRanges = CaptionTextLayout.wordRanges(in: displayText)
        guard wordRanges.count == wordCount else { return }

        // Determine active word based on actual word timings if available, otherwise uniform division.
        // wordTimings.start values use absolute source/clean timeline coordinates.
        let activeWordIndex = CaptionTextLayout.activeWordIndex(
            displayWords: words,
            timeInCaption: timeInCaption,
            captionDuration: captionDuration,
            currentTime: currentTime,
            wordTimings: wordTimings
        )

        // Theme-driven colors
        let highlightColor = theme.karaokeHighlight.uiColor
        let dimColor = theme.karaokeDim.uiColor
        let activeColor = config.textColor
        let emphasisFont = UIFont.systemFont(ofSize: font.pointSize, weight: .heavy)

        // Build attributed string with per-word coloring
        let fullText = displayText
        let attributed = NSMutableAttributedString(string: fullText, attributes: [
            .font: font,
            .paragraphStyle: paragraphStyle
        ])

        for (i, range) in wordRanges.enumerated() {
            let isSemanticEmphasis = Self.isSemanticEmphasisWord(words[i])
            if i < activeWordIndex {
                // Already revealed — full color
                attributed.addAttribute(.foregroundColor, value: isSemanticEmphasis ? highlightColor : activeColor, range: range)
            } else if i == activeWordIndex {
                // Currently active — highlight color
                attributed.addAttribute(.foregroundColor, value: highlightColor, range: range)
            } else {
                // Not yet revealed — dimmed
                attributed.addAttribute(.foregroundColor, value: dimColor, range: range)
            }
            if isSemanticEmphasis && i <= activeWordIndex {
                attributed.addAttribute(.font, value: emphasisFont, range: range)
                attributed.addAttribute(.strokeColor, value: theme.shadowColor.uiColor, range: range)
                attributed.addAttribute(.strokeWidth, value: -1.8, range: range)
            }
        }

        // Draw active-word background before text so it does not cover glyphs.
        if activeWordIndex < wordCount {
            drawWordHighlight(
                words: words,
                activeIndex: activeWordIndex,
                font: font,
                config: config,
                textRect: textRect,
                maxWidth: maxWidth,
                theme: theme,
                context: context
            )
        }

        // Shadow pass
        let shadowAttributed = NSMutableAttributedString(string: fullText, attributes: [
            .font: font,
            .paragraphStyle: paragraphStyle,
            .foregroundColor: UIColor.clear
        ])
        for index in 0...min(activeWordIndex, wordRanges.count - 1) {
            shadowAttributed.addAttribute(.foregroundColor, value: theme.shadowColor.uiColor, range: wordRanges[index])
        }
        let shadowOffset: CGFloat = 2
        let shadowRect = textRect.offsetBy(dx: shadowOffset, dy: shadowOffset)
        shadowAttributed.draw(in: shadowRect)

        // Main text pass
        attributed.draw(in: textRect)

        // Semantic keywords get a restrained glow even in cleaner tech templates.
        if activeWordIndex < wordCount,
           theme.glowEnabled || Self.isSemanticEmphasisWord(words[activeWordIndex]) {
            drawNeonGlow(
                words: words,
                activeIndex: activeWordIndex,
                font: font,
                config: config,
                textRect: textRect,
                maxWidth: maxWidth,
                highlightColor: highlightColor,
                context: context
            )
        }
    }

    private func drawWordHighlight(
        words: [String],
        activeIndex: Int,
        font: UIFont,
        config: StyleConfig,
        textRect: CGRect,
        maxWidth: CGFloat,
        theme: TemplateConfig.CaptionTheme,
        context: CGContext
    ) {
        // Only draw highlight for single-line captions to avoid position miscalculation
        let fullText = words.joined(separator: " ")
        let singleLineSize = (fullText as NSString).size(withAttributes: [.font: font])

        // If text wraps to multiple lines, skip the highlight box (karaoke colors still work)
        guard singleLineSize.width <= maxWidth else { return }

        let prefix = words[0..<activeIndex].joined(separator: " ")
        let prefixWithSpace = prefix.isEmpty ? "" : prefix + " "
        let activeWord = words[activeIndex]

        let prefixSize = (prefixWithSpace as NSString).size(withAttributes: [.font: font])
        let wordSize = (activeWord as NSString).size(withAttributes: [.font: font])

        let padH: CGFloat = 6
        let padV: CGFloat = 4

        var highlightX: CGFloat
        if config.alignment == .center {
            let textStartX = textRect.midX - singleLineSize.width / 2
            highlightX = textStartX + prefixSize.width - padH
        } else {
            highlightX = textRect.origin.x + prefixSize.width - padH
        }

        let highlightRect = CGRect(
            x: highlightX,
            y: textRect.origin.y - padV,
            width: wordSize.width + padH * 2,
            height: wordSize.height + padV * 2
        )

        let bgPath = UIBezierPath(roundedRect: highlightRect, cornerRadius: 4)
        theme.wordHighlightBg.uiColor.setFill()
        bgPath.fill()
    }

    private func drawNeonGlow(
        words: [String],
        activeIndex: Int,
        font: UIFont,
        config: StyleConfig,
        textRect: CGRect,
        maxWidth: CGFloat,
        highlightColor: UIColor,
        context: CGContext
    ) {
        // Only draw glow for single-line captions
        let fullText = words.joined(separator: " ")
        let singleLineSize = (fullText as NSString).size(withAttributes: [.font: font])
        guard singleLineSize.width <= maxWidth else { return }

        let prefix = words[0..<activeIndex].joined(separator: " ")
        let prefixWithSpace = prefix.isEmpty ? "" : prefix + " "
        let activeWord = words[activeIndex]

        let prefixSize = (prefixWithSpace as NSString).size(withAttributes: [.font: font])
        let wordSize = (activeWord as NSString).size(withAttributes: [.font: font])

        var glowX: CGFloat
        if config.alignment == .center {
            glowX = textRect.midX - singleLineSize.width / 2 + prefixSize.width
        } else {
            glowX = textRect.origin.x + prefixSize.width
        }

        let glowRect = CGRect(
            x: glowX - 8,
            y: textRect.origin.y - 6,
            width: wordSize.width + 16,
            height: wordSize.height + 12
        )

        for i in stride(from: 3, through: 1, by: -1) {
            let expand = CGFloat(i) * 3
            let alpha = 0.08 / CGFloat(i)
            let expandedRect = glowRect.insetBy(dx: -expand, dy: -expand)
            let path = UIBezierPath(roundedRect: expandedRect, cornerRadius: 6 + expand)
            highlightColor.withAlphaComponent(alpha).setFill()
            path.fill()
        }
    }

    private static func isSemanticEmphasisWord(_ word: String) -> Bool {
        semanticEmphasisTokens.contains(normalizedEmphasisToken(word))
    }

    private static func normalizedEmphasisToken(_ word: String) -> String {
        word
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "tr_TR"))
            .filter { $0.isLetter || $0.isNumber }
    }

    private struct StyleConfig {
        let fontSize: CGFloat
        let fontWeight: UIFont.Weight
        let textColor: UIColor
        let hasBackground: Bool
        let backgroundColor: UIColor
        let cornerRadius: CGFloat
        let alignment: NSTextAlignment
    }

    private func styleConfig(for style: CaptionStyle, theme: TemplateConfig.CaptionTheme = .premiumGold) -> StyleConfig {
        switch style {
        case .hookImpact:
            return StyleConfig(
                fontSize: 58,
                fontWeight: .heavy,
                textColor: theme.hookTextColor.uiColor,
                hasBackground: true,
                backgroundColor: theme.hookBgColor.uiColor,
                cornerRadius: 8,
                alignment: .center
            )
        case .boldCenterViral:
            return StyleConfig(
                fontSize: 50,
                fontWeight: .bold,
                textColor: theme.defaultTextColor.uiColor,
                hasBackground: true,
                backgroundColor: UIColor.black.withAlphaComponent(0.54),
                cornerRadius: 6,
                alignment: .center
            )
        case .premiumLowerThird:
            return StyleConfig(
                fontSize: 42,
                fontWeight: .semibold,
                textColor: theme.defaultTextColor.uiColor,
                hasBackground: true,
                backgroundColor: UIColor.black.withAlphaComponent(0.6),
                cornerRadius: 4,
                alignment: .left
            )
        case .focusStatement:
            return StyleConfig(
                fontSize: 46,
                fontWeight: .bold,
                textColor: theme.defaultTextColor.uiColor,
                hasBackground: true,
                backgroundColor: UIColor.black.withAlphaComponent(0.55),
                cornerRadius: 6,
                alignment: .center
            )
        case .minimalWellness:
            return StyleConfig(
                fontSize: 38,
                fontWeight: .medium,
                textColor: theme.defaultTextColor.uiColor,
                hasBackground: true,
                backgroundColor: UIColor.black.withAlphaComponent(0.45),
                cornerRadius: 6,
                alignment: .center
            )
        case .neonGlow:
            return StyleConfig(
                fontSize: 52,
                fontWeight: .bold,
                textColor: theme.karaokeHighlight.uiColor,
                hasBackground: true,
                backgroundColor: UIColor.black.withAlphaComponent(0.7),
                cornerRadius: 6,
                alignment: .center
            )
        case .elegantSerif:
            return StyleConfig(
                fontSize: 44,
                fontWeight: .regular,
                textColor: theme.defaultTextColor.uiColor,
                hasBackground: true,
                backgroundColor: UIColor.black.withAlphaComponent(0.4),
                cornerRadius: 8,
                alignment: .center
            )
        case .typewriterClean:
            return StyleConfig(
                fontSize: 40,
                fontWeight: .medium,
                textColor: theme.defaultTextColor.uiColor,
                hasBackground: true,
                backgroundColor: UIColor.black.withAlphaComponent(0.5),
                cornerRadius: 0,
                alignment: .left
            )
        case .glitchBold:
            return StyleConfig(
                fontSize: 60,
                fontWeight: .black,
                textColor: theme.defaultTextColor.uiColor,
                hasBackground: true,
                backgroundColor: UIColor.black.withAlphaComponent(0.65),
                cornerRadius: 2,
                alignment: .center
            )
        case .retroVHS:
            return StyleConfig(
                fontSize: 44,
                fontWeight: .medium,
                textColor: theme.defaultTextColor.uiColor,
                hasBackground: true,
                backgroundColor: UIColor.black.withAlphaComponent(0.7),
                cornerRadius: 0,
                alignment: .center
            )
        }
    }
}

// MARK: - Custom Composition Instruction

final class CaptionCompositionInstruction: NSObject, AVVideoCompositionInstructionProtocol, @unchecked Sendable {
    let timeRange: CMTimeRange
    let enablePostProcessing: Bool = false
    let containsTweening: Bool = false
    let requiredSourceTrackIDs: [NSValue]?
    let passthroughTrackID: CMPersistentTrackID = kCMPersistentTrackID_Invalid

    let captions: [CaptionSegment]
    let editDecisions: [EditDecision]
    let colorGrade: TemplateConfig.ColorGrade
    let captionTheme: TemplateConfig.CaptionTheme
    let renderSize: CGSize
    let showWatermark: Bool
    let sourceTransform: CGAffineTransform

    init(
        timeRange: CMTimeRange,
        sourceTrackID: CMPersistentTrackID,
        captions: [CaptionSegment],
        editDecisions: [EditDecision] = [],
        colorGrade: TemplateConfig.ColorGrade = .none,
        captionTheme: TemplateConfig.CaptionTheme = .premiumGold,
        renderSize: CGSize,
        showWatermark: Bool = false,
        sourceTransform: CGAffineTransform = .identity
    ) {
        self.timeRange = timeRange
        self.requiredSourceTrackIDs = [NSNumber(value: sourceTrackID)]
        self.captions = captions
        self.editDecisions = editDecisions
        self.colorGrade = colorGrade
        self.captionTheme = captionTheme
        self.renderSize = renderSize
        self.showWatermark = showWatermark
        self.sourceTransform = sourceTransform
        super.init()
    }
}
