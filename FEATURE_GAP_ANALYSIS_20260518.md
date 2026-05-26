# CutSense vs Prequel/CapCut/InShot: Comprehensive Feature Gap Analysis

**Analysis Date:** 2026-05-18
**Scope:** iOS video editing features, UI/UX parity, editing capabilities
**Assessment:** BRUTALLY HONEST

---

## EXECUTIVE SUMMARY

CutSense is currently a **single-purpose AI rough-cut editor** — it accepts a raw video, auto-detects cuts/filler, and exports with captions + effects. It does NOT support manual editing, reordering, aspect ratio changes, or most post-production workflow features that users expect from CapCut/InShot/Prequel.

**Feature Coverage:**
- CapCut: ~8% parity (basic video trim via rough cut, captions, simple export)
- InShot: ~5% parity (video, captions only)
- Prequel: ~3% parity (effects/templates exist but no UI to customize)

**Critical Missing Categories:**
1. **Manual editing controls** — no trim UI, no reorder, no split
2. **Visual customization** — no crop/zoom, no rotate/flip, no aspect ratio change
3. **Asset libraries** — no music browser, no SFX picker, no sticker gallery
4. **Advanced audio** — no voiceover recording, no waveform editing
5. **Content discovery** — no trending templates, no community features
6. **Multi-platform export** — no format options, no quality presets

---

## DETAILED FEATURE ASSESSMENT

### CATEGORY 1: EDITING CONTROLS

| Feature | CutSense | CapCut | InShot | Prequel | Impact | Complexity | Priority |
|---------|----------|--------|--------|---------|--------|------------|----------|
| **Manual trim/split** | ❌ No | ✓ Yes | ✓ Yes | ✓ Yes | **CRITICAL** | 40h | P0 |
| **Reorder segments** | ❌ No | ✓ Yes | ✓ Yes | ✓ Yes | **CRITICAL** | 20h | P0 |
| **Duplicate segment** | ❌ No | ✓ Yes | ✓ Yes | ⚠️ Limited | Must-have | 8h | P1 |
| **Aspect ratio change** | ❌ Hard-coded 9:16 | ✓ 15+ presets | ✓ 10+ presets | ✓ 8+ presets | **CRITICAL** | 25h | P0 |
| **Crop/pan per segment** | ❌ No | ✓ Yes | ✓ Yes | ✓ Yes | Must-have | 35h | P1 |
| **Rotate/flip** | ❌ No | ✓ Yes | ✓ Yes | ✓ Yes | Nice-to-have | 12h | P2 |
| **Speed control (slow-mo/fast)** | ❌ No | ✓ Yes (0.25x-4x) | ✓ Yes | ✓ Yes | Must-have | 18h | P1 |
| **Timeline scrubber with preview** | ⚠️ Rough cut only | ✓ Full timeline | ✓ Full timeline | ✓ Full timeline | **CRITICAL** | 45h | P0 |

**CutSense Status:**
- RoughCutReviewScreen allows selecting "Keep/Cut/Review" per segment (UI-only)
- No manual trim handles or visual timeline
- No reordering — segments are locked to source order
- Aspect ratio is hard-coded to 9:16 in ExportService (line 454: `resolution: "1080x1920"`)
- Users cannot adjust crops, pans, or zoom per-segment

**Impact:** A user cannot edit their own video manually. CutSense is AI-only. If AI makes wrong cut, user must live with it or re-analyze.

---

### CATEGORY 2: VISUAL & EFFECTS

| Feature | CutSense | CapCut | InShot | Prequel | Impact | Complexity | Priority |
|---------|----------|--------|--------|---------|--------|------------|----------|
| **Filter gallery (swipeable preview)** | ⚠️ Partial | ✓ 50+ | ✓ 40+ | ✓ 60+ | Must-have | 30h | P1 |
| **Stickers/emojis overlay** | ❌ No | ✓ Yes (1000+) | ✓ Yes (500+) | ✓ Yes (800+) | Must-have | 25h | P1 |
| **Text overlay (manual, not captions)** | ❌ No | ✓ Yes | ✓ Yes | ✓ Yes | Must-have | 20h | P1 |
| **Drawing/markup tools** | ❌ No | ✓ Yes | ✓ Yes | ✓ Yes | Nice-to-have | 22h | P2 |
| **Blur (face, objects)** | ❌ No | ✓ Yes | ✓ Yes | ✓ Yes | Must-have | 18h | P1 |
| **Green screen/chroma key** | ❌ No | ✓ Yes | ✓ Yes | ❌ No | Differentiator | 40h | P2 |
| **Transitions (20+ types)** | ❌ Hard-coded | ✓ Yes | ✓ Yes | ✓ Yes | Must-have | 28h | P1 |
| **Color correction per segment** | ⚠️ Template-wide only | ✓ Per-clip | ✓ Per-clip | ✓ Per-clip | Nice-to-have | 32h | P2 |

