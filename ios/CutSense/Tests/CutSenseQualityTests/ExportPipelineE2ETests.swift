import Testing
import AVFoundation
import UIKit
@testable import CutSense

/// End-to-end export pipeline test: generates a test video, runs full export
/// for all 5 templates, extracts frames, and saves them for visual inspection.
// Anchor class for finding test bundle resources
private class _ExportTestBundleAnchor {}

@Suite("Export Pipeline E2E — All Templates", .serialized, .timeLimit(.minutes(10)))
struct ExportPipelineE2ETests {

    // MARK: - Test Video

    /// Copy pre-made test video to temp directory
    static func generateTestVideo() async throws -> URL {
        let destURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cutsense_test_\(UUID().uuidString.prefix(8)).mp4")
        try? FileManager.default.removeItem(at: destURL)

        // Try test bundle, then main bundle
        let anchor = Bundle(for: _ExportTestBundleAnchor.self)
        let bundles = [anchor, Bundle.main]
        for bundle in bundles {
            if let srcURL = bundle.url(forResource: "cutsense_test_video", withExtension: "mp4") {
                try FileManager.default.copyItem(at: srcURL, to: destURL)
                return destURL
            }
            // Also check inside the xctest bundle
            let xctestPath = bundle.bundlePath
            let direct = URL(fileURLWithPath: xctestPath)
                .appendingPathComponent("cutsense_test_video.mp4")
            if FileManager.default.fileExists(atPath: direct.path) {
                try FileManager.default.copyItem(at: direct, to: destURL)
                return destURL
            }
        }

        throw NSError(domain: "TestVideo", code: -1, userInfo: [
            NSLocalizedDescriptionKey: "cutsense_test_video.mp4 not found in any bundle. Searched: \(bundles.map(\.bundlePath))"
        ])
    }

    /// Each test gets its own copy to avoid AVFoundation locking conflicts
    static func getOrCreateTestVideo() async throws -> URL {
        return try await generateTestVideo()
    }

    // MARK: - Mock Pipeline Data

    static let mockCaptions: [CaptionSegment] = [
        CaptionSegment(startTime: 0.2, endTime: 1.2, text: "This is the hook line", role: .hook, style: .hookImpact, sceneBehavior: .hookImpact),
        CaptionSegment(startTime: 1.4, endTime: 2.4, text: "Key insight here", role: .keyword, style: .focusStatement, sceneBehavior: .keywordLockOn),
        CaptionSegment(startTime: 2.5, endTime: 3.0, text: "Follow for more", role: .conclusion, style: .minimalWellness, sceneBehavior: .conclusionHold),
    ]

    static let mockDecisions: [RoughCutDecision] = [
        RoughCutDecision(startTime: 0.0, endTime: 3.0, action: .keep, reason: "Content", confidence: 0.95, linkedTranscriptText: nil, requiresReview: false),
    ]

    static func mockEditPlan(template: TemplateConfig) -> EditPlan {
        let keepDecisions = [
            RoughCutDecision(startTime: 0, endTime: 3, action: .keep, reason: "Content", confidence: 0.95, linkedTranscriptText: nil, requiresReview: false)
        ]
        let roughCut = RoughCutResult(
            decisions: keepDecisions,
            originalDuration: 3.0,
            cleanDuration: 3.0,
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
        generator.maximumSize = CGSize(width: 540, height: 960)

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
        let url = try await Self.getOrCreateTestVideo()
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        #expect(CMTimeGetSeconds(duration) >= 2.5)

        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        #expect(!videoTracks.isEmpty)

        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        #expect(!audioTracks.isEmpty)
    }

    @Test("Premium Founder — full export + frame inspection")
    func premiumFounderExport() async throws {
        let sourceURL = try await Self.getOrCreateTestVideo()
        let outputURL = try await Self.runExport(template: .premiumFounder, sourceURL: sourceURL)

        // Verify output exists and has content
        let attrs = try FileManager.default.attributesOfItem(atPath: outputURL.path)
        let size = attrs[.size] as? Int64 ?? 0
        #expect(size > 10_000) // at least 10KB

        // Extract frames at caption timestamps
        let frames = try await Self.extractFrames(from: outputURL, at: [0.5, 1.5, 2.7])
        #expect(frames.count == 3)

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
        let sourceURL = try await Self.getOrCreateTestVideo()
        let outputURL = try await Self.runExport(template: .viralCaption, sourceURL: sourceURL)

        let attrs = try FileManager.default.attributesOfItem(atPath: outputURL.path)
        let size = attrs[.size] as? Int64 ?? 0
        #expect(size > 10_000)

        let frames = try await Self.extractFrames(from: outputURL, at: [0.5, 1.5, 2.7])
        let dir = try Self.saveFrames(frames, templateName: "viral_caption")
        print("[TEST] Viral Caption frames saved: \(dir.path)")

        #expect(frames.count == 3)
    }

    @Test("Clean Expert — full export + frame inspection")
    func cleanExpertExport() async throws {
        let sourceURL = try await Self.getOrCreateTestVideo()
        let outputURL = try await Self.runExport(template: .cleanExpert, sourceURL: sourceURL)

        let attrs = try FileManager.default.attributesOfItem(atPath: outputURL.path)
        let size = attrs[.size] as? Int64 ?? 0
        #expect(size > 10_000)

        let frames = try await Self.extractFrames(from: outputURL, at: [0.5, 1.5, 2.7])
        let dir = try Self.saveFrames(frames, templateName: "clean_expert")
        print("[TEST] Clean Expert frames saved: \(dir.path)")

        #expect(frames.count == 3)
    }

    @Test("Cinematic Storyteller — full export + frame inspection")
    func cinematicStorytellerExport() async throws {
        let sourceURL = try await Self.getOrCreateTestVideo()
        let outputURL = try await Self.runExport(template: .cinematicStoryteller, sourceURL: sourceURL)

        let attrs = try FileManager.default.attributesOfItem(atPath: outputURL.path)
        let size = attrs[.size] as? Int64 ?? 0
        #expect(size > 10_000)

        let frames = try await Self.extractFrames(from: outputURL, at: [0.5, 1.5, 2.7])
        let dir = try Self.saveFrames(frames, templateName: "cinematic_storyteller")
        print("[TEST] Cinematic Storyteller frames saved: \(dir.path)")

        #expect(frames.count == 3)
    }

    @Test("Podcast Highlights — full export + frame inspection")
    func podcastHighlightsExport() async throws {
        let sourceURL = try await Self.getOrCreateTestVideo()
        let outputURL = try await Self.runExport(template: .podcastHighlights, sourceURL: sourceURL)

        let attrs = try FileManager.default.attributesOfItem(atPath: outputURL.path)
        let size = attrs[.size] as? Int64 ?? 0
        #expect(size > 10_000)

        let frames = try await Self.extractFrames(from: outputURL, at: [0.5, 1.5, 2.7])
        let dir = try Self.saveFrames(frames, templateName: "podcast_highlights")
        print("[TEST] Podcast Highlights frames saved: \(dir.path)")

        #expect(frames.count == 3)
    }
}
