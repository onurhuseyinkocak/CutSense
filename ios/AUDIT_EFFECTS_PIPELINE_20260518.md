# CutSense Edit Plan & Visual Effects Audit vs Prequel (10/10 Target)

## Executive Summary
CutSense has a **solid foundation** but falls significantly short of Prequel's sophistication. Current estimated quality: **5.2/10**. Major gaps exist in effect variety, intelligent timing, dynamic composition, and render quality.

---

## Audit Scorecard

| Dimension | Score | Notes |
|-----------|-------|-------|
| **1. Transition Variety** | 4/10 | 4 types total (cutTransition, crossfade, zoomThrough, slidePush); lacks sophisticated multi-layer sequences |
| **2. Effect Timing & Easing** | 6/10 | Uses smoothstep + exponential decay; basic parametric control but no velocity-aware timing |
| **3. Edit Plan Intelligence** | 5/10 | Scene-behavior-driven decision tree exists; no context-aware effect sequencing, no visual continuity analysis |
| **4. Visual Effect Rendering Quality** | 5/10 | Per-frame CGContext rendering; no motion blur, depth blur, color blooming, or particle systems |
| **5. Effect-to-Template Mapping** | 6/10 | 15 templates × caption themes; effect selection static per scene behavior, not adaptive to footage |
| **Overall** | **5.2/10** | Foundation strong, lacks premium multi-effect choreography and intelligent effect sequencing |

---

## Current Implementation Details

### 1. Transition Variety (4/10)

**Implemented (9 EditType total):**
- sfx, zoom, shake, flash, colorShift, cutTransition, crossfade, zoomThrough, slidePush

**Transition Implementations:**

| Type | Duration | Method | Quality |
|------|----------|--------|---------|
| **cutTransition** | 0.18–0.25s | V-shaped opacity peaking midpoint | Basic midpoint flash |
| **crossfade** | varies | Bell-curve opacity (black overlay) | Flat black, no color variance |
| **zoomThrough** | varies | Zoom in + fade (first half) → zoom out + fade (second half) | 15% max scale; feels sluggish |
| **slidePush** | varies | Dark bar slides L→R with soft edge glow | 15% bar width; single-color glow |
| **zoom** (scene behavior) | per-caption | 35% scale at full intensity | Aggressive; no acceleration curve |
| **shake** | per-effect | Exponential decay sin/cos with 8π phase | Micro-shake OK; lacks directional impact |
| **flash** | 0.15–0.4s | Quick peak at 15%, fades by 50% | Simple white overlay |

**Gaps vs Prequel:**
- No cross-dissolve with color shift
- No match-cut (visual continuity between frames)
- No glitch/digital effects
- No wipe, reveal, or 3D transforms
- No multi-stage transitions (entrance → hold → exit)
- No velocity-based timing (anticipation/overshoot)
- Transitions are symmetrical; Prequel uses asymmetrical easing for impact

---

### 2. Effect Timing & Easing (6/10)

**Easing Function:**
```swift
private func smoothstep(_ t: CGFloat) -> CGFloat {
    let clamped = min(max(t, 0), 1)
    return clamped * clamped * (3 - 2 * clamped)  // Hermite 3rd-order
}
```

**Effect-Specific Timing:**

| Effect | Easing | Phase/Decay | Quality |
|--------|--------|-------------|---------|
| **flash** | peak + linear fade | 2.5× progress decay | Feels abrupt; no hold phase |
| **colorShift** | smoothstep | no decay | Uniform fade; ignores color harmony |
| **zoom** | smoothstep | no decay | Constant acceleration, no anticipation |
| **shake** | exponential decay | `exp(-3.0 * progress)` × sin/cos | Good decay; 8π frequency OK for micro |
| **cutTransition** | smoothstep V-curve | symmetric | No asymmetry for punch |

**Gaps vs Prequel:**
- No cubic-bezier for custom easing (e.g., `cubic-bezier(0.68, -0.55, 0.27, 1.55)` for overshoot)
- No velocity/acceleration curves
- No ease-out for landing; all ease-out same shape
- No color bloom/vibration easing (separate RGB curves)
- No damping/spring physics for bounce
- Effect timing locked to duration; no anticipatory pre-effect ramps

---

### 3. Edit Plan Intelligence (5/10)

