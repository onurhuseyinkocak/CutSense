# CutSense iOS Export Pipeline Audit — Green Screen + Audio Distortion Issues

**Date:** 2026-05-18
**Status:** CRITICAL BLOCKERS IDENTIFIED
**Scope:** ExportService.swift, CaptionOverlayCompositor.swift, AudioMixService.swift, CleanTimelineBuilder.swift

---

## Executive Summary

Full trace of the export pipeline reveals **3 CRITICAL video rendering bugs** causing GREEN SCREEN and **3 HIGH-SEVERITY audio bugs** causing DISTORTION and CLIPPING.

**Root Causes:**
1. Asynchronous CIContext.render() not flushed before CGContext lock → uninitialized memory read
2. Pixel buffer format mismatch (YUV/10-bit input, BGRA assumed) → wrong color interpretation
3. Clipping guard calculated once, applied to all tracks → progressive clipping as tracks multiply
4. Loudness gain stacking (3× multipliers) without limiter enforcement → 2.0 cap exceeded
5. SFX envelope duration mismatch (uses full composition duration, not clip duration)

---

## CRITICAL ISSUE #1: CIImage Render Before Lock (GREEN SCREEN)

**File:** `CutSense/Export/CaptionOverlayCompositor.swift`
**Lines:** 198-205

```swift
// If source not yet drawn (no grade applied), render source via CIImage
// BEFORE locking for CGContext. CIImage handles YUV/BGRA/10-bit transparently.
if !sourceIsAlreadyDrawn, let sourceBuffer {
    let ciSource = CIImage(cvPixelBuffer: sourceBuffer)
    ciContext.render(ciSource, to: outputBuffer)  // ← ASYNC, NO FLUSH
}

CVPixelBufferLockBaseAddress(outputBuffer, [])    // ← LOCK IMMEDIATELY
defer { CVPixelBufferUnlockBaseAddress(outputBuffer, []) }
```

### Problem
- `CIContext.render()` is **asynchronous** — it queues the render command but does NOT guarantee completion
- Lock happens **immediately after** without synchronization barrier
- CGContext (line 212) tries to create a bitmap from `CVPixelBufferGetBaseAddress(outputBuffer)`
- Buffer may still contain **uninitialized data** from the render context pool
- Result: **GREEN SCREEN** (zero-initialized memory or stale pixels)

### Why This Causes Green
- Uninitialized pixel buffer typically reads as 0x00000000 (black in ARGB) or 0xFF00FF00 (green in BGRA)
- OR: CIContext reads succeed but write doesn't, leaving green=255 from previous allocation

### Fix
```swift
if !sourceIsAlreadyDrawn, let sourceBuffer {
    let ciSource = CIImage(cvPixelBuffer: sourceBuffer)
    ciContext.render(ciSource, to: outputBuffer)
    ciContext.flush()  // ← FLUSH TO ENSURE COMPLETION
}

CVPixelBufferLockBaseAddress(outputBuffer, [])
```

---

## CRITICAL ISSUE #2: Pixel Buffer Format Mismatch (GREEN SCREEN)

**File:** `CutSense/Export/CaptionOverlayCompositor.swift`
**Lines:** 6-20, 208-220

### Declared Input Formats (line 6-14)
```swift
var sourcePixelBufferAttributes: [String: any Sendable]? {
    [
        kCVPixelBufferPixelFormatTypeKey as String: [
            Int(kCVPixelFormatType_32BGRA),                       // ✓ 8-bit BGRA
            Int(kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange), // ← 10-bit YUV
            Int(kCVPixelFormatType_420YpCbCr10BiPlanarFullRange)   // ← 10-bit YUV
        ]
    ]
}
```

### Actual Handling (line 208-220)
```swift
let colorSpace = CGColorSpaceCreateDeviceRGB()
let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue |
                 CGBitmapInfo.byteOrder32Little.rawValue

guard let context = CGContext(
    data: outputBase,
    width: width,
    height: height,
    bitsPerComponent: 8,                    // ← ALWAYS 8-BIT ASSUMED
    bytesPerRow: CVPixelBufferGetBytesPerRow(outputBuffer),
    space: colorSpace,                      // ← RGB COLOR SPACE ASSUMED
    bitmapInfo: bitmapInfo                  // ← ALWAYS BGRA ASSUMED
)
```

