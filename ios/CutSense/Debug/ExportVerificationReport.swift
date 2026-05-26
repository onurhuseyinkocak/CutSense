import AVFoundation
import Foundation

struct ExportVerificationReport: Codable, Sendable {
    let timestamp: Date
    let outputPath: String
    let passed: Bool
    let fileSizeBytes: Int64?
    let duration: Double?
    let expectedDuration: Double?
    let durationDrift: Double?
    let resolution: String?
    let expectedResolution: String?
    let codec: String?
    let hasVideoTrack: Bool
    let hasAudioTrack: Bool
    let audioRMSDBFS: Double?
    let audioPeakDBFS: Double?
    let audioSampleCount: Int?
    let failedChecks: [String]

    var failureSummary: String {
        failedChecks.joined(separator: ", ")
    }

    init(
        timestamp: Date,
        outputPath: String,
        passed: Bool,
        fileSizeBytes: Int64?,
        duration: Double?,
        expectedDuration: Double?,
        durationDrift: Double?,
        resolution: String?,
        expectedResolution: String?,
        codec: String?,
        hasVideoTrack: Bool,
        hasAudioTrack: Bool,
        audioRMSDBFS: Double? = nil,
        audioPeakDBFS: Double? = nil,
        audioSampleCount: Int? = nil,
        failedChecks: [String]
    ) {
        self.timestamp = timestamp
        self.outputPath = outputPath
        self.passed = passed
        self.fileSizeBytes = fileSizeBytes
        self.duration = duration
        self.expectedDuration = expectedDuration
        self.durationDrift = durationDrift
        self.resolution = resolution
        self.expectedResolution = expectedResolution
        self.codec = codec
        self.hasVideoTrack = hasVideoTrack
        self.hasAudioTrack = hasAudioTrack
        self.audioRMSDBFS = audioRMSDBFS
        self.audioPeakDBFS = audioPeakDBFS
        self.audioSampleCount = audioSampleCount
        self.failedChecks = failedChecks
    }

