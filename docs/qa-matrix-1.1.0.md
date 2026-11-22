# CutSense iOS 1.1.0 — QA scenario matrix

Device: iPhone 16e (iOS 26.5). Build: Debug, scheme CutSenseDevice (local StoreKit config).
Fixtures: generated with ffmpeg/`say` (recipes in "Fixtures"), copied to the app's Documents
(`devicectl device copy to`) and either run through the DEBUG autorun path
(`CUTSENSE_AUTORUN_VIDEO_URL=qa/<file>`: analyze → review → export, skips only the PhotosPicker copy)
or seeded into Photos (`CUTSENSE_QA_SEED_PHOTOS=1`, DebugQASeed.swift) and picked through the real picker.
Tests: `ios/CutSense/Tests/UI/EdgeCaseUITests.swift` (+ existing `DeviceFlowUITests.swift`).

Status legend: PASS · FAIL · FIXED (failed, fixed, re-run green) · UNVERIFIED (not run / not automatable).
The Status column is filled in by the run; evidence = xcresult/screenshot path in the report.

## A. Fixtures (pick → analyze → review → save)

| # | Fixture | Expected |
|---|---------|----------|
| A1 | 01 talk 1080p30 H.264, pauses | review shows cuts (~3 pauses), save to Photos works |
| A2 | 02 4K HEVC 60 fps | review + preview play, export keeps 3840x2160 (or clean fallback) |
| A3 | 03 landscape with rotation=90 metadata | preview + export keep orientation |
| A4 | 04 portrait 9:16 | review, export portrait |
| A5 | 05 one-second tone | nothing to cut → review with 0 cuts or clear message, no crash |
| A6 | 06 20-minute talk (low bitrate) | progress moves, Cancel works, review reached, export finishes |
| A7 | 07 continuous music | few/no cuts, low-speech hint, no crash |
| A8 | 08 silent audio track | "No speech was found" failed state, Try Again → home |
| A9 | 09 no audio track | "This video has no audio" message |
| A10 | 10 speech at −40 dB | adaptive threshold still finds speech (or no-speech message), no crash |
| A11 | 11 clipping loud speech | cuts found, export works |
| A12 | 12 variable frame rate | review + export, A/V stays in sync (duration matches plan) |
| A13 | 13 8 kHz mono audio | analysis works |
| A14 | 14 two audio tracks | analysis uses first track, export works |
| A15 | 15 odd resolution 1082x1922 | export works |
| A16 | 16 120 fps 1080p | export works |
| A17 | 17 truncated mp4 (no moov) | Photos rejects it at seed time; autorun → clean load/no-video error |
| A18 | owner's real 4:34 camera clip (picker) | imports, review, save |
| A19 | iCloud-optimized (not downloaded) video | download progress, then review |
| A20 | HDR / Dolby Vision camera recording | imports, export plays in Photos |

## B. Review actions (on A1)

| # | Scenario | Expected |
|---|----------|----------|
| B1 | change intensity Balanced → Tight → Hardcore | cut count / new length update, no export |
| B2 | Review cuts → Keep all | new length = original |
| B3 | Cut all after Keep all | length back |
| B4 | restore one cut | new length changes |
| B5 | fine-tune when not Pro | paywall opens |
| B6 | fine-tune when Pro | fine-tune sheet opens, apply re-plans |
| B7 | Share → sheet opens → cancel | back on review, no stuck overlay |
| B8 | New Video | home, storage 0 |

## C. User errors

| # | Scenario | Expected |
|---|----------|----------|
| C1 | double / triple tap Choose Video | one picker |
| C2 | double tap Save | one export, one Photos asset |
| C3 | double tap Share | one share sheet |
| C4 | Save then immediately Share | second action ignored while exporting |
| C5 | double tap New Video | home, no crash |
| C6 | double tap Keep all / intensity segments | consistent final state |
| C7 | double tap Skip on ad card | card gone, no crash |
| C8 | New Video during export (if reachable) | export cancelled, home |
| C9 | swipe-dismiss cut sheet mid-animation | review usable |
| C10 | background during analyze → reopen | finishes or clean error, no stuck UI |
| C11 | background during export → reopen | finishes or clean error on review |
| C12 | terminate during export → relaunch | home, Settings storage 0 |
| C13 | Photos permission denied → Save | notice with Open Settings |
| C14 | Photos limited access → pick | picker works (picker is out-of-process) |
| C15 | cancel import/analysis on long video | home, storage 0 |

