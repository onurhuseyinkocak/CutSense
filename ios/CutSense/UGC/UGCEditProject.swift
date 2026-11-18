import Foundation
import SwiftUI

// MARK: - Feature Flag

enum UGCFeatureFlag {
    /// Set to false to disable the Auto UGC Editor without affecting Silence Cutter.
    static let isEnabled = true
}

// MARK: - Editing Intensity

enum UGCIntensity: String, CaseIterable, Identifiable, Sendable {
    case conservative
    case balanced
    case aggressive

    var id: String { rawValue }

    var title: String {
        title(for: .tr)
    }

    var detail: String {
        detail(for: .tr)
    }

    func title(for language: AppLanguage) -> String {
        switch self {
        case .conservative:
            appText(language, "Korumalı", "Conservative")
        case .balanced:
            appText(language, "Dengeli", "Balanced")
        case .aggressive:
            appText(language, "Cesur", "Aggressive")
        }
    }

    func detail(for language: AppLanguage) -> String {
        switch self {
        case .conservative:
            appText(language, "Yalnızca bariz hatalı çekimleri kaldırır. Belirsiz kararları onaya bırakır.", "Only removes obvious failed takes. Leaves uncertain decisions for review.")
        case .balanced:
            appText(language, "Muhtemel hataları kaldırır. Kırpma sınırlarını orta düzeyde tutar.", "Removes likely mistakes. Uses moderate cut boundaries.")
        case .aggressive:
            appText(language, "Dolgu ifadeleri fazla olan çekimleri kaldırır. Kırpma sınırlarını dar tutar.", "Removes filler-heavy takes. Uses tight cut boundaries.")
        }
    }

    var similarityThreshold: Float {
        switch self {
        case .conservative: 0.85
        case .balanced: 0.75
        case .aggressive: 0.65
        }
    }

    var uncertaintyThreshold: Float {
        switch self {
        case .conservative: 12
        case .balanced: 8
        case .aggressive: 5
        }
    }

    var silencePadStart: Double {
        switch self {
        case .conservative: 0.20
        case .balanced: 0.14
        case .aggressive: 0.10
        }
    }

    var silencePadEnd: Double {
        switch self {
        case .conservative: 0.25
        case .balanced: 0.18
        case .aggressive: 0.12
        }
    }

    var minTakeDuration: Double {
        switch self {
        case .conservative: 0.5
        case .balanced: 0.5
        case .aggressive: 0.3
        }
    }
}

/// Spoken language is independent from the app interface language.
enum UGCContentLanguage: String, CaseIterable, Identifiable, Sendable {
    case automatic
    case turkish
    case english
    case spanish
    case german
    case french
    case arabic

    var id: String { rawValue }

    func title(for interfaceLanguage: AppLanguage) -> String {
        switch self {
        case .automatic: return appText(interfaceLanguage, "Otomatik", "Auto")
        case .turkish: return "Türkçe"
        case .english: return "English"
        case .spanish: return "Español"
        case .german: return "Deutsch"
        case .french: return "Français"
        case .arabic: return "العربية"
        }
    }

    var locale: Locale {
        switch self {
        case .automatic, .turkish: return Locale(identifier: "tr-TR")
        case .english: return Locale(identifier: "en-US")
        case .spanish: return Locale(identifier: "es-ES")
        case .german: return Locale(identifier: "de-DE")
        case .french: return Locale(identifier: "fr-FR")
        case .arabic: return Locale(identifier: "ar-SA")
        }
    }

    /// Automatic must test the spoken content, not reuse the interface locale.
    /// The list is deliberately bounded so a long video does not trigger an
    /// unbounded recognition loop on device.
    var recognitionLocales: [Locale] {
        switch self {
        case .automatic:
            return [
                Locale(identifier: "tr-TR"), Locale(identifier: "en-US"),
                Locale(identifier: "es-ES"), Locale(identifier: "de-DE"),
                Locale(identifier: "fr-FR"), Locale(identifier: "ar-SA")
            ]
        default:
            return [locale]
        }
    }
}

// MARK: - UGC Data Models

/// A single take — one spoken attempt at a sentence or idea.
struct UGCTake: Identifiable, Sendable, Codable {
    let id: UUID
    var startTime: Double
    var endTime: Double
    var transcript: String
    var normalizedTranscript: String
    var wordTimings: [WordTiming]
    var speechConfidence: Float
    var completionScore: Float
    var fluencyScore: Float
    var audioQualityScore: Float
    var deliveryScore: Float
    var facePresenceScore: Float
    var mistakePenalty: Float
    var finalScore: Float
    var status: TakeStatus
    var rejectionReason: String?
    var groupID: UUID?
    var isRecovered: Bool