### Problem
- Compositor accepts **10-bit YUV** formats but **treats all buffers as 8-bit BGRA RGB**
- Line 202: `CIImage(cvPixelBuffer: sourceBuffer)` renders YUV → BGRA conversion **expected**
- But if source is 10-bit YUV and CIContext rendering fails or incomplete:
  - CGContext created with RGB color space on YUV data
  - Byte interpretation: Y channel → Red, U → Green, V → Blue
  - Result: **GREEN SCREEN** (U component misinterpreted as green)

### Why 10-Bit YUV Causes Green Specifically
- 10-bit YUV uses 2 planes: Y (10-bit luma) + UV (10-bit interleaved chroma)
- If mistaken as BGRA: U (chroma) values (typically 128-256 in 10-bit) → interpreted as green
- Y values (typically 64-940 in 10-bit) → compressed into 8-bit BGRA, mostly green

### Fix
```swift
// Validate pixel format and handle accordingly
let pixelFormat = CVPixelBufferGetPixelFormatType(outputBuffer)
let is10Bit = pixelFormat == kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange ||
              pixelFormat == kCVPixelFormatType_420YpCbCr10BiPlanarFullRange

guard pixelFormat == kCVPixelFormatType_32BGRA else {
    #if DEBUG
    print("[Compositor] ERROR: Unsupported pixel format \(pixelFormat). Expected BGRA.")
    #endif
    return  // Skip CGContext drawing for non-BGRA formats
}
```

---

## CRITICAL ISSUE #3: Missing Buffer Synchronization Between Passes

**File:** `CutSense/Export/CaptionOverlayCompositor.swift`
**Lines:** 143-160

```swift
if hasGrade {
    CVPixelBufferLockBaseAddress(outputBuffer, [])
    let ciImage = CIImage(cvPixelBuffer: sourceBuffer)
    let graded = FilterEngine.applyGrade(grade, to: ciImage)
    ciContext.render(graded, to: outputBuffer)
    CVPixelBufferUnlockBaseAddress(outputBuffer, [])    // ← UNLOCK

    drawOverlay(
        on: outputBuffer,  // ← SAME BUFFER USED AGAIN
        ...
        sourceIsAlreadyDrawn: true
    )
}
```

### Problem
1. Grade rendered + buffer unlocked
2. drawOverlay immediately locks the same buffer again (line 205)
3. Between unlock and lock, **buffer contents not guaranteed**
4. No synchronization between CIContext and CGContext operations
5. If CIContext render is still in-flight when drawOverlay locks, **DATA RACE**

### Symptom
- First frame: correct (grade applied, overlay drawn)
- Subsequent frames: **corruption** (overlay drawn on stale graded frame, or uninit data)
- Appears as flickering green/corruption

### Fix
```swift
if hasGrade {
    CVPixelBufferLockBaseAddress(outputBuffer, [])
    let ciImage = CIImage(cvPixelBuffer: sourceBuffer)
    let graded = FilterEngine.applyGrade(grade, to: ciImage)
    ciContext.render(graded, to: outputBuffer)
    ciContext.flush()  // ← SYNCHRONOUS FLUSH BEFORE UNLOCK
    CVPixelBufferUnlockBaseAddress(outputBuffer, [])

    drawOverlay(
        on: outputBuffer,
        ...
        sourceIsAlreadyDrawn: true
    )
}
```

---

## HIGH ISSUE #1: Clipping Guard Calculated Once, Applied To Multiple Tracks

**File:** `CutSense/Export/ExportService.swift`
**Lines:** 156-172

```swift
// Count total audio tracks for clipping guard
let totalAudioTracks = timeline.composition.tracks(withMediaType: .audio).count  // ← COUNT NOW
let clippingGuardGain = AudioMixService.clippingGuardGain(for: totalAudioTracks)  // ← GAIN NOW

// SFX track parameters with fade envelope + clipping guard
for track in sfxTracks {
    let adjustedSFXVolume = template.sfxVolume * clippingGuardGain  // ← USE SAME GAIN FOR EACH
    ...
    audioMix.inputParameters = audioMix.inputParameters + [sfxParams]
}

// BGM ducking params (auto-duck under voice, fade in/out) + clipping guard
if let bgmTrack {
    let bgmParams = BackgroundMusicService.duckingParams(
        ...
        baseVolume: template.backgroundMusicVolume * clippingGuardGain,  // ← USE SAME GAIN
        ...
    )
    audioMix.inputParameters = audioMix.inputParameters + [bgmParams]
}
```

