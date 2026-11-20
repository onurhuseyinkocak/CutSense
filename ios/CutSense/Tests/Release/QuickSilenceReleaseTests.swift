import XCTest
import AVFoundation
@testable import CutSense

final class QuickSilenceReleaseTests: XCTestCase {
    // Fixture: 4 x 2.5 s silences around 3 spoken sentences, 17.36 s total.
    private var fixtureURL: URL {
        get throws {
            try XCTUnwrap(Bundle(for: Self.self).url(forResource: "silence_fixture", withExtension: "mp4"))
        }
    }

    func testKeepRangesIsComplementOfCuts() {
        let keep = QuickSilenceEngine.keepRanges(silence: [0...1, 3...4], duration: 6)
        XCTAssertEqual(keep, [1...3, 4...6])
    }

    func testProtectedCutRangesPadsInnerSilenceAndDropsShortGaps() {
        let cuts = QuickSilenceEngine.protectedCutRanges(silence: [0...2, 5...6, 8...8.2], pad: 0.1, minimumRemovedGap: 0.3, duration: 10)
        XCTAssertEqual(cuts.count, 2)
        XCTAssertEqual(cuts[0].lowerBound, 0, accuracy: 1e-9)       // leading silence cut to the edge
        XCTAssertEqual(cuts[0].upperBound, 1.9, accuracy: 1e-9)
        XCTAssertEqual(cuts[1].lowerBound, 5.1, accuracy: 1e-9)
        XCTAssertEqual(cuts[1].upperBound, 5.9, accuracy: 1e-9)
    }

    func testMergedJoinsSmallGaps() {
        XCTAssertEqual(QuickSilenceEngine.merged([0...1, 1.05...2, 3...4], gap: 0.1), [0...2, 3...4])
    }

    func testAnalyzerFindsTheFourPauses() async throws {
        let result = try await AudioAnalysisService.analyze(url: try fixtureURL, options: .tight)
        XCTAssertEqual(result.duration, 17.36, accuracy: 0.1)
        XCTAssertEqual(result.silenceIntervals.count, 4, "\(result.silenceIntervals)")
    }

    func testCutRemovesSilenceForEveryIntensity() async throws {
        for intensity in QuickSilenceEngine.CutIntensity.allCases {
            let result = try await QuickSilenceEngine.cut(url: try fixtureURL, intensity: intensity, language: .en) { _ in }
            defer { try? FileManager.default.removeItem(at: result.outputURL) }
            let out = try await AVURLAsset(url: result.outputURL).load(.duration).seconds
            XCTAssertEqual(out, result.outputDuration, accuracy: 0.2)
            XCTAssertLessThan(out, 11, "\(intensity): \(out)s")      // ~10 s of silence removed
            XCTAssertGreaterThan(out, 7, "\(intensity): \(out)s")    // speech (~7.4 s) kept
            let audio = try await AVURLAsset(url: result.outputURL).loadTracks(withMediaType: .audio)
            XCTAssertFalse(audio.isEmpty)
        }
    }

    func testRejectsVideoWithoutAudio() async throws {
        let src = try fixtureURL
        let asset = AVURLAsset(url: src)
        let comp = AVMutableComposition()
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let v = try XCTUnwrap(videoTracks.first)
        let track = try XCTUnwrap(comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid))
        try track.insertTimeRange(CMTimeRange(start: .zero, duration: CMTime(seconds: 3, preferredTimescale: 600)), of: v, at: .zero)
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("noaudio-\(UUID()).mp4")
        let session = try XCTUnwrap(AVAssetExportSession(asset: comp, presetName: AVAssetExportPresetPassthrough))
        session.outputURL = out
        session.outputFileType = .mp4
        await session.export()
        defer { try? FileManager.default.removeItem(at: out) }
        do {
            _ = try await QuickSilenceEngine.cut(url: out, language: .en) { _ in }
            XCTFail("expected failure")
        } catch AudioAnalysisError.noAudioTrack {
        }
    }
}