**CutSense Status:**
- TemplateConfig has ColorGrade (saturation, brightness, contrast, warmth, vignette) but applied globally
- FilterEngine exists but only applies template-wide grade, not per-segment
- CaptionEngine creates karaoke-style captions (word-by-word with emphasis)
- NO sticker, emoji, drawing, or text overlay UI
- NO transition picker — transitions not implemented in export
- NO face blur, green screen, or chroma key

**Impact:** App feels basic. Users compare to TikTok/Instagram filters and see CutSense as limited. No appeal for cosmetic customization.

---

### CATEGORY 3: AUDIO

| Feature | CutSense | CapCut | InShot | Prequel | Impact | Complexity | Priority |
|---------|----------|--------|--------|---------|--------|------------|----------|
| **Voiceover recording** | ❌ No | ✓ Yes | ✓ Yes | ✓ Yes | Must-have | 28h | P1 |
| **Music library browser** | ❌ No | ✓ Royalty-free | ✓ Royalty-free | ✓ Royalty-free | Must-have | 35h | P1 |
| **Sound effects browser** | ❌ No (only AI-assigned SFX) | ✓ 1000+ | ✓ 500+ | ✓ 800+ | Must-have | 28h | P1 |
| **Audio waveform visualization** | ❌ No | ✓ Yes | ✓ Yes | ✓ Yes | Nice-to-have | 20h | P1 |
| **Audio ducking/auto-mix** | ✓ Yes (template-based) | ✓ Yes | ✓ Yes | ✓ Yes | Must-have | 12h | P1 |
| **Voiceover timeline alignment** | ❌ No | ✓ Yes | ✓ Yes | ✓ Yes | Must-have | 24h | P1 |

**CutSense Status:**
- AudioMixService applies voice boost + SFX volume per template
- SFXAssetManager inserts SFX based on AI decisions (EditDecision.type == .sfx)
- NO UI to browse/pick SFX — all determined by AI
- NO voiceover recording capability
- NO music library browser
- NO waveform visualization in timeline

**Impact:** Audio is fully AI-driven. User has no control. If they want to add their own voiceover or background music, they must use a different app.

---

### CATEGORY 4: EXPORT & DISTRIBUTION

| Feature | CutSense | CapCut | InShot | Prequel | Impact | Complexity | Priority |
|---------|----------|--------|--------|---------|--------|------------|----------|
| **Quality presets (720p/1080p/4K)** | ❌ Hard-coded 1080p | ✓ Yes | ✓ Yes | ✓ Yes | Must-have | 12h | P1 |
| **Format options (MP4/MOV/GIF)** | ❌ MP4 only | ✓ MP4/MOV | ✓ MP4/MOV | ✓ MP4/MOV | Must-have | 10h | P1 |
| **Watermark option** | ✓ Yes (free) | ✓ Yes | ✓ Yes | ✓ Yes | Must-have | 8h | P1 |
| **Batch export** | ❌ No | ✓ Yes | ✓ Yes | ✓ Yes | Differentiator | 30h | P2 |
| **Direct share to TikTok** | ❌ Uses native share | ✓ Direct API | ✓ Direct API | ✓ Direct API | Must-have | 20h | P1 |
| **Direct share to Instagram** | ❌ Uses native share | ✓ Direct API | ✓ Direct API | ✓ Direct API | Must-have | 20h | P1 |
| **Direct share to YouTube** | ❌ Uses native share | ✓ Direct API | ✗ No | ✓ Direct API | Nice-to-have | 18h | P2 |
| **Platform-specific aspect ratios** | ❌ No (9:16 always) | ✓ Yes (TikTok/IG/YT) | ✓ Yes | ✓ Yes | **CRITICAL** | 20h | P0 |

