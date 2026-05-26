# GradedVideoPlayer — Real-Time Color Grade Preview

A SwiftUI video player that applies template color grading in real-time using Metal and CIFilter.

## Architecture

### Components

1. **GradedVideoPlayer** (SwiftUI View)
   - Main public API
   - Manages player lifecycle, playback state, and time tracking
   - Accepts `AVPlayerItem` and optional `TemplateConfig.ColorGrade`
   - Emits playback events via callbacks

2. **MetalGradedVideoView** (UIViewRepresentable)
   - Wraps Metal rendering into SwiftUI
   - Bridges player and colorGrade changes

3. **MetalVideoContainer** (UIView)
   - Manages MTKView (Metal view)
   - Handles CADisplayLink for 30fps frame polling
   - Runs video output on dedicated queue (AVPlayerItemVideoOutput)
   - Uses `PlayerReference` (nonisolated) to avoid @MainActor crashes

4. **FilterEngine.applyGrade()**
   - Applies CIFilter chain to each frame
   - Uses shared CIContext (thread-safe)
   - Supports all template grades: saturation, brightness, warmth, vignette, tints, LUT, grain, etc.

## Usage

```swift
import AVFoundation

// Load a video
let videoURL = URL(fileURLWithPath: "/path/to/video.mov")
let asset = AVAsset(url: videoURL)
let playerItem = AVPlayerItem(asset: asset)

// Create player with a template grade
@State var template = TemplateConfig.viralCaption

VStack {
    GradedVideoPlayer(
        playerItem: playerItem,
        colorGrade: template.colorGrade,
        onPlaybackStateChanged: { isPlaying in
            print("Playback: \(isPlaying)")
        },
        onTimeUpdated: { time in
            print("Time: \(time.seconds)s")
        }
    )
    .frame(height: 400)
}

// Template changes update the grade in real-time
.onChange(of: selectedTemplate) { _, newTemplate in
    template = newTemplate
}
```

## How It Works

### Frame Polling (CADisplayLink → 30fps)

```
Main Thread:
  CADisplayLink ticks at 30fps
    ↓
  displayLinkTick() checks AVPlayerItemVideoOutput
    ↓
  hasNewPixelBuffer() → true
    ↓
  Enqueue frame to background queue

Background Queue:
  copyPixelBuffer() grabs the CVPixelBuffer
    ↓
  CIImage(cvPixelBuffer:)
    ↓
  FilterEngine.applyGrade() applies all filters
    ↓
  CIContext.render() → MTKView drawable texture
    ↓
  MTLCommandBuffer presents drawable
```

### Swift 6 Safety (@MainActor)

The implementation follows the GATE pattern from `ios-swift.md`:

- **PlayerReference** is a simple nonisolated class holding weak references
- Background callbacks (CADisplayLink, CIContext.render) never capture `[weak self]`
- No `MainActor.assumeIsolated` needed—rendering stays off main thread
- Safe on physical devices (iOS 26 dispatch_assert_queue won't crash)

### Color Grading Pipeline

1. **Pixel buffer input** (32BGRA format, Metal-compatible)
2. **CIImage conversion**
3. **FilterEngine.applyGrade()** applies in order:
   - Color controls (saturation, brightness, contrast)
   - Temperature/warmth shift
   - Vignette
   - Fade (black point lift)
   - Tone overlays (highlights + shadows tints)
   - Sharpening (unsharp mask)
   - Clarity (highlight-shadow adjustment)
   - Film grain (random noise overlay)
   - LUT (if specified)
4. **Metal texture render** to MTKView drawable
5. **Display** via CADisplayLink refresh

## Performance

- **Frame rate:** 30fps (via CADisplayLink)
- **Format:** 32BGRA (GPU-optimized)
- **Processing:** Background thread (no main thread blocking)
- **Memory:** Reuses pixel buffer pool via AVPlayerItemVideoOutput
- **Filter chain:** All operations composited before render (no per-step GPU transfer)

## Limitations

- Simulator rendering is slower due to software Metal
- Does not support timeline composition (use CaptionPreviewPlayer for full composition with captions)
- Grade updates are immediate but don't cross-fade (template switches appear instantly)

## Testing Integration

Use with existing video preview flows:

```swift
// In TemplateHubScreen or EditScreen
@State var selectedTemplate = TemplateConfig.viralCaption
@State var currentVideoItem: AVPlayerItem?

VStack {
    // Show graded preview
    if let item = currentVideoItem {
        GradedVideoPlayer(
            playerItem: item,
            colorGrade: selectedTemplate.colorGrade
        )
        .frame(height: 400)
    }

    // Template picker
    Picker("Template", selection: $selectedTemplate) {
        ForEach(TemplateConfig.all) { t in
            Text(t.name).tag(t)
        }
    }
}
```

## File Location

`CutSense/Preview/GradedVideoPlayer.swift`

## Dependencies

- AVFoundation (playback + video output)
- MetalKit (rendering)
- CoreImage (filtering)
- SwiftUI (UI)
