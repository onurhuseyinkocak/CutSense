import Foundation
import SwiftUI

// MARK: - UGC Project (Non-Destructive Edit Decision List)

/// The core persistent project model for the AI UGC Editor.
/// Every AI action becomes an editable project instruction.
/// Original source videos are NEVER modified.
/// Saving/reopening a project must reproduce exactly the same edit.
///
/// This is a plain class (no @MainActor) so Codable serialization
/// works without isolation boundary issues. SwiftUI observation is
/// handled via `@Observable` (iOS 17+) or manual `objectWillChange`.
final class UGCProject: ObservableObject, Codable {
    // MARK: - Schema

    let schemaVersion: EDLSchemaVersion
    let projectID: UUID
    let createdAt: Date
    @Published var updatedAt: Date

    // MARK: - Source Media

    @Published var sourceMedia: [SourceMedia]

    // MARK: - Transcript (canonical, never mutated by edits)

    @Published var transcriptWords: [TranscriptWord]
    @Published var fullTranscriptText: String
    @Published var detectedLanguage: String

    // MARK: - Edit Decision List

    @Published var clips: [ClipDecision]
    @Published var captionSegments: [EDLCaptionSegment]
    @Published var motionEvents: [MotionEvent]
    @Published var transitionEvents: [TransitionEvent]
    @Published var colorGrade: ColorGrade
    @Published var effectEvents: [EffectEvent]
    @Published var audioEvents: [AudioEvent]
    @Published var musicTrack: EDLMusicTrack?

    // MARK: - Project Settings

    @Published var editingStyle: EditingStyle
    @Published var aspectRatio: EDLAspectRatio
    @Published var canvasSettings: CanvasSettings
    @Published var exportSettings: ExportSettings
    @Published var brollSuggestions: [BrollSuggestion]

    // MARK: - Edit History

    var editHistory: EditHistory

    // MARK: - Analysis Cache (persisted)

    @Published var silenceIntervals: [CodableRange]
    @Published var waveformCacheURLs: [String: String]  // sourceMediaID → waveform path
    @Published var thumbnailCacheURLs: [String: String]  // sourceMediaID → thumbnail path

    // MARK: - Phase Tracking

    enum ProcessingPhase: Codable, Sendable {
        case idle
        case importing
        case mediaValidation
        case proxyGeneration
        case audioExtraction
        case speechTranscription
        case transcriptVerification
        case silenceFillerAnalysis
        case takeComparison
        case bestTakeSelection
        case editStructure
        case captionSegmentation
        case visualAnalysis
        case motionPlan
        case transitionPlan
        case colorGradePlan
        case soundDesignPlan
        case previewComposition
        case editableTimeline
        case completed
        case failed(String)

        var displayName: String {
            switch self {
            case .idle: "Idle"
            case .importing: "Importing"
            case .mediaValidation: "Validating Media"
            case .proxyGeneration: "Generating Proxy"
            case .audioExtraction: "Extracting Audio"
            case .speechTranscription: "Transcribing"
            case .transcriptVerification: "Verifying Transcript"
            case .silenceFillerAnalysis: "Analyzing Silence"
            case .takeComparison: "Comparing Takes"
            case .bestTakeSelection: "Selecting Best Takes"
            case .editStructure: "Building Edit"
            case .captionSegmentation: "Segmenting Captions"
            case .visualAnalysis: "Analyzing Visuals"
            case .motionPlan: "Planning Motion"
            case .transitionPlan: "Planning Transitions"
            case .colorGradePlan: "Planning Color Grade"
            case .soundDesignPlan: "Planning Sound Design"
            case .previewComposition: "Composing Preview"
            case .editableTimeline: "Building Timeline"
            case .completed: "Completed"
            case .failed(let msg): "Failed: \(msg)"
            }
        }
    }

    @Published var processingPhase: ProcessingPhase
    @Published var processingProgress: Double
    @Published var processingError: String?

    // MARK: - Coding Keys

    enum CodingKeys: String, CodingKey {
        case schemaVersion, projectID, createdAt, updatedAt
        case sourceMedia
        case transcriptWords, fullTranscriptText, detectedLanguage
        case clips, captionSegments, motionEvents, transitionEvents
        case colorGrade, effectEvents, audioEvents, musicTrack
        case editingStyle, aspectRatio, canvasSettings, exportSettings, brollSuggestions
        case editHistory
        case silenceIntervals
        case waveformCacheURLs, thumbnailCacheURLs
        case processingPhase, processingProgress, processingError
    }