**CutSense Status:**
- ExportService hard-codes: `resolution: "1080x1920"` (9:16 only)
- No quality selector — renders at 1080p always
- Watermark added if !isPro (visible in ExportScreen line 97)
- ShareLink(item: url) — generic iOS share sheet only
- No TikTok/Instagram API integration
- No batch export

**Impact:** Users can't optimize for TikTok (1:1 or 9:16), Instagram Reels (9:16 or 4:5), or YouTube Shorts (9:16). Exported video won't fit platform standards perfectly.

---

### CATEGORY 5: CONTENT DISCOVERY & COMMUNITY

| Feature | CutSense | CapCut | InShot | Prequel | Impact | Complexity | Priority |
|---------|----------|--------|--------|---------|--------|------------|----------|
| **Trending template discovery** | ❌ No | ✓ Yes | ✓ Yes | ✓ Yes | Nice-to-have | 25h | P2 |
| **Community templates** | ⚠️ TemplateHubScreen exists | ✓ Yes (rated) | ✓ Yes (rated) | ✓ Yes | Must-have | 18h | P1 |
| **Template rating/review** | ✓ Partial (no UI shown) | ✓ Yes | ✓ Yes | ✓ Yes | Nice-to-have | 12h | P2 |
| **Custom template builder** | ✓ Partial (skeleton) | ✓ Yes | ✓ Yes | ✓ Yes | Differentiator | 35h | P1 |
| **Share custom templates** | ❌ No (local only) | ✓ Yes | ✓ Yes | ✓ Yes | Differentiator | 22h | P2 |

**CutSense Status:**
- TemplateHubScreen exists but NOT wired into nav (not in RootView)
- TemplateConfig.all contains 6 built-in templates (Cinematic, Viral, Minimal, etc.)
- CustomTemplateBuilderScreen exists but NOT in nav
- CustomTemplateStore allows import JSON files
- No online template sharing, no discovery UI

**Impact:** Users see only 6 built-in templates. No way to explore, download, or share custom styles with community.

---

### CATEGORY 6: ONBOARDING & LEARNING

| Feature | CutSense | CapCut | InShot | Prequel | Impact | Complexity | Priority |
|---------|----------|--------|--------|---------|--------|------------|----------|
| **First-run tutorial** | ✓ Yes (3-page) | ✓ Yes | ✓ Yes | ✓ Yes | Must-have | 8h | P1 |
| **Feature tooltips in-app** | ❌ No | ✓ Yes | ✓ Yes | ✓ Yes | Nice-to-have | 18h | P2 |
| **Sample project to edit** | ❌ No | ✓ Yes | ✓ Yes | ✓ Yes | Nice-to-have | 20h | P2 |
| **Video tutorials (in-app)** | ❌ No | ✓ Yes | ✓ Yes | ✓ Yes | Differentiator | 40h | P2 |
| **Contextual help** | ❌ No | ✓ Yes | ✓ Yes | ✓ Yes | Nice-to-have | 15h | P2 |

**CutSense Status:**
- OnboardingScreen has 3 pages (Welcome, Smart Analysis, One-Tap Export) with Lottie animations
- AppStorage flag: `hasSeenOnboarding`
- NO in-app tooltips or contextual help
- NO sample project
- NO video tutorials

**Impact:** Users don't understand why CutSense works differently from CapCut (AI-driven vs manual). Onboarding doesn't educate on unique value.

---

## SEVERITY-BASED RECOMMENDATIONS

### MUST-HAVE (blocks market fit)

1. **Manual trim/split + timeline UI** (40h)
   - Without this, app is not a real video editor
   - Users expect to cut out parts manually
   - Rough cut alone is insufficient for creative control

2. **Aspect ratio picker (9:16, 16:9, 1:1, 4:5)** (20h)
   - Current hard-coded 9:16 breaks Instagram, YouTube, TikTok workflows
   - Users need to optimize per platform
   - Implementation: Add aspect ratio picker in ExportScreen, update ExportService to render different resolutions

3. **Reorder segments** (20h)
   - Users want to rearrange scenes, not just cut
   - Drag-to-reorder in timeline + rebuild composition
   - Currently segments are locked to source order

4. **Music library + voiceover recording** (35h)
   - Every competitor has this
   - CutSense has no way to add background music
   - Voiceover recording is baseline expectation

