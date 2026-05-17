import AVFoundation
import CoreImage
import UIKit

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
            trackID = (availableIDs.first as? NSNumber)?.int32Value ?? 1
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

        let hasOverlay = activeCaption != nil || !activeEffects.isEmpty
        let hasGrade = grade.saturation != 1.0 || grade.brightness != 0.0 ||
                       grade.contrast != 1.0 || abs(grade.warmth) > 0.01 ||
                       grade.vignetteIntensity > 0.01

        #if DEBUG
        frameCount += 1
        if activeCaption != nil { captionHitCount += 1 }
        if !activeEffects.isEmpty { effectHitCount += 1 }
        if frameCount == 1 || frameCount % 300 == 0 {
            print("[Compositor] frame=\(frameCount) t=\(String(format: "%.2f", currentTime))s captions=\(instruction.captions.count) captionHits=\(captionHitCount) effectHits=\(effectHitCount) hasGrade=\(hasGrade)")
        }
        #endif

        // No processing needed — pass through
        guard hasOverlay || hasGrade else {
            request.finish(withComposedVideoFrame: sourceBuffer)
            return
        }

        // Get output buffer from AVFoundation's managed pool
        guard let outputBuffer = renderContext?.newPixelBuffer() else {
            #if DEBUG
            print("[Compositor] WARNING: newPixelBuffer() nil at frame \(frameCount) — memory pressure. Passing through source.")
            #endif
            // Under memory pressure — pass through source frame instead of crashing
            request.finish(withComposedVideoFrame: sourceBuffer)
            return
        }

        // Grade-only: render CIFilter directly to pool buffer
        if hasGrade && !hasOverlay {
            CVPixelBufferLockBaseAddress(outputBuffer, [])
            let ciImage = CIImage(cvPixelBuffer: sourceBuffer)
            let graded = FilterEngine.applyGrade(grade, to: ciImage)
            ciContext.render(graded, to: outputBuffer)
            CVPixelBufferUnlockBaseAddress(outputBuffer, [])
            request.finish(withComposedVideoFrame: outputBuffer)
            return
        }

        // Grade + overlay: render grade first, then draw overlay on top
        if hasGrade {
            CVPixelBufferLockBaseAddress(outputBuffer, [])
            let ciImage = CIImage(cvPixelBuffer: sourceBuffer)
            let graded = FilterEngine.applyGrade(grade, to: ciImage)
            ciContext.render(graded, to: outputBuffer)
            CVPixelBufferUnlockBaseAddress(outputBuffer, [])

            drawOverlay(
                on: outputBuffer,
                caption: activeCaption,
                effects: activeEffects,
                currentTime: currentTime,
                renderSize: instruction.renderSize,
                captionTheme: instruction.captionTheme,
                sourceIsAlreadyDrawn: true
            )
        } else {
            // Overlay only: copy source to pool buffer, then draw overlay
            drawOverlay(
                on: outputBuffer,
                caption: activeCaption,
                effects: activeEffects,
                currentTime: currentTime,
                renderSize: instruction.renderSize,
                captionTheme: instruction.captionTheme,
                sourceIsAlreadyDrawn: false,
                sourceBuffer: sourceBuffer
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
        sourceBuffer: CVPixelBuffer? = nil
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
    }

    // MARK: - Visual Effects

    private func applyVisualEffects(_ effects: [EditDecision], context: CGContext, width: Int, height: Int, currentTime: Double) {
        // Zoom effect: scale from center
        if let zoom = effects.first(where: { $0.type == .zoom }) {
            let progress = effectProgress(zoom, at: currentTime)
            let eased = smoothstep(progress)
            let scale = 1.0 + CGFloat(zoom.intensity) * 0.15 * eased
            let cx = CGFloat(width) / 2
            let cy = CGFloat(height) / 2
            context.translateBy(x: cx, y: cy)
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: -cx, y: -cy)
        }

        // Shake effect: small deterministic offset
        if let shake = effects.first(where: { $0.type == .shake }) {
            let progress = effectProgress(shake, at: currentTime)
            let magnitude = CGFloat(shake.intensity) * 8.0
            let phase = progress * .pi * 6
            let dx = sin(phase) * magnitude
            let dy = cos(phase * 1.3) * magnitude
            context.translateBy(x: dx, y: dy)
        }
    }

    private func drawFlashEffect(_ effects: [EditDecision], context: CGContext, frameRect: CGRect, currentTime: Double) {
        guard let flash = effects.first(where: { $0.type == .flash }) else { return }
        let progress = effectProgress(flash, at: currentTime)
        let alpha = CGFloat(flash.intensity) * 0.6 * max(0, 1.0 - progress * 2.0)
        if alpha > 0.01 {
            context.setFillColor(UIColor.white.withAlphaComponent(alpha).cgColor)
            context.fill(frameRect)
        }
    }

    private func drawColorShiftEffect(_ effects: [EditDecision], context: CGContext, frameRect: CGRect, currentTime: Double) {
        guard let color = effects.first(where: { $0.type == .colorShift }) else { return }
        let progress = effectProgress(color, at: currentTime)
        let eased = smoothstep(progress)
        let alpha = CGFloat(color.intensity) * 0.2 * eased
        if alpha > 0.01 {
            context.setFillColor(UIColor(red: 1.0, green: 0.85, blue: 0.5, alpha: alpha).cgColor)
            context.setBlendMode(.overlay)
            context.fill(frameRect)
            context.setBlendMode(.normal)
        }
    }

    private func drawCutTransitionEffect(_ effects: [EditDecision], context: CGContext, frameRect: CGRect, currentTime: Double) {
        guard let cut = effects.first(where: { $0.type == .cutTransition }) else { return }
        let progress = effectProgress(cut, at: currentTime)
        // V-shaped opacity: peaks at midpoint then fades out (brief black dip)
        let midAlpha = CGFloat(cut.intensity) * 0.7
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

        let maxWidth = width * CaptionSafeArea.maxWidthRatio
        let horizontalInset = (width - maxWidth) / 2

        // Positions in UIKit coordinates (y=0 at top)
        let yPosition: CGFloat = switch caption.style {
        case .premiumLowerThird:
            height * 0.78   // Lower third area
        case .hookImpact, .boldCenterViral:
            height * 0.38   // Center
        case .focusStatement:
            height * 0.42   // Slightly below center
        case .minimalWellness:
            height * 0.74   // Just above lower third
        }

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = config.alignment
        paragraphStyle.lineSpacing = 4

        let font = UIFont.systemFont(ofSize: config.fontSize, weight: config.fontWeight)

        let text = caption.text as NSString
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: config.textColor,
            .paragraphStyle: paragraphStyle
        ]

        let textRect = CGRect(
            x: horizontalInset,
            y: yPosition,
            width: maxWidth,
            height: height * 0.2
        )

        let textSize = text.boundingRect(
            with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: textAttributes,
            context: nil
        )

        if config.hasBackground {
            let bgPadH: CGFloat = 20
            let bgPadV: CGFloat = 12
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
            let bgPath = UIBezierPath(roundedRect: bgRect, cornerRadius: config.cornerRadius)
            config.backgroundColor.setFill()
            bgPath.fill()
            UIGraphicsPopContext()
        }

        // Draw text with word-by-word karaoke reveal
        UIGraphicsPushContext(context)

        let words = caption.text.split(separator: " ").map(String.init)
        let captionDuration = caption.endTime - caption.startTime
        let timeInCaption = currentTime - caption.startTime

        if words.count > 1 && captionDuration > 0.3 {
            // Karaoke mode: highlight words progressively
            drawKaraokeText(
                words: words,
                font: font,
                config: config,
                paragraphStyle: paragraphStyle,
                textRect: textRect,
                timeInCaption: timeInCaption,
                captionDuration: captionDuration,
                maxWidth: maxWidth,
                theme: theme,
                context: context
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
        words: [String],
        font: UIFont,
        config: StyleConfig,
        paragraphStyle: NSMutableParagraphStyle,
        textRect: CGRect,
        timeInCaption: Double,
        captionDuration: Double,
        maxWidth: CGFloat,
        theme: TemplateConfig.CaptionTheme,
        context: CGContext
    ) {
        let wordCount = words.count
        let wordDuration = captionDuration / Double(wordCount)
        let activeWordIndex = min(Int(timeInCaption / wordDuration), wordCount - 1)

        // Theme-driven colors
        let highlightColor = theme.karaokeHighlight.uiColor
        let dimColor = theme.karaokeDim.uiColor
        let activeColor = config.textColor

        // Build attributed string with per-word coloring
        let fullText = words.joined(separator: " ")
        let attributed = NSMutableAttributedString(string: fullText, attributes: [
            .font: font,
            .paragraphStyle: paragraphStyle
        ])

        // Track character positions for each word
        var charOffset = 0
        for (i, word) in words.enumerated() {
            let range = NSRange(location: charOffset, length: word.count)

            if i < activeWordIndex {
                // Already revealed — full color
                attributed.addAttribute(.foregroundColor, value: activeColor, range: range)
            } else if i == activeWordIndex {
                // Currently active — highlight color
                attributed.addAttribute(.foregroundColor, value: highlightColor, range: range)
            } else {
                // Not yet revealed — dimmed
                attributed.addAttribute(.foregroundColor, value: dimColor, range: range)
            }

            charOffset += word.count + 1 // +1 for space
        }

        // Shadow pass
        let shadowAttributed = NSMutableAttributedString(attributedString: attributed)
        shadowAttributed.addAttribute(
            .foregroundColor,
            value: theme.shadowColor.uiColor,
            range: NSRange(location: 0, length: fullText.count)
        )
        let shadowOffset: CGFloat = 2
        let shadowRect = textRect.offsetBy(dx: shadowOffset, dy: shadowOffset)
        shadowAttributed.draw(in: shadowRect)

        // Main text pass
        attributed.draw(in: textRect)

        // Draw highlight background behind active word
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

        // Neon glow on active word (for viral template)
        if theme.glowEnabled && activeWordIndex < wordCount {
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
        // Calculate x position of active word
        let prefix = words[0..<activeIndex].joined(separator: " ")
        let prefixWithSpace = prefix.isEmpty ? "" : prefix + " "
        let activeWord = words[activeIndex]

        let prefixSize = (prefixWithSpace as NSString).size(withAttributes: [.font: font])
        let wordSize = (activeWord as NSString).size(withAttributes: [.font: font])

        let padH: CGFloat = 6
        let padV: CGFloat = 4

        var highlightX: CGFloat
        if config.alignment == .center {
            // Center-aligned: calculate from center
            let fullText = words.joined(separator: " ")
            let fullSize = (fullText as NSString).boundingRect(
                with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin],
                attributes: [.font: font],
                context: nil
            )
            let textStartX = textRect.midX - fullSize.width / 2
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
        let prefix = words[0..<activeIndex].joined(separator: " ")
        let prefixWithSpace = prefix.isEmpty ? "" : prefix + " "
        let activeWord = words[activeIndex]

        let prefixSize = (prefixWithSpace as NSString).size(withAttributes: [.font: font])
        let wordSize = (activeWord as NSString).size(withAttributes: [.font: font])

        var glowX: CGFloat
        if config.alignment == .center {
            let fullText = words.joined(separator: " ")
            let fullSize = (fullText as NSString).boundingRect(
                with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin],
                attributes: [.font: font],
                context: nil
            )
            glowX = textRect.midX - fullSize.width / 2 + prefixSize.width
        } else {
            glowX = textRect.origin.x + prefixSize.width
        }

        // Draw multiple passes with increasing blur for glow effect
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
                fontSize: 64,
                fontWeight: .heavy,
                textColor: theme.hookTextColor.uiColor,
                hasBackground: true,
                backgroundColor: theme.hookBgColor.uiColor,
                cornerRadius: 8,
                alignment: .center
            )
        case .boldCenterViral:
            return StyleConfig(
                fontSize: 56,
                fontWeight: .bold,
                textColor: theme.defaultTextColor.uiColor,
                hasBackground: true,
                backgroundColor: UIColor.black.withAlphaComponent(0.75),
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
                fontSize: 48,
                fontWeight: .bold,
                textColor: theme.defaultTextColor.uiColor,
                hasBackground: false,
                backgroundColor: .clear,
                cornerRadius: 0,
                alignment: .center
            )
        case .minimalWellness:
            return StyleConfig(
                fontSize: 38,
                fontWeight: .medium,
                textColor: theme.defaultTextColor.uiColor,
                hasBackground: false,
                backgroundColor: .clear,
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

    init(
        timeRange: CMTimeRange,
        sourceTrackID: CMPersistentTrackID,
        captions: [CaptionSegment],
        editDecisions: [EditDecision] = [],
        colorGrade: TemplateConfig.ColorGrade = .none,
        captionTheme: TemplateConfig.CaptionTheme = .premiumGold,
        renderSize: CGSize
    ) {
        self.timeRange = timeRange
        self.requiredSourceTrackIDs = [NSNumber(value: sourceTrackID)]
        self.captions = captions
        self.editDecisions = editDecisions
        self.colorGrade = colorGrade
        self.captionTheme = captionTheme
        self.renderSize = renderSize
        super.init()
    }
}