## D. Purchase (local StoreKit)

| # | Scenario | Expected |
|---|----------|----------|
| D1 | clear transactions → PRO capsule visible | yes |
| D2 | open paywall twice fast | one sheet |
| D3 | buy → cancel at sheet | still free, paywall usable |
| D4 | buy → confirm | capsule gone, fine-tune unlocked |
| D5 | restore with nothing | no Pro, message |
| D6 | restore with purchase | Pro kept |

## E. Environment

| # | Scenario | Expected |
|---|----------|----------|
| E1 | language switch mid-review (Settings) | review strings switch, plan kept |
| E2 | Dynamic Type XXXL home/review | no clipped primary buttons |
| E3 | accessibility audit home / review / settings | no critical issues |
| E4 | low free disk (device had 177 MB free + 75 GB purgeable) | import works or clear storage message |

## Fixtures

All in `scratchpad/qa-fixtures` (deleted after the run). Speech track = macOS `say` with 2 s / 1.5 s / 3 s pauses, 16.2 s.
`testsrc2` video; H.264 `-preset veryfast`, AAC. 02 = libx265 hvc1 3840x2160@60. 03 = `-display_rotation 90` remux.
06 = speech looped to 1200 s, 640x360@24, 150 kb/s. 07 = modulated two-sine tone 30 s. 08 = anullsrc. 09 = video only.
10 = `volume=-40dB`. 11 = `volume=30dB` + limiter. 12 = `select` filter + `-fps_mode vfr`. 13 = `-ar 8000 -ac 1`.
14 = speech + 300 Hz sine as second track (.mov). 15 = 1082x1922. 16 = 1080p120. 17 = first 1.5 MB of 01.

## Status — round 1–3 (2026-11-21, device runs r1/r2/r3; evidence in scratchpad/qa/*.xcresult)

Entitlement state in r1: leftover local Pro (no ads, no ad break) for EdgeCase tests; OfferFlow ran free after clearing transactions.
"Engine only" = autorun path (PhotosPicker copy not exercised).

| # | Status | Evidence / note |
|---|--------|-----------------|
| A1 01 talk 1080p | PASS (engine only) | r1 testFixture01, saved |
| A2 4K HEVC60 | PASS (engine only) | r1 testFixture02 |
| A3 rotated | PASS (engine only) | r1 testFixture03 |
| A4 portrait | PASS (engine only) | r1 testFixture04 |
| A5 1 s | PASS (engine only) | r1 |
| A6 20 min | PASS (engine only) | r1 background-analyze, background-export, terminate tests; review 36% removed |
| A7 music | PASS (engine only) | r1 |
| A8 silent track | PASS (message) | "No speech was found…" shown; test step Try Again re-run pending (tap helper fixed) |
| A9 no audio | PASS (message) | "This video has no audio track…" |
| A10 −40 dB | PASS (no-speech message) | arguably correct at −40 dBFS |
| A11–A16 | PASS (engine only) | r1 |
| A17 truncated | FIXED (code), re-run pending | was "try a softer cut setting"; now unreadable-file message |
| A18 owner 4:34 clip via picker | FIXED (import) | was Photos export failure after 2.5 min transcode; with `.current` review in ~24 s (pick2 review screenshot). Save not yet confirmed: device auto-lock/lost connection |
| A19 iCloud-only clip | UNVERIFIED | none available on device |
| A20 HDR/Dolby Vision camera clip | UNVERIFIED | needs a camera recording |
| B1–B4 | PASS | r1 testIntensityKeepAllCutAllAndDoubleTaps |
| B5/B6 fine-tune | UNVERIFIED this round |
| B7 share open/cancel | share sheet opens (r1 screenshot); cancel assertion re-run pending |
| B8 new video → storage 0 | PASS | r1 storage "Zero KB" |
| C2 triple Save + Share during export | PASS | r1 testDoubleTapSaveThenShare |
| C10 background during analyze | PASS | r1 |
| C11 background during export | PASS | r1 (saved after return) |
| C12 terminate during export → storage 0 | PASS | r1 |
| C13 Photos denied → Open Settings | PASS | r1 screenshot |
| C15 cancel long analysis | test-tap issue fixed, re-run pending |
| D1/D3 paywall + cancel at sheet | PASS | r1 (capsule visible after clear, cancel kept paywall) |
| D4/D6 buy/restore | re-run pending (empty-restore message wait was 15 s) |
| E2 Dynamic Type AX-XXXL | FIXED (home clipped; capped like review) re-run pending |
| E3 accessibility audit | PASS w/ notes | only intentional Dynamic Type caps + disabled "Clear" contrast |
| Onboarding pages 1–3, Skip, persist | PASS | r1 OfferFlow; sim screenshots EN/DE/ES/FR |
| Onboarding badge truncation (de/es) | FIXED | sim screenshots |
| Offer pill/panel/expiry/Pro-owner | PASS (sim, old policy) | needs re-run under new owner policy |
| Cut audition + Before/After | IMPLEMENTED, device screenshots pending | r2/r3 blocked: device locked |