### Problem
1. **Timing:** Track count is sampled at line 157, BEFORE all SFX tracks are added
2. **Static:** The clipping guard gain is calculated once and reused for ALL subsequent tracks
3. **Track Addition:** SFX tracks added (lines 100-104), then used in loop (lines 161-172)
4. **Result:** If initial count is 2 tracks (voice + SFX master), gain = 0.7. But 5 SFX sub-tracks are then added + BGM = 8 tracks total using gain 0.7

### Numeric Example
```
Timeline: voice (1 track) + SFX (1 master track) = 2 tracks
clippingGuardGain = 0.7 (correct for 2 tracks)

SFX insertion adds 4 more specific SFX tracks → now 6 tracks
BGM insertion adds 1 more → now 7 tracks total

Audio mix:
  Voice: 1.0 × (1.5 loudness boost) = 1.5
  SFX master: 0.5 × 0.7 = 0.35 ← Should be 0.33 for 7 tracks
  SFX sub 1-4: each 0.5 × 0.7 = 0.35 × 4 = 1.4
  BGM: 0.8 × 0.7 = 0.56 ← Should be 0.29 for 7 tracks

Total: 1.5 + 0.35 + 1.4 + 0.56 = 3.81 (EXTREME CLIPPING, should be < 1.0)
```

### Fix
```swift
// Step 4: Insert SFX audio tracks BEFORE analyzing track count
let sfxResult = await SFXAssetManager.insertSFX(
    into: timeline.composition,
    decisions: remappedEdits,
    sfxVolume: template.sfxVolume
)
let sfxTracks = sfxResult.tracks

// Step 5: Insert background music
let bgmTrack = await BackgroundMusicService.insertBackgroundMusic(...)

// ONLY NOW count total tracks after all additions
let totalAudioTracks = timeline.composition.tracks(withMediaType: .audio).count
let clippingGuardGain = AudioMixService.clippingGuardGain(for: totalAudioTracks)

// Apply clipping guard to all tracks
for track in sfxTracks {
    let adjustedSFXVolume = template.sfxVolume * clippingGuardGain
    ...
}
```

---

## HIGH ISSUE #2: Loudness Gain Stacking Without Limiter

**File:** `CutSense/Export/ExportService.swift`
**Lines:** 131-154

```swift
let loudnessGain: Float
if eqResult != nil {
    loudnessGain = 1.0
} else {
    let loudness = await LoudnessNormalizer.analyze(url: sourceURL)
    loudnessGain = loudness.gainLinear * loudness.presenceBoostLinear * loudness.peakLimiterGain
    // ↑ MULTIPLYING 3 GAINS TOGETHER
}
```

Then later (AudioMixService.swift, line 42):
```swift
let totalGain = min(boostLinear * loudnessGain, 2.0)  // ← CAPS AT 2.0, NOT A LIMITER
inputParams.setVolume(totalGain, at: .zero)
```

### Problem
1. **Gain Multiplication:** Three independent gains multiplied:
   - `gainLinear`: Normalizes input level (e.g., 1.5 for -4dB input)
   - `presenceBoostLinear`: Adds air/clarity (e.g., 1.2)
   - `peakLimiterGain`: Prevents peak clipping (e.g., 1.1)
   - **Result: 1.5 × 1.2 × 1.1 = 1.98**

2. **Cap is Not a Limiter:** `min(1.98 * boostDB, 2.0)` just clamps at 2.0, doesn't compress
   - At 2.0 gain, any signal > -6dBFS becomes clipped
   - No lookahead, no knee, no ratio — just hard clipping

3. **Voice + SFX:** When voice is at 2.0 gain and SFX/BGM reduced to 0.5-0.7:
   - Voice dominates mix
   - SFX gets buried, then when boosted to be audible, distorts

### Numeric Example
```
Input: -8dBFS recording
Analysis:
  measuremLUFS = -25
  targetLUFS = -23
  gainLinear = 10^((−23−(−25))/20) = 10^(0.1) = 1.26 ✓
  presenceBoostLinear = 1.2 ✓
  peakLimiterGain = 1.15 ✓
  loudnessGain = 1.26 × 1.2 × 1.15 = 1.74

Voice boost: 1.5dB = 10^(1.5/20) = 1.19
Total: 1.19 × 1.74 = 2.07 → capped at 2.0

At 2.0 gain:
  Input peak (0dBFS) → Output: 0 + 20log10(2.0) = +6dBFS → DIGITAL CLIPPING
  SFX peaks get buried, need 2× boost to be audible → MORE CLIPPING
```

