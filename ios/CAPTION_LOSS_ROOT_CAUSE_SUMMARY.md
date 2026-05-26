# CutSense Caption Loss — Root Cause Summary

## The Problem
User reports: **Exported videos have NO captions**, despite captions appearing in the preview.

## Where Captions Get Lost

The caption flow has **3 checkpoints** where loss occurs:

### 1️⃣ TimelineMapper.remapCaptions() — Line 47 (CRITICAL)

**File:** `/Users/jinx/Documents/projeler/CutSense/ios/CutSense/Export/TimelineMapper.swift`

```swift
return captions.compactMap { caption in
    guard let cleanStart = mapToClean(caption.startTime, mapping: mapping) else { return nil }  // ← FILTERS OUT SILENTLY
    // ...
}
```

**What happens:** When `mapToClean()` returns `nil`, the caption is **dropped** by `compactMap`. No error, no warning. Just gone.

**Why it returns nil:**

```swift
static func mapToClean(_ sourceTime: Double, mapping: [Segment]) -> Double? {
    for seg in mapping {
        if sourceTime >= seg.sourceStart && sourceTime <= seg.sourceEnd {
            return seg.cleanStart + (sourceTime - seg.sourceStart)
        }
    }
    return nil  // ← Caption start time wasn't in any keep segment
}
```

**When this fails:**
- Caption start time is in a cut region (was supposed to be filtered, but wasn't)
- Floating-point precision error causes `3.0000000001` to not match `sourceStart == 3.0`
- Rough cut was modified after captions were generated

---

### 2️⃣ ExportService.buildVideoComposition() — Line 674 (SECONDARY)

**File:** `/Users/jinx/Documents/projeler/CutSense/ios/CutSense/Export/ExportService.swift`

```swift
let hasContent = !captions.isEmpty || !editDecisions.isEmpty
guard hasContent || hasGrade || showWatermark else { return nil }
```

**What happens:** If remapped captions are empty AND there are no visual effects, the function returns `nil` (no compositor created). When `videoComposition` is `nil`, the `CaptionOverlayCompositor` never runs.

**The chain:**
- Captions all filtered out by `remapCaptions()` → `remappedCaptions = []`
- No visual effects exist → `editDecisions = []`
- Template has no color grade → `hasGrade = false`
- No watermark → `showWatermark = false`
- Result: `buildVideoComposition()` returns `nil` → no compositor → no captions

---

### 3️⃣ CaptionOverlayCompositor.startRequest() — Line 117 (TERTIARY)

**File:** `/Users/jinx/Documents/projeler/CutSense/ios/CutSense/Export/CaptionOverlayCompositor.swift`

```swift
guard hasOverlay || hasGrade || instruction.showWatermark else {
    request.finish(withComposedVideoFrame: sourceBuffer)  // ← Just passes through
    return
}
```

**What happens:** If there's no overlay (no active captions at this frame), just passes through source frame. Video exports, user sees no captions.

---

## The Exact Failure Point

**Most likely scenario:**

1. User analyzes video → rough cut created → captions generated from transcript segments in source time
2. User fine-tunes rough cut (adds/removes cuts)
3. Export starts:
   - Line 85-87: `remapCaptions()` tries to map captions from source time to clean timeline
   - `mapToClean()` fails for ALL captions because they no longer align with new keep segments
   - `remappedCaptions` becomes `[]`
   - Line 91: Debug log shows `"captions=5→0"` (5 captions → 0 after remapping)
   - Line 674: `buildVideoComposition()` returns `nil` (no content)
   - Line 241: `videoComposition = nil` assigned to export session
   - Compositor never runs → **no captions rendered**
   - Video exports successfully (no error) but user sees NO captions

---

## Evidence in Code

### Caption Generation (Source Time)
**File:** `CaptionEngine.swift`, lines 36-42

```swift
captions.append(CaptionSegment(
    startTime: segment.startTime,  // ← Transcript segment time (source time)
    endTime: segment.endTime,
    text: segment.text,
    role: role,
    style: style
))
```

### Caption Remapping (Clean Time)
**File:** `ExportService.swift`, lines 85-87

```swift
let remappedCaptions = TimelineMapper.resolveOverlaps(
    TimelineMapper.remapCaptions(captions, mapping: mapping)
)
```

### Silent Failure Check
**File:** `ExportService.swift`, line 91

```swift
print("[Export] Step 3: Remapped — captions=\(captions.count)→\(remappedCaptions.count), ...")
// ↑ If this prints "captions=5→0", captions have been lost
// ↓ But no error is thrown!
```

### Compositor Not Created
**File:** `ExportService.swift`, line 189

```swift
let videoComposition = buildVideoComposition(
    timeline: timeline,
    captions: remappedCaptions,  // ← Empty!
    editDecisions: remappedEdits
)
// buildVideoComposition() will return nil if remappedCaptions is empty
```

---

## Why This Wasn't Caught

1. **No error is thrown** — video exports successfully
2. **No user warning** — silent failure
3. **Compositor still runs** — but with empty captions array
4. **Debug log exists** (line 91) — but only in DEBUG builds, user never sees it
5. **Tests pass** — because tests use consistent rough cuts, no timing variance

---

## Quick Diagnosis

**To confirm this is the issue**, check the device logs during export:

```
[Export] Step 3: Remapped — captions=5→0, effects=0→0
```

If you see `captions=N→0` where N > 0, **all captions were filtered out during remapping**, and this is the exact cause.

---

## The Fix (3 Steps)

### Step 1: Tolerance-Based Time Matching
**File:** `TimelineMapper.swift`, function `mapToClean()`

```swift
// BEFORE:
if sourceTime >= seg.sourceStart && sourceTime <= seg.sourceEnd {

// AFTER:
let tolerance = 0.05  // 50ms tolerance for floating-point variance
if sourceTime >= (seg.sourceStart - tolerance) && sourceTime <= (seg.sourceEnd + tolerance) {
```

### Step 2: User Warning if All Captions Dropped
**File:** `ExportService.swift`, after line 87

```swift
if captions.count > 0 && remappedCaptions.count == 0 {
    errorMessage = "No captions could be placed in the video. Try adjusting your cuts or regenerating captions."
    return nil
}
```

### Step 3: Force Recomputation if Rough Cut Changed
**File:** `EditScreen.swift`, function `startFullExport()`

```swift
// If rough cut was modified since captions were generated, regenerate them
let roughCutModified = /* check if rough cut changed */
if roughCutModified {
    await captionVM.generate(
        transcription: transcript,
        roughCut: roughCut,
        template: template
    )
}
```

---

## Files to Review

| File | Line(s) | Issue |
|------|---------|-------|
| `TimelineMapper.swift` | 33-40 | Floating-point precision in range check |
| `TimelineMapper.swift` | 43-58 | Silent caption filtering via compactMap |
| `ExportService.swift` | 85-95 | No warning when captions drop to 0 |
| `ExportService.swift` | 664-674 | Returns nil if no captions + no effects |
| `CaptionEngine.swift` | 14-18 | Initial filtering uses source time ranges |
| `EditScreen.swift` | 364-404 | startFullExport doesn't detect rough cut changes |

