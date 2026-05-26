# CutSense Caption Export Flow — Complete Trace

## Data Flow from Captions → Export

```
EditScreen.startFullExport()
  ↓
  └─→ CaptionPreviewViewModel.generate()
        ↓
        └─→ CaptionEngine.generateCaptions()
              Input: transcription, roughCut (with keepSegments)
              ├─ Filter transcript segments within keepSegments (SOURCE TIME)
              └─→ Output: captions[] with source time coordinates
                    Example: [Caption(startTime: 3.5, endTime: 5.2, text: "hello")]

  ↓
  └─→ ExportService.exportWithPipeline()
        ├─ Line 67: Load clean timeline from decisions
        ├─ Line 84: Build mapping from decisions
        │    TimelineMapper.buildMapping(decisions)
        │    └─→ Extract .keep segments → create source→clean mapping
        │        Example: Segment(sourceStart: 0, sourceEnd: 5, cleanStart: 0)
        │                 Segment(sourceStart: 10, sourceEnd: 15, cleanStart: 5)
        │        (Gap 5-10 was cut)
        │
        ├─ Line 85-87: REMAP CAPTIONS ⚠️  CRITICAL POINT
        │    remappedCaptions = TimelineMapper.remapCaptions(captions, mapping)
        │
        │    For each caption:
        │      caption.startTime = 3.5
        │      └─→ mapToClean(3.5) searches mapping segments
        │          ├─ Check if 3.5 in [0, 5]? YES ✓
        │          └─→ Returns 0 + (3.5 - 0) = 3.5 (clean time)
        │
        │      BUT if caption.startTime = 5.3 (in cut region):
        │      └─→ mapToClean(5.3) searches mapping segments
        │          ├─ Check if 5.3 in [0, 5]? NO ✗
        │          ├─ Check if 5.3 in [10, 15]? NO ✗
        │          └─→ Returns nil → CAPTION FILTERED OUT by compactMap
        │
        │    Line 91: Debug print shows: captions=5→0 (all filtered!)
        │
        ├─ Line 189-197: BUILD VIDEO COMPOSITION
        │    buildVideoComposition(
        │      timeline,
        │      captions: remappedCaptions,  // ← EMPTY []
        │      editDecisions: remappedEdits
        │    )
        │
        │    Line 664: hasContent = !captions.isEmpty || !editDecisions.isEmpty
        │             hasContent = false (both empty)
        │
        │    Line 674: guard hasContent || hasGrade || showWatermark else {
        │             return nil  // ← NO COMPOSITOR CREATED
        │             }
        │
        ├─ Line 241: session.videoComposition = nil  // ← Null compositor
        │
        └─→ Session exports without compositor
              └─→ CaptionOverlayCompositor.startRequest() never called
                    → drawCaption() never called
                    → Video exports with NO CAPTIONS
```

---

## Step-by-Step Failure Scenario

### Step 1: Caption Generation (Correct)
```
TranscriptSegment[0]: startTime=0.5, endTime=1.2, text="Hello"
TranscriptSegment[1]: startTime=2.1, endTime=3.8, text="World"
TranscriptSegment[2]: startTime=4.2, endTime=5.5, text="Great"

RoughCut.keepSegments: [
  Segment(start=0, end=3),      // Keep first 3 seconds
  Segment(start=5, end=10),     // Keep 5-10 (skip 3-5)
]

CaptionEngine output:
  Caption[0]: start=0.5, end=1.2, text="Hello"      ✓ In keep [0-3]
  Caption[1]: start=2.1, end=3.8, text="World"      ✓ In keep [0-3]
  Caption[2]: start=4.2, end=5.5, text="Great"      ? Partially in cut [3-5]
```

### Step 2: User Fine-Tunes Rough Cut (Disaster)
```
New RoughCut.keepSegments: [
  Segment(start=0, end=2),      // Now only keep 0-2 (was 0-3)
  Segment(start=5, end=10),     // Still keep 5-10
]
```

### Step 3: Caption Remapping (Failure)

**Mapping created from new rough cut:**
```
Segment(sourceStart=0, sourceEnd=2, cleanStart=0)
Segment(sourceStart=5, sourceEnd=10, cleanStart=2)
```

**Remapping each caption:**
```
Caption[0]: start=0.5 (in [0,2]?)    → YES  → maps to 0.5 ✓
Caption[1]: start=2.1 (in [0,2]?)    → NO   → not in [0,2]
            (in [5,10]?)    → NO   → not in [5,10]
            → DROPS caption ✗

Caption[2]: start=4.2 (in [0,2]?)    → NO
            (in [5,10]?)    → NO
            → DROPS caption ✗

Result: remappedCaptions = [Caption(start=0.5, end=1.2)]  // 2 captions lost!
```