5. **Sticker/text overlay UI** (25h)
   - Without decorative overlays, video feels plain
   - Users expect emoji, text, shapes on top of video
   - Captions alone are not enough

6. **Template picker with visual preview** (15h)
   - Current 6 templates are pills only
   - Users need thumbnail preview of each style
   - Template customization UI (CustomTemplateBuilderScreen) is unfinished

7. **Fix export failures** (already documented in audit)
   - ExportScreen has 16+ UI/data flow bugs (see AUDIT_UI_FLOW_2026_05_17.md)
   - Export fails silently; users see "Complete" even when it failed
   - This must be fixed before any market launch

---

### NICE-TO-HAVE (differentiators)

8. **Direct TikTok/Instagram share** (20h)
   - Saves user 3 taps (export → open TikTok → paste)
   - CapCut/InShot both have this
   - Implementation: Add TikTok/Instagram API integration, credential storage

9. **Trending templates discovery** (25h)
   - Shows what's popular, drives engagement
   - TemplateHubScreen exists but not in nav
   - Implementation: Wire into nav, add trending algorithm, caching

10. **Custom template sharing** (22h)
    - Lets users share styles with friends
    - Builds community
    - Low priority but high engagement lift

11. **Color correction per-segment** (32h)
    - Allows more creative control
    - Currently template-wide only
    - Complex: requires UI + per-clip grade storage

12. **Batch export** (30h)
    - Export same video in multiple formats/aspect ratios at once
    - Saves time for power users
    - Implementation: Queue system + background rendering

---

## COMPARISON MATRIX: FEATURE MATURITY

```
                    CutSense  CapCut  InShot  Prequel  Tier
Manual Editing      0%        100%    100%    95%      P0
Aspect Ratios       5%        100%    95%     90%      P0
Reordering         0%        100%    100%    95%      P0
Text/Stickers      0%        100%    95%     100%     P0
Music Library      0%        100%    100%    100%     P0
Voiceover          0%        100%    100%    95%      P0
Filters            10%       100%    95%     100%     P1
Audio Editing      30%       100%    100%    95%      P1
Transitions        0%        100%    100%    100%     P1
Export Options     10%       100%    95%     95%      P1
Social Share       30%       100%    100%    95%      P1
Templates          5%        100%    95%     100%     P1
Tutorials          20%       100%    100%    95%      P2
---
Average Parity:    7%        100%    97%     96%

CutSense is still in BETA (AI rough-cut only) vs PRODUCTION (full editor) status.
```

---

## WHY CUTSENSE LOSES

### Current Positioning (AI rough-cut tool)
**Pros:**
- Unique: AI auto-detects cuts/filler (no competitor does this)
- Fast: Export in 1 minute vs CapCut's 10 minutes
- Smart captions: Karaoke-style word emphasis

**Cons:**
- No creative control: User can't adjust crops, aspect ratios, overlays
- Limited output: 9:16 only, no platform optimization
- No discovery: Users don't know it exists (marketing is zero)
- Export is broken: App crashes or fails silently on real device

### Why Users Choose CapCut/InShot Instead
1. **Full manual editor first** — AI effects second (CutSense is opposite)
2. **Works on all platforms** — 9:16, 4:5, 1:1, 16:9 supported
3. **Asset libraries** — music, SFX, stickers built-in
4. **One-stop shop** — don't need another app to add voiceover
5. **Social API** — direct TikTok/IG upload without leaving app
6. **Community** — trending templates, creator marketplace

**CutSense cannot compete without addressing #1-2 above.**

---

## REALISTIC ROADMAP (12-month vision)

### Phase 1: FOUNDATION (Weeks 1-8) — **FIX & UNBLOCK**
- [ ] Fix 16 UI/data flow bugs (export failures, silent errors)
- [ ] Add aspect ratio picker (9:16, 4:5, 1:1, 16:9)
- [ ] Implement manual trim/split UI (drag handles on timeline)
- [ ] Add reorder segments (drag in timeline)
- **Effort:** 120h
- **Outcome:** App is usable as a real editor, not just AI tool

### Phase 2: ENGAGEMENT (Weeks 9-16) — **STICKERS & TEMPLATES**
- [ ] Add text overlay UI (no captions, manual text boxes)
- [ ] Add sticker/emoji picker (basic 100+ pack)
- [ ] Wire TemplateHubScreen into nav + add visual previews
- [ ] Finish CustomTemplateBuilderScreen UI
- **Effort:** 95h
- **Outcome:** App looks modern, creative control exists

