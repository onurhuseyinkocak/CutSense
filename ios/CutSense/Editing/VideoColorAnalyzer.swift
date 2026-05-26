import AVFoundation
@preconcurrency import CoreImage
import os

/// Analyzes source video color characteristics for adaptive color grading.
/// Samples frames across the video and extracts brightness, warmth, saturation metrics.
enum VideoColorAnalyzer {
    struct ColorProfile: Sendable {
        let averageBrightness: Float   // 0-1
        let averageWarmth: Float       // <0 cool, >0 warm (R-B channel difference)
        let averageSaturation: Float   // 0-1
        let contrastRange: Float       // dynamic range (high = high contrast)
        let isDark: Bool               // avg brightness < 0.35
        let isOverexposed: Bool        // avg brightness > 0.75
    }

    private struct FrameSample: Sendable {
        let brightness: Float
        let warmth: Float
        let saturation: Float
    }

    /// Sample ~8 frames across the video and compute average color characteristics.
    nonisolated static func analyze(url: URL) async throws -> ColorProfile {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        guard duration > 0 else {
            return ColorProfile(averageBrightness: 0.5, averageWarmth: 0, averageSaturation: 0.5,
                                contrastRange: 0.5, isDark: false, isOverexposed: false)
        }

        let sampleCount = 8
        let interval = duration / Double(sampleCount + 1)
        var times: [NSValue] = []
        for i in 1...sampleCount {
            let t = interval * Double(i)
            times.append(NSValue(time: CMTime(seconds: t, preferredTimescale: 600)))
        }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 320, height: 240) // small for speed
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.05, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.05, preferredTimescale: 600)

        let ciContext = FilterEngine.sharedCIContext

        // Thread-safe collection — callback fires on arbitrary thread
        let samplesLock = OSAllocatedUnfairLock(initialState: [FrameSample]())

        let remainingLock = OSAllocatedUnfairLock(initialState: times.count)

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            guard !times.isEmpty else { continuation.resume(); return }

            generator.generateCGImagesAsynchronously(forTimes: times) { _, cgImage, _, _, _ in
                if let cgImage {
                    let ciImage = CIImage(cgImage: cgImage)
                    let extent = ciImage.extent

                    if let avgFilter = CIFilter(name: "CIAreaAverage", parameters: [
                        kCIInputImageKey: ciImage,
                        kCIInputExtentKey: CIVector(cgRect: extent)
                    ]), let output = avgFilter.outputImage {
                        var pixel = [UInt8](repeating: 0, count: 4)
                        ciContext.render(output, toBitmap: &pixel, rowBytes: 4,
                                        bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                                        format: CIFormat.RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
                        let r = Float(pixel[0]) / 255.0
                        let g = Float(pixel[1]) / 255.0
                        let b = Float(pixel[2]) / 255.0

                        let luma = 0.299 * r + 0.587 * g + 0.114 * b
                        let warmth = r - b
                        let maxC = max(r, g, b)
                        let minC = min(r, g, b)
                        let sat = maxC > 0.01 ? (maxC - minC) / maxC : Float(0)

                        samplesLock.withLock { $0.append(FrameSample(brightness: luma, warmth: warmth, saturation: sat)) }
                    }
                }
                let done = remainingLock.withLock { state -> Bool in
                    state -= 1
                    return state == 0
                }
                if done { continuation.resume() }
            }
        }

        let samples = samplesLock.withLock { $0 }

        guard !samples.isEmpty else {
            return ColorProfile(averageBrightness: 0.5, averageWarmth: 0, averageSaturation: 0.5,
                                contrastRange: 0.5, isDark: false, isOverexposed: false)
        }

        let count = Float(samples.count)
        let avgBrightness = samples.map(\.brightness).reduce(0, +) / count
        let avgWarmth = samples.map(\.warmth).reduce(0, +) / count
        let avgSaturation = samples.map(\.saturation).reduce(0, +) / count
        let brightnesses = samples.map(\.brightness)
        let contrastRange = (brightnesses.max() ?? 0) - (brightnesses.min() ?? 0)

        return ColorProfile(
            averageBrightness: avgBrightness,
            averageWarmth: avgWarmth,
            averageSaturation: avgSaturation,
            contrastRange: contrastRange,
            isDark: avgBrightness < 0.35,
            isOverexposed: avgBrightness > 0.75
        )
    }
}
