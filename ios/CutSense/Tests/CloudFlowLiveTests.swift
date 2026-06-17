import Testing
import Foundation
@testable import CutSense

/// Marker so we can resolve the test bundle (which holds the sample videos).
private final class _CloudBundleToken {}

/// Live integration test for the cloud editing client: signs in, uploads a
/// bundled talking-head, polls the real backend job to completion. Exercises the
/// exact CloudJobClient + VideoCompressor code the UI uses, bypassing the
/// PhotosPicker (which can't be driven headlessly).
///
/// Network-dependent + needs the Mac poller running, so it is OFF by default and
/// only runs when CS_LIVE_CLOUD=1 is set in the test environment.
@Suite(.serialized)
struct CloudFlowLiveTests {
    @Test("cloud flow: signin → upload → poll → done")
    func liveFlow() async throws {
        guard ProcessInfo.processInfo.environment["CS_LIVE_CLOUD"] == "1" else {
            print("CS_LIVE_SKIP")
            return
        }
        print("CS_LIVE_RUN")

        // 1) auth (anonymous — same as the app does in DEBUG)
        _ = try await supabase.auth.signInAnonymously()

        // 2) bundled sample video
        let bundle = Bundle(for: _CloudBundleToken.self)
        let video = try #require(
            bundle.url(forResource: "whatsapp_test_video", withExtension: "mp4")
                ?? bundle.url(forResource: "cutsense_test_video", withExtension: "mp4")
        )

        // 3) compress + create job + upload (the real client path)
        let compressed = try await VideoCompressor.compress(video)
        let job = try await CloudJobClient.shared.createJob()
        try await CloudJobClient.shared.uploadRaw(fileURL: compressed, job: job)
        try await CloudJobClient.shared.enqueue(jobId: job.job_id)

        // 4) poll to a terminal state (≤ 3 min)
        var terminal: CloudJobStatus?
        for _ in 0..<90 {
            try await Task.sleep(for: .seconds(2))
            let s = try await CloudJobClient.shared.status(jobId: job.job_id)
            if s.status == "done" || s.status == "failed" { terminal = s; break }
        }

        let result = try #require(terminal, "job did not finish in time")
        #expect(result.status == "done", "render failed: \(result.error ?? "?")")
        #expect(result.final_url != nil, "no final video URL")

        // 5) the finished video downloads
        if let finalStr = result.final_url {
            let local = try await CloudJobClient.shared.download(finalStr)
            let size = (try? FileManager.default.attributesOfItem(atPath: local.path)[.size]) as? Int64 ?? 0
            #expect(size > 10_000, "final video too small (\(size) bytes)")
        }
    }
}