**Decision Tree (EditDecisionEngine.editsForCaption):**

```
Caption SceneBehavior → [EditDecision array]
├─ hookImpact         → zoom(0.85) + sfx(0.7) + flash(0.4)
├─ focusBlur          → zoom(0.6) + riser-sfx(0.35)
├─ underlineReveal    → flash(0.5) + pop-sfx(0.35)
├─ keywordLockOn      → zoom(0.55) + pop-sfx(0.4)
├─ transitionWhoosh   → whoosh-sfx(0.6) + flash(0.3)
├─ conclusionHold     → colorShift(0.45) + confirm-sfx(0.3)
├─ subtleZoom         → zoom(0.35)
├─ punchIn            → zoom(0.55) + pop-sfx(0.3)
└─ none               → []
```

**Cut Transition Selection:**
- Cycles through [cutTransition, crossfade, zoomThrough, slidePush] via modulo
- Intensity-aware: high → 0.25s duration, low/medium → 0.18s

**Constraints Applied:**
1. **IntensityLimiter** — max 4/6/10 effects per 10s window (low/medium/high)
2. **OverEditingGuard** — max 40 effects/min; min 1.5s gap between same-type effects

**Gaps vs Prequel:**
- No visual continuity analysis (scene color, motion direction)
- No effect sequencing based on caption content keywords
- No multi-effect choreography (effects 1→2→3 orchestrated with delays)
- No feedback loop from roughCut gaps (missing seconds) to effect intensity
- Scene behavior locked; no sub-variation by content tone/energy
- No effect ripple from preceding captions (momentum carry-over)
- Transition selection deterministic (modulo), not stochastic (variety per context)

---

### 4. Visual Effect Rendering Quality (5/10)

**Rendering Pipeline:**

1. **Source frame** → CVPixelBuffer (BGRA 32-bit)
2. **Grade** → FilterEngine.applyGrade(colorGrade) via CoreImage
3. **Overlay** → CGContext drawing on top
   - Caption text (karaoke + styling)
   - Scene behavior transforms (zoom, vignette, blur)
   - Edit effects (flash, colorShift, shake, etc.)
4. **Memory management** → autoreleasepool per frame; cached ColorSpace

**Rendering Gaps vs Prequel:**

| Feature | CutSense | Prequel | Gap |
|---------|----------|---------|-----|
| **Motion blur** | None | Yes (shake/zoom trails) | Loss of kinetic energy |
| **Depth blur (background)** | None | Yes | No visual hierarchy |
| **Color bloom/glare** | No; just overlays | Yes; bloom filter | Flat overlays |
| **Particle systems** | No | Yes (impact spark, whoosh) | No visual texture |
| **LUTs/color grade quality** | Basic overlay + tint | Multi-curve + HSL | Limited color control |
| **Vignette quality** | Static per scene | Dynamic, intensity-linked | No effect interaction |
| **Text glow** | None; just shadow | Neon glow option | Flat text |
| **Anti-aliasing** | Context default | Explicit supersampling | Aliased edges |
| **Effect layering** | Linear alpha blend | Multiply/overlay blend modes | Limited blending |

**Specific Rendering Issues:**

1. **Flash effect:** White overlay only; no color variance (gold for warmCinematic, cyan for neonViral, etc.)
2. **ColorShift:** Hardcoded `(1.0, 0.85, 0.5)` (warm amber); should derive from theme
3. **Crossfade:** Always black; should respect template theme or color grade
4. **SlidePush:** Hard-edged bar; no soft feather or gradient
5. **Zoom:** Linear scale; no anticipation or overshoot

---

### 5. Effect-to-Template Mapping (6/10)

**Current State:**

- **15 templates** with distinct caption themes (gold, neon, pastels, monochrome, etc.)
- **Theme colors** → CaptionTheme (karaokeHighlight, hookBgColor, etc.)
- **Effect intensities** NOT tied to theme color psychology
- **SFX hints** (impact, whoosh, pop, confirm, riser) → muted by template sfxVolume only
- **Color grade** → per-template base (saturation, warmth, contrast, vignette, tints)
- **AdaptiveTemplateEngine** → fine-tunes timing/audio/color based on VideoProfile + source footage

