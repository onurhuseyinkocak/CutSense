# Golden Test Scenarios

10 scenarios for real-device QA. Each defines input, expected pipeline behavior, and pass criteria.

---

## 1. Clean Single Take (Baseline)
**Input:** 30s talking-head, no mistakes, no filler
**Expected:**
- 0 cuts
- Captions for every sentence
- Hook on first, conclusion on last
- 1-2 SFX, 1 zoom
**Pass:** Retention >= 95%, captions present, at least 1 effect

## 2. Heavy Filler
**Input:** 60s video, "ii", "eee", "sey" every 5s
**Expected:**
- All standalone fillers cut
- "yani" / "aslinda" in sentences NOT cut
- Review queue for ambiguous fillers
**Pass:** Fillers removed, content preserved, retention 70-90%

## 3. Multiple Takes (3x Same Sentence)
**Input:** Speaker says same sentence 3 times, improving each time
**Expected:**
- TakeDetectionEngine groups all 3
- Best take (highest confidence + last) kept
- Other 2 cut
**Pass:** Only 1 take survives, best score wins

## 4. Edit Command in Turkish
**Input:** "...bastan aliyorum... dur dur tekrar alayim... bunu kes..."
**Expected:**
- All 3 edit commands cut with >= 0.7 confidence
- Content before/after kept
**Pass:** Edit commands cut, no false cuts on content

## 5. "Olmadi" False Positive Test
**Input:** "Bu strateji olmadi cunku..." (content, not edit command)
**Expected:**
- NOT cut
- Classified as content with high confidence
**Pass:** 0 false cuts

## 6. Long Silence
**Input:** 3s of silence between two content blocks
**Expected:**
- Silence region cut
- 0.15s breathing room at edges
- Audio crossfade at cut point
**Pass:** Silence removed, no audio pop, smooth transition

## 7. Hook + Reveal Pattern
**Input:** "En guclu tarafi su..." followed by key reveal
**Expected:**
- First segment: hook role + hookImpact behavior
- Reveal segment: underlineReveal or keywordLockOn
- SFX on hook, zoom on reveal
**Pass:** Both scene behaviors assigned, effects present

## 8. Over-Editing Stress Test
**Input:** 60s video, 20 short sentences (3s each)
**Expected:**
- IntensityLimiter caps effects
- Max 5 SFX/10s, 4 zooms/10s, 2 flashes/10s
- No stacked SFX at same timestamp
**Pass:** All limits respected

## 9. Mixed Language (Turkish + English)
**Input:** Speaker switches between TR and EN mid-sentence
**Expected:**
- Both languages transcribed
- Edit commands detected in both languages
- Caption styles applied consistently
**Pass:** No language-based false cuts

## 10. Minimal Content (< 10s)
**Input:** Very short clip, 2 sentences
**Expected:**
- No aggressive cutting
- At least 1 caption
- Quality gate passes with score >= 60
**Pass:** Output exists, not empty, playable
