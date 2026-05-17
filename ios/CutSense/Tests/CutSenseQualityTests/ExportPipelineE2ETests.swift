import Testing
import AVFoundation
import UIKit
@testable import CutSense

/// End-to-end export pipeline test: generates a test video, runs full export
/// for all 5 templates, extracts frames, and saves them for visual inspection.
@Suite("Export Pipeline E2E — All Templates", .serialized)
struct ExportPipelineE2ETests {

    // MARK: - Test Video Generation

    /// Generate a 10-second 1080x1920 test video with color gradient + silent audio
    static func generateTestVideo() async throws -> URL {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cutsense_test_\(UUID().uuidString.prefix(8)).mp4")
        try? FileManager.default.removeItem(at: outputURL)

        let width = 1080
        let height = 1920
        let fps: Int32 = 30
        let duration: Double = 10.0
        let totalFrames = Int(duration * Double(fps))
        let sampleRate: Float64 = 44100

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)

        // Video input
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ]
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height
            ]
        )
        writer.add(videoInput)

        // Audio input — AAC compressed
        let audioSettings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 64000
        ]
        let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        audioInput.expectsMediaDataInRealTime = false
        writer.add(audioInput)

        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        // Write video frames
        for frame in 0..<totalFrames {
            while !videoInput.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 5_000_000)
            }

            guard let pool = adaptor.pixelBufferPool else { continue }
            var pixelBuffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
            guard let buffer = pixelBuffer else { continue }

            CVPixelBufferLockBaseAddress(buffer, [])
            if let base = CVPixelBufferGetBaseAddress(buffer) {
                let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
                let progress = Float(frame) / Float(totalFrames)

                for y in 0..<height {
                    let row = base.advanced(by: y * bytesPerRow).assumingMemoryBound(to: UInt8.self)
                    for x in 0..<width {
                        let offset = x * 4
                        let yRatio = Float(y) / Float(height)
                        let r = UInt8(min(255, max(0, Int(40.0 + progress * 180.0 * yRatio))))
                        let g = UInt8(min(255, max(0, Int(60.0 + (1 - progress) * 120.0 * Float(x) / Float(width)))))
                        let b = UInt8(min(255, max(0, Int(80.0 + (1 - yRatio) * 150.0))))
                        row[offset + 0] = b  // BGRA
                        row[offset + 1] = g
                        row[offset + 2] = r
                        row[offset + 3] = 255
                    }
                }
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])

            let time = CMTime(value: Int64(frame), timescale: fps)
            adaptor.append(buffer, withPresentationTime: time)
        }
        videoInput.markAsFinished()

        // Write audio — PCM sine wave samples fed to AAC encoder
        let totalSamples = Int(sampleRate * duration)
        let samplesPerChunk = 1024
        var samplesWritten = 0

        // Create format description for PCM source
        var asbd = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
            mBytesPerPacket: 2,
            mFramesPerPacket: 1,
            mBytesPerFrame: 2,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 16,
            mReserved: 0
        )
        var fmtDesc: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(allocator: nil, asbd: &asbd, layoutSize: 0, layout: nil,
                                       magicCookieSize: 0, magicCookie: nil, extensions: nil,
                                       formatDescriptionOut: &fmtDesc)
        guard let audioFmt = fmtDesc else {
            videoInput.markAsFinished()
            await writer.finishWriting()
            throw NSError(domain: "TestVideo", code: -2, userInfo: [NSLocalizedDescriptionKey: "Audio format creation failed"])
        }

        while samplesWritten < totalSamples {
            while !audioInput.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 5_000_000)
            }

            let count = min(samplesPerChunk, totalSamples - samplesWritten)
            let dataSize = count * 2

            // Allocate PCM data
            let pcmData = UnsafeMutablePointer<Int16>.allocate(capacity: count)
            defer { pcmData.deallocate() }
            for i in 0..<count {
                let t = Double(samplesWritten + i) / sampleRate
                let envelope = 0.5 + 0.5 * sin(2.0 * .pi * 0.5 * t)
                let sample = sin(2.0 * .pi * 440.0 * t) * envelope * 0.5
                pcmData[i] = Int16(clamping: Int(sample * 32767))
            }

            var blockBuf: CMBlockBuffer?
            CMBlockBufferCreateWithMemoryBlock(
                allocator: nil, memoryBlock: pcmData, blockLength: dataSize,
                blockAllocator: kCFAllocatorNull, customBlockSource: nil,
                offsetToData: 0, dataLength: dataSize, flags: 0, blockBufferOut: &blockBuf
            )
            guard let block = blockBuf else { break }

            var timing = CMSampleTimingInfo(
                duration: CMTime(value: 1, timescale: Int32(sampleRate)),
                presentationTimeStamp: CMTime(value: Int64(samplesWritten), timescale: Int32(sampleRate)),
                decodeTimeStamp: .invalid
            )
            var sampleBuf: CMSampleBuffer?
            CMSampleBufferCreate(allocator: nil, dataBuffer: block, dataReady: true,
                                 makeDataReadyCallback: nil, refcon: nil,
                                 formatDescription: audioFmt, sampleCount: count,
                                 sampleTimingEntryCount: 1, sampleTimingArray: &timing,
                                 sampleSizeEntryCount: 0, sampleSizeArray: nil,
                                 sampleBufferOut: &sampleBuf)
            if let sb = sampleBuf {
                audioInput.append(sb)
            }
            samplesWritten += count
        }
        audioInput.markAsFinished()

        await writer.finishWriting()

        guard writer.status == .completed else {
            throw NSError(domain: "TestVideo", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Video generation failed: \(writer.error?.localizedDescription ?? "unknown")"
            ])
        }

        return outputURL
    }

    // MARK: - Mock Pipeline Data

    static let mockCaptions: [CaptionSegment] = [
        CaptionSegment(startTime: 0.5, endTime: 2.5, text: "This is the hook line that grabs attention", role: .hook, style: .hookImpact, sceneBehavior: .hookImpact),
        CaptionSegment(startTime: 2.8, endTime: 4.5, text: "Here is a key insight you need to know", role: .keyword, style: .focusStatement, sceneBehavior: .keywordLockOn),
        CaptionSegment(startTime: 4.8, endTime: 6.5, text: "The details that matter most to you", role: .regular, style: .premiumLowerThird, sceneBehavior: .subtleZoom),
        CaptionSegment(startTime: 6.8, endTime: 8.5, text: "Breaking down the important points", role: .regular, style: .boldCenterViral, sceneBehavior: .punchIn),
        CaptionSegment(startTime: 8.8, endTime: 10.0, text: "Follow for more insights like this", role: .conclusion, style: .minimalWellness, sceneBehavior: .conclusionHold),
    ]

    static let mockDecisions: [RoughCutDecision] = [
        RoughCutDecision(startTime: 0.0, endTime: 10.0, action: .keep, reason: "Content", confidence: 0.95, linkedTranscriptText: nil, requiresReview: false),
    ]

    static func mockEditPlan(template: TemplateConfig) -> EditPlan {
        let keepDecisions = [
            RoughCutDecision(startTime: 0, endTime: 10, action: .keep, reason: "Content", confidence: 0.95, linkedTranscriptText: nil, requiresReview: false)
        ]
        let roughCut = RoughCutResult(
            decisions: keepDecisions,
            originalDuration: 10.0,
            cleanDuration: 10.0,
            keepSegments: keepDecisions,
            cutSegments: [],
            reviewSegments: []
        )
        return EditDecisionEngine.generateEditPlan(
            captions: mockCaptions,
            roughCut: roughCut,
            template: template
        )
    }

    // MARK: - Frame Extraction

    static func extractFrames(from url: URL, at times: [Double]) async throws -> [UIImage] {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.05, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.05, preferredTimescale: 600)
        generator.maximumSize = CGSize(width: 1080, height: 1920)

        var images: [UIImage] = []
        for t in times {
            let cmTime = CMTime(seconds: t, preferredTimescale: 600)
            let (cgImage, _) = try await generator.image(at: cmTime)
            images.append(UIImage(cgImage: cgImage))
        }
        return images
    }

    static func saveFrames(_ images: [UIImage], templateName: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CutSense/FrameInspection/\(templateName)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        for (i, img) in images.enumerated() {
            let path = dir.appendingPathComponent("frame_\(i).png")
            if let data = img.pngData() {
                try data.write(to: path)
            }
        }
        return dir
    }

    // MARK: - Export Runner

    @MainActor
    static func runExport(template: TemplateConfig, sourceURL: URL) async throws -> URL {
        let exportService = ExportService()
        let editPlan = mockEditPlan(template: template)

        guard let outputURL = await exportService.exportWithPipeline(
            sourceURL: sourceURL,
            decisions: mockDecisions,
            captions: mockCaptions,
            template: template,
            editPlan: editPlan
        ) else {
            throw NSError(domain: "ExportTest", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Export failed for \(template.name): \(exportService.errorMessage ?? "unknown")"
            ])
        }

        return outputURL
    }

    // MARK: - Tests

    @Test("Generate test video")
    func generateVideo() async throws {
        let url = try await Self.generateTestVideo()
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        #expect(CMTimeGetSeconds(duration) >= 9.5)

        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        #expect(!videoTracks.isEmpty)

        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        #expect(!audioTracks.isEmpty)
    }

    @Test("Premium Founder — full export + frame inspection")
    func premiumFounderExport() async throws {
        let sourceURL = try await Self.generateTestVideo()
        let outputURL = try await Self.runExport(template: .premiumFounder, sourceURL: sourceURL)

        // Verify output exists and has content
        let attrs = try FileManager.default.attributesOfItem(atPath: outputURL.path)
        let size = attrs[.size] as? Int64 ?? 0
        #expect(size > 100_000) // at least 100KB

        // Extract frames at caption timestamps
        let frames = try await Self.extractFrames(from: outputURL, at: [1.5, 3.5, 5.5, 7.5, 9.5])
        #expect(frames.count == 5)

        // Save for inspection
        let dir = try Self.saveFrames(frames, templateName: "premium_founder")
        print("[TEST] Premium Founder frames saved: \(dir.path)")

        // Verify frame dimensions
        for frame in frames {
            #expect(frame.size.width > 0)
            #expect(frame.size.height > 0)
        }
    }

    @Test("Viral Caption — full export + frame inspection")
    func viralCaptionExport() async throws {
        let sourceURL = try await Self.generateTestVideo()
        let outputURL = try await Self.runExport(template: .viralCaption, sourceURL: sourceURL)

        let attrs = try FileManager.default.attributesOfItem(atPath: outputURL.path)
        let size = attrs[.size] as? Int64 ?? 0
        #expect(size > 100_000)

        let frames = try await Self.extractFrames(from: outputURL, at: [1.5, 3.5, 5.5, 7.5, 9.5])
        let dir = try Self.saveFrames(frames, templateName: "viral_caption")
        print("[TEST] Viral Caption frames saved: \(dir.path)")

        #expect(frames.count == 5)
    }

    @Test("Clean Expert — full export + frame inspection")
    func cleanExpertExport() async throws {
        let sourceURL = try await Self.generateTestVideo()
        let outputURL = try await Self.runExport(template: .cleanExpert, sourceURL: sourceURL)

        let attrs = try FileManager.default.attributesOfItem(atPath: outputURL.path)
        let size = attrs[.size] as? Int64 ?? 0
        #expect(size > 100_000)

        let frames = try await Self.extractFrames(from: outputURL, at: [1.5, 3.5, 5.5, 7.5, 9.5])
        let dir = try Self.saveFrames(frames, templateName: "clean_expert")
        print("[TEST] Clean Expert frames saved: \(dir.path)")

        #expect(frames.count == 5)
    }

    @Test("Cinematic Storyteller — full export + frame inspection")
    func cinematicStorytellerExport() async throws {
        let sourceURL = try await Self.generateTestVideo()
        let outputURL = try await Self.runExport(template: .cinematicStoryteller, sourceURL: sourceURL)

        let attrs = try FileManager.default.attributesOfItem(atPath: outputURL.path)
        let size = attrs[.size] as? Int64 ?? 0
        #expect(size > 100_000)

        let frames = try await Self.extractFrames(from: outputURL, at: [1.5, 3.5, 5.5, 7.5, 9.5])
        let dir = try Self.saveFrames(frames, templateName: "cinematic_storyteller")
        print("[TEST] Cinematic Storyteller frames saved: \(dir.path)")

        #expect(frames.count == 5)
    }

    @Test("Podcast Highlights — full export + frame inspection")
    func podcastHighlightsExport() async throws {
        let sourceURL = try await Self.generateTestVideo()
        let outputURL = try await Self.runExport(template: .podcastHighlights, sourceURL: sourceURL)

        let attrs = try FileManager.default.attributesOfItem(atPath: outputURL.path)
        let size = attrs[.size] as? Int64 ?? 0
        #expect(size > 100_000)

        let frames = try await Self.extractFrames(from: outputURL, at: [1.5, 3.5, 5.5, 7.5, 9.5])
        let dir = try Self.saveFrames(frames, templateName: "podcast_highlights")
        print("[TEST] Podcast Highlights frames saved: \(dir.path)")

        #expect(frames.count == 5)
    }
}
