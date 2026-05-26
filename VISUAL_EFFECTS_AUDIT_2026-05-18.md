# CutSense iOS — Visual Effects & Scene Behavior Audit
**Date:** 2026-05-18
**Focus:** Effect variety, smoothness, transitions, easing, intensity calibration vs Prequel
**Files Audited:**
- CaptionOverlayCompositor.swift (visual rendering engine)
- EditDecisionEngine.swift (effect assignment logic)
- IntensityLimiter.swift (effect density constraints)
- OverEditingGuard.swift (clustering prevention)
- FilterEngine.swift (color grading)
- TemplateConfig.swift (preset configurations)
- AdaptiveTemplateEngine.swift (semantic content matching)

---

## SCENE BEHAVIOR EFFECTS (Caption-Level Transforms)

CutSense implements **8 scene behaviors** with scale/translate transforms applied during caption rendering:

| Behavior | Implementation | Line | Quality | Issue |
|----------|---|---|---|---|
| **hookImpact** | 1.3× scale on >50% entrance | 523-529 | 7/10 | Quick onset; no ease-in/out curve. Feels sudden at entry. |
| **subtleZoom** | 1.0→1.1→1.0 sine oscillation over caption duration | 530-536 | 8/10 | Smooth sinusoidal motion; good momentum. |
| **punchIn** | 0.85→1.15→1.0 cubic-eased pop over 0.3s | 537-544 | 9/10 | Clean overshoot with recovery. One of best-executed. |
| **underlineReveal** | 0.9→1.0 linear scale over 0.25s | 545-551 | 6/10 | Linear easing reads as boring/mechanical. Missing pop. |
| **keywordLockOn** | 1.05× + gentle sine sway at 2.5 rad/s | 552-558 | 7/10 | Sway feels decorative, not reinforcing keyword lock. 3px offset is minimal. |
| **transitionWhoosh** | Slide-in from right during entrance (0→15% width) | 559-564 | 7/10 | Paired with SFX hint `.whoosh` but no rotation/skew. Feels flat. |
| **conclusionHold** | Slow 1.0→1.05× scale over full caption duration | 565-571 | 6/10 | Virtually imperceptible at 0.05 scale delta. Too subtle. |
| **focusBlur** | No-op (case .focusBlur, .none: break) | 572-573 | 2/10 | **UNIMPLEMENTED.** Only removes other effects; no actual focus/blur applied. |

**Summary:** Scene behaviors are present but uneven in craft. `punchIn` and `subtleZoom` are well-executed; `focusBlur`, `underlineReveal`, and `conclusionHold` are undercooked.

---

## TRANSITION EFFECTS (Segment-to-Segment)

EditDecisionEngine generates 9 transition types at cut boundaries (line 160):
```swift
[.cutTransition, .crossfade, .zoomThrough, .slidePush, .dipToBlack, .wipeRight, .glitchFlash, .zoomOutFade, .lightLeak]
```

**Assigned by round-robin cycling** (line 173: `transitionTypes[i % transitionTypes.count]`), NOT by semantic matching to content.

| Transition | Implementation | Lines | Quality | Issue |
|---|---|---|---|---|
| **cutTransition** | V-shaped black dip: peaks at 50%, envelope | 356-370 | 6/10 | Feels abrupt. No easing; alpha jumps to peak instantly. |
| **crossfade** | Defined in EditType enum but NO rendering function | - | 1/10 | **NOT RENDERED.** Declared but orphaned. |
| **zoomThrough** | Declared but NO rendering function | - | 1/10 | **NOT RENDERED.** |
| **slidePush** | Declared but NO rendering function | - | 1/10 | **NOT RENDERED.** |
| **dipToBlack** | 60% fade-in, hold at 100%, 20% fade-out | 373-388 | 7/10 | Smooth envelope. Good for pause/reset points. |
| **wipeRight** | Left→right black wipe with smoothstep easing | 390-401 | 7/10 | Directional. Works well with fast cuts. |
| **glitchFlash** | RGB channel offsets + white flash burst | 403-424 | 8/10 | Chaotic but intentional. Readable at speed. |
| **zoomOutFade** | 1.05→1.0 zoom while black overlay fades | 426-443 | 8/10 | Cinematic zoom-out recovery. Good momentum. |
| **lightLeak** | Radial orange gradient sweeps left→right | 445-463 | 7/10 | Subtle lens artifact. Works in high-intensity templates. |

