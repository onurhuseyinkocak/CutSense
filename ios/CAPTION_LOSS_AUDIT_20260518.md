# CutSense Caption Loss Audit — 2026-05-18

## Problem Statement

User reports: **NO captions appear in exported video.**

## Root Cause Analysis

The caption flow has **3 critical points** where captions can be lost:

### Point 1: Caption Generation (CaptionEngine.swift, lines 14-18)

```swift
let keptTranscriptSegments = transcription.segments.filter { segment in
    keptTimeRanges.contains { range in
        range.contains(segment.startTime) || range.contains(segment.endTime)
    }
}
```

**What this does:** Filters transcript segments to only those that fall within the rough cut's kept time ranges.

**Issue:** Uses **source time coordinates**. If a transcript segment's boundaries don't align exactly with keep segment boundaries, it might be incorrectly filtered out.

---

### Point 2: Caption Remapping (ExportService.swift, lines 85-87)

```swift
let remappedCaptions = TimelineMapper.resolveOverlaps(
    TimelineMapper.remapCaptions(captions, mapping: mapping)
)
```

**What this does:** Remaps captions from source time to clean timeline time using the keep/cut mapping.

**The remapping logic** (TimelineMapper.swift, lines 43-58):

```swift
static func remapCaptions(_ captions: [CaptionSegment], mapping: [Segment]) -> [CaptionSegment] {
    if mapping.isEmpty { return captions }  // ← EARLY EXIT 1

    return captions.compactMap { caption in
        guard let cleanStart = mapToClean(caption.startTime, mapping: mapping) else { return nil }  // ← FILTERS OUT
        let cleanEnd = mapToClean(caption.endTime, mapping: mapping)
            ?? mapToClean(caption.endTime - 0.05, mapping: mapping)
            ?? (cleanStart + (caption.endTime - caption.startTime))

        var remapped = caption
        remapped.startTime = cleanStart
        remapped.endTime = max(cleanEnd, cleanStart + 0.1)
        return remapped
    }
}
```

**Critical bug:** When `mapToClean(caption.startTime)` returns `nil`, the caption is **silently dropped** by the `compactMap`.

**When does `mapToClean()` return nil?** (TimelineMapper.swift, lines 33-40)

```swift
static func mapToClean(_ sourceTime: Double, mapping: [Segment]) -> Double? {
    for seg in mapping {
        if sourceTime >= seg.sourceStart && sourceTime <= seg.sourceEnd {
            return seg.cleanStart + (sourceTime - seg.sourceStart)
        }
    }
    return nil  // ← Returns nil if sourceTime doesn't fall in ANY keep segment
}
```

**This fails when:**
1. A caption's `startTime` is in a cut region (should have been filtered by CaptionEngine, but wasn't)
2. A caption's `startTime` is exactly at a cut boundary and floating-point precision causes it to miss the range check
3. The rough cut was modified after captions were generated, creating a mismatch

---

### Point 3: Video Composition Creation (ExportService.swift, lines 664-674)

```swift
let hasContent = !captions.isEmpty || !editDecisions.isEmpty
// ...
guard hasContent || hasGrade || showWatermark else { return nil }
```

**What this does:** Returns `nil` (no compositor) if there are no captions, no effects, no color grading, and no watermark.

**Issue:** If `remappedCaptions` is empty after remapping, and there are no edit effects, `buildVideoComposition()` returns `nil`. When the compositor is `nil`, **no overlay rendering happens**, so even if the compositor was supposed to run, it doesn't.

---

## Evidence Chain

### 1. CaptionEngine Generates Captions in Source Time
- File: `/Users/jinx/Documents/projeler/CutSense/ios/CutSense/Captions/CaptionEngine.swift`, lines 37-38
- Captions get `segment.startTime` and `segment.endTime` which are transcript segment times

### 2. ExportService Remaps Captions
- File: `/Users/jinx/Documents/projeler/CutSense/ios/CutSense/Export/ExportService.swift`, lines 85-87
- Debug output at line 91 shows: `"captions=\(captions.count)→\(remappedCaptions.count)"`
- **If remappedCaptions count drops to 0, user will see no captions but no error**

### 3. buildVideoComposition Returns Nil if No Captions
- File: `/Users/jinx/Documents/projeler/CutSense/ios/CutSense/Export/ExportService.swift`, lines 664-674
- If `videoComposition` is `nil`, line 241 sets `session.videoComposition = nil`
- When videoComposition is nil, no compositor runs, so drawCaption() is never called

