# CutSense Caption Loss — Precise Locations & Fixes

## Primary Failure Point

### TimelineMapper.swift — Lines 33-40, 47

**The Bug:**
```swift
// Line 33-40: Exact floating-point matching
static func mapToClean(_ sourceTime: Double, mapping: [Segment]) -> Double? {
    for seg in mapping {
        if sourceTime >= seg.sourceStart && sourceTime <= seg.sourceEnd {  // ← EXACT MATCH FAILS ON PRECISION ERROR
            return seg.cleanStart + (sourceTime - seg.sourceStart)
        }
    }
    return nil  // ← Returns nil if sourceTime not found
}

// Line 43-58: Silent filtering
static func remapCaptions(_ captions: [CaptionSegment], mapping: [Segment]) -> [CaptionSegment] {
    if mapping.isEmpty { return captions }

    return captions.compactMap { caption in
        guard let cleanStart = mapToClean(caption.startTime, mapping: mapping) else { return nil }  // ← FILTERS OUT CAPTION
        // ...
    }
}
```

**The Fix:**
```swift
// Add tolerance for floating-point precision
static func mapToClean(_ sourceTime: Double, mapping: [Segment]) -> Double? {
    let tolerance = 0.05  // 50ms tolerance
    for seg in mapping {
        if sourceTime >= (seg.sourceStart - tolerance) && sourceTime <= (seg.sourceEnd + tolerance) {
            return seg.cleanStart + (sourceTime - seg.sourceStart)
        }
    }
    return nil
}
```

---

## Secondary Failure Points

### ExportService.swift — Lines 85-87

**The Issue:**
Captions are remapped with no validation. If all are filtered, nothing warns the user.

```swift
let remappedCaptions = TimelineMapper.resolveOverlaps(
    TimelineMapper.remapCaptions(captions, mapping: mapping)  // ← Can return []
)
```

**The Fix:**
```swift
let remappedCaptions = TimelineMapper.resolveOverlaps(
    TimelineMapper.remapCaptions(captions, mapping: mapping)
)

// Add this check immediately after:
if captions.count > 0 && remappedCaptions.isEmpty {
    errorMessage = "No captions could be placed in the exported video. This happens when cuts remove the regions where captions appear. Try regenerating captions or adjusting your cuts."
    #if DEBUG
    print("[Export] ⚠️  CRITICAL: All \(captions.count) captions were filtered during remapping!")
    print("[Export] Caption times don't map to kept segments. This will result in a video with no captions.")
    #endif
    return nil
}
```

---

### ExportService.swift — Lines 664-674

**The Issue:**
If remapped captions are empty and there are no visual effects, no compositor is created.

```swift
private func buildVideoComposition(...) -> AVMutableVideoComposition? {
    let hasContent = !captions.isEmpty || !editDecisions.isEmpty
    // ...
    guard hasContent || hasGrade || showWatermark else { return nil }  // ← Returns nil if empty
}
```

This is actually correct behavior (no need to render if nothing to overlay). The issue is earlier in the chain.

---

### ExportService.swift — Line 91

**The Issue:**
Debug log only in DEBUG builds. User never sees it.

```swift
#if DEBUG
print("[Export] Step 3: Remapped — captions=\(captions.count)→\(remappedCaptions.count), effects=\(allEditDecisions.count)→\(remappedEdits.count)")
if let first = remappedCaptions.first {
    print("[Export]   First caption: \"\(first.text.prefix(30))\" at \(String(format: "%.2f", first.startTime))-\(String(format: "%.2f", first.endTime))s role=\(first.role)")
}
#endif
```

**The Fix:**
Promote to production logging:
```swift
print("[Export] Step 3: Remapped — captions=\(captions.count)→\(remappedCaptions.count), effects=\(allEditDecisions.count)→\(remappedEdits.count)")
if let first = remappedCaptions.first {
    print("[Export]   First caption: \"\(first.text.prefix(30))\" at \(String(format: "%.2f", first.startTime))-\(String(format: "%.2f", first.endTime))s role=\(first.role)")
}
```

---

## Tertiary Issues

### CaptionEngine.swift — Lines 14-18

**The Issue:**
Initial filtering uses exact range matching, could miss captions.

```swift
let keptTranscriptSegments = transcription.segments.filter { segment in
    keptTimeRanges.contains { range in
        range.contains(segment.startTime) || range.contains(segment.endTime)
    }
}
```