### Step 4: Compositor Skipped
```
buildVideoComposition(captions=[...], editDecisions=[])
  hasContent = !captions.isEmpty = false  // Has 1 caption, so TRUE
  // Actually this WOULD create compositor...
```

Wait, let me reconsider. If there's at least 1 caption, `hasContent` would be true. Let me recheck the exact failure mode...

---

## Revised: The ACTUAL Failure Point

Looking at line 664 again:
```swift
let hasContent = !captions.isEmpty || !editDecisions.isEmpty
```

If **ANY** captions make it through remapping, this is true. So the compositor WOULD be created.

But if **ALL** captions are filtered out:
```
remappedCaptions = []
editDecisions = [] (or no visual effects)
hasContent = false
hasGrade = false (template has no color grade)
showWatermark = false (free user)
→ buildVideoComposition returns nil
```

So the failure is specifically: **ALL captions filtered during remapping**.

---

## Detection: Look for This Debug Output

**In ExportService.swift, line 91:**

```swift
print("[Export] Step 3: Remapped — captions=\(captions.count)→\(remappedCaptions.count), effects=...")
```

**If this prints:**
```
[Export] Step 3: Remapped — captions=5→0, effects=0→0
```

**Then:** All 5 captions were dropped. Video will have no captions.

---

## Root Causes (In Order of Likelihood)

### 1. Floating-Point Precision (MOST LIKELY)

```swift
// This is line 33-40 in TimelineMapper
if sourceTime >= seg.sourceStart && sourceTime <= seg.sourceEnd {
```

**Problem:** Floating-point comparison is exact.

Caption startTime from transcript: `3.0000000001` (result of some calculation)
Keep segment from rough cut: `3.0` to `5.0`

The comparison `3.0000000001 >= 3.0` is true, but if there's any precision error in either value, it fails silently.

**Example that fails:**
```
sourceTime = 2.9999999999  (should be 3.0)
seg.sourceStart = 3.0
sourceTime >= 3.0? → FALSE (2.9999... < 3.0)
→ Skips this segment, checks next
→ If no segment matches, returns nil
→ Caption filtered out
```

### 2. Rough Cut Modification (LIKELY)

User generates captions with original rough cut. Then fine-tunes rough cut. Export uses new rough cut, but captions are still in old source time coordinates. Mismatch causes filtering.

### 3. Initial Filtering Error (POSSIBLE)

```swift
// Line 14-16 in CaptionEngine
let keptTranscriptSegments = transcription.segments.filter { segment in
    keptTimeRanges.contains { range in
        range.contains(segment.startTime) || range.contains(segment.endTime)
    }
}
```

If a transcript segment that should be kept is filtered out here, fewer captions are created. Then if remaining captions fall in cut zones, they're all filtered during remapping.

---

## The Fix

### Immediate (Stop the Bleeding)

**File:** `TimelineMapper.swift`, line 33-35

```swift
// BEFORE:
if sourceTime >= seg.sourceStart && sourceTime <= seg.sourceEnd {

// AFTER:
let tolerance = 0.05  // 50ms tolerance
if sourceTime >= (seg.sourceStart - tolerance) && sourceTime <= (seg.sourceEnd + tolerance) {
```

### Warning (Alert User)

**File:** `ExportService.swift`, after line 87

```swift
if captions.count > 0 && remappedCaptions.isEmpty {
    errorMessage = "Caption export failed: captions couldn't be mapped to the edited timeline. Try regenerating captions."
    return nil
}
```

### Prevention (Avoid Mismatch)

**File:** `EditScreen.swift`, in `startFullExport()`

Detect if rough cut changed since captions were generated, and regenerate:

```swift
// If rough cut was modified after caption generation, regenerate
let captionsGenerated = captionVM.captions.count > 0
if captionsGenerated {
    let roughCutChanged = /* check if roughCut.decisions differ from stored version */
    if roughCutChanged {
        await captionVM.generate(transcription: transcript, roughCut: roughCut, template: template)
    }
}
```

---

## Summary Table

| Component | File | Line(s) | Issue | Impact |
|-----------|------|---------|-------|--------|
| **Remap** | TimelineMapper.swift | 33-40 | Exact floating-point match | SILENT LOSS |
| **Remap** | TimelineMapper.swift | 47 | compactMap filters silently | NO ERROR |
| **Export** | ExportService.swift | 85-87 | No validation of remap result | NO WARNING |
| **Compositor** | ExportService.swift | 664-674 | Returns nil if no captions | NO OVERLAY |
| **Generation** | CaptionEngine.swift | 14-18 | Initial filter may be wrong | FEWER CAPTIONS |
| **UI** | EditScreen.swift | 364-404 | No rough cut change detection | STALE CAPTIONS |

