#error("RECON GAP: lines 1-8 of PipelineModels.swift unrecoverable")
public struct CaptionWord: Sendable, Hashable {
#error("RECON GAP: lines 10-13 of PipelineModels.swift unrecoverable")
    public init(text: String, start: Double, end: Double, confidence: Float) {
#error("RECON GAP: lines 15-29 of PipelineModels.swift unrecoverable")
    public init(words: [CaptionWord], language: String, fullText: String, durationSeconds: Double) {
#error("RECON GAP: lines 31-37 of PipelineModels.swift unrecoverable")
// MARK: - Edit Mode
#error("RECON GAP: lines 39-39 of PipelineModels.swift unrecoverable")
public enum CutSenseEditMode: String, Sendable, CaseIterable {
    case automaticEdit = "automatic_edit"
#error("RECON GAP: lines 42-48 of PipelineModels.swift unrecoverable")
        case .automaticEdit: "Auto Edit"
#error("RECON GAP: lines 50-58 of PipelineModels.swift unrecoverable")
        case .automaticEdit: "wand.and.stars"
#error("RECON GAP: lines 60-68 of PipelineModels.swift unrecoverable")
        case .automaticEdit, .silenceCut:
#error("RECON GAP: lines 70-77 of PipelineModels.swift unrecoverable")
        case .automaticEdit, .captionsOnly:
#error("RECON GAP: lines 79-86 of PipelineModels.swift unrecoverable")
        case .automaticEdit, .sfxOnly:
#error("RECON GAP: lines 88-95 of PipelineModels.swift unrecoverable")
        case .automaticEdit, .visualEffectsOnly:
#error("RECON GAP: lines 97-103 of PipelineModels.swift unrecoverable")
        self == .automaticEdit
#error("RECON GAP: lines 105-108 of PipelineModels.swift unrecoverable")
        case .automaticEdit, .captionsOnly, .visualEffectsOnly:
#error("RECON GAP: lines 110-117 of PipelineModels.swift unrecoverable")
        case .automaticEdit: "Export Auto Edit"
#error("RECON GAP: lines 119-127 of PipelineModels.swift unrecoverable")
        case .automaticEdit: "Türkçe model hazırlanıyor…"
#error("RECON GAP: lines 129-137 of PipelineModels.swift unrecoverable")
        case .automaticEdit: "Kurgu planı hazırlanıyor…"
#error("RECON GAP: lines 139-147 of PipelineModels.swift unrecoverable")
        case .automaticEdit: "Altyazılar ve efektler yerleştiriliyor…"
        case .silenceCut: "Kesilmiş timeline hazırlanıyor…"
#error("RECON GAP: lines 150-157 of PipelineModels.swift unrecoverable")
        case .automaticEdit: "Görsel + ses tasarımı üretiliyor…"
#error("RECON GAP: lines 159-168 of PipelineModels.swift unrecoverable")
public enum CaptionStyleName: String, Sendable, CaseIterable {
#error("RECON GAP: lines 170-176 of PipelineModels.swift unrecoverable")
public enum CaptionPosition: String, Sendable {
#error("RECON GAP: lines 178-208 of PipelineModels.swift unrecoverable")
    public init(localURL: URL, cleanStart: Double, cleanEnd: Double, kind: AssetKind, source: AssetSource, keyword: String) {
#error("RECON GAP: lines 210-219 of PipelineModels.swift unrecoverable")

public enum Mood: String, Sendable, CaseIterable {
    case energetic
    case chill
    case dramatic
    case comedic
    case emotional
    case subtle
}

public enum SFXKind: String, Sendable {
    case whoosh
    case pop
    case riser
    case ding
    case impact
    case transition
}

public struct SFXPlacement: Sendable {
    public let url: URL
    public let cleanTime: Double
    public let gain: Float
    public let kind: SFXKind
    public init(url: URL, cleanTime: Double, gain: Float, kind: SFXKind) {
        self.url = url
        self.cleanTime = cleanTime
        self.gain = gain
        self.kind = kind
    }
}

public struct DuckingRange: Sendable {
    public let start: Double
    public let end: Double
    public init(start: Double, end: Double) {
        self.start = start
        self.end = end
    }
}

/// Full audio plan for a single render. `musicURL` may be nil if the
/// curated library is empty or no match for the mood; in that case only
/// SFX + source audio survive.
public struct AudioPlan: Sendable {
    public let musicURL: URL?
    public let mood: Mood
    public let bpm: Double
    public let beats: [Double]
    public let sfxPlacements: [SFXPlacement]
    public let duckingRanges: [DuckingRange]
    public init(
        musicURL: URL?,
        mood: Mood,
        bpm: Double,
        beats: [Double],
        sfxPlacements: [SFXPlacement],
        duckingRanges: [DuckingRange]
    ) {
        self.musicURL = musicURL
        self.mood = mood
        self.bpm = bpm
        self.beats = beats
        self.sfxPlacements = sfxPlacements
        self.duckingRanges = duckingRanges
    }
}

// MARK: - Speech Range (auto-cut)

/// A speech-only window in the source video. Composition keeps these
#error("RECON GAP: lines 291-291 of PipelineModels.swift unrecoverable")
public struct SpeechRange: Sendable {
#error("RECON GAP: lines 293-295 of PipelineModels.swift unrecoverable")
    public init(sourceStart: Double, sourceEnd: Double, cleanStart: Double) {
#error("RECON GAP: lines 297-315 of PipelineModels.swift unrecoverable")
    public init(
#error("RECON GAP: lines 317-351 of PipelineModels.swift unrecoverable")
    public init(stage: Stage, fraction: Double, message: String) {
#error("RECON GAP: lines 353-360 of PipelineModels.swift unrecoverable")
public extension Array where Element == SpeechRange {
#error("RECON GAP: end of PipelineModels.swift unknown (file may continue past line 361)")