    enum TakeStatus: String, Codable, Sendable {
        case selected
        case rejected
        case uncertain
        case pending
    }

    struct WordTiming: Sendable, Codable {
        let word: String
        let startTime: Double
        let duration: Double

        var endTime: Double { startTime + duration }
    }

    init(
        id: UUID = UUID(),
        startTime: Double,
        endTime: Double,
        transcript: String,
        normalizedTranscript: String = "",
        wordTimings: [WordTiming] = [],
        speechConfidence: Float = 0,
        completionScore: Float = 0,
        fluencyScore: Float = 0,
        audioQualityScore: Float = 0,
        deliveryScore: Float = 0,
        facePresenceScore: Float = 0,
        mistakePenalty: Float = 0,
        finalScore: Float = 0,
        status: TakeStatus = .pending,
        rejectionReason: String? = nil,
        groupID: UUID? = nil,
        isRecovered: Bool = false
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.transcript = transcript
        self.normalizedTranscript = normalizedTranscript
        self.wordTimings = wordTimings
        self.speechConfidence = speechConfidence
        self.completionScore = completionScore
        self.fluencyScore = fluencyScore
        self.audioQualityScore = audioQualityScore
        self.deliveryScore = deliveryScore
        self.facePresenceScore = facePresenceScore
        self.mistakePenalty = mistakePenalty
        self.finalScore = finalScore
        self.status = status
        self.rejectionReason = rejectionReason
        self.groupID = groupID
        self.isRecovered = isRecovered
    }

    var duration: Double { max(0, endTime - startTime) }

    func scoreExplanation(for language: AppLanguage) -> String {
        guard status != .pending else {
            return appText(language, "Henüz değerlendirilmedi", "Not yet evaluated")
        }
        let scores: [(String, String, Float)] = [
            ("Konuşma Güveni", "Speech Confidence", speechConfidence * 100),
            ("Tamamlama", "Completion", completionScore * 100),
            ("Akıcılık", "Fluency", fluencyScore * 100),
            ("Ses Kalitesi", "Audio Quality", audioQualityScore * 100),
            ("Sunum", "Delivery", deliveryScore * 100),
            ("Yüz Görünürlüğü", "Face Presence", facePresenceScore * 100)
        ]
        let activeScores = scores.filter { $0.2 > 0 }
        let label = language == .tr ? "%" : "%"
        let parts = activeScores.map { "\($0.0)/\($0.1): \(label)\(Int($0.2))" }
        let base = parts.joined(separator: ", ")
        if mistakePenalty > 0 {
            let penaltyLabel = appText(language, "Hata Cezası", "Mistake Penalty")
            return base + ", \(penaltyLabel): -\(label)\(Int(mistakePenalty * 100))"
        }
        return base
    }
}

/// A group of repeated takes of the same sentence or idea.
struct UGCTakeGroup: Identifiable, Sendable {
    let id: UUID
    let takes: [UGCTake]
    let canonicalText: String
    let startTime: Double
    let endTime: Double
    var selectedTakeID: UUID?
    var isUncertain: Bool

    init(
        id: UUID = UUID(),
        takes: [UGCTake],
        canonicalText: String,
        startTime: Double,
        endTime: Double,
        selectedTakeID: UUID? = nil,
        isUncertain: Bool = false
    ) {
        self.id = id
        self.takes = takes
        self.canonicalText = canonicalText
        self.startTime = startTime
        self.endTime = endTime
        self.selectedTakeID = selectedTakeID
        self.isUncertain = isUncertain
    }

    var selectedTake: UGCTake? {
        takes.first(where: { $0.id == selectedTakeID })
    }

    var rejectedTakes: [UGCTake] {
        takes.filter { $0.id != selectedTakeID && $0.status == .rejected }
    }

    var pendingTakes: [UGCTake] {
        takes.filter { $0.status == .pending }
    }
}

/// A timeline segment in the final edit decision list.
struct TimelineSegment: Identifiable, Sendable {
    let id: UUID
    let sourceTakeID: UUID?
    let startTime: Double
    let endTime: Double
    let type: SegmentType
    let reasonCode: UGCReasonCode
    let reasonDescription: String

    enum SegmentType: String, Sendable {
        case keptTake
        case silence
        case removedTake
        case uncertain
        case manuallyRestored
    }
}

