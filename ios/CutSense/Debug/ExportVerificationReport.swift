import Foundation

/// Post-export verification report — captures all pipeline metrics for debugging.
/// Saved as JSON to Documents/CutSense/Reports/ after each export.
struct ExportVerificationReport: Codable, Sendable {
    let timestamp: Date
    let videoFileName: String

    // Pipeline stages
    let transcription: TranscriptionMetrics
    let roughCut: RoughCutMetrics
    let captions: CaptionMetrics
    let editPlan: EditPlanMetrics
    let export: ExportMetrics
    let qualityScore: Int

    struct TranscriptionMetrics: Codable, Sendable {
        let segmentCount: Int
        let language: String
        let averageConfidence: Float
        let totalDuration: Double
    }

    struct RoughCutMetrics: Codable, Sendable {
        let originalDuration: Double
        let cleanDuration: Double
        let retentionPercent: Double
        let keepCount: Int
        let cutCount: Int
        let reviewCount: Int
        let fillersRemoved: Int
        let restartsDetected: Int
        let duplicatesDetected: Int
    }

    struct CaptionMetrics: Codable, Sendable {
        let totalCaptions: Int
        let hookCount: Int
        let regularCount: Int
        let conclusionCount: Int
        let revealCount: Int
        let keywordCount: Int
        let averageLength: Double
        let maxLength: Int
        let sceneBehaviorBreakdown: [String: Int]
    }

    struct EditPlanMetrics: Codable, Sendable {
        let totalEffects: Int
        let sfxCount: Int
        let zoomCount: Int
        let shakeCount: Int
        let flashCount: Int
        let colorShiftCount: Int
        let averageIntensity: Float
        let effectsPerMinute: Double
    }

    struct ExportMetrics: Codable, Sendable {
        let outputDuration: Double
        let outputFileSize: Int64
        let exportTimeSeconds: Double
        let resolution: String
        let codec: String
    }

    // MARK: - Save to disk

    func save() {
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        let reportsDir = docs.appendingPathComponent("CutSense/Reports", isDirectory: true)

        try? fm.createDirectory(at: reportsDir, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let fileName = "report_\(formatter.string(from: timestamp)).json"
        let fileURL = reportsDir.appendingPathComponent(fileName)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        if let data = try? encoder.encode(self) {
            try? data.write(to: fileURL)
            #if DEBUG
            print("[CutSense] Report saved: \(fileURL.lastPathComponent)")
            #endif
        }
    }

    // MARK: - Builder from pipeline results

    static func build(
        videoFileName: String,
        transcription: TranscriptionResult,
        roughCut: RoughCutResult,
        analysisOutput: SmartTranscriptAnalyzer.AnalysisOutput?,
        captions: [CaptionSegment],
        editPlan: EditPlan,
        qualityReport: QualityReport,
        outputDuration: Double,
        outputFileSize: Int64,
        exportTime: Double,
        resolution: String = "1080x1920",
        codec: String = "H.264"
    ) -> ExportVerificationReport {
        let captionRoles = Dictionary(grouping: captions, by: \.role)
        let behaviors = Dictionary(grouping: captions, by: \.sceneBehavior)
            .mapValues(\.count)
            .reduce(into: [String: Int]()) { $0[$1.key.rawValue] = $1.value }

        let effectTypes = Dictionary(grouping: editPlan.decisions, by: \.type)

        let avgLen = captions.isEmpty ? 0 : captions.reduce(0.0) { $0 + Double($1.text.count) } / Double(captions.count)
        let maxLen = captions.map(\.text.count).max() ?? 0

        let cleanDur = roughCut.cleanDuration
        let epm = cleanDur > 0 ? Double(editPlan.totalEffects) / (cleanDur / 60.0) : 0

        return ExportVerificationReport(
            timestamp: Date(),
            videoFileName: videoFileName,
            transcription: TranscriptionMetrics(
                segmentCount: transcription.segments.count,
                language: transcription.language,
                averageConfidence: transcription.overallConfidence,
                totalDuration: transcription.segments.last?.endTime ?? 0
            ),
            roughCut: RoughCutMetrics(
                originalDuration: roughCut.originalDuration,
                cleanDuration: roughCut.cleanDuration,
                retentionPercent: roughCut.originalDuration > 0
                    ? (roughCut.cleanDuration / roughCut.originalDuration) * 100 : 0,
                keepCount: roughCut.keepSegments.count,
                cutCount: roughCut.cutSegments.count,
                reviewCount: roughCut.reviewSegments.count,
                fillersRemoved: analysisOutput?.fillersRemoved ?? 0,
                restartsDetected: analysisOutput?.restartsDetected ?? 0,
                duplicatesDetected: analysisOutput?.duplicatesDetected ?? 0
            ),
            captions: CaptionMetrics(
                totalCaptions: captions.count,
                hookCount: captionRoles[.hook]?.count ?? 0,
                regularCount: captionRoles[.regular]?.count ?? 0,
                conclusionCount: captionRoles[.conclusion]?.count ?? 0,
                revealCount: captionRoles[.reveal]?.count ?? 0,
                keywordCount: captionRoles[.keyword]?.count ?? 0,
                averageLength: avgLen,
                maxLength: maxLen,
                sceneBehaviorBreakdown: behaviors
            ),
            editPlan: EditPlanMetrics(
                totalEffects: editPlan.totalEffects,
                sfxCount: effectTypes[.sfx]?.count ?? 0,
                zoomCount: effectTypes[.zoom]?.count ?? 0,
                shakeCount: effectTypes[.shake]?.count ?? 0,
                flashCount: effectTypes[.flash]?.count ?? 0,
                colorShiftCount: effectTypes[.colorShift]?.count ?? 0,
                averageIntensity: editPlan.averageIntensity,
                effectsPerMinute: epm
            ),
            export: ExportMetrics(
                outputDuration: outputDuration,
                outputFileSize: outputFileSize,
                exportTimeSeconds: exportTime,
                resolution: resolution,
                codec: codec
            ),
            qualityScore: qualityReport.score
        )
    }
}
