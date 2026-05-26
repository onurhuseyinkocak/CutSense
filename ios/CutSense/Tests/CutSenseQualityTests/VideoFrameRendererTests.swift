import CoreGraphics
import CoreImage
import CoreVideo
import Testing
@testable import CutSense

@Suite("VideoFrameRenderer")
struct VideoFrameRendererTests {
    @Test("Rotated source frame fills portrait canvas without blank half")
    func rotatedSourceFrameFillsCanvas() throws {
        let source = try Self.makeStripedPixelBuffer(width: 40, height: 20)
        let renderSize = CGSize(width: 20, height: 40)
        let transform = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 20, ty: 0)

        let output = try Self.render(
            source: source,
            transform: transform,
            renderSize: renderSize
        )

        let samples = [
            try Self.pixel(in: output, x: 5, y: 5),
            try Self.pixel(in: output, x: 14, y: 5),
            try Self.pixel(in: output, x: 5, y: 34),
            try Self.pixel(in: output, x: 14, y: 34),
        ]

        #expect(samples.allSatisfy { $0.brightness > 80 })
    }

    @Test("Source transform rotates vertical stripes into horizontal bands")
    func sourceTransformRotatesImageContent() throws {
        let source = try Self.makeStripedPixelBuffer(width: 40, height: 20)
        let renderSize = CGSize(width: 20, height: 40)
        let transform = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 20, ty: 0)

        let identityOutput = try Self.render(
            source: source,
            transform: .identity,
            renderSize: renderSize
        )
        let rotatedOutput = try Self.render(
            source: source,
            transform: transform,
            renderSize: renderSize
        )

        let identityTopLeft = try Self.pixel(in: identityOutput, x: 5, y: 10)
        let identityTopRight = try Self.pixel(in: identityOutput, x: 14, y: 10)
        let identityBottomLeft = try Self.pixel(in: identityOutput, x: 5, y: 30)
        let identityBottomRight = try Self.pixel(in: identityOutput, x: 14, y: 30)

        #expect(identityTopLeft.distance(to: identityBottomLeft) < 80)
        #expect(identityTopRight.distance(to: identityBottomRight) < 80)
        #expect(identityTopLeft.distance(to: identityTopRight) > 180)

        let rotatedTopLeft = try Self.pixel(in: rotatedOutput, x: 5, y: 10)
        let rotatedTopRight = try Self.pixel(in: rotatedOutput, x: 14, y: 10)
        let rotatedBottomLeft = try Self.pixel(in: rotatedOutput, x: 5, y: 30)
        let rotatedBottomRight = try Self.pixel(in: rotatedOutput, x: 14, y: 30)

        #expect(rotatedTopLeft.distance(to: rotatedTopRight) < 80)
        #expect(rotatedBottomLeft.distance(to: rotatedBottomRight) < 80)
        #expect(rotatedTopLeft.distance(to: rotatedBottomLeft) > 180)
        #expect(rotatedTopLeft.isRed)
        #expect(rotatedBottomLeft.isBlue)
    }

    @Test("Mirrored WhatsApp rotation matrix maps to upright mirrored portrait")
    func mirroredRotationMatrixUsesImageOrientation() throws {
        let source = try Self.makeStripedPixelBuffer(width: 40, height: 20)
        let renderSize = CGSize(width: 20, height: 40)
        let whatsappTransform = CGAffineTransform(a: 0, b: 1, c: 1, d: 0, tx: 0, ty: 0)

        let output = try Self.render(
            source: source,
            transform: whatsappTransform,
            renderSize: renderSize
        )
        let expected = try Self.renderExpected(
            source: source,
            orientation: .leftMirrored,
            renderSize: renderSize
        )

        for sample in [(5, 5), (14, 5), (5, 34), (14, 34)] {
            let actualPixel = try Self.pixel(in: output, x: sample.0, y: sample.1)
            let expectedPixel = try Self.pixel(in: expected, x: sample.0, y: sample.1)
            #expect(actualPixel.distance(to: expectedPixel) < 20)
        }
    }

    private static func render(
        source: CVPixelBuffer,
        transform: CGAffineTransform,
        renderSize: CGSize
    ) throws -> CVPixelBuffer {
        let image = VideoFrameRenderer.orientedAspectFillImage(
            from: source,
            sourceTransform: transform,
            renderSize: renderSize
        )
        let composited = VideoFrameRenderer.compositedOverBlack(image, renderSize: renderSize)

        var output: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(renderSize.width),
            Int(renderSize.height),
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &output
        )
        guard status == kCVReturnSuccess, let output else {
            throw TestError.pixelBufferCreationFailed(status)
        }

        let context = CIContext(options: [.useSoftwareRenderer: true])
        context.render(
            composited,
            to: output,
            bounds: CGRect(origin: .zero, size: renderSize),
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        return output
    }

    private static func renderExpected(
        source: CVPixelBuffer,
        orientation: CGImagePropertyOrientation,
        renderSize: CGSize
    ) throws -> CVPixelBuffer {
        let image = orientedAspectFillImage(
            from: source,
            orientation: orientation,
            renderSize: renderSize
        )
        let composited = VideoFrameRenderer.compositedOverBlack(image, renderSize: renderSize)

        var output: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(renderSize.width),
            Int(renderSize.height),
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &output
        )
        guard status == kCVReturnSuccess, let output else {
            throw TestError.pixelBufferCreationFailed(status)
        }

        let context = CIContext(options: [.useSoftwareRenderer: true])
        context.render(
            composited,
            to: output,
            bounds: CGRect(origin: .zero, size: renderSize),
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        return output
    }

    private static func orientedAspectFillImage(
        from sourceBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation,
        renderSize: CGSize
    ) -> CIImage {
        var image = CIImage(cvPixelBuffer: sourceBuffer).oriented(orientation)
        image = image.transformed(by: CGAffineTransform(
            translationX: -image.extent.minX,
            y: -image.extent.minY
        ))

        let scale = max(renderSize.width / image.extent.width, renderSize.height / image.extent.height)
        image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let extent = image.extent
        image = image.transformed(by: CGAffineTransform(
            translationX: (renderSize.width - extent.width) / 2 - extent.minX,
            y: (renderSize.height - extent.height) / 2 - extent.minY
        ))
        return image.cropped(to: CGRect(origin: .zero, size: renderSize))
    }

    private static func makeStripedPixelBuffer(width: Int, height: Int) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &buffer
        )
        guard status == kCVReturnSuccess, let buffer else {
            throw TestError.pixelBufferCreationFailed(status)
        }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else {
            throw TestError.missingBaseAddress
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let bytes = baseAddress.assumingMemoryBound(to: UInt8.self)

        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * 4
                if x < width / 2 {
                    bytes[offset] = 0
                    bytes[offset + 1] = 0
                    bytes[offset + 2] = 255
                    bytes[offset + 3] = 255
                } else {
                    bytes[offset] = 255
                    bytes[offset + 1] = 0
                    bytes[offset + 2] = 0
                    bytes[offset + 3] = 255
                }
            }
        }

        return buffer
    }

    private static func pixel(in buffer: CVPixelBuffer, x: Int, y: Int) throws -> Pixel {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else {
            throw TestError.missingBaseAddress
        }

        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        guard x >= 0, x < width, y >= 0, y < height else {
            throw TestError.pixelOutOfBounds
        }

        let offset = y * CVPixelBufferGetBytesPerRow(buffer) + x * 4
        let bytes = baseAddress.assumingMemoryBound(to: UInt8.self)
        return Pixel(red: bytes[offset + 2], green: bytes[offset + 1], blue: bytes[offset])
    }

    private struct Pixel {
        let red: UInt8
        let green: UInt8
        let blue: UInt8

        var brightness: Int {
            Int(red) + Int(green) + Int(blue)
        }

        func distance(to other: Pixel) -> Int {
            abs(Int(red) - Int(other.red)) +
            abs(Int(green) - Int(other.green)) +
            abs(Int(blue) - Int(other.blue))
        }

        var isRed: Bool {
            Int(red) > 180 && Int(blue) < 80
        }

        var isBlue: Bool {
            Int(blue) > 180 && Int(red) < 80
        }
    }

    private enum TestError: Error {
        case missingBaseAddress
        case pixelBufferCreationFailed(CVReturn)
        case pixelOutOfBounds
    }
}