**Example (viral_caption):**
- Theme: neonViral (cyan-green karaoke, hot pink hook bg)
- Effects: high intensity (hooks get zoom 0.85 + impact SFX 0.7 + flash 0.4)
- Color grade: saturated (1.15), warm orange highlights, deep navy shadows
- Audio: SFX 0.30, BGM 0.15, voice +4.5dB

**But Missing:**
- Theme color NOT reflected in flash/colorShift effects
- No color bleeding (effect color → theme highlight hue)
- No effect emphasis tied to hook role (hook effects always same intensity, not scaled by theme "energy")
- No template-specific transition selection (e.g., "cinematicStoryteller" favors crossfade; "gamingHighlights" favors glitch)
- No SFX → visual effect sync (e.g., "impact" SFX pauses to make flash pop, not concurrent)

---

## Top 5 Quality Gaps vs Prequel

### Gap 1: No Effect Composition Language (Scoring Impact: 2.0/10)
**Current:** Effects applied independently per time window. No orchestration.
**Prequel:** Effects are sequenced — entrance effect → hold → exit, with inter-effect delays and momentum.

**Example:**
```
CutSense:  [flash(0.2s)] + [zoom(0.4s)] + [sfx(0.2s)]  → all play simultaneously
Prequel:   flash(0→0.1s) → zoom(0.1→0.5s, staggered) → peak(0.3→0.4s) → decay(0.4→0.6s) → echo
```

**Fix Required:** Introduce EffectComposition struct; orchestrate via timeline offsets, not time-based filtering.

---

### Gap 2: No Motion-Aware Easing (Scoring Impact: 1.5/10)
**Current:** All effects use smoothstep; no anticipation, overshoot, or spring physics.
**Prequel:** Easing curves vary by effect type and intensity. Hook effects overshoot for punch; transitions ease-out for land.

**Example:**
```
CutSense:   zoom: ease-in-out (symmetric 35% scale)
Prequel:    hookZoom: ease-out-back (40% scale + 5% overshoot + settle to 25%)
```

**Fix Required:** Per-effect easing library (spring, elastic, back), configurable via intensity × effect type.

---

### Gap 3: No Context-Aware Effect Selection (Scoring Impact: 1.8/10)
**Current:** Scene behavior determines effect type; no adaption to roughCut gaps, audio content, or caption context.
**Prequel:** Effect choice influenced by:
- Preceding effect (avoid duplication)
- Gap duration (large gap → more dramatic transition)
- Audio spike (concurrent SFX → visual emphasis)
- Caption sentiment/keywords ("shocking" → glitch; "smooth" → crossfade)

**Example:**
```
CutSense:   Gap=1.2s → always cutTransition(0.25s), intensity 0.5
Prequel:    Gap=1.2s → glitch(0.4s, high) [big gap needs impact]; Gap=0.4s → soft-cut(0.15s, low)
```

**Fix Required:** EditDecisionEngine.generateEditPlan needs roughCut gap analysis; caption sentiment tie-in.

---

### Gap 4: No Visual Continuity Linking (Scoring Impact: 1.5/10)
**Current:** Transitions appear in isolation; no color/motion carryover from adjacent captions.
**Prequel:** Transition exit color echoes next caption theme; motion direction flows from prior motion.

**Example:**
```
CutSense:   Caption A (red bg) → [black crossfade] → Caption B (blue bg)
Prequel:    Caption A (red bg) → [crossfade: red→purple→blue] → Caption B (blue bg)
```

**Fix Required:** Transition needs color/motion context from adjacent captions; generate dynamic gradient/motion path.

---

### Gap 5: No Depth/Texture in Effects (Scoring Impact: 1.4/10)
**Current:** Effects are 2D overlays (solid colors, no motion blur, no particles).
**Prequel:** Effects have texture: motion blur trails, color bloom, particle sparks, glitch scanlines, depth separation.

**Example:**
```
CutSense:   flash → white rectangle, alpha fade
Prequel:    flash → white core + gold bloom + motion trails + particle sparks (x5)
```

**Fix Required:** Particle system for impact SFX, motion blur trails for zoom/shake, bloom filter for color effects.

---

## Implementation Roadmap to 8/10

### Phase 1: Effect Composition (Est. 40h)
- [ ] Add `EffectSequence` model (entrance, hold, exit phases)
- [ ] Refactor `EditDecisionEngine` to generate sequences, not isolated decisions
- [ ] Implement inter-effect delays and stagger (0–0.2s offsets)
- [ ] Add `composition` field to EditDecision