### 4. Compositor Silently Passes Through
- File: `/Users/jinx/Documents/projeler/CutSense/ios/CutSense/Export/CaptionOverlayCompositor.swift`, lines 117-120
- If no overlay or color grade, it passes through source frame
- No error is logged, video exports successfully but without captions

---

## Where Captions Get Lost

### Scenario 1: All Captions Fall into Cut Regions

If the rough cut removes all regions where captions exist:
1. CaptionEngine filters transcript segments → finds some in kept ranges
2. ExportService remaps them → `mapToClean()` returns nil for all start times
3. `remappedCaptions` becomes empty array `[]`
4. `buildVideoComposition` sees empty captions + no edits → returns `nil`
5. Compositor never runs → no captions rendered

**Fix:** Return a warning if `remappedCaptions.isEmpty` but original `captions` was not empty.

---

### Scenario 2: Floating-Point Precision Mismatch

Caption startTime: `3.0000000001` (from transcript segment)
Keep segment range: `[3.0, 5.0]`

The range check `sourceTime >= seg.sourceStart && sourceTime <= seg.sourceEnd` would fail if sourceTime is just slightly outside the range.

**Fix:** Use tolerance-based comparison (e.g., `±0.05` seconds).

---

### Scenario 3: Rough Cut Modified After Captions Generated

1. User generates captions with original rough cut
2. User fine-tunes rough cut (adds/removes cuts)
3. Export uses **new rough cut for remapping** but **old captions** from original rough cut
4. Caption times don't match new keep segments → captions filtered out

**Fix:** Regenerate captions if rough cut changes, or warn user.

---

## Debug Output to Add

### ExportService.swift, line 91

Current:
```swift
print("[Export] Step 3: Remapped — captions=\(captions.count)→\(remappedCaptions.count), effects=...")
```

Add this check immediately after:
```swift
if captions.count > 0 && remappedCaptions.count == 0 {
    print("[Export] ⚠️  CRITICAL: All \(captions.count) captions were filtered out during remapping!")
    print("[Export] This means no captions will appear in the exported video.")
    print("[Export] Likely cause: caption times don't fall within kept segments after remapping.")
    for (i, cap) in captions.prefix(3).enumerated() {
        print("[Export]   Caption \(i): '\(cap.text.prefix(20))...' at \(String(format: "%.2f", cap.startTime))-\(String(format: "%.2f", cap.endTime))s")
    }
}
```

### TimelineMapper.swift, remapCaptions function

Add debug logging:
```swift
static func remapCaptions(_ captions: [CaptionSegment], mapping: [Segment]) -> [CaptionSegment] {
    if mapping.isEmpty {
        #if DEBUG
        print("[TimelineMapper] Mapping is empty (no cuts) — passing all \(captions.count) captions through unchanged")
        #endif
        return captions
    }

    var droppedCaptions: [CaptionSegment] = []
    let remapped = captions.compactMap { caption in
        guard let cleanStart = mapToClean(caption.startTime, mapping: mapping) else {
            droppedCaptions.append(caption)  // Track which ones were dropped
            return nil
        }
        // ... rest of logic
    }

    #if DEBUG
    if !droppedCaptions.isEmpty {
        print("[TimelineMapper] ⚠️  Dropped \(droppedCaptions.count) captions during remapping:")
        for (i, cap) in droppedCaptions.prefix(3).enumerated() {
            print("[TimelineMapper]   Dropped \(i): '\(cap.text.prefix(20))...' at \(String(format: "%.2f", cap.startTime))s (not in any keep segment)")
            let segInfo = mapping.map { "[\(String(format: "%.2f", $0.sourceStart))-\(String(format: "%.2f", $0.sourceEnd))]" }.joined(separator: " ")
            print("[TimelineMapper]   Keep segments: \(segInfo)")
        }
    }
    #endif

    return remapped
}
```

---

## Recommended Fixes (In Order of Impact)

### Fix 1: Tolerance-Based Time Mapping (HIGH PRIORITY)

File: `TimelineMapper.swift`, function `mapToClean`

**Current:**
```swift
if sourceTime >= seg.sourceStart && sourceTime <= seg.sourceEnd {
```

**Better:**
```swift
let tolerance = 0.05  // Allow 50ms tolerance for floating-point variance
if sourceTime >= (seg.sourceStart - tolerance) && sourceTime <= (seg.sourceEnd + tolerance) {
```

**Rationale:** Floating-point arithmetic often introduces tiny precision errors. A 50ms tolerance is imperceptible to the user but handles rounding errors.

---

### Fix 2: Warn User If All Captions Dropped (HIGH PRIORITY)

File: `ExportService.swift`, after line 87