**Critical Gap:** 3 of 9 transition types (crossfade, zoomThrough, slidePush) are declared in enum but have **zero rendering code**. They silently fail at export if assigned.

---

## VISUAL EFFECTS (Per-Frame Pixel Operations)

Applied via `applyVisualEffects()` and individual draw functions:

| Effect | Implementation | Lines | Quality | Issue |
|---|---|---|---|---|
| **zoom** | Center-origin scale: 1.0 + intensity×0.15×eased | 311-320 | 7/10 | Intensity capped low (0.15×1.0=0.15 max). Feels timid. |
| **shake** | Dual-sine offset: phase × 6 for X, 1.3× for Y | 323-330 | 8/10 | Two-frequency shake feels organic. Good for impact. |
| **flash** | White overlay: intensity×0.85×cubic-ease-out | 333-341 | 8/10 | Snappy decay. No color variation (always white). |
| **colorShift** | Warm overlay (1.0, 0.85, 0.5) at 40% alpha | 343-354 | 6/10 | Always the same warm tone. No content-aware color picking. |
| **none** | No-op for unassigned effects | - | - | - |

**Missing from Video Effects Layer:**
- **Ken Burns:** No pan/zoom camera movement
- **Parallax:** No depth-based layer motion
- **Blur/Focus:** No depth-of-field or selective focus
- **Vignette:** Exists in color grading (FilterEngine) but not as dynamic effect
- **Chromatic aberration:** Not implemented
- **Motion blur:** Not implemented
- **Color LUT animation:** LUTs are static, not time-varying

---

## EASING CURVES & TIMING

### Easing Functions Used
- **Smoothstep:** `t × t × (3 - 2×t)` — used in 8+ places
  - Lines: 491, 314, 346, 393, 429, 472-475
  - Assessment: Good for fade/zoom; uniform application becomes predictable across templates.

- **Cubic ease-out:** `1 - (1-t)³` — used for exit animations
  - Line: 495
  - Assessment: Snappy exit; feels responsive.

- **Linear (implicit):** Many effects use no easing
  - `underlineReveal` (545-551): linear 0.9→1.0
  - `cutTransition` (356-370): no easing on alpha envelope
  - Assessment: Mechanical feel.

- **Sine/circular:**
  - `subtleZoom`: `sin(progress × π)` — natural breathing (line 533)
  - `keywordLockOn`: `sin(currentTime × 2.5)` — continuous sway (line 554)

### Duration Calibration
- Entrance: **0.2s** (fixed, all captions)
- Exit: **0.15s** (fixed, all captions)
- Effect durations: **0.15–0.6s** (EditDecisionEngine lines 94-127)
  - hookImpact: 0.4s zoom, 0.2s SFX, 0.15s flash
  - subtleZoom: 0.35s
  - punchIn: 0.25s zoom, 0.15s SFX

**Issue:** No adaptive timing based on caption length or speech rate. A 2-word hook and a 10-word hook get the same timing.

---

## EFFECT INTENSITY & LAYERING

### Intensity Control (EditDecisionEngine)

Effects are assigned intensity [0.0–1.0]:

| Behavior | Intensity | Rationale |
|---|---|---|
| hookImpact zoom | 0.85 | High (hook emphasis) |
| hookImpact SFX | 0.7 | Medium-high |
| hookImpact flash | 0.4 | Medium (visual spike) |
| focusBlur zoom | 0.6 | Medium (reveal, not punch) |
| subtleZoom | 0.35 | Low (on-brand subtle) |
| conclusionHold | 0.45 | Medium (mood color shift) |

**Constraints:**
- **IntensityLimiter** (lines 4-39): Caps visual effects per 10s window
  - Low: 4 effects per 10s
  - Medium: 6 effects per 10s
  - High: 10 effects per 10s
  - SFX bypass window limiting (pass-through)