### Phase 2: Easing & Spring Physics (Est. 25h)
- [ ] Implement easing library (cubic-bezier, spring, elastic, back)
- [ ] Map effect type → easing curve matrix (hook → overshoot, transition → ease-out)
- [ ] Add per-effect damping/tension parameters
- [ ] Test with slow-motion playback (0.5×) to verify easing feel

### Phase 3: Context-Aware Transition Selection (Est. 35h)
- [ ] Extend EditDecisionEngine to analyze roughCut gaps
- [ ] Implement caption sentiment/keyword extraction (hook, reveal, emphasis, conclusion)
- [ ] Add transition selection matrix (gap duration × sentiment × prior effect → transition type)
- [ ] Stochastic variant selection (not modulo-based)

### Phase 4: Visual Continuity (Est. 20h)
- [ ] Extract color from next caption theme in advance
- [ ] Generate dynamic gradient for crossfade (current color → next color)
- [ ] Analyze motion direction from prior zoom/shake; echo in transition
- [ ] Smooth caption theme color transitions (avoid jarring hue shifts)

### Phase 5: Depth & Particles (Est. 50h)
- [ ] Add particle emitter to CompositionInstruction
- [ ] Implement motion blur trails for zoom/shake via multi-frame accumulation
- [ ] Add bloom filter for flash/colorShift effects (CoreImage CIBloom)
- [ ] Generate glitch scanlines for tech/gaming templates
- [ ] Depth-blur background (separate layer rendering)

---

## Quality Verification Checklist

### Before 8/10 Claim
- [ ] A/B side-by-side with Prequel short-form (15s, viral_caption template)
- [ ] Effect composition test: hook + transition + emphasis (expect 3 distinct phases)
- [ ] Motion curve test: slow-mo playback at 0.5× shows smooth easing (no jerks)
- [ ] Transition gap test: 0.5s gap vs 1.5s gap → visibly different intensity/duration
- [ ] Theme color test: warm theme → warm flash; cool theme → cool glow
- [ ] Particle/bloom test: impact SFX → spark/glow visible on export

### Manual QA
- [ ] 10x full-length exports (1–5 min) with all templates
- [ ] Frame-by-frame inspection of transition boundaries (no black frames)
- [ ] Audio-visual sync test (SFX onset ± 2 frames of effect peak)
- [ ] Performance: no dropped frames during 4K export

---

## Estimated Prequel Parity (Current → 9/10)

| Feature | CutSense Now | Prequel Parity Level |
|---------|--------------|---------------------|
| Transition variety | 4 core types | 12+ types + multi-stage |
| Easing sophistication | Smoothstep only | 6+ curves + physics |
| Effect sequencing | Independent | Choreographed compositions |
| Visual continuity | None | Full color/motion linking |
| Render depth | 2D overlays | Particles, bloom, blur, glitch |
| Audio-visual sync | Timing-only | Velocity-aware sync |
| Template personalization | Static per role | Adaptive per content |

**CutSense → 8/10 feasible in ~170h focused work on Phases 1–3.**
**CutSense → 9/10 requires full Phases 1–5 + micro-timing tuning (~300h).**

---

## File References

- `/Users/jinx/Documents/projeler/CutSense/ios/CutSense/Editing/EditDecisionEngine.swift` — edit decision logic
- `/Users/jinx/Documents/projeler/CutSense/ios/CutSense/Export/CaptionOverlayCompositor.swift` — effect rendering (1603 lines)
- `/Users/jinx/Documents/projeler/CutSense/ios/CutSense/Editing/TemplateConfig.swift` — 15 presets, 12 caption themes
- `/Users/jinx/Documents/projeler/CutSense/ios/CutSense/Editing/AdaptiveTemplateEngine.swift` — content-aware adaptation
- `/Users/jinx/Documents/projeler/CutSense/ios/CutSense/Editing/IntensityLimiter.swift` — effect windowing
- `/Users/jinx/Documents/projeler/CutSense/ios/CutSense/Editing/OverEditingGuard.swift` — effect capping & clustering

Audit Date: 2026-05-18
Auditor: Claude Code Agent