## Status — round 4 (2026-11-22, device runs e4/e5/e6; evidence in scratchpad/qa/e4|e5.xcresult, att-e4, att-e5)

Free user (ads on, banner pass until Nov 24) for EdgeCase. Developer certificate trusted (runner launches).

| # | Status | Evidence / note |
|---|--------|-----------------|
| A1–A5, A7–A17 (engine) | PASS | e4 + e5 rerun (05/11/14 had failed from test helper; green in e5) |
| A6 / C10 / C11 / C12 / C15 | PASS | e4 long-video tests |
| B1–B4, C6, C9 | PASS | e4 testIntensityKeepAllCutAllAndDoubleTaps |
| B7 share open/cancel | PASS | e5 testDoubleTapShareThenCancel |
| C2/C4 triple Save + Share during export | test fixed, re-run pending | probe matched the "36%" removed stat; now uses the overlay's "Creating video" label |
| C13 Photos denied → Open Settings | PASS | e5 |
| E1 language switch, E2 AX-XXXL, E3 a11y audit | PASS | e4 |
| Bug #1 kept pause survives Tight | PASS | e4 tight-after-keep screenshot (0:03–0:05 Keep) |
| Bug #4 Share → Save busy → saved | PASS | e4 testShareThenSaveShowsBusyThenSaved |
| Bug #6 background expiry message | UNVERIFIED | 20-min export finished inside iOS grace period (Saved after 70 s away); message path not triggered on device |
| Bug #9 cold-start flash auto-present | PASS | e5 testFlashAutoOpensOnColdStart (new) |
| Cut audition Before/After, hold-to-compare | PASS | e5 testCutAuditionBeforeAfter, e4 testHoldToCompare |
| Flash pill red countdown + auto-open once (in session) | PASS | e5 flash-pill / flash-auto screenshots |
| Flash pill after relaunch | FAIL → under investigation | e5: after relaunch neither pill nor PRO capsule (products not loaded?); snapshot added |
| Flash expiry → PRO capsule back | PASS | e5 |
| Pro owner sees nothing | PASS | e5 |
| Onboarding skip/swipe | PASS | e5 |
| Welcome $5.99 + Not now | test fixed, re-run pending | double tap on page 2 reached the welcome offer (valid) |
| D3/D5 restore empty | test fixed, re-run pending | AppStore.sync shows Xcode "Sign in" alert; test now answers OK |
| Crash: CheckedContinuation double resume in VideoImportService.loadMovie (build 32) | FIXED (code, compiled) | once-guard in ProgressBox.claimResume |
| Crash: Binding force-unwrap (build 31) | already FIXED | QuickSilenceView no longer uses Binding($plan) |
| DeviceFlow owner 4:34 clip via picker, seeded fixtures | not run | device locked at 10:00 |