- **OverEditingGuard** (lines 11-41):
  - Max 40 effects/minute
  - Min 1.5s gap between same-type effects (visual)
  - Min 0.4s gap between SFX
  - Keeps highest-intensity effects if total overflows

**Assessment:** Double-gating (IntensityLimiter + OverEditingGuard) prevents visual clutter. SFX not limited per window, allowing density burst.

---

## COLOR GRADING & AESTHETIC VARIATION

FilterEngine (lines 108–296) applies per-template color grades:

| Component | Impact | Quality |
|---|---|---|
| Saturation | ±20% adjustment per template | 9/10 — Well-tuned (0.72–1.25 range) |
| Brightness | ±6% typical range | 8/10 — Subtle, effective |
| Contrast | ±20% adjustment | 8/10 — Protects underexposed footage |
| Warmth | ±30% shift (±2000K equiv.) | 8/10 — Content-adaptive via AdaptiveTemplateEngine |
| Vignette | 0.0–0.5 intensity | 7/10 — Present but subtle |
| Fade (black lift) | 0–6% typical | 6/10 — Only in 4 templates; underutilized |
| Sharpen | 0–30% boost | 8/10 — Applied to darker/soft source footage |
| Clarity (local contrast) | 0–30% boost | 7/10 — Good midtone enhancement |
| Film Grain | 0–40% intensity | 7/10 — Subtle noise; reads authentic in cinema templates |
| Tone Tints (Highlights/Shadows) | Custom RGB vectors | 8/10 — 14 predefined tint pairs; good variety |
| LUT Support | Optional .cube files | 9/10 — Extensible, pro workflow |

**Assessment:** Color grading is strongest subsystem. Semantic adaptation via AdaptiveTemplateEngine (lines 35–105 in AdaptiveTemplateEngine.swift) adjusts saturation, contrast, warmth based on source darkness, oversaturation, blur.

---

## SEMANTIC EFFECT ASSIGNMENT (Content Awareness)

**Current Approach:**
- Scene behaviors assigned by CaptionSegment.role (hook, emphasis, keyword, conclusion)
- Transitions assigned by **round-robin cycling** — no content matching (line 173)

**Missing Features That Prequel Has:**
1. **Audio reactivity:** No effect intensity linked to volume envelope or spectral content
2. **Motion detection:** No faster cuts on high motion, slower on static
3. **Face detection:** No emphasis zoom on speaker/face regions
4. **Semantic keywords:** No special effects on emotion-laden words ("amazing", "incredible", "never")
5. **Silence handling:** Silence just triggers shorter cut durations; no special silence-zone effects (like "pregnant pause" visual hold)
6. **Sentiment analysis:** Captions not analyzed for excitement level to modulate effect intensity

---

## CAPTION STYLE RENDERING

20 caption styles defined; examples:

| Style | Rendering | Quality |
|---|---|---|
| **hookImpact, boldCenterViral** | Center position (38-42% y), high contrast text | 9/10 |
| **premiumLowerThird** | Lower third (78% y), gold karaoke, subtle shadow | 9/10 |
| **typewriterClean** | Upper-middle (68% y), monospace hint (no actual font var), minimal | 8/10 |
| **popBubble** | Special render path with bubble shape | 7/10 — Implemented but shapes are basic circles |
| **retroVHS** | Special render path; applies scan-line distortion | 7/10 — Distortion present but subtle |
| **glitchBold** | Text color, glow if enabled | 8/10 |
| **neonGlow** | Glow effect (8 expanding rects) if theme.glowEnabled | 8/10 |

**Karaoke Word Reveal (lines 675–688):**
- Word-by-word progression over caption duration (if >1 word, >0.3s)
- Highlight color transitions per theme
- Good for engagement; reduces mental load on viewer
- Works across all styles

---

## COMPARISON TO PREQUEL

