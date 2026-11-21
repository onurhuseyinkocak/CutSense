**Karar:** Lime tamamen kalkıyor; uygulama kromunda sıfır renk, yalnız siyah-beyaz-gri kalıyor (renk yalnız kullanıcının videosunda, üçüncü taraf reklam kreatifinde ve sistem sheet'lerinde). Uygulama zaten siyah zemin + beyaz buton olduğu için fark renkten gelmez; yapıdan, tipografiden ve hareketten gelecek. Marka öğesi "sinyal": home'da ürünü 6 saniyede anlatan canlı dalga formu, processing'de aynı dalganın taramaya dönüşmesi, review'da `Analysis.windowRMS`'ten çizilen gerçek dalga formu. Durumlar renk yerine dolu/boş, yükseklik, parlaklık, ikon ve metinle kodlanır. Dark-only kalır: video aracı, OLED siyah, light mod QA'yı ikiye katlar. Font paketlenmez: SF Pro (expanded genişlik) + SF Mono, 0 KB, TR/JA/KO glifleri garantili. `ios/` git reposu olduğu için rollback git ile yapılır.

**Adımlar:**

## 1. Direction
- Premium here means a measuring instrument, not a template: pure black, hairlines instead of cards, one white action per screen, numbers as typography.
- State is luminance and shape, never hue. White full-height bar = kept speech; short dim bar = cut. Filled = on; outlined = off.
- Motion explains the product: silence collapses, speech slides together. Every state change animates, and every animation has a Reduce Motion fallback.

## 2. Tokens (namespace `Mono`)
**Color** (contrast on #000 / #0E0E0E / #171717, computed):

| Token | Hex | Role | Contrast |
|---|---|---|---|
| `bg` | #000000 | screen | n/a |
| `raised` | #0E0E0E | sheets, control tracks, rows | n/a |
| `elevated` | #171717 | pressed state, native ad background | n/a |
| `hairline` | white 10% | dividers, strokes | decorative |
| `strong` | white 22% | outline strokes | decorative |
| `text` | #FFFFFF | primary text | 21.0 / 19.3 / 17.9 |
| `text2` | #A3A3A3 | secondary text | 8.3 / 7.7 / 7.1 |
| `text3` | #808080 | tertiary text | 5.3 / 4.9 / 4.5 |
| `disabled` | #4D4D4D | disabled only | 2.5 |
| `waveCut` | #3A3A3A | cut bars (also height-coded) | decorative |
| `onWhite2` | #6B6B6B | secondary text on white | 5.3 on white |
| `offer` | #FF453A | flash offer only, on `bg` only; never on raised/white, never under white text | 6.16 on #000 |
| `offerDim` | `offer` 35% | flash offer hairlines | decorative |

Scrim is black 90%. There are no gradients, shadows or blur materials; the old blue-black `LinearGradient` is removed everywhere.

**Type** (SF only; apply via `.monoText(_:)`, which scales with `@ScaledMetric`). Never uppercase programmatically, because Turkish i/İ breaks.

| Token | Spec |
|---|---|
| `display` | 40 semibold, tracking −1.2, lineLimit 2, minimumScaleFactor 0.7 |
| `title` | 28 semibold, tracking −0.6 |
| `numeralXL` | 56 medium, `.width(.expanded)`, monospacedDigit, tracking −1 |
| `numeralL` | 34 semibold, expanded, monospacedDigit |
| `numeralM` | 20 medium, `.monospaced` design |
| `headline` | 17 semibold, tracking −0.2 |
| `body` | 15 regular |
| `label` | 13 medium |
| `overline` | 11 medium, monospaced, tracking +0.8, natural case |
| `caption` | 12 regular |

**Spacing:** 4, 8, 12, 16, 24, 32, 48. **Radii** (continuous): chip 10, native ad 12, card 24, sheet 28; all buttons and controls are capsules.

**Motion:**
- `snappy` = `.spring(response: 0.28, dampingFraction: 0.86)`
- `smooth` = `.spring(response: 0.45, dampingFraction: 0.9)`
- `bouncy` = `.spring(response: 0.5, dampingFraction: 0.68)`
- `fade` = `.easeOut(duration: 0.2)`
- Entrance: offset y 14→0 plus opacity, `smooth`, delay `0.05 * index`.
- Offer sweep 2.4 s / 6 s, countdown linear 1 s, final-minute tick 0.5 Hz.
- `Mono.Motion.pick(_:reduce:)` returns `fade` when Reduce Motion is on. Under Reduce Motion there are no offsets, scales or loops.

**Haptics** (`.sensoryFeedback`, iOS 17):

| Event | Feedback |
|---|---|
| Video picked | `.impact(weight: .medium)` |
| Intensity change | `.selection` |
| Review appears | `.impact(flexibility: .soft)` |
| Cut toggle | `.selection` |
| Keep all / Cut all | `.impact(weight: .medium)` |
| Scrub crosses a cut edge | `.selection` |
| Slider commit | `.impact(weight: .light)` |
| Saved | `.success` |
| Save error, failed state | `.error` |
| Export cancel | `.impact(weight: .light)` |
| Purchase or restore success | `.success` |
| Paywall message appears | `.warning` |

## 3. Components
New files: `CutSense/QuickSilence/MonoKit.swift` and `CutSense/QuickSilence/MonoWave.swift`. That directory is already a `project.yml` source; `CutSense/DesignSystem/` is legacy and not in the target.

- **`MonoPrimaryButtonStyle(outlined: Bool = false)`**
  - Height 56, capsule. Filled: white background, black text; pressed: scale 0.97 and #E6E6E6 (`snappy`); disabled: opacity 0.4.
  - Outlined: clear background, 1.5pt white stroke, white text, never dimmed when disabled.
- **`MonoActionLabel(_ title: String, systemImage: String)`**
  - Title at leading 22 in `headline`, with a trailing 40pt circle chip inset 8.
  - Chip is black with a white glyph on filled buttons, white with a black glyph on outlined ones.
  - The image is `accessibilityHidden`, so the button label equals the title.
- **`MonoSecondaryButtonStyle`**: height 48, capsule, `raised` fill, hairline stroke, white 15 semibold, lineLimit 1, minimumScaleFactor 0.8, pressed → `elevated`.
- **`MonoTertiaryButtonStyle`**: no background, 15 medium `text2`, minimum 44×44, pressed opacity 0.6.
- **`MonoIntensityControl(selection:language:hint:)`** (same signature as `CutIntensityPicker`)
  - Track: 44 high, capsule, `raised`, hairline stroke.
  - Thumb: white capsule inset 3, moved with `matchedGeometryEffect` on `smooth`.
  - Segments are Buttons: selected black 14 semibold, others `text2`, minimumScaleFactor 0.75, `.isSelected` trait. Container label is the existing "Cut intensity" key.
  - Hint line: `caption`, `text2`, lineLimit 2, minHeight 16. When `hint != nil`, show white text prefixed by `exclamationmark.circle` (no orange). Crossfade on change.
- **`MonoToggleStyle`**
  - Label on the left, 51×31 switch on the trailing edge. On: white track, black 27pt knob. Off: clear track, 1.5pt `strong` stroke, `text2` knob. Knob moves on `snappy`; the whole row is tappable.
  - Must include `.accessibilityRepresentation { Toggle(isOn: configuration.$isOn) { configuration.label } }` so XCUITest still sees a switch.
- **`MonoBadge(_ text:, filled: Bool)`**: `overline`, horizontal padding 8, height 22, capsule; filled is white with black text, otherwise hairline stroke with white text.
- **`MonoNotice(text:systemImage:actionTitle:action:)`**: glyph plus `caption` white text (lineLimit 2) plus an optional bold underlined action; `raised` fill, radius 10, padding 10.
- **`MonoProgressRing(progress:size: = 132)`**: 2pt hairline track, 2pt white round-cap trim from −90°, animated with `smooth`.
- **`MonoCheckSeal(size: = 72)`**
  - Black 60% circle, 1.5pt white ring, checkmark `Path` trim 0→1 over 0.35 s, scale 0.8→1 on `bouncy`.
  - One ring pulse: scale 1→2.2, opacity 0.6→0, 0.7 s.
  - Reduce Motion: fade only.
- **`.monoSheet()`**: `.presentationBackground(Mono.C.raised)`, `.presentationCornerRadius(28)`, `.presentationDragIndicator(.visible)`, `.preferredColorScheme(.dark)`. The opaque background fixes the muddy translucent sheet in `raw_cuts.png`.
- **`.monoEntrance(_ index: Int)`**: the entrance token.
- **`SignalField(mode:)`** (hero and progress; `View, Animatable`, `Canvas` in `TimelineView(.animation(minimumInterval: 1/30))`, `accessibilityHidden`)
  - Modes: `.demo`, `.scanning(progress: Double)`, `.flat`.
  - Geometry: 48 slots, `slot = width / 48`, bar width `slot * 0.5`, fully rounded, vertically centred.
  - Envelope: speech at indices 0–10, 17–29, 35–47 with `e = 0.28 + 0.72 * abs(sin(i*1.31)*0.6 + sin(i*0.47+1.3)*0.4)`; silence at 11–16 and 30–34 with `e = 0.05`. Speech bars breathe: `× (0.85 + 0.15 * sin(t*2.4 + i*0.55))`.
  - `.demo` loop (T = 6.4 s):

    | Time | What happens |
    |---|---|
    | 0–2.0 | 1.5pt playhead sweeps left to right; passed speech bars go 0.45→1.0 opacity, passed silence bars go to 0.22 |
    | 2.0–2.4 | playhead fades out |
    | 2.4–3.2 | collapse `c` 0→1 (easeInOut): silence slot width is `slot*(1−c)`, the row re-centres, a 1pt full-height line at white `0.5*c` marks each join |
    | 3.2–5.4 | hold |
    | 5.4–6.4 | `c` back to 0 |

  - `.scanning(p)`: all bars speech-like (`0.2 + 0.8 * abs(sin(i*0.9)*0.5 + sin(i*0.31)*0.5)`), breathing at double speed. Bars with `(i+0.5)/48 <= p` are white 1.0, the rest 0.2; a 1.5pt scan line sits at `p * width`. `animatableData` is `AnimatablePair(progress, amplitude)`.
  - `.flat`: amplitude animates to 0, leaving a 3pt line at white 0.35.
  - Reduce Motion: no timeline. Demo renders the static `c = 1` frame; scanning renders static bars with the progress fill.
- **`WaveformTimeline(bars:plan:playhead:compacted:onScrub:)`** (plain views, not Canvas, so SwiftUI animates it)
  - `HStack(spacing: 0)` of 84 slots; each bar is a capsule of width `slot * 0.6`.
  - Kept: white, height `bars[i] * H`. Cut: `waveCut`, height `max(3, bars[i] * H * 0.35)`. Animated with `smooth.delay(Double(i) * 0.004)`.
  - A bar is cut if an active cut overlaps at least 40% of its time window, or it contains an active cut's midpoint.
  - `compacted == true`: cut slots animate to width 0, so the final video's waveform remains.
  - Playhead: 1.5pt white line at `playhead / duration`, hidden when nil or compacted.
  - With `onScrub`: `DragGesture(minimumDistance: 0)` reports original seconds. Accessibility: one element labelled "Timeline" with `.accessibilityAdjustableAction` in ±5 s steps.
- **`MonoWave.bars(from rms: [Float], count: Int = 84) -> [Float]`**: per-bucket max; divide by the 95th percentile (floor 1e-4); clamp to 1; `pow(v, 0.6)`; floor 0.06. Compute once per analysis.
- **Ad containers**
  - Banner (B's call site): opaque black background plus a top hairline. Never touch `AdBannerSlot` or its height.
  - Native (D): spec in section 4.

## 4. Screens
**Shared chrome (B).** Toolbar items are plain glyphs with no custom circle background; iOS 26 already draws its own capsule, which is the double chrome in the screenshots.
- Settings: `gearshape`, 17 medium, white, 44×44.
- Privacy: `hand.raised`, same treatment.
- `proCapsule`: text "PRO" in `overline` bold; on iOS < 26 wrap it in a hairline capsule (`if #available(iOS 26.0, *)`).
- Phase changes animate through a derived `phaseKey: Int` (`Phase` is not Equatable): `.animation(Mono.Motion.smooth, value: phaseKey)`, transition `.blurReplace` (opacity under Reduce Motion).
- `SignalField` sits outside the `switch phase` so its identity survives the 350 ms progress updates.

**Home (idle)**, left-aligned, horizontal padding 24:
1. `Spacer(minLength: 8)`
2. `SignalField(.demo)`, height 96
3. 28 gap, then overline "CutSense" in `text3`
4. Title "Cut Silence" (existing key) in `display`
5. Existing subtitle in `body`, `text2`
6. `Spacer`
7. `MonoIntensityControl`
8. 16 gap, then `PhotosPicker` with `MonoActionLabel(Choose Video, "plus")`, `MonoPrimaryButtonStyle`, id `chooseVideoButton`
9. 12 gap, then "Free · No watermark · On-device" in `overline`, `text3`, centred
- Entrance indices 0–5. Vertical padding 16, plus the existing banner inset.

**Processing**, centred, vertical padding 16:
1. `SignalField(.scanning(progress))`, height 64, with `.animation(.easeOut(duration: 0.4), value: progress)`
2. Percent in `numeralXL` with `.contentTransition(.numericText(value:))`
3. `state.title` in `headline`
4. Cancel as tertiary
5. `NativeAdCard` under the existing gating, unchanged
- The block is one accessibility element (label = title, value = percent, `.updatesFrequently`).
- 16e budget: 719 − banner ≈131 − 32 = 556 available; content is 64+12+64+4+22+12+44+16+236 = 474.

**Failed:**
1. `SignalField(.flat)`, height 64
2. Title "This video couldn't be processed" in `title`
3. Message in `body`, `text2`
4. `MonoActionLabel(Try Again, "arrow.clockwise")`
- `.error` haptic on entry.

**Review (C)**, `VStack(spacing: 0)`, horizontal 16, bottom 8:

| Element | Height | Gap after |
|---|---|---|
| Video stage: system `VideoPlayer`, radius 24, hairline stroke, loading spinner | flexible, min 220 | 10 |
| `WaveformTimeline` 44 + time row 14 (`0:00` left, total right, `overline`, `text3`, `accessibilityHidden`) | 58 | 12 |
| Stats | 52 | 12 |
| `MonoIntensityControl` | 66–80 | 10 |
| Review cuts + Fine-tune, both secondary | 48 | 10 |
| `MonoNotice` (only when `saveError`; glyph `exclamationmark.triangle`, action "Open Settings") | 40 | 10 |
| Save (flexible primary) + 56pt Share circle | 56 | 6 |
| New Video, tertiary | 40 | n/a |

- **16e budget (763 safe − 44 nav = 719):** fixed 334 + gaps 60 + padding 12 leaves 313 for video; worst case (2-line hint plus notice) leaves 263.
- **Stats:** asymmetric, no cards.
  - Left: `numeralL` "37%" with caption "removed".
  - Then, behind 28pt-high hairline dividers, two smaller cells: `numeralM` time with caption ("silence", "new length").
  - Values use `.contentTransition(.numericText())` on `smooth` and count in from 0 on first appear.
  - The time values must stay separate `Text` elements with the plain `m:ss` label. Do not use `children: .combine`: the UI test regex `^[0-9]+:[0-9]{2}$` reads them.
- **Buttons:**
  - Save: `MonoActionLabel("Save to Photos", "arrow.down")`. When `saved`, the same button becomes `outlined: true` with "Saved to Photos" and a `checkmark` chip, crossfaded via `.contentTransition(.symbolEffect(.replace))`.
  - Share: `MonoSecondaryButtonStyle` circle, `square.and.arrow.up`, label "Share".
  - All existing identifiers stay.
- **Saved moment** (`onChange(of: saved)` to true, total ≤ 1.2 s because the rating prompt fires then):
  - `.success` haptic.
  - `WaveformTimeline.compacted = true`.
  - `MonoCheckSeal` over the video centre: in 0.25 s, hold 0.7 s, out 0.25 s, `allowsHitTesting(false)`.
  - New Video text turns white.
  - `compacted` resets when `saved` goes false.
- **Entering review:** `.impact(.soft)`; bars grow from 0 height with the stagger.

**Cut list sheet (C)**, system `.sheet`, detents medium/large, `.monoSheet()`, no `NavigationStack`:
1. Header (padding 20): "%d cuts" in `title` 22, with "Removing %@" trailing in `overline`, `text2`.
2. Mini `WaveformTimeline`, height 28, non-interactive.
3. Two secondary buttons, height 40: `keepAllCutsButton` and `cutAllButton`, same disable logic, disabled opacity 0.35.
4. `ScrollView` + `LazyVStack` rows, 60 high, hairline separators:
   - index "01" in `overline`, `text3`, width 28;
   - a Button with the existing row title format in mono 15 (white when cut, `text3` when kept) that seeks on tap;
   - a `Toggle` with `MonoToggleStyle` whose label is "Cut"/"Keep" in `label`, with the same accessibility label, value and `cutToggle_<id>`.
5. Empty state: existing string, centred.

**Fine-tune sheet (C)**, `.height(300)`, `.monoSheet()`:
- Title in `title` 22.
- Two blocks, each: name (15 semibold) with value (`numeralM`, numericText) on the right, a system `Slider` with `.tint(.white)`, and a caption in `text3` (new keys 3 and 4).
- Commit on drag end is unchanged.

**Export overlay (C):**
- 90% scrim.
- `MonoProgressRing` with percent in `numeralL` inside (numericText).
- "Creating video" in `headline`; "Keep the app open." in `caption`, `text2`.
- Cancel as tertiary.
- Ring enters with scale 0.92→1 plus fade.

**Rewarded intro card (B, `ProcessingAdCountdownView`)**; copy, timing and logic unchanged:
- Card: `raised` at 97%, radius 24, hairline stroke, padding 16.
- 48pt countdown ring: 2pt white trim 1→0 linear over 1 s, re-keyed per tick, number inside in `numeralM` (numericText, counting down).
- Overline "Ad break" plus the status text in `caption`, `text2`, `fixedSize(vertical)`.
- Skip: secondary, 36 visual / 44 hit, id `skipAdButton`.
- "Remove ads forever": white capsule, 44 high, black 15 semibold.
- Thanks state: `checkmark` in the ring with `.symbolEffect(.bounce, value:)`.
- Transition: `.move(edge: .top)` plus opacity (opacity only under Reduce Motion).

**Paywall (D)**, black background:
1. Close: 44pt, `xmark`, `text2`.
2. Overline "CutSense Pro".
3. Headline (new key 1) at 34 semibold, tracking −0.8, lineLimit 3, minimumScaleFactor 0.8.
4. Subline: existing "Fine-tune: minimum pause and breathing room" in `body`, `text2`.
5. Comparison table (the centrepiece):
   - No card background; rows 48 high with hairlines; columns are label (flexible), Free 64, Pro 72.
   - The Pro column sits on one white `RoundedRectangle(20)` spanning header and rows. Header "Pro" is black bold; Pro checkmarks are black bold.
   - Free marks: `checkmark` in `text2`, or `minus` in `disabled`.
   - Reveal: Pro column mask height 0→full on `smooth` after 0.15 s; rows use `monoEntrance(i)`.
6. Pinned footer:
   - optional message in `caption`, `text2`;
   - CTA `MonoActionLabel("Unlock for %@", "arrow.right")` (black `ProgressView` while working);
   - caption "One-time purchase. No subscription.";
   - "Restore Purchases" as tertiary (label unchanged);
   - Terms · Privacy in `text3`.
- The three old bullets are removed; their translation rows may stay.

**Settings (D)**: keep `List` (insetGrouped) for accessibility and test safety.
- Chrome: `.scrollContentBackground(.hidden)`, black background, `.listRowBackground(Mono.C.raised)`, `.listRowSeparatorTint(Mono.C.hairline)`, `.tint(.white)` (removes the blue links), headers in `overline` with `.textCase(nil)`.
- First row when not Pro: a white card (radius 24, padding 20) with "CutSense Pro" in black `headline`, "One-time purchase. No subscription." in `onWhite2`, and a trailing black arrow chip.
  - It is a Button that opens the paywall, with accessibility label "Unlock Pro".
  - It replaces the old "Unlock Pro" row, so the IAP stays reachable for App Review.
- Every row gets a leading 17pt `text2` glyph in a 28pt frame: `globe`, `internaldrive`, `trash`, `arrow.clockwise`, `hand.raised`, `doc.text`, `doc.plaintext`, `questionmark.circle`, `info.circle`. Links get a trailing `arrow.up.right` at 12, `text3`.
- Storage row: `HStack { Image; LabeledContent(title, value:) }.accessibilityElement(children: .combine).accessibilityIdentifier("storageUsageRow")`; value uses numericText.
- Pro status when Pro: "Unlocked" plus `checkmark.seal.fill`.
- New row when `AdFreePass.expiry != nil && !isPro`: "Banner ads paused until" plus the formatted date.

**Native ad (D):**
- Background `elevated`, hairline border on the layer, SwiftUI clip radius 12 (no larger, or AdChoices gets clipped).
- Badge: white text in a 1pt white-50% bordered pill, 10 bold; no yellow.
- CTA: white capsule, black text.
- Height stays 236.

**New English keys** (A adds seven languages each; grep for duplicates first):

| # | English | Turkish | Used by |
|---|---|---|---|
| 1 | "No ads. Finer control. Pay once." | "Reklam yok. Daha ince ayar. Tek ödeme." | D |
| 2 | "Removing %@" | "%@ kesiliyor" | C |
| 3 | "Pauses shorter than this are kept." | "Bundan kısa duraklamalar kalır." | C |
| 4 | "Silence left around each sentence." | "Her cümlenin etrafında bırakılan sessizlik." | C |
| 5 | "This video couldn't be processed" | "Bu video işlenemedi" | B |
| 6 | "Banner ads paused until" | "Banner reklamlar şu saate kadar kapalı" | D |
| 7 | "Timeline" | "Zaman çizelgesi" | C |

## 5. App icon: redesign
The current icon is dark grey on black (illegible at 60 px) and weighs 1.0 MB. PIL recipe, 1024×1024 RGB, no alpha:
- Background: vertical gradient #1C1C1C (top) → #000000.
- Six white bars, width 72, radius 36, centred on y = 512. (x-left, height): (150, 200), (262, 440), (374, 300), (578, 360), (690, 520), (802, 240).
- Cut line: white rounded rect x 502–522, y 172–852, radius 10.
- Save as `icon_1024.png`; produce every other existing size with `sips -z`, same file names; leave `Contents.json` alone.
- `SplashLogo.imageset`: the same shapes on transparent RGBA at 600, then Lanczos to 400 and 200, existing names.

## 6. Work breakdown (zero file overlap)

| Task | Files | When |
|---|---|---|
| A0 | `MonoKit.swift`, `MonoWave.swift` (new), `Services/Translations.swift`, plus the one-off seam below | first, blocking |
| B | `QuickSilence/QuickSilenceView.swift` | after A0, parallel |
| C | `QuickSilence/ReviewScreen.swift` | after A0, parallel |
| D | `Pro/PaywallView.swift`, `UI/SettingsScreen.swift`, `Ads/NativeAdCard.swift`, `AppIcon.appiconset/*.png`, `SplashLogo.imageset/*.png` | after A0, parallel |
| Integration | legacy symbol removal | last, by the executor |

1. **A0**
   - Create the two files and add the seven translation rows.
   - Seam: add `let waveform: [Float]` to `ReviewScreen` directly after `plan`, and pass `waveform: analysis?.windowRMS ?? []` in `QuickSilenceView.review(...)`.
   - Run `xcodegen generate` in `ios/` (the pbxproj is yml-derived). Nobody else adds files.
   - Accept: build is green; `xcodebuild test -scheme CutSense` passes `TranslationsTests`; a temporary `#Preview` shows every component.
2. **B**: home, processing, failed, toolbar, banner frame, intro card. Do not delete `QSPrimary`, `QSSecondary` or `CutIntensityPicker`; just stop using them. Logic lines 310–680 are untouched except for adding `.sensoryFeedback`.
3. **C**: review, cut sheet, fine-tune, export overlay, saved moment. Stop using `qsAccent` but do not delete it.
   - **C5 (last, cuttable): playhead and scrub.** Additive members on `PreviewPlayer`:
     - `private(set) var originalTime: Double`, fed by one 1/20 s periodic observer.
     - Clock mapping: `usesFallback ? t : walk keepRanges` (accumulate lengths until `t` falls inside one).
     - `func scrub(toOriginal:)` with 0.05 s tolerance.
     - Only a small `PlayheadTimeline` subview reads `originalTime`, so the screen body does not re-evaluate at 20 Hz.
4. **D**: paywall, settings, native ad, icon.
5. **Integration**: once `grep -rn "qsAccent\|QSPrimary\|QSSecondary\|CutIntensityPicker\|accent" CutSense/QuickSilence CutSense/Pro` shows only definitions, delete them. The coordinator serialises builds (one DerivedData, tight disk); B, C and D do not build concurrently.

**Screenshots** (simulator `3C9044C5-36C3-4899-BAEB-6A9563BB790E`; launch with `SIMCTL_CHILD_<VAR>=… xcrun simctl launch <id> com.cutsense.app`; capture with `xcrun simctl io <id> screenshot`; each one both full size and with `CUTSENSE_CLAMP_16E=1`):

| Owner | Shots |
|---|---|
| B | home at two points of the loop (t ≈ 1 s and t ≈ 4 s); processing (`CUTSENSE_AUTORUN_VIDEO_URL=/tmp/claude-501/demo_talk.mp4`, `CUTSENSE_AUTORUN_HOLD_SECONDS=6`); failed (autorun URL pointing at a missing file); intro card (non-Pro, 2–4 s after review appears) |
| C | review free; review with `CUTSENSE_FORCE_PRO=1`; cut sheet; fine-tune; export overlay; saved state; German review (language set in Settings) |
| D | paywall (`CUTSENSE_SHOW_PAYWALL=1`) in EN and DE; settings free and Pro; native ad during processing; icon at 60 px |

## 7. Further product improvements

| Improvement | This release? |
|---|---|
| Full haptics map | Yes |
| Hero loop as the onboarding moment (no separate onboarding screen) | Yes |
| Real waveform, animated stats, saved moment | Yes |
| Mini waveform in the cut sheet | Yes |
| Ad-free pass row in Settings | Yes |
| Icon diet (about −1 MB) | Yes |
| Playhead and waveform scrubbing | Yes, as C5, first to cut |
| Before/after hold-to-compare (needs a second player item) | Next |
| "Audition this cut" loop per row | Next |
| Drag cut edges, pinch-zoom the waveform | Next |
| Undo for toggles | Next |
| Custom player chrome | Next |
| Export Live Activity | Next |
| UI sound design | Next |

**Cut order under time pressure:** C5 scrub → the `AdFreePass` row → paywall column reveal → cut-sheet mini waveform → splash regeneration. Never cut the home hero, the real waveform or the saved moment; those are what make the redesign visible.

**Dokunma:**
- `QuickSilenceEngine`, `WorkFiles`, `ProStore`, `AdMobService.swift` (including `AdBannerSlot` and `AdFreePass`), `AdMobIDs`, `project.yml`, `Info.plist` ve test dosyalarına dokunulmaz.
- `QuickSilenceView` içinde reklam zamanlaması/gating, export, import ve teardown fonksiyonlarının gövdeleri aynı kalır.
- Erişilebilirlik kimliklerinin tamamı korunur.
- Şu İngilizce etiketler değişmez: "Saved to Photos", "Restore Purchases", "Unlock for …". Pro iken "Unlock" ile başlayan hiçbir buton görünmez.
- Stat süreleri ayrı `Text` kalır; yeni `m:ss` etiketleri (zaman satırı) `accessibilityHidden` olur.
- Kesim listesi sistem `.sheet` olarak kalır (test `swipeDown` ile kapatıyor).
- Reklamların üstüne animasyon bindirilmez, AdChoices kırpılmaz, ödül metni ve Skip kalır.
- Yeni SPM paketi, font dosyası, Lottie ve programatik uppercase yok.

**Doğrulama:**
- **Build ve test:** `cd /Users/jinx/Documents/projeler/CutSense/ios && xcodegen generate`, ardından `CutSense` şemasıyla build ve `xcodebuild test -scheme CutSense -destination 'id=3C9044C5-36C3-4899-BAEB-6A9563BB790E'`; `TranslationsTests` dahil yeşil olmalı.
- **Kimlikler:** `grep -rn "chooseVideoButton\|settingsButton\|proCapsule\|reviewCutsButton\|fineTuneButton\|saveButton\|newVideoButton\|cutToggle_\|keepAllCutsButton\|cutAllButton\|skipAdButton\|storageUsageRow" CutSense/QuickSilence CutSense/UI/SettingsScreen.swift` çıktısında 12 kimliğin hepsi bulunmalı.
- **Renk temizliği:** `grep -rn "orange\|\.blue\|red: 182\|LinearGradient\|design: .rounded" CutSense/QuickSilence CutSense/Pro CutSense/UI/SettingsScreen.swift CutSense/Ads/NativeAdCard.swift` boş dönmeli.
- **Toggle:** kesim sheet'i açıkken erişilebilirlik dökümünde (xcodebuildmcp `describe_ui`) `cutToggle_0` tipi Switch olmalı. Değilse geri dönüş: sistem switch stili + `.tint(Color(white: 0.5))`.
- **Ekranlar:** bölüm 6'daki görüntüler. 16e clamp'te kırmızı çerçeve içinde review kaydırmasız sığmalı ve video en az 220 pt olmalı; Almanca'da kırpılma olmamalı.
- **Hata yolları:** eksik dosyayla failed ekranı; depolama ya da izin reddinde `MonoNotice` + "Open Settings"; ürün yüklenemezse paywall mesajı.
- **Reduce Motion:** açıkken home statik kare göstermeli, kayıt anında yalnız fade olmalı.
- **Boyut:** arşivlenmiş uygulama 6.1 MB + 1.5 MB sınırının altında kalmalı (ikon küçüldüğü için net azalma beklenir).

**Risk:**
- UNVERIFIED: `accessibilityRepresentation` ile dıştaki `accessibilityIdentifier`/label/value'nun Switch öğesine taşınması; geri dönüş yukarıda tanımlı.
- UNVERIFIED: `DeviceFlowUITests` yalnız cihaz şemasında (`CutSenseDevice`); bu çalışmada koşturulmadı. Uyumluluk grep ve erişilebilirlik dökümüyle kanıtlanacak, teslimden önce iPhone 16e'de bir tur gerekir.
- UNVERIFIED: iOS 26 araç çubuğu camının düz glifle tek krom vereceği; iOS 17/18 görünümü simülatörde doğrulanamaz (tek simülatör kuralı).
- UNVERIFIED: 16e'de `largeAnchoredAdaptiveBanner` yüksekliği ekran görüntüsünden yaklaşık 123 pt ölçüldü; processing bütçesi buna göre hesaplandı.
- UNVERIFIED: Reduce Motion'ın simülatörde komutla açılması; gerekirse Ayarlar uygulamasından açılır.
- RISK: C5, composition ve fallback saatlerini karıştırırsa playhead kayar; ilk kesilecek kalem bu.
- RISK: Sistem `VideoPlayer` kromu bilinçli olarak korundu (AirPlay ve erişilebilirlik bedava geliyor); özel oynatıcı sonraki sürüme kaldı.
- RISK: B, C ve D derlemeden yazacağı için entegrasyonda derleme hatası turu beklenir.
- Bakılmayanlar: `AdMobService` banner iç yerleşimi, JA/KO'da expanded rakam genişliği, diğer 7 dilin çevirileri (A0 yazacak). Hiçbir kod yazılmadı ve build alınmadı; bu yalnız spesifikasyondur.