/// One visible timeline clip. `clean*` is what the user sees and edits;
/// `source*` is what AVFoundation consumes during render.
struct UGCEditableClip: Identifiable, Sendable {
    let id: UUID
    let decisionID: UUID
    let sourceStart: Double
    let sourceEnd: Double
    let cleanStart: Double
    let cleanEnd: Double

    var duration: Double { cleanEnd - cleanStart }
}

/// A final edit decision list item.
struct UGCEditDecision: Identifiable, Sendable {
    let id: UUID
    let takeID: UUID?
    let groupID: UUID?
    let startTime: Double
    let endTime: Double
#error("RECON GAP: lines 327-375 of UGCEditProject.swift unrecoverable")
            return appText(language, "Aşırı tereddüt", "Severe hesitation")
        case .accidentalSetupSpeech:
            return appText(language, "Hazırlık konuşması", "Setup speech")
        case .uncertainDuplicate:
            return appText(language, "Belirsiz tekrar", "Uncertain duplicate")
        case .manuallyRemoved:
            return appText(language, "Kullanıcı tarafından kaldırıldı", "Manually removed")
        case .manuallyRestored:
            return appText(language, "Kullanıcı tarafından geri alındı", "Manually restored")
        case .keptByUser:
            return appText(language, "Kullanıcı tarafından seçildi", "Selected by user")
        case .bestTakeSelected:
            return appText(language, "En iyi çekim seçildi", "Best take selected")
        }
    }
}

/// Full UGC edit project state.
@MainActor
final class UGCEditProject: ObservableObject {
    let id: UUID
    let sourceVideoURL: URL
    let originalDuration: Double

    @Published var phase: Phase = .idle
    @Published var intensity: UGCIntensity = .conservative
    @Published var transcriptResult: TranscriptionResult?
    @Published var audioSegments: [AudioSegment]?
    @Published var takes: [UGCTake] = []
    @Published var takeGroups: [UGCTakeGroup] = []
    @Published var editDecisions: [UGCEditDecision] = []
    @Published var timelineSegments: [TimelineSegment] = []
    @Published var captions: [CaptionSegment] = []
    @Published var finalCompositionURL: URL?
    @Published var removedTakes: [UGCTake] = []
    @Published var manuallyRestoredTakeIDs: Set<UUID> = []
    @Published var manuallyRemovedTakeIDs: Set<UUID> = []
    @Published var exportMetadata: UGCProcessor.ExportMetadata?
    @Published var faceResults: [UUID: FacePresenceAnalysisService.FacePresenceResult] = [:]
    @Published var silenceIntervals: [ClosedRange<Double>] = []
    @Published var selectedCaptionStyle: String = "subtitleMinimal"
    @Published var captionsEnabled: Bool = true
    @Published var sourceLikelyHasBurnedCaptions: Bool = false
    @Published var sfxEnabled: Bool = true

    enum Phase: Sendable {
        case idle
        case importing
        case analyzingAudio
        case transcribing
        case segmenting
        case findingRepeats
        case scoring
        case buildingEdit
        case reviewReady
        case exporting
        case done
        case failed(String)
    }

    init(id: UUID = UUID(), sourceVideoURL: URL, originalDuration: Double) {
        self.id = id
        self.sourceVideoURL = sourceVideoURL
        self.originalDuration = originalDuration
    }

    // MARK: - Computed Properties

    var originalDurationFormatted: String {
        formatDuration(originalDuration)
    }

    var editedDuration: Double {
        timelineSegments
            .filter { $0.type == .keptTake || $0.type == .manuallyRestored }
            .reduce(0) { $0 + ($1.endTime - $1.startTime) }
    }

    var editedDurationFormatted: String {
        formatDuration(editedDuration)
    }

    var timeSaved: Double {
        max(0, originalDuration - editedDuration)
    }

    var timeSavedFormatted: String {
        formatDuration(timeSaved)
    }

    var silenceSegmentCount: Int {
        editDecisions.filter { $0.reasonCode == .silence || $0.reasonCode == .longPause }.count
    }

    var removedTakeCount: Int {
        editDecisions.filter { $0.action == .remove && $0.reasonCode != .silence && $0.reasonCode != .longPause }.count
    }

    var uncertainDecisionCount: Int {
        editDecisions.filter { $0.action == .uncertain }.count
    }

    var takeGroupCount: Int {
        takeGroups.count
    }

    var failedTakeCount: Int {
        takes.filter { $0.status == .rejected }.count
    }

    var hasUncertainDecisions: Bool {
        uncertainDecisionCount > 0
    }

    private func formatDuration(_ seconds: Double) -> String {
        let s = Int(max(0, seconds.rounded()))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