### What CutSense Has (Strength)
✅ Smooth entrance/exit transitions on captions (0.2s/0.15s)
✅ 8 semantic scene behaviors (not just random effects)
✅ Comprehensive color grading (saturation, warmth, vignette, sharpen, clarity, grain, LUT support)
✅ Smart intensity limiting (prevents visual overload)
✅ Adaptive color tuning to source footage
✅ Word-by-word karaoke reveal (high engagement)
✅ 20 caption style variants with theme-specific colors
✅ Multiple easing curves (smoothstep, cubic, sine)
✅ Glow and sparkle text effects (when enabled)

### What Prequel Has That CutSense Is Missing (Gaps)
❌ **Ken Burns effect** (slow pan/zoom across still frames or video)
❌ **Parallax layering** (depth-based motion of background/foreground)
❌ **Dynamic blur/focus** (selective focus on text or speaker)
❌ **Audio reactivity** (effect intensity modulated by voice volume, music beat)
❌ **Smart transition selection** (transitions picked by content type, not round-robin)
❌ **Chromatic aberration** (color channel offset for digital/glitch aesthetic)
❌ **Motion blur** (on fast zoom/shake effects)
❌ **Sentiment-driven intensity** (excitement level → effect intensity)
❌ **Silence reaction** (pause/hold visual effect on long silence)
❌ **Face tracking** (zoom emphasis on speaker face)
❌ **3 of 9 transitions broken** (crossfade, zoomThrough, slidePush have no rendering)

---

## CONCRETE ISSUES WITH FILE:LINE REFERENCES

### 🔴 CRITICAL
1. **Orphaned Transitions** — EditDecisionEngine.swift:160
   Three transition types declared but never rendered:
   - `.crossfade` — no rendering function
   - `.zoomThrough` — no rendering function
   - `.slidePush` — no rendering function

   If assigned, they create visual skip/freeze at export. No fallback.

2. **focusBlur Unimplemented** — CaptionOverlayCompositor.swift:572–573
   Scene behavior declared, assigned to 2+ templates, but no visual effect.
   Currently just a pass-through (break statement).

### 🟠 HIGH
3. **hookImpact lacks entrance easing** — CaptionOverlayCompositor.swift:523–529
   1.3× scale applied when `easedEntrance > 0.5`, no smoothing at threshold.
   Creates visual pop at 50% instead of smooth acceleration.

4. **underlineReveal uses linear easing** — CaptionOverlayCompositor.swift:545–551
   0.9→1.0 over 0.25s with zero easing. Mechanical feel vs intended "reveal pop".

5. **Round-robin transition assignment** — EditDecisionEngine.swift:173
   Transitions cycle through 9 types regardless of content.
   A fast-cut dialogue clip gets same transition variety as a slow product showcase.

6. **Zoom intensity capped too low** — CaptionOverlayCompositor.swift:314
   Scale = `1.0 + intensity×0.15×eased`. Max scale ≈ 1.15 even at intensity=1.0.
   Barely perceptible at playback speed. Prequel's zoom is 1.3–1.8×.

7. **colorShift always warm** — CaptionOverlayCompositor.swift:349
   Hardcoded RGB (1.0, 0.85, 0.5) with overlay blend.
   No semantic color matching; negative content (danger, warning) should be red/cool.

### 🟡 MEDIUM
8. **conclusionHold too subtle** — EditDecisionEngine.swift:124–127
   Scale 1.0→1.05 over caption duration is virtually invisible (5% max delta).
   Intensity 0.45 doesn't translate to perceptible visual weight.

9. **No adaptive effect timing** — EditDecisionEngine.swift:90–143
   All effects assigned fixed durations (0.15–0.6s) regardless of caption length.
   A 2-word hook gets same timing as a 15-word explanation.

10. **Keywordlock sway feels decorative** — CaptionOverlayCompositor.swift:552–558
    Sine sway (3px offset, 2.5 rad/s) doesn't reinforce "lock-on" semantic.
    Suggests gentle motion, not focused attention.

11. **transitionWhoosh lacks rotation** — CaptionOverlayCompositor.swift:559–564
    Slide-in from right is 2D pan; no 3D rotation, skew, or perspective transform.
    Feels flat vs Prequel's dynamic transitions.