**The Fix:**
Add tolerance:
```swift
let tolerance = 0.05
let keptTranscriptSegments = transcription.segments.filter { segment in
    keptTimeRanges.contains { range in
        let tolerantRange = (range.lowerBound - tolerance)...(range.upperBound + tolerance)
        return tolerantRange.contains(segment.startTime) || tolerantRange.contains(segment.endTime)
    }
}
```

---

### EditScreen.swift — Lines 364-404 (startFullExport function)

**The Issue:**
No detection if rough cut changes after captions were generated.

```swift
private func startFullExport() async {
    // ... generates captions using original rough cut
    await captionVM.generate(...)
    
    // ... later exports using potentially modified rough cut
    let url = await exportService.exportWithPipeline(
        sourceURL: videoURL,
        decisions: roughCut.decisions,  // ← Could be different from when captions were generated
        captions: captionVM.captions,   // ← Still in old timeline coordinates
        ...
    )
}
```

**The Fix:**
Detect and regenerate:
```swift
private func startFullExport() async {
    guard let roughCut = analysisVM.roughCutResult,
          let transcript = analysisVM.transcriptionResult,
          let template = selectedTemplate else { return }

    // Check if rough cut was modified
    let originalRoughCutHash = // store after analysis
    let currentRoughCutHash = roughCut.decisions.map { "\($0.startTime),\($0.endTime),\($0.action)" }.joined()
    
    if originalRoughCutHash != currentRoughCutHash && !captionVM.captions.isEmpty {
        // Rough cut changed — regenerate captions
        phase = .generatingCaptions
        await captionVM.generate(transcription: transcript, roughCut: roughCut, template: template)
    }
    
    // Continue with export...
}
```

---

## Summary of All Changes

| File | Lines | Change | Priority |
|------|-------|--------|----------|
| TimelineMapper.swift | 35 | Add tolerance to range check | **HIGH** |
| ExportService.swift | 87-95 | Add validation error | **HIGH** |
| ExportService.swift | 91 | Promote debug log to always-on | **MEDIUM** |
| CaptionEngine.swift | 15 | Add tolerance to filter | **MEDIUM** |
| EditScreen.swift | 375-404 | Detect rough cut changes | **MEDIUM** |

---

## Testing the Fix

### Test 1: Floating-Point Variance
```swift
@Test("remapCaptions survives floating-point variance")
func test_floatingPointVariance() {
    let decisions = [makeKeep(start: 0, end: 5)]
    let mapping = TimelineMapper.buildMapping(from: decisions)
    
    let captions = [
        makeCaption(start: 3.0000000001, end: 4),
        makeCaption(start: 4.9999999999, end: 5),
    ]
    
    let remapped = TimelineMapper.remapCaptions(captions, mapping: mapping)
    #expect(remapped.count == 2, "Floating-point variance should not drop captions")
}
```

### Test 2: All Captions Dropped Detection
```swift
@Test("exportWithPipeline warns when all captions dropped")
func test_allCaptionsDropped() {
    let decisions = [
        makeKeep(start: 0, end: 3),
        makeCut(start: 3, end: 10),
    ]
    let captions = [
        makeCaption(start: 5, end: 7, text: "in cut"),
        makeCaption(start: 6, end: 8, text: "also in cut"),
    ]
    
    let exportService = ExportService()
    let result = await exportService.exportWithPipeline(
        sourceURL: testVideoURL,
        decisions: decisions,
        captions: captions,
        template: .cleanExpert
    )
    
    #expect(result == nil, "Export should fail with error message")
    #expect(exportService.errorMessage != nil, "Error message should be set")
    #expect(exportService.errorMessage?.contains("captions") == true)
}
```

---

## Impact Verification

After implementing fixes, check:

1. **Build still compiles:**
   ```bash
   xcodebuild -scheme CutSense -destination 'platform=iOS Simulator,name=iPhone 17' build
   ```

2. **All tests pass:**
   ```bash
   xcodebuild -scheme CutSense -destination 'platform=iOS Simulator,name=iPhone 17' test
   ```

3. **Export with captions still works:**
   - Generate captions in app
   - Export video
   - Verify captions appear

4. **Fine-tune cuts then export:**
   - Generate captions
   - Modify rough cut
   - Export video
   - Should either regenerate captions or show error

5. **Check logs for error detection:**
   ```
   [Export] Step 3: Remapped — captions=5→0, effects=0→0
   [Export] ⚠️  CRITICAL: All 5 captions were filtered during remapping!
   ```

