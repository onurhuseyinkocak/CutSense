# Real iPhone QA Checklist

25-step checklist for device testing. Do this before every TestFlight submission.

## Pre-Test
1. [ ] Fresh install (delete app, reinstall from Xcode)
2. [ ] Sign in with Apple ID
3. [ ] Grant all permissions (Photos, Microphone, Speech Recognition)
4. [ ] Prepare test video (30-60s talking head with at least 1 edit command)
5. [ ] Note device model, iOS version, available storage

## Import & Analysis
6. [ ] Import video from Photos library
7. [ ] Analysis starts automatically (progress indicator visible)
8. [ ] Transcription completes (segments visible in UI)
9. [ ] Rough cut decisions shown (keep/cut/review labels)
10. [ ] No crash during analysis
11. [ ] Analysis time < 2x video duration

## Review
12. [ ] Tap segment to review decision
13. [ ] Toggle keep/cut works
14. [ ] Review queue segments marked clearly
15. [ ] Timeline scrubber matches segment positions

## Caption & Effects
16. [ ] Caption preview shows styled text
17. [ ] Hook caption has distinct style
18. [ ] Template selector changes caption appearance
19. [ ] Effect preview shows zoom/flash indicators

## Export
20. [ ] Export button enabled after review
21. [ ] Export progress bar shows
22. [ ] Export completes without crash
23. [ ] Video saved to Photos library
24. [ ] Exported video plays correctly in Photos
25. [ ] Exported video has: audio, captions visible, effects applied, correct duration

## Post-Export
- [ ] Check ExportVerificationReport in Files app (Documents/CutSense/Reports/)
- [ ] Quality score >= 70
- [ ] No "critical" checks failed
- [ ] File size reasonable (< 2x input for same resolution)

## Results
Device: _______________
iOS Version: __________
Test Video Duration: ___s
Analysis Time: ___s
Export Time: ___s
Quality Score: ___/100
Pass: [ ] Yes [ ] No
Notes: ________________