### Phase 3: CONTENT (Weeks 17-24) — **AUDIO & DISCOVERY**
- [ ] Integrate music library (Epidemic/AudioJungle API)
- [ ] Add voiceover recording + timeline alignment
- [ ] Implement trending templates discovery
- [ ] Add TikTok/Instagram direct share
- **Effort:** 130h
- **Outcome:** One-stop shop for creators, social integration

### Phase 4: POLISH (Weeks 25-32) — **QUALITY & SCALE**
- [ ] Implement quality presets (720p, 1080p, 4K)
- [ ] Add filters gallery + color correction per-clip
- [ ] Batch export & render queue
- [ ] Video tutorials + feature tooltips
- **Effort:** 85h
- **Outcome:** Production-ready app, parity with InShot

### Phase 5: DIFFERENTIATION (Weeks 33+) — **KEEP AI ADVANTAGE**
- [ ] AI-suggested edits during manual editing
- [ ] AI-powered scene detection for best moments
- [ ] Real-time quality feedback during editing
- [ ] Creator analytics dashboard
- **Effort:** TBD
- **Outcome:** Leverage AI uniqueness, not just compete on features

**Total effort to MVP parity:** ~430h (11 weeks full-time team of 2)

---

## RISK ASSESSMENT

**Low Risk (Can implement in weeks):**
- Aspect ratio picker
- Manual trim/split basic UI
- Text overlay
- Sticker pack
- Quality presets

**Medium Risk (4-8 weeks, needs careful design):**
- Reorder segments (timeline rebuild complexity)
- Music library integration (API rate limits, licensing)
- Voiceover recording (AVAudioEngine complexity, iOS 26 @MainActor issues)
- Custom template builder UI

**High Risk (needs external help or pivot):**
- TikTok/Instagram API (requires app approval, credential management)
- Batch render (queue + background processing, battery drain)
- Green screen/chroma key (complex ML, device performance)
- Face blur (requires CoreML model, on-device or server)

---

## COMPETITIVE ANALYSIS: UNIQUE ANGLES

### CutSense CAN Win On:
1. **AI-first workflow** — User uploads messy raw footage, gets polished video
2. **No learning curve** — Tap "Analyze" then "Export" (vs CapCut's 50+ tools)
3. **Speed** — 1-minute export vs 10 minutes in CapCut (on older phones)
4. **Niche: Podcasters/YouTubers** — They have long raw takes, need fast cutting

### CutSense CANNOT Win On (Don't Try):
- Feature count (CapCut has 300+ features vs CutSense's 8)
- Design (Prequel has stronger aesthetic)
- Market share (TikTok's CapCut has 200M users)
- Community (InShot has 400M users, templates, creator network)

---

## FINAL VERDICT

**CutSense's Current State:** Prototype. Beta. Not market-ready.

**Critical Issues to Fix Before Launch:**
1. Export pipeline is broken (16 bugs, silent failures)
2. No manual editing (app can't be called an "editor")
3. Hard-coded 9:16 (doesn't fit TikTok/YouTube/IG standards)
4. Zero UI for community/discovery (isolated app)

**Path Forward:**
- **Option A (Aggressive):** Build full editor in 12 weeks, compete head-to-head with CapCut
  - Requires 2 engineers, focus on MVP parity
  - Risk: Feature creep, launch delays
  
- **Option B (Focused):** Double down on AI uniqueness, target podcasters/YouTubers
  - Fix critical bugs + add manual trim/reorder
  - Keep template library simple, focus on AI quality
  - Market as "AI-first, manual-capable" not "full editor"
  - Risk: Smaller TAM, slow growth

- **Option C (Pivot):** Become a TikTok trending-content auto-editor
  - AI analyzes trending audio, suggests cuts
  - One-tap TikTok upload
  - Target: TikTok creators with no editing skills
  - Risk: Platform dependency, algorithm changes

**Recommendation:** Option B (Focused). CutSense's strength is AI. Don't try to out-CapCut CapCut. Instead, own the "AI auto-editor for podcasters" niche. Fix bugs, add manual trim, ship in 8 weeks.

