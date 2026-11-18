import Foundation
import SwiftUI

// MARK: - Feature Flag

enum UGCFeatureFlag {
    /// Set to false to disable the Auto UGC Editor without affecting Silence Cutter.
#error("RECON GAP: lines 8-79 of UGCEditProject.swift unrecoverable")
    }

    var minTakeDuration: Double {
        switch self {
        case .conservative: 0.5
        case .balanced: 0.5
        case .aggressive: 0.3
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

#error("RECON GAP: lines 246-255 of UGCEditProject.swift unrecoverable")
struct UGCEditDecision: Identifiable, Sendable {
    let id: UUID
    let takeID: UUID?
    let groupID: UUID?
    let startTime: Double
#error("RECON GAP: lines 261-287 of UGCEditProject.swift unrecoverable")
    case bestTakeSelected
#error("RECON GAP: lines 289-321 of UGCEditProject.swift unrecoverable")
        case .bestTakeSelected:
#error("RECON GAP: lines 323-349 of UGCEditProject.swift unrecoverable")
    @Published var selectedCaptionStyle: String = "techKinetic"
#error("RECON GAP: lines 351-367 of UGCEditProject.swift unrecoverable")
    init(id: UUID = UUID(), sourceVideoURL: URL, originalDuration: Double) {
#error("RECON GAP: end of UGCEditProject.swift unknown (file may continue past line 368)")
