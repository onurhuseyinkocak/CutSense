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

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {
        renderContext = newRenderContext
    }

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        guard let instruction = request.videoCompositionInstruction as? CaptionCompositionInstruction else {
            request.finish(with: NSError(domain: "CaptionOverlay", code: -1))
            return
        }

        let trackID = (instruction.requiredSourceTrackIDs?.first as? NSNumber)?.int32Value ?? 1
        guard let sourceBuffer = request.sourceFrame(byTrackID: trackID) else {
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

        // No processing needed — pass through
        guard hasOverlay || hasGrade else {
            request.finish(withComposedVideoFrame: sourceBuffer)
            return
        }

        // Get output buffer from AVFoundation's managed pool (NOT CVPixelBufferCreate)
        guard let outputBuffer = renderContext?.newPixelBuffer() else {
            request.finish(withComposedVideoFrame: sourceBuffer)
            return
        }

        // Grade-only: render CIFilter directly to pool buffer
        if hasGrade && !hasOverlay {
            let ciImage = CIImage(cvPixelBuffer: sourceBuffer)
            let graded = FilterEngine.applyGrade(grade, to: ciImage)
            ciContext.render(graded, to: outputBuffer)
            request.finish(withComposedVideoFrame: outputBuffer)
            return
        }

        // Grade + overlay: render grade to pool buffer, then draw overlay on top
        if hasGrade {
            let ciImage = CIImage(cvPixelBuffer: sourceBuffer)
            let graded = FilterEngine.applyGrade(grade, to: ciImage)
            ciContext.render(graded, to: outputBuffer)
            drawOverlay(
                on: outputBuffer,
                caption: activeCaption,
                effects: activeEffects,
                currentTime: currentTime,
                renderSize: instruction.renderSize,
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
                sourceIsAlreadyDrawn: false,
                sourceBuffer: sourceBuffer
            )
        }

        request.finish(withComposedVideoFrame: outputBuffer)
    }

    func cancelAllPendingVideoCompositionRequests() {}

    // MARK: - Overlay Drawing

    /// Draw captions + visual effects onto an output buffer.
    /// If `sourceIsAlreadyDrawn` is true, buffer already has the frame content (from CIContext grade).
    /// Otherwise, source must be copied from `sourceBuffer` first.
    private func drawOverlay(
        on outputBuffer: CVPixelBuffer,
        caption: CaptionSegment?,
        effects: [EditDecision],
        currentTime: Double,
        renderSize: CGSize,
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
            // Buffer already has graded frame. Need to re-draw with effects.
            // Make image from current buffer content, clear, apply effects, redraw.
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

        // Draw caption on top
        if let caption {
            drawCaption(caption, in: context, width: CGFloat(width), height: CGFloat(height))
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

    private func drawCaption(_ caption: CaptionSegment, in context: CGContext, width: CGFloat, height: CGFloat) {
        let config = styleConfig(for: caption.style)

        let maxWidth = width * CaptionSafeArea.maxWidthRatio
        let horizontalInset = (width - maxWidth) / 2

        let yPosition: CGFloat = switch caption.style {
        case .premiumLowerThird:
            height * 0.15
        case .hookImpact, .boldCenterViral:
            height * 0.45
        case .focusStatement:
            height * 0.40
        case .minimalWellness:
            height * 0.20
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
            height: height * 0.3
        )

        let textSize = text.boundingRect(
            with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: textAttributes,
            context: nil
        )

        if config.hasBackground {
            let bgRect = CGRect(
                x: horizontalInset - 16,
                y: yPosition - 8,
                width: textSize.width + 32,
                height: textSize.height + 16
            )

            context.saveGState()
            context.setFillColor(config.backgroundColor.cgColor)
            let path = UIBezierPath(roundedRect: bgRect, cornerRadius: config.cornerRadius)
            context.addPath(path.cgPath)
            context.fillPath()
            context.restoreGState()
        }

        UIGraphicsPushContext(context)
        text.draw(in: textRect, withAttributes: textAttributes)
        UIGraphicsPopContext()
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

    private func styleConfig(for style: CaptionStyle) -> StyleConfig {
        switch style {
        case .hookImpact:
            return StyleConfig(
                fontSize: 64,
                fontWeight: .heavy,
                textColor: .white,
                hasBackground: true,
                backgroundColor: UIColor(red: 1, green: 0.2, blue: 0.2, alpha: 0.85),
                cornerRadius: 8,
                alignment: .center
            )
        case .boldCenterViral:
            return StyleConfig(
                fontSize: 56,
                fontWeight: .bold,
                textColor: .white,
                hasBackground: true,
                backgroundColor: UIColor.black.withAlphaComponent(0.75),
                cornerRadius: 6,
                alignment: .center
            )
        case .premiumLowerThird:
            return StyleConfig(
                fontSize: 42,
                fontWeight: .semibold,
                textColor: .white,
                hasBackground: true,
                backgroundColor: UIColor.black.withAlphaComponent(0.6),
                cornerRadius: 4,
                alignment: .left
            )
        case .focusStatement:
            return StyleConfig(
                fontSize: 48,
                fontWeight: .bold,
                textColor: .white,
                hasBackground: false,
                backgroundColor: .clear,
                cornerRadius: 0,
                alignment: .center
            )
        case .minimalWellness:
            return StyleConfig(
                fontSize: 38,
                fontWeight: .medium,
                textColor: UIColor.white.withAlphaComponent(0.9),
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
    let renderSize: CGSize

    init(
        timeRange: CMTimeRange,
        sourceTrackID: CMPersistentTrackID,
        captions: [CaptionSegment],
        editDecisions: [EditDecision] = [],
        colorGrade: TemplateConfig.ColorGrade = .none,
        renderSize: CGSize
    ) {
        self.timeRange = timeRange
        self.requiredSourceTrackIDs = [NSNumber(value: sourceTrackID)]
        self.captions = captions
        self.editDecisions = editDecisions
        self.colorGrade = colorGrade
        self.renderSize = renderSize
        super.init()
    }
}
