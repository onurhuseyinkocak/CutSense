# CutSense Testing Guide

## Test Architecture

```
Tests/CutSenseQualityTests/
  TestHelpers.swift              — TestFixture factory (segments, captions, decisions)
  GoldenTranscriptTests.swift    — 7 end-to-end scenarios (A-G)
  RoughCutModuleTests.swift      — Unit tests per rough cut component
  ExportVerificationTests.swift  — Quality gate, timeline, caption, edit tests
```

## Running Tests

### CLI (fastest)
```bash
cd ios/
xcodebuild test \
  -scheme CutSense \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:CutSenseTests \
  2>&1 | xcpretty
```

### Xcode
1. Open `CutSense.xcodeproj`
2. Cmd+U to run all tests
3. Check Test Navigator (Cmd+6) for results

## Test Categories

### Golden Transcript Tests (Scenarios A-G)
Synthetic transcripts that verify the full rough cut pipeline without real video.

| Scenario | What It Tests | Pass Criteria |
|----------|--------------|---------------|
| A | Explicit restart ("bastan aliyorum") | Edit command cut, clean take kept |
| B | False cut protection ("olmadi" as content) | Content NOT cut |
| C | "Dur" as content | "Dur demeyi..." NOT cut |
| D | "Dur" as edit command | "dur dur tekrar alayim" cut |
| E | Repeated takes | Takes grouped, best selected |
| F | Reveal/keyword detection | Scene behaviors assigned |
| G | Over-editing guard | SFX/zoom/flash within limits |

### Module Tests
Each rough cut component tested independently:
- ContextAwareEditCommandDetector (4 tests)
- TranscriptCleanupAnalyzer (4 tests)
- TakeDetectionEngine (3 tests)
- BestTakeSelector (3 tests)
- MeaningPreservationEngine (3 tests)
- ContinuityChecker (3 tests)
- RoughCutDecisionEngine (3 tests)

### Export Verification Tests
Post-analysis pipeline:
- QualityGateService (3 tests)
- TimelineMapper (3 tests)
- CaptionEngine (3 tests)
- EditDecisionEngine (3 tests)

## Adding New Tests

Use `TestFixture` factory methods:
```swift
let seg = TestFixture.segment(start: 0, end: 3, text: "Content")
let transcription = TestFixture.transcription(segments: [seg])
let audio = TestFixture.audioResult(duration: 3.0)
let roughCut = TestFixture.roughCutAllKept(segments: [seg], originalDuration: 3.0)
```

## Debug Tools

### ExportVerificationReport
JSON report saved to `Documents/CutSense/Reports/` after each export.
Contains metrics for every pipeline stage.

### DebugTimelineScreen
Visual per-segment view showing: action, reason, confidence, caption role, effects.
Access via shake gesture in dev builds.
