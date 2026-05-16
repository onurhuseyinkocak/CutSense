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

        // Find active caption
        let activeCaption = instruction.captions.first { caption in
            currentTime >= caption.startTime && currentTime < caption.endTime
        }

        guard let caption = activeCaption else {
            // No caption at this time — pass through
            request.finish(withComposedVideoFrame: sourceBuffer)
            return
        }

        // Render caption overlay
        let outputBuffer = renderCaptionOverlay(
            sourceBuffer: sourceBuffer,
            caption: caption,
            renderSize: instruction.renderSize
        )

        request.finish(withComposedVideoFrame: outputBuffer ?? sourceBuffer)
    }

    func cancelAllPendingVideoCompositionRequests() {}

    // MARK: - Caption Rendering

    private func renderCaptionOverlay(
        sourceBuffer: CVPixelBuffer,
        caption: CaptionSegment,
        renderSize: CGSize
    ) -> CVPixelBuffer? {
        let width = CVPixelBufferGetWidth(sourceBuffer)
        let height = CVPixelBufferGetHeight(sourceBuffer)

        // Create bitmap context
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        // Draw source frame
        CVPixelBufferLockBaseAddress(sourceBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(sourceBuffer, .readOnly) }

        if let baseAddress = CVPixelBufferGetBaseAddress(sourceBuffer) {
            let sourceContext = CGContext(
                data: baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(sourceBuffer),
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
            )
            if let image = sourceContext?.makeImage() {
                context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            }
        }

        // Draw caption text
        drawCaption(caption, in: context, width: CGFloat(width), height: CGFloat(height))

        // Create output pixel buffer
        guard let outputImage = context.makeImage() else { return nil }

        var outputBuffer: CVPixelBuffer?
        CVPixelBufferCreate(
            kCFAllocatorDefault,
            width, height,
            kCVPixelFormatType_32BGRA,
            [kCVPixelBufferCGImageCompatibilityKey: true, kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary,
            &outputBuffer
        )

        guard let output = outputBuffer else { return nil }
        CVPixelBufferLockBaseAddress(output, [])
        defer { CVPixelBufferUnlockBaseAddress(output, []) }

        if let outputBase = CVPixelBufferGetBaseAddress(output) {
            let outputCtx = CGContext(
                data: outputBase,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(output),
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
            )
            outputCtx?.draw(outputImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        }

        return output
    }

    private func drawCaption(_ caption: CaptionSegment, in context: CGContext, width: CGFloat, height: CGFloat) {
        let config = styleConfig(for: caption.style)

        // Text positioning
        let maxWidth = width * CaptionSafeArea.maxWidthRatio
        let horizontalInset = (width - maxWidth) / 2

        // Calculate Y position based on style
        let yPosition: CGFloat = switch caption.style {
        case .premiumLowerThird:
            height * 0.15 // Lower third area (CoreGraphics Y is flipped)
        case .hookImpact, .boldCenterViral:
            height * 0.45 // Center
        case .focusStatement:
            height * 0.40
        case .minimalWellness:
            height * 0.20
        }

        // Setup text attributes
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = config.alignment
        paragraphStyle.lineSpacing = 4

        let font = UIFont.systemFont(ofSize: config.fontSize, weight: config.fontWeight)

        // Draw background pill if needed
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

        // Background
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

        // Draw text using UIGraphics push/pop
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
    let renderSize: CGSize

    init(
        timeRange: CMTimeRange,
        sourceTrackID: CMPersistentTrackID,
        captions: [CaptionSegment],
        renderSize: CGSize
    ) {
        self.timeRange = timeRange
        self.requiredSourceTrackIDs = [NSNumber(value: sourceTrackID)]
        self.captions = captions
        self.renderSize = renderSize
        super.init()
    }
}