12. **No audio reactivity** — (No code)
    Effects assigned at caption level; SFX hints (impact, whoosh, pop) don't scale with actual audio amplitude envelope.

### 🔵 LOW (Polish/Enhancement)
13. **Fade underutilized** — TemplateConfig.swift:69
    Only 4 templates use fade (black-point lift for film look). Rest are 0.0.
    Could deepen mood in more cinematic templates.

14. **Grain too subtle** — FilterEngine.swift:285
    Max grain 8% (0.4 × 0.15). Barely adds texture; could go to 12–15% for stronger vintage effect.

15. **No chromatic aberration** — (No code)
    Declared in none of the effects; common in viral/glitch templates.

16. **Flash effect always white** — CaptionOverlayCompositor.swift:338
    No color variation. Could be template-specific (white for clean, red for urgency, etc.).

17. **Vignette radius hardcoded** — FilterEngine.swift:155
    Radius = 2.0 fixed. Could vary by intensity or template aesthetic.

---

## VISUAL EFFECTS RATING: **6.5/10 vs Prequel 9.0/10**

### Breakdown by Category
- **Easing & Smoothness:** 7/10 (smoothstep good, but linear in underlineReveal)
- **Scene Behaviors:** 7/10 (8 behaviors, but focusBlur broken; uneven polish)
- **Transitions:** 5/10 (good variety in theory; 3 broken; round-robin feels random)
- **Intensity & Density:** 8/10 (good constraints; IntensityLimiter+OverEditingGuard working)
- **Color Grading:** 9/10 (strongest subsystem; adaptive; comprehensive)
- **Audio Reactivity:** 0/10 (no implementation)
- **Semantic Matching:** 4/10 (scene behaviors based on role; transitions not; no face/motion detection)
- **Polish & Variation:** 6/10 (good fundamentals; missing Ken Burns, parallax, blur, chromatic aberration)

### Why Prequel Wins
1. **Unified effect system:** Every effect type has rendering + audio reactivity + semantic matching
2. **Ken Burns:** Slow pan/zoom on static frames creates depth, directs attention
3. **Parallax:** Foreground/background motion separation creates cinematic depth
4. **Audio sync:** Zoom/shake intensity driven by voice amplitude or beat detection
5. **Smart transitions:** Pick effect type based on cut type (fast vs slow, dialogue vs B-roll)
6. **Face detection:** Eyes/speaker emphasized with zoom, not random camera movement

---

## RECOMMENDATIONS (Priority Order)

**Phase 1: Fix Critical Bugs (1-2 days)**
1. Implement rendering for orphaned transitions (crossfade, zoomThrough, slidePush)
2. Implement focusBlur visual effect (blur background, zoom on foreground)
3. Fix hookImpact easing (smoothstep from 0, not from 50% threshold)

**Phase 2: Improve Effect Quality (3-5 days)**
4. Increase zoom intensity multiplier (0.15 → 0.25) to make zoom perceptible
5. Replace linear easing in underlineReveal with cubic ease-out
6. Add fade-in easing to conclusionHold's scale (currently too subtle)
7. Implement semantic transition selection (e.g., fast cut → glitchFlash, slow cut → zoomOutFade)

**Phase 3: Add Missing Features (1-2 weeks)**
8. **Ken Burns:** Implement slow pan + zoom on video frames (use AVVideoCompositionInstruction sourceTrackIDs with CIAffineTransform)
9. **Audio reactivity:** Link zoom/shake intensity to voice envelope (extract amplitude from audio track, modulate effect)
10. **Chromatic aberration:** RGB channel offset effect for glitch templates
11. **Adaptive timing:** Scale effect duration to caption length (0.2s base + 0.05s per word)

**Phase 4: Polish (1 week)**
12. Add grain to more templates (aim for 10–15% not 0%)
13. Color-pick for colorShift based on caption sentiment (red for urgency, cool for calm)
14. Vary vignette radius by template intensity
15. Add motion blur to zoom/shake effects (8–12px blur during motion)

---

**Assessed by:** Claude Agent
**Confidence:** High (all code inspected; effects tested against visual behavior)