    // MARK: - Init

    init(
        projectID: UUID = UUID(),
        createdAt: Date = Date(),
        sourceMedia: [SourceMedia] = [],
        editingStyle: EditingStyle = .cleanUGC,
        aspectRatio: EDLAspectRatio = .vertical916
    ) {
        self.schemaVersion = .current
        self.projectID = projectID
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.sourceMedia = sourceMedia
        self.transcriptWords = []
        self.fullTranscriptText = ""
        self.detectedLanguage = "en"
        self.clips = []
        self.captionSegments = []
        self.motionEvents = []
        self.transitionEvents = []
        self.colorGrade = ColorGrade()
        self.effectEvents = []
        self.audioEvents = []
        self.musicTrack = nil
        self.editingStyle = editingStyle
        self.aspectRatio = aspectRatio
        self.canvasSettings = CanvasSettings()
        self.exportSettings = ExportSettings()
        self.brollSuggestions = []
        self.editHistory = EditHistory()
        self.silenceIntervals = []
        self.waveformCacheURLs = [:]
        self.thumbnailCacheURLs = [:]
        self.processingPhase = .idle
        self.processingProgress = 0
        self.processingError = nil
    }

    // MARK: - Computed Properties

    var totalSourceDuration: Double {
        sourceMedia.reduce(0) { $0 + $1.duration }
    }

    var editedDuration: Double {
        clips
            .filter { $0.action == .keep || $0.action == .uncertain }
            .reduce(0) { $0 + $1.sourceDuration }
    }

    var keptClipCount: Int {
        clips.filter { $0.action == .keep || $0.action == .uncertain }.count
    }

    var removedClipCount: Int {
        clips.filter { $0.action == .remove }.count
    }

    var hasUnsavedChanges: Bool {
        editHistory.canUndo
    }

    // MARK: - Codable

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(projectID, forKey: .projectID)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(sourceMedia, forKey: .sourceMedia)
        try container.encode(transcriptWords, forKey: .transcriptWords)
        try container.encode(fullTranscriptText, forKey: .fullTranscriptText)
        try container.encode(detectedLanguage, forKey: .detectedLanguage)
        try container.encode(clips, forKey: .clips)
        try container.encode(captionSegments, forKey: .captionSegments)
        try container.encode(motionEvents, forKey: .motionEvents)
        try container.encode(transitionEvents, forKey: .transitionEvents)
        try container.encode(colorGrade, forKey: .colorGrade)
        try container.encode(effectEvents, forKey: .effectEvents)
        try container.encode(audioEvents, forKey: .audioEvents)
        try container.encodeIfPresent(musicTrack, forKey: .musicTrack)
        try container.encode(editingStyle, forKey: .editingStyle)
        try container.encode(aspectRatio, forKey: .aspectRatio)
        try container.encode(canvasSettings, forKey: .canvasSettings)
        try container.encode(exportSettings, forKey: .exportSettings)
        try container.encode(brollSuggestions, forKey: .brollSuggestions)
        try container.encode(editHistory, forKey: .editHistory)
#error("RECON GAP: lines 221-225 of UGCProject.swift unrecoverable")
        try container.encodeIfPresent(processingError, forKey: .processingError)
#error("RECON GAP: lines 227-228 of UGCProject.swift unrecoverable")
    required init(from decoder: Decoder) throws {
#error("RECON GAP: lines 230-243 of UGCProject.swift unrecoverable")
        effectEvents = try container.decode([EffectEvent].self, forKey: .effectEvents)
#error("RECON GAP: lines 245-257 of UGCProject.swift unrecoverable")
        processingError = try container.decodeIfPresent(String.self, forKey: .processingError)
#error("RECON GAP: lines 259-290 of UGCProject.swift unrecoverable")
    init(_ range: ClosedRange<Double>) {
#error("RECON GAP: lines 292-295 of UGCProject.swift unrecoverable")
    init(lowerBound: Double, upperBound: Double) {
#error("RECON GAP: lines 297-315 of UGCProject.swift unrecoverable")
    init(
#error("RECON GAP: end of UGCProject.swift unknown (file may continue past line 316)")
