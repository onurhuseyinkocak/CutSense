# CutSense Manual QA Checklist

## Scoring System
Each category scored 0-5. Pass threshold: 85/100 total.

### Hard Fail Conditions (instant reject)
- [ ] App crashes during export
- [ ] Exported video has no audio
- [ ] Exported video is black/empty
- [ ] Captions completely absent when segments exist
- [ ] Export file size is 0

---

## Categories

### 1. Rough Cut Quality (0-5)
- [ ] Content sentences kept
- [ ] Edit commands ("bastan aliyorum", "tekrar alayim") cut
- [ ] Fillers ("ii", "eee") cut when standalone
- [ ] Content connectors ("yani", "aslinda") NOT cut
- [ ] Natural pauses (<1s) preserved
- [ ] Long silences (>1s) trimmed

Score: ___/5

### 2. Caption Presence (0-5)
- [ ] Captions appear on screen
- [ ] Caption timing matches speech
- [ ] First segment gets hook style
- [ ] Last segment gets conclusion style
- [ ] No captions during cut segments

Score: ___/5

### 3. Caption Readability (0-5)
- [ ] Text readable at viewing distance
- [ ] Font size adequate
- [ ] Contrast sufficient against background
- [ ] No text clipping at edges
- [ ] Display duration sufficient (>0.5s per caption)

Score: ___/5

### 4. Caption Style (0-5)
- [ ] Hook caption visually distinct
- [ ] Style matches selected template
- [ ] Reveal/keyword captions have emphasis
- [ ] Transition captions are smooth
- [ ] No jarring style changes

Score: ___/5

### 5. Visual Effects (0-5)
- [ ] Zoom effects visible on hook
- [ ] Flash effects on reveals
- [ ] Color shift on conclusion
- [ ] Effects not overwhelming
- [ ] No visual glitches from effects

Score: ___/5

### 6. Sound Effects (0-5)
- [ ] SFX audible on hook
- [ ] Whoosh on transitions
- [ ] SFX volume balanced with voice
- [ ] No SFX stacking at same timestamp
- [ ] No audio pops/clicks from SFX insertion

Score: ___/5

### 7. Audio Quality (0-5)
- [ ] Voice clear throughout
- [ ] No clipping
- [ ] Volume consistent
- [ ] Crossfades at cut points
- [ ] Background music volume appropriate (if template uses it)

Score: ___/5

### 8. Timeline Coherence (0-5)
- [ ] Story flow makes sense
- [ ] No dangling references ("bu yuzden..." after cut context)
- [ ] Transitions between segments smooth
- [ ] No duplicate content
- [ ] Total duration reasonable (30-80% of original)

Score: ___/5

### 9. Export Quality (0-5)
- [ ] Resolution matches input (1080x1920)
- [ ] No encoding artifacts
- [ ] File size reasonable
- [ ] Playback smooth (no dropped frames)
- [ ] Saves to Photos library correctly

Score: ___/5

### 10. Template Fidelity (0-5)
- [ ] Color grading matches template
- [ ] Effect intensity matches template level
- [ ] Caption style consistent with template
- [ ] Overall feel matches template description
- [ ] No template elements missing

Score: ___/5

---

## Total Score
___/50 (multiply by 2 for percentage)

Pass: >= 85% (43/50)
Conditional Pass: 70-84% (35-42/50) — fix noted issues
Fail: < 70% (< 35/50) — requires pipeline debugging