### Fix
```swift
// Option 1: Use a proper limiter
let loudnessGain = loudness.gainLinear  // ← SINGLE GAIN FACTOR
// Apply boosts AFTER loudness normalization, not multiplied together

// Option 2: Cap intermediate gains
loudnessGain = min(
    loudness.gainLinear * loudness.presenceBoostLinear,  // Normalize + presence
    1.5  // ← Cap combined at 1.5, not 2.0
) * loudness.peakLimiterGain
```

---

## HIGH ISSUE #3: SFX Envelope Duration Mismatch

**File:** `CutSense/Export/AudioMixService.swift`
**Lines:** 65-96

```swift
static func applySFXEnvelope(
    to params: AVMutableAudioMixInputParameters,
    sfxTrackDuration: CMTime,  // ← FULL COMPOSITION DURATION PASSED
    baseVolume: Float,
    audioTrackCount: Int
) {
    ...
    // Fade out: baseVolume → 0.0 over 50ms at end
    let fadeOutStart = CMTimeSubtract(totalDuration, fadeOutDuration)  // ← fadeOutStart = 59.95s if total is 60s
    if CMTimeGetSeconds(fadeOutStart) >= 0 && CMTimeGetSeconds(fadeOutDuration) > 0 {
        params.setVolumeRamp(
            fromStartVolume: baseVolume,
            toEndVolume: 0.0,
            timeRange: CMTimeRange(start: fadeOutStart, duration: fadeOutDuration)
        )
    }
}
```

Caller (ExportService.swift, line 167):
```swift
AudioMixService.applySFXEnvelope(
    to: sfxParams,
    sfxTrackDuration: timeline.totalDuration,  // ← PASSES FULL DURATION
    baseVolume: adjustedSFXVolume,
    audioTrackCount: totalAudioTracks
)
```

### Problem
1. **Parameter Name Misleading:** `sfxTrackDuration` is the **full composition duration**, not the individual SFX clip duration
2. **Fade Calculation Wrong:** Fade-out time is relative to composition end, not SFX clip end
3. **Result:** SFX plays at full volume for entire composition, no natural tail fade

### Example
```
Composition: 60 seconds total
SFX: "whoosh" sound at 30s, naturally 0.5s long
Expected: SFX should fade out from 30s to 30.05s

Actual:
  sfxTrackDuration = 60s (composition total)
  fadeOutStart = 60 - 0.05 = 59.95s
  fadeOutRange: [59.95s, 60.0s]
  Result: SFX plays full volume from 30.0s to 59.95s, fades in last 50ms of composition
```

### Fix
**Pass actual SFX clip duration, not composition duration:**
```swift
let sfxDuration = sfxResult.actualClipDurations[track] ?? CMTime(seconds: 0.5)  // Get actual duration
AudioMixService.applySFXEnvelope(
    to: sfxParams,
    sfxTrackDuration: sfxDuration,  // ← ACTUAL SFX DURATION
    baseVolume: adjustedSFXVolume,
    audioTrackCount: totalAudioTracks
)
```

OR: Rename parameter to `compositionDuration` and recalculate internally:
```swift
// In AudioMixService
let fadeOutStart = CMTimeSubtract(track.timeRange.end, fadeOutDuration)
```

---

## MEDIUM ISSUE #1: Compositor Pass-Through Doesn't Ensure Format Consistency

**File:** `CutSense/Export/CaptionOverlayCompositor.swift`
**Lines:** 117-120

```swift
guard hasOverlay || hasGrade || instruction.showWatermark else {
    request.finish(withComposedVideoFrame: sourceBuffer)  // ← PASS THROUGH UNPROCESSED
    return
}
```

### Problem
- If no overlays/grades/watermarks, source buffer passes through unchanged
- If source is YUV, 10-bit, or has weird format, it stays that way
- Rest of export might expect BGRA

### Fix
```swift
guard hasOverlay || hasGrade || instruction.showWatermark else {
    // Still render to output buffer to ensure consistent format
    if let outputBuffer = renderContext?.newPixelBuffer() {
        let ciSource = CIImage(cvPixelBuffer: sourceBuffer)
        ciContext.render(ciSource, to: outputBuffer)
        ciContext.flush()  // ← FLUSH BEFORE RETURNING
        request.finish(withComposedVideoFrame: outputBuffer)
    } else {
        request.finish(withComposedVideoFrame: sourceBuffer)
    }
    return
}
```

---

## MEDIUM ISSUE #2: No Pixel Format Validation

**File:** `CutSense/Export/CaptionOverlayCompositor.swift`
**Lines:** 59-65

