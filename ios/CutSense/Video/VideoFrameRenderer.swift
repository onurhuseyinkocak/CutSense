import CoreGraphics
import CoreImage
import CoreVideo
import ImageIO

enum VideoFrameRenderer {
    static func orientedAspectFillImage(
        from sourceBuffer: CVPixelBuffer,
        sourceTransform: CGAffineTransform,
        renderSize: CGSize
    ) -> CIImage {
        let outputRect = CGRect(origin: .zero, size: renderSize)
        guard renderSize.width > 0, renderSize.height > 0 else {
            return CIImage(color: .black).cropped(to: outputRect)
        }

        var image = orientedImage(from: sourceBuffer, sourceTransform: sourceTransform)

        image = normalizeToOrigin(image)

        let sourceExtent = image.extent
        guard sourceExtent.width > 0, sourceExtent.height > 0 else {
            return CIImage(color: .black).cropped(to: outputRect)
        }

        let scale = max(renderSize.width / sourceExtent.width, renderSize.height / sourceExtent.height)
        image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        let scaledExtent = image.extent
        let x = (renderSize.width - scaledExtent.width) / 2 - scaledExtent.minX
        let y = (renderSize.height - scaledExtent.height) / 2 - scaledExtent.minY
        image = image.transformed(by: CGAffineTransform(translationX: x, y: y))

        return image.cropped(to: outputRect)
    }

    static func compositedOverBlack(_ image: CIImage, renderSize: CGSize) -> CIImage {
        let outputRect = CGRect(origin: .zero, size: renderSize)
        let clearImage = CIImage(color: .black).cropped(to: outputRect)
        return image
            .composited(over: clearImage)
            .cropped(to: outputRect)
    }

    private static func normalizeToOrigin(_ image: CIImage) -> CIImage {
        let extent = image.extent
        return image.transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
    }

    private static func orientedImage(
        from sourceBuffer: CVPixelBuffer,
        sourceTransform: CGAffineTransform
    ) -> CIImage {
        let image = CIImage(cvPixelBuffer: sourceBuffer)
        if let orientation = imageOrientation(for: sourceTransform) {
            return image.oriented(orientation)
        }
        if !sourceTransform.isIdentity {
            return image.transformed(by: sourceTransform)
        }
        return image
    }

    private static func imageOrientation(for transform: CGAffineTransform) -> CGImagePropertyOrientation? {
        func close(_ lhs: CGFloat, _ rhs: CGFloat) -> Bool {
            abs(lhs - rhs) < 0.001
        }

        switch (transform.a, transform.b, transform.c, transform.d) {
        case let (a, b, c, d) where close(a, 1) && close(b, 0) && close(c, 0) && close(d, 1):
            return .up
        case let (a, b, c, d) where close(a, -1) && close(b, 0) && close(c, 0) && close(d, -1):
            return .down
        case let (a, b, c, d) where close(a, 0) && close(b, 1) && close(c, -1) && close(d, 0):
            return .right
        case let (a, b, c, d) where close(a, 0) && close(b, -1) && close(c, 1) && close(d, 0):
            return .left
        case let (a, b, c, d) where close(a, -1) && close(b, 0) && close(c, 0) && close(d, 1):
            return .upMirrored
        case let (a, b, c, d) where close(a, 1) && close(b, 0) && close(c, 0) && close(d, -1):
            return .downMirrored
        case let (a, b, c, d) where close(a, 0) && close(b, 1) && close(c, 1) && close(d, 0):
            return .leftMirrored
        case let (a, b, c, d) where close(a, 0) && close(b, -1) && close(c, -1) && close(d, 0):
            return .rightMirrored
        default:
            return nil
        }
    }
}