    func save() {
        let reportsDirectory = URL.documentsDirectory
            .appending(path: "CutSense", directoryHint: .isDirectory)
            .appending(path: "Reports", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: reportsDirectory, withIntermediateDirectories: true)

        let seconds = Int(timestamp.timeIntervalSince1970.rounded())
        let fileURL = reportsDirectory.appending(path: "export_verification_\(seconds).json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(self) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }
}

enum ExportVerifier {
    static func verify(
        outputURL: URL,
        expectedDuration: Double?,
        expectedResolution: String?,
        minimumFileSizeBytes: Int64 = 16_384,
        minimumAudioRMSDBFS: Double = -55,
        minimumAudioPeakDBFS: Double = -45
    ) async -> ExportVerificationReport {
        let attributes = try? FileManager.default.attributesOfItem(atPath: outputURL.path)
        let fileSize = attributes?[.size] as? Int64
        var failedChecks: [String] = []

        if !FileManager.default.fileExists(atPath: outputURL.path) {
            failedChecks.append("file missing")
        }

        if (fileSize ?? 0) < minimumFileSizeBytes {
            failedChecks.append("file too small")
        }

        let asset = AVURLAsset(url: outputURL)
        let loadedDuration = try? await asset.load(.duration)
        let duration = loadedDuration.map(\.seconds).flatMap { seconds in
            seconds.isFinite && seconds > 0 ? seconds : nil
        }
        let videoTracks = (try? await asset.loadTracks(withMediaType: .video)) ?? []
        let audioTracks = (try? await asset.loadTracks(withMediaType: .audio)) ?? []
        let resolution = await resolutionString(for: videoTracks.first)
        let codec = await codecString(for: videoTracks.first)
        let audioLevels = await audioLevelReport(asset: asset, track: audioTracks.first)

        if duration == nil {
            failedChecks.append("duration unreadable")
        }

        if videoTracks.isEmpty {
            failedChecks.append("video track missing")
        }

        if audioTracks.isEmpty {
            failedChecks.append("audio track missing")
        } else if let audioLevels {
            if audioLevels.rmsDBFS < minimumAudioRMSDBFS || audioLevels.peakDBFS < minimumAudioPeakDBFS {
                failedChecks.append("audio silent")
            }
        } else {
            failedChecks.append("audio unreadable")
        }

        let durationDrift: Double?
        if let expectedDuration, let duration {
            let drift = abs(duration - expectedDuration)
            durationDrift = drift
            let tolerance = max(0.75, expectedDuration * 0.04)
            if drift > tolerance {
                failedChecks.append("duration drift \(drift.formatted(.number.precision(.fractionLength(2))))s")
            }
        } else {
            durationDrift = nil
        }

        if let expectedResolution, let resolution, expectedResolution != resolution {
            failedChecks.append("resolution \(resolution) != expected \(expectedResolution)")
        } else if expectedResolution != nil && resolution == nil {
            failedChecks.append("resolution unreadable")
        }

        return ExportVerificationReport(
            timestamp: Date(),
            outputPath: outputURL.path,
            passed: failedChecks.isEmpty,
            fileSizeBytes: fileSize,
            duration: duration,
            expectedDuration: expectedDuration,
            durationDrift: durationDrift,
            resolution: resolution,
            expectedResolution: expectedResolution,
            codec: codec,
            hasVideoTrack: !videoTracks.isEmpty,
            hasAudioTrack: !audioTracks.isEmpty,
            audioRMSDBFS: audioLevels?.rmsDBFS,
            audioPeakDBFS: audioLevels?.peakDBFS,
            audioSampleCount: audioLevels?.sampleCount,
            failedChecks: failedChecks
        )
    }

    private struct AudioLevelReport: Sendable {
        let rmsDBFS: Double
        let peakDBFS: Double
        let sampleCount: Int
    }

    private static func audioLevelReport(asset: AVURLAsset, track: AVAssetTrack?) async -> AudioLevelReport? {
        guard let track else { return nil }

        do {
            let reader = try AVAssetReader(asset: asset)
            let output = AVAssetReaderTrackOutput(
                track: track,
                outputSettings: [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVLinearPCMBitDepthKey: 16,
                    AVLinearPCMIsFloatKey: false,
                    AVLinearPCMIsBigEndianKey: false,
                    AVLinearPCMIsNonInterleaved: false
                ]
            )
            output.alwaysCopiesSampleData = false

            guard reader.canAdd(output) else { return nil }
            reader.add(output)
            guard reader.startReading() else { return nil }

            var sumSquares = 0.0
            var peak = 0.0
            var sampleCount = 0

            while let sampleBuffer = output.copyNextSampleBuffer() {
                guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
                    continue
                }

                let length = CMBlockBufferGetDataLength(blockBuffer)
                guard length > 0 else { continue }

                var data = Data(count: length)
                let copyStatus = data.withUnsafeMutableBytes { rawBuffer -> OSStatus in
                    guard let destination = rawBuffer.baseAddress else { return kCMBlockBufferBadPointerParameterErr }
                    return CMBlockBufferCopyDataBytes(
                        blockBuffer,
                        atOffset: 0,
                        dataLength: length,
                        destination: destination
                    )
                }
                guard copyStatus == noErr else { continue }

                data.withUnsafeBytes { rawBuffer in
                    let samples = rawBuffer.bindMemory(to: Int16.self)
                    for sample in samples {
                        let normalized = Double(sample) / Double(Int16.max)
                        let magnitude = abs(normalized)
                        peak = max(peak, magnitude)
                        sumSquares += normalized * normalized
                        sampleCount += 1
                    }
                }
            }

            guard sampleCount > 0, reader.status == .completed else {
                return nil
            }

            let rms = sqrt(sumSquares / Double(sampleCount))
            return AudioLevelReport(
                rmsDBFS: dbFS(rms),
                peakDBFS: dbFS(peak),
                sampleCount: sampleCount
            )
        } catch {
            return nil
        }
    }

    private static func dbFS(_ amplitude: Double) -> Double {
        guard amplitude.isFinite, amplitude > 0 else { return -120 }
        return max(-120, 20 * log10(amplitude))
    }

    private static func resolutionString(for track: AVAssetTrack?) async -> String? {
        guard let track,
              let naturalSize = try? await track.load(.naturalSize),
              let transform = try? await track.load(.preferredTransform) else {
            return nil
        }

        let transformed = naturalSize.applying(transform)
        let width = Int(abs(transformed.width).rounded())
        let height = Int(abs(transformed.height).rounded())
        return "\(width)x\(height)"
    }

    private static func codecString(for track: AVAssetTrack?) async -> String? {
        guard let track,
              let formatDescriptions = try? await track.load(.formatDescriptions),
              let formatDescription = formatDescriptions.first else {
            return nil
        }

        let code = CMFormatDescriptionGetMediaSubType(formatDescription)
        return fourCCString(code)
    }

    private static func fourCCString(_ code: FourCharCode) -> String {
        let bytes = [
            UInt8((code >> 24) & 0xff),
            UInt8((code >> 16) & 0xff),
            UInt8((code >> 8) & 0xff),
            UInt8(code & 0xff)
        ].filter { $0 != 0 }
        return String(bytes: bytes, encoding: .macOSRoman) ?? "\(code)"
    }
}
