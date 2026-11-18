import Foundation

// MARK: - Edit History (Undo/Redo)

/// Records every editable project instruction for undo/redo.
/// Each instruction is a reversible mutation on the project state.
struct EditHistory: Sendable, Codable {
    private(set) var undoStack: [EditInstruction] = []
    private(set) var redoStack: [EditInstruction] = []
    let maxHistorySize: Int

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    init(maxHistorySize: Int = 200) {
        self.maxHistorySize = maxHistorySize
    }

    /// Push a new instruction. Clears the redo stack (new branch).
    mutating func push(_ instruction: EditInstruction) {
        undoStack.append(instruction)
        redoStack.removeAll()
        if undoStack.count > maxHistorySize {
            undoStack.removeFirst(undoStack.count - maxHistorySize)
        }
    }

    /// Pop the last undo instruction. Returns nil if nothing to undo.
    mutating func undo() -> EditInstruction? {
        guard let instruction = undoStack.popLast() else { return nil }
        redoStack.append(instruction)
        return instruction
    }

    /// Pop the last redo instruction. Returns nil if nothing to redo.
    mutating func redo() -> EditInstruction? {
        guard let instruction = redoStack.popLast() else { return nil }
        undoStack.append(instruction)
        return instruction
    }

    mutating func clear() {
        undoStack.removeAll()
        redoStack.removeAll()
    }
}

// MARK: - Edit Instruction

/// A single reversible edit operation on the project.
struct EditInstruction: Sendable, Codable {
    let id: UUID
    let timestamp: Date
    let type: InstructionType
    let description: String

    /// The before-state snapshot for undo.
    let beforeData: InstructionData
    /// The after-state snapshot for redo.
    let afterData: InstructionData

    enum InstructionType: String, Codable, Sendable {
        case clipKeep
        case clipRemove
        case clipRestore
        case clipTrim
        case clipSplit
        case clipReplaceTake
        case clipReorder
        case captionEdit
        case captionSplit
        case captionMerge
        case captionStyleChange
        case captionPositionChange
        case captionWordEmphasis
        case captionAdd
        case captionRemove
        case motionAdd
        case motionRemove
        case motionUpdate
        case transitionAdd
        case transitionRemove
        case transitionUpdate
        case colorGradeChange
        case colorGradeUpdate
        case effectAdd
        case effectRemove
        case effectUpdate
        case audioEventAdd
        case audioEventRemove
        case audioEventUpdate
        case musicTrackAdd
        case musicTrackRemove
        case musicTrackUpdate
        case globalStyleChange
        case globalAspectChange
        case globalCanvasChange
    }

    enum InstructionData: Sendable, Codable {
        case clipClip(ClipDecision)
        case captionSegment(EDLCaptionSegment)
        case motionEvent(MotionEvent)
        case transitionEvent(TransitionEvent)
        case colorGrade(ColorGrade)
        case effectEvent(EffectEvent)
        case audioEvent(AudioEvent)
        case musicTrack(EDLMusicTrack)
        case clips([ClipDecision])
        case captions([EDLCaptionSegment])
        case motions([MotionEvent])
        case transitions([TransitionEvent])
        case colorGradeFull(ColorGrade)
        case effects([EffectEvent])
        case audioEvents([AudioEvent])
        case musicTrackFull(EDLMusicTrack)
        case style(EDLCaptionStyleName)
        case aspectRatio(EDLAspectRatio)
        case canvasSettings(CanvasSettings)
        case empty
    }

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        type: InstructionType,
        description: String,
        beforeData: InstructionData,
        afterData: InstructionData
    ) {
        self.id = id
        self.timestamp = timestamp
        self.type = type
        self.description = description
        self.beforeData = beforeData
        self.afterData = afterData
    }
}
