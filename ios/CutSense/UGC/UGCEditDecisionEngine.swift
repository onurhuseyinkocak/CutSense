import Foundation

/// Builds the final edit decision list from scored takes and take groups.
/// Preserves original chronological order, never reorders, never combines unrelated content.
enum UGCEditDecisionEngine {
    static func editableClips(from decisions: [UGCEditDecision]) -> [UGCEditableClip] {
        var cleanCursor = 0.0
        return decisions
            .filter { $0.action == .keep }
            .sorted { $0.startTime < $1.startTime }
            .compactMap { decision in
                let duration = decision.endTime - decision.startTime
                guard duration > 0.05 else { return nil }
                defer { cleanCursor += duration }
                return UGCEditableClip(
                    id: decision.id, decisionID: decision.id,
                    sourceStart: decision.startTime, sourceEnd: decision.endTime,
                    cleanStart: cleanCursor, cleanEnd: cleanCursor + duration
                )
            }
    }

    static func sourceTime(forCleanTime cleanTime: Double, clips: [UGCEditableClip]) -> Double? {
        guard let clip = clips.first(where: { cleanTime >= $0.cleanStart && cleanTime <= $0.cleanEnd }) else { return nil }
        return clip.sourceStart + (cleanTime - clip.cleanStart)
    }
    /// Build edit decisions from take groups.
    /// - Parameters:
    ///   - groups: The analyzed take groups (each group = one idea/sentence).
    ///   - originalDuration: Total original video duration.
    ///   - silenceIntervals: Silence intervals from audio analysis.
    ///   - intensity: Editing intensity setting.
    /// - Returns: Array of edit decisions in chronological order.
    static func buildEditDecisions(
        groups: [UGCTakeGroup],
        originalDuration: Double,
        silenceIntervals: [ClosedRange<Double>],
        intensity: UGCIntensity
    ) -> [UGCEditDecision] {
        guard !groups.isEmpty else { return [] }

        var decisions: [UGCEditDecision] = []

        // Sort groups chronologically
        let sortedGroups = groups.sorted { $0.startTime < $1.startTime }

        for group in sortedGroups {
            guard let selectedTake = group.selectedTake else {
                // No selection — uncertain group
                let bestGuess = group.takes.max(by: { $0.finalScore < $1.finalScore })
                if let bestGuess {
                    decisions.append(UGCEditDecision(
                        id: UUID(),
                        takeID: bestGuess.id,
                        groupID: group.id,
                        startTime: bestGuess.startTime,
                        endTime: bestGuess.endTime,
                        action: .uncertain,
                        reasonCode: .uncertainDuplicate,
                        reasonDescription: "İki çekim benzer puana sahipti, karar belirsiz / Two takes had similar scores, decision is uncertain"
                    ))
                }
                continue
            }

            // Keep the selected take
            decisions.append(UGCEditDecision(
                id: UUID(),
                takeID: selectedTake.id,
                groupID: group.id,
                startTime: selectedTake.startTime,
                endTime: selectedTake.endTime,
                action: group.isUncertain ? .uncertain : .keep,
                reasonCode: .bestTakeSelected,
                reasonDescription: selectionReason(for: selectedTake, in: group)
            ))

            // Rejected takes get removal decisions
            for rejectedTake in group.rejectedTakes {
                decisions.append(UGCEditDecision(
                    id: UUID(),
                    takeID: rejectedTake.id,
                    groupID: group.id,
                    startTime: rejectedTake.startTime,
                    endTime: rejectedTake.endTime,
#error("RECON GAP: lines 86-110 of UGCEditDecisionEngine.swift unrecoverable")
    static func buildTimelineSegments(from decisions: [UGCEditDecision]) -> [TimelineSegment] {
#error("RECON GAP: lines 112-144 of UGCEditDecisionEngine.swift unrecoverable")
    static func paddedKeepRanges(
        from decisions: [UGCEditDecision],
#error("RECON GAP: lines 147-160 of UGCEditDecisionEngine.swift unrecoverable")
    static func keepRanges(from decisions: [UGCEditDecision]) -> [ClosedRange<Double>] {
#error("RECON GAP: lines 162-218 of UGCEditDecisionEngine.swift unrecoverable")
    ) -> [UGCEditDecision] {
        let minSilenceToCut: Double
        switch intensity {
        case .conservative: minSilenceToCut = 0.8
        case .balanced: minSilenceToCut = 0.5
        case .aggressive: minSilenceToCut = 0.3
        }

        return silenceIntervals.compactMap { silenceRange -> UGCEditDecision? in
            let duration = silenceRange.upperBound - silenceRange.lowerBound
            guard duration >= minSilenceToCut else { return nil }

            // Don't cut silence that overlaps with kept takes (protect padding)
            let overlapsKeptContent = existingTakeRanges.contains { takeRange in
                takeRange.overlaps(silenceRange)
            }
            guard !overlapsKeptContent else { return nil }

            return UGCEditDecision(
                id: UUID(),
                takeID: nil,
                groupID: nil,
                startTime: silenceRange.lowerBound,
#error("RECON GAP: end of UGCEditDecisionEngine.swift unknown (file may continue past line 241)")
