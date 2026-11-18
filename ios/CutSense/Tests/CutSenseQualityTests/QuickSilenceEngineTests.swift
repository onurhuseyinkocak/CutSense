import XCTest
import AVFoundation
@testable import CutSense

/// Real functional proof that the one job of the app — cutting silence — works.
final class QuickSilenceEngineTests: XCTestCase {

    func testCutsSilenceFromRealVideo() async throws {
        let bundle = Bundle(for: Self.self)
        guard let url = bundle.url(forResource: "cutsense_test_video", withExtension: "mp4") else {
            throw XCTSkip("cutsense_test_video.mp4 not in test bundle")
        }

        let originalDuration = try await AVURLAsset(url: url).load(.duration).seconds
        XCTAssertGreaterThan(originalDuration, 0, "source video has no duration")

        let result = try await QuickSilenceEngine.cut(url: url, progress: { _ in })

        // 1. It produced a real output file.
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.outputURL.path),
                      "engine did not produce an output file")
        // 2. The output is a valid, playable video with non-zero duration.
        let outAsset = AVURLAsset(url: result.outputURL)
        let outDuration = try await outAsset.load(.duration).seconds
        let outVideoTracks = try await outAsset.loadTracks(withMediaType: .video)
        XCTAssertGreaterThan(outDuration, 0, "output has zero duration")
        XCTAssertFalse(outVideoTracks.isEmpty, "output has no video track")
        // 3. It never produced something longer than the source.
        XCTAssertLessThanOrEqual(result.outputDuration, originalDuration + 0.5,
                                 "output longer than source — that's not a cut")

        print("[QuickSilence] original=\(originalDuration)s output=\(result.outputDuration)s removed=\(result.removedPercent)% segmentsKept=\(result.segmentsKept)")
    }

    func testStressVideoFromEnvironment() async throws {
        guard let url = videoURL(
            bundledResource: "cutsense_stress_10min",
            environmentKey: "CUTSENSE_STRESS_VIDEO_URL",
            fallbackPath: "/tmp/cutsense-stress/4k60_10min_speech_silence.mp4"
        ) else {
            throw XCTSkip("Set CUTSENSE_STRESS_VIDEO_URL to run long-video stress coverage.")
        }

        let extractedMetadata = await VideoMetadataService.extract(from: url)
        let metadata = try XCTUnwrap(extractedMetadata, "stress video metadata could not be read")

        XCTAssertGreaterThanOrEqual(metadata.duration, 590)
        XCTAssertGreaterThanOrEqual(metadata.resolution.width * metadata.resolution.height, 3840 * 2160)
        XCTAssertGreaterThanOrEqual(metadata.frameRate, 59)
        XCTAssertTrue(metadata.hasAudio)
        XCTAssertTrue(metadata.isSupported)

        let start = Date()
        let progressProbe = ProgressProbe()
        let result = try await QuickSilenceEngine.cut(url: url) { update in
            progressProbe.record(update)
        }
        let elapsed = Date().timeIntervalSince(start)
        let lastProgress = await progressProbe.lastProgress

        XCTAssertGreaterThan(lastProgress, 0.95)
        XCTAssertGreaterThan(result.outputDuration, 0)
        XCTAssertLessThanOrEqual(result.outputDuration, metadata.duration + 0.5)
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.outputURL.path))

        let extractedOutputMetadata = await VideoMetadataService.extract(from: result.outputURL)
        let outputMetadata = try XCTUnwrap(extractedOutputMetadata)
        XCTAssertGreaterThan(outputMetadata.duration, 0)
        XCTAssertTrue(outputMetadata.hasAudio, "stress output should preserve the source audio track")
        XCTAssertGreaterThanOrEqual(
            outputMetadata.resolution.width * outputMetadata.resolution.height,
            3840 * 2160,
            "passthrough stress output should preserve 4K frame dimensions"
        )
        let outputVideoTracks = try await AVURLAsset(url: result.outputURL).loadTracks(withMediaType: .video)
        XCTAssertFalse(outputVideoTracks.isEmpty)

        print("[QuickSilenceStress] input=\(metadata.formattedDuration) \(metadata.formattedResolution)@\(metadata.frameRate)fps output=\(outputMetadata.formattedDuration) elapsed=\(String(format: "%.1f", elapsed))s segments=\(result.segmentsKept)")
    }

    func testFiveMinuteVideoCompletesAndCutsSilence() async throws {
        guard let url = videoURL(
            environmentKey: "CUTSENSE_FIVE_MIN_VIDEO_URL",
            fallbackPath: "/tmp/cutsense-stress/cutsense_5min_speech_silence.mp4"
        ) else {
            throw XCTSkip("Set CUTSENSE_FIVE_MIN_VIDEO_URL to run 5-minute simulator coverage.")
        }

        let extractedMetadata = await VideoMetadataService.extract(from: url)
        let metadata = try XCTUnwrap(extractedMetadata, "5-minute video metadata could not be read")
        XCTAssertGreaterThanOrEqual(metadata.duration, 299)
        XCTAssertTrue(metadata.hasAudio)
        XCTAssertTrue(metadata.isSupported)

        let start = Date()
        let progressProbe = ProgressProbe()
        let result = try await QuickSilenceEngine.cut(url: url, intensity: .tight) { update in
            progressProbe.record(update)
        }
        let elapsed = Date().timeIntervalSince(start)
        let lastProgress = await progressProbe.lastProgress

        XCTAssertGreaterThan(lastProgress, 0.95, "progress never reached completion")
        XCTAssertLessThan(elapsed, 90, "5-minute silence cut took too long: \(elapsed)s")
        XCTAssertGreaterThan(result.outputDuration, 150, "output should preserve the speech sections")
        XCTAssertLessThan(result.outputDuration, metadata.duration - 20, "output should remove meaningful silence")
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.outputURL.path))

        let extractedOutputMetadata = await VideoMetadataService.extract(from: result.outputURL)
        let outputMetadata = try XCTUnwrap(extractedOutputMetadata)
        XCTAssertTrue(outputMetadata.hasAudio)
        XCTAssertGreaterThan(outputMetadata.duration, 150)
        XCTAssertLessThanOrEqual(outputMetadata.duration, metadata.duration)
        let outputVideoTracks = try await AVURLAsset(url: result.outputURL).loadTracks(withMediaType: .video)
        XCTAssertFalse(outputVideoTracks.isEmpty)

        print("[QuickSilence5Min] input=\(metadata.formattedDuration) output=\(outputMetadata.formattedDuration) elapsed=\(String(format: "%.1f", elapsed))s segments=\(result.segmentsKept)")
    }

    func testNoiseOnlyVideoFromEnvironment() async throws {
        guard let url = videoURL(
            bundledResource: "noise_only_30s",
            environmentKey: "CUTSENSE_NOISE_ONLY_VIDEO_URL",
            fallbackPath: "/tmp/cutsense-stress/noise_only_30s.mp4"
        ) else {
            throw XCTSkip("Set CUTSENSE_NOISE_ONLY_VIDEO_URL to run background-noise hard-cut coverage.")
        }

        do {
            _ = try await QuickSilenceEngine.cut(url: url, progress: { _ in })
            XCTFail("noise-only video should be rejected as nothing to keep")
        } catch QuickSilenceEngine.Failure.nothingToKeep {
            // Expected: steady background noise is cuttable and should not be kept as speech.
        }
    }

    func testRejectsNoAudioVideo() async throws {
        let bundle = Bundle(for: Self.self)
        guard let sourceURL = bundle.url(forResource: "cutsense_test_video", withExtension: "mp4") else {
            throw XCTSkip("cutsense_test_video.mp4 not in test bundle")
        }
        let noAudioURL = try await makeVideoOnlyCopy(from: sourceURL)

        do {
            _ = try await QuickSilenceEngine.cut(url: noAudioURL, progress: { _ in })
            XCTFail("no-audio video should not export unchanged as a successful cut")
        } catch AudioAnalysisError.noAudioTrack {
            // Expected: no-audio clips are rejected instead of producing a fake success.
        }
    }

    private func videoURL(bundledResource: String? = nil, environmentKey: String, fallbackPath: String) -> URL? {
        if let bundledResource, let bundledURL = Bundle(for: Self.self).url(forResource: bundledResource, withExtension: "mp4") {
            return bundledURL
        }

        if let path = ProcessInfo.processInfo.environment[environmentKey], !path.isEmpty {
            return URL(fileURLWithPath: path)
        }

        let fallbackURL = URL(fileURLWithPath: fallbackPath)
        return FileManager.default.fileExists(atPath: fallbackURL.path) ? fallbackURL : nil
    }

    private func makeVideoOnlyCopy(from sourceURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: sourceURL)
        let composition = AVMutableComposition()
        guard
            let sourceVideo = try await asset.loadTracks(withMediaType: .video).first,
            let outputVideo = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )
        else {
            XCTFail("source fixture has no video track")
            throw QuickSilenceEngine.Failure.noVideoTrack
        }

        let duration = try await asset.load(.duration)
        try outputVideo.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: sourceVideo, at: .zero)
        outputVideo.preferredTransform = try await sourceVideo.load(.preferredTransform)

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cutsense-no-audio-\(UUID().uuidString).mp4")
        try? FileManager.default.removeItem(at: outputURL)
        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            XCTFail("could not create no-audio export session")
            throw QuickSilenceEngine.Failure.exportFailed("no-audio fixture export session could not be created")
        }
        session.outputURL = outputURL
        session.outputFileType = .mp4
        await withCheckedContinuation { continuation in
            session.exportAsynchronously { continuation.resume() }
        }
        if session.status != .completed {
            throw QuickSilenceEngine.Failure.exportFailed(session.error?.localizedDescription ?? "\(session.status)")
        }
        return outputURL
    }
}

@MainActor
private final class ProgressProbe {
    private(set) var lastProgress = 0.0

    func record(_ update: QuickSilenceEngine.ProgressUpdate) {
        lastProgress = max(lastProgress, update.fraction)
    }
}