```swift
if captions.count > 0 && remappedCaptions.count == 0 {
    errorMessage = "No captions could be placed in the exported video. This may happen if the cuts remove all regions where captions appear. Try adjusting your cuts."
    return nil
}
```

**Rationale:** Users will see a clear error message instead of a silent failure.

---

### Fix 3: Regenerate Captions If Rough Cut Changed (MEDIUM PRIORITY)

File: `EditScreen.swift`, function `startFullExport`

Before remapping, check if rough cut was modified:
```swift
let roughCutHash = roughCut.decisions.map { "\($0.startTime),\($0.endTime),\($0.action)" }.joined()
let originalHash = // (need to store after analysis)

if roughCutHash != originalHash {
    // User fine-tuned cuts — regenerate captions
    await captionVM.generate(
        transcription: transcript,
        roughCut: roughCut,
        template: template
    )
}
```

---

### Fix 4: Cap tion Generation Filtering Robustness (MEDIUM PRIORITY)

File: `CaptionEngine.swift`, lines 14-18

Use tolerance-based range checking:
```swift
let tolerance = 0.05
let keptTranscriptSegments = transcription.segments.filter { segment in
    keptTimeRanges.contains { range in
        let rangeWithTol = (range.lowerBound - tolerance)...(range.upperBound + tolerance)
        return rangeWithTol.contains(segment.startTime) || rangeWithTol.contains(segment.endTime)
    }
}
```

---

## Verification Checklist

After implementing fixes:

- [ ] Run `swift test` — all TimelineMapper tests should pass
- [ ] Add new test: "caption remapping survives floating-point variance"
- [ ] Add new test: "non-empty captions can't become empty after remapping without error"
- [ ] Export a test video, verify captions appear
- [ ] Fine-tune rough cut, export again, verify captions still appear
- [ ] Check debug logs for "CRITICAL" warnings

---

## Files Affected

| File | Issue | Severity | Fix |
|------|-------|----------|-----|
| `TimelineMapper.swift` | Floating-point precision loses captions | **HIGH** | Add tolerance to range check |
| `ExportService.swift` | Silent failure when all captions dropped | **HIGH** | Warn user with error message |
| `CaptionEngine.swift` | Initial filtering can miss captions | **MEDIUM** | Use tolerance in range check |
| `EditScreen.swift` | No detection of rough cut changes | **MEDIUM** | Regenerate captions if cut changed |
| `ExportService.swift` | No debug logging when captions lost | **MEDIUM** | Add detailed debug output |

---

## Testing Script

```swift
// TimelineMapperTests.swift — add new tests

@Test("remapCaptions survives floating-point variance")
func remapCaptionsFloatingPointVariance() {
    let decisions = [
        makeKeep(start: 0, end: 5),
        makeCut(start: 5, end: 10),
        makeKeep(start: 10, end: 20),
    ]
    let mapping = TimelineMapper.buildMapping(from: decisions)

    // Caption with floating-point variance in start time
    let captions = [
        makeCaption(start: 3.0000000001, end: 4, text: "first"),    // slightly past 3.0
        makeCaption(start: 4.9999999999, end: 5, text: "boundary"),  // just before 5.0
        makeCaption(start: 10.0000000001, end: 12, text: "second"),  // slightly past 10.0
    ]

    let remapped = TimelineMapper.remapCaptions(captions, mapping: mapping)
    #expect(remapped.count == 3, "Floating-point variance should not drop captions")
}

@Test("caption remapping warns if all captions dropped")
func remapCaptionsAllDropped() {
    let decisions = [
        makeKeep(start: 0, end: 3),
        makeCut(start: 3, end: 10),
    ]
    let mapping = TimelineMapper.buildMapping(from: decisions)

    // All captions in the cut region
    let captions = [
        makeCaption(start: 5, end: 7, text: "in cut zone"),
        makeCaption(start: 6, end: 8, text: "also in cut"),
    ]

    let remapped = TimelineMapper.remapCaptions(captions, mapping: mapping)
    #expect(remapped.count == 0, "Captions in cut zones should be dropped")
    // Caller (ExportService) should detect this and error
}
```

---

## Summary

**The exact point where captions get lost:**

1. **Best case:** Captions remapped successfully but coordinator composition not created because empty
   - Location: `ExportService.buildVideoComposition()` returns `nil` at line 674

2. **Worst case:** Captions filtered out during remapping with no error
   - Location: `TimelineMapper.remapCaptions()` compactMap at line 47
   - Cause: Caption startTime doesn't fall within any keep segment (floating-point variance or rough cut mismatch)

**Immediate action:**
1. Add tolerance to `mapToClean()` range check
2. Warn user if captions dropped
3. Add debug logging to see which captions were lost and why