```swift
guard let sourceBuffer = request.sourceFrame(byTrackID: trackID) else {
    request.finish(with: NSError(domain: "CaptionOverlay", code: -2))
    return
}
// ← NO VALIDATION OF FORMAT HAPPENS HERE
```

### Missing Checks
- Pixel format validation (BGRA vs YUV vs 10-bit)
- Width/height vs renderSize match
- CVPixelBuffer validity (not corrupted, properly allocated)

### Fix
```swift
guard let sourceBuffer = request.sourceFrame(byTrackID: trackID) else {
    request.finish(with: NSError(domain: "CaptionOverlay", code: -2))
    return
}

// Validate pixel buffer format
let pixelFormat = CVPixelBufferGetPixelFormatType(sourceBuffer)
guard pixelFormat == kCVPixelFormatType_32BGRA ||
      pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange ||
      pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange else {
    #if DEBUG
    print("[Compositor] Unsupported pixel format: \(pixelFormat)")
    #endif
    request.finish(with: NSError(domain: "CaptionOverlay", code: -3))
    return
}

// Validate dimensions
let width = CVPixelBufferGetWidth(sourceBuffer)
let height = CVPixelBufferGetHeight(sourceBuffer)
guard width > 0 && height > 0 else {
    request.finish(with: NSError(domain: "CaptionOverlay", code: -4))
    return
}
```

---

## MEDIUM ISSUE #3: RenderSize Not Validated Against Output Buffer

**File:** `CutSense/Export/CaptionOverlayCompositor.swift`
**Lines:** 194-196, 686

Compositor receives `instruction.renderSize` but doesn't validate it matches actual `outputBuffer` dimensions.

```swift
let width = CVPixelBufferGetWidth(outputBuffer)
let height = CVPixelBufferGetHeight(outputBuffer)
// ← These are used for text positioning, NOT instruction.renderSize
```

### Problem
- If export preset override changes buffer size (ExportService line 207-216), captions may render off-screen
- Text positioned for 1080x1920 might render at wrong coordinates on 720x1280 buffer

### Fix
```swift
let bufferWidth = CVPixelBufferGetWidth(outputBuffer)
let bufferHeight = CVPixelBufferGetHeight(outputBuffer)

let expectedWidth = Int(instruction.renderSize.width)
let expectedHeight = Int(instruction.renderSize.height)

guard bufferWidth == expectedWidth && bufferHeight == expectedHeight else {
    #if DEBUG
    print("[Compositor] WARNING: RenderSize mismatch. Expected \(expectedWidth)x\(expectedHeight), got \(bufferWidth)x\(bufferHeight)")
    #endif
    // Adjust captions or skip rendering
}
```

---

## PRIORITY FIX ORDER

### Phase 1: CRITICAL (Block all exports until fixed)
1. **Add CIContext.flush()** after every render (lines 148, 202)
2. **Validate pixel format** before CGContext usage
3. **Add synchronization** between CIContext and CGContext passes

### Phase 2: HIGH (Fix audio before next upload)
4. **Move track count AFTER all track insertions** (line 157 → after line 126)
5. **Fix loudness gain stacking** (cap at 1.5, not 2.0)
6. **Fix SFX envelope duration** (pass actual clip duration)

### Phase 3: MEDIUM (Polish)
7. Add pixel format validation on sourceBuffer
8. Ensure pass-through uses consistent format
9. Validate renderSize vs actual buffer dimensions

---

## Testing Strategy

### Green Screen Test
```swift
// Export with captions + video grade
// Expected: Captions visible, no green frame
// Bug: Green screen on frame with both caption AND grade
```

### Audio Distortion Test
```swift
// Export with voice + 5 SFX effects + background music
// Expected: All tracks balanced, no clipping
// Bug: Heavy clipping, SFX distorted
```

### Format Validation Test
```swift
// Export HDR source (10-bit YUV)
// Expected: Correct colors, no green/magenta cast
// Bug: Green or magenta artifacts
```

---

## Files to Modify

1. `/Users/jinx/Documents/projeler/CutSense/ios/CutSense/Export/CaptionOverlayCompositor.swift` (4 fixes)
2. `/Users/jinx/Documents/projeler/CutSense/ios/CutSense/Export/ExportService.swift` (2 fixes)
3. `/Users/jinx/Documents/projeler/CutSense/ios/CutSense/Editing/AudioMixService.swift` (1 fix)

**Total Lines Affected:** ~50 lines of actual code changes
