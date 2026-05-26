import Foundation
import OSLog

enum PipelineDiagnosticSource: String, Codable, Sendable {
    case appLaunch = "app_launch"
    case cache
    case live
    case synthetic
    case userEdit = "user_edit"
    case export
    case store
}

struct PipelineDiagnosticEvent: Codable, Sendable {
    let id: UUID
    let createdAt: Date
    let projectId: UUID?
    let stage: PipelineStage?
    let status: PipelineStageStatus?
    let source: PipelineDiagnosticSource
    let message: String
    let artifactCount: Int?
    let durationSeconds: Double?
    let metadata: [String: String]
}

@MainActor
enum PipelineDiagnostics {
    static var testLogURL: URL?

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.cutsense.app",
        category: "PipelineDiagnostics"
    )

    static func record(
        projectId: UUID?,
        stage: PipelineStage,
        status: PipelineStageStatus,
        source: PipelineDiagnosticSource,
        message: String,
        artifactCount: Int? = nil,
        durationSeconds: Double? = nil,
        metadata: [String: String] = [:]
    ) {
        writeEvent(
            projectId: projectId,
            stage: stage,
            status: status,
            source: source,
            message: message,
            artifactCount: artifactCount,
            durationSeconds: durationSeconds,
            metadata: metadata
        )
    }

    static func recordAppEvent(_ message: String, metadata: [String: String] = [:]) {
        writeEvent(
            projectId: nil,
            stage: nil,
            status: nil,
            source: .appLaunch,
            message: message,
            artifactCount: nil,
            durationSeconds: nil,
            metadata: metadata
        )
    }

    static func clear() {
        try? FileManager.default.removeItem(at: logURL)
    }

    static func loadEvents() -> [PipelineDiagnosticEvent] {
        guard let data = try? Data(contentsOf: logURL),
              let text = String(data: data, encoding: .utf8) else {
            return []
        }

        let decoder = JSONDecoder.pipelineDiagnostics
        return text
            .split(separator: "\n")
            .compactMap { line in
                guard let data = String(line).data(using: .utf8) else { return nil }
                return try? decoder.decode(PipelineDiagnosticEvent.self, from: data)
            }
    }

    private static func writeEvent(
        projectId: UUID?,
        stage: PipelineStage?,
        status: PipelineStageStatus?,
        source: PipelineDiagnosticSource,
        message: String,
        artifactCount: Int?,
        durationSeconds: Double?,
        metadata: [String: String]
    ) {
        let event = PipelineDiagnosticEvent(
            id: UUID(),
            createdAt: Date(),
            projectId: projectId,
            stage: stage,
            status: status,
            source: source,
            message: message,
            artifactCount: artifactCount,
            durationSeconds: durationSeconds,
            metadata: metadata
        )

        let stageName = stage?.rawValue ?? "app"
        let statusName = status?.rawValue ?? "event"
        logger.info("stage=\(stageName, privacy: .public) status=\(statusName, privacy: .public) source=\(source.rawValue, privacy: .public) message=\(message, privacy: .public)")
        append(event)
    }

    private static func append(_ event: PipelineDiagnosticEvent) {
        do {
            try FileManager.default.createDirectory(
                at: logURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            var data = try JSONEncoder.pipelineDiagnostics.encode(event)
            data.append(0x0A)

            if FileManager.default.fileExists(atPath: logURL.path) {
                let handle = try FileHandle(forWritingTo: logURL)
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.close()
            } else {
                try data.write(to: logURL, options: [.atomic])
            }
        } catch {
            #if DEBUG
            print("[CutSense] Pipeline diagnostic write failed: \(error.localizedDescription)")
            #endif
        }
    }

    private static var logURL: URL {
        if let testLogURL {
            return testLogURL
        }

        return URL.applicationSupportDirectory
            .appending(path: "CutSense", directoryHint: .isDirectory)
            .appending(path: "PipelineDiagnostics", directoryHint: .isDirectory)
            .appending(path: "pipeline-events.jsonl")
    }
}

private extension JSONDecoder {
    static var pipelineDiagnostics: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private extension JSONEncoder {
    static var pipelineDiagnostics: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}
