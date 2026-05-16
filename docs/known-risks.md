# CutSense Known Risks

| Risk | Severity | Status | Mitigation |
|------|----------|--------|------------|
| Apple Speech word-level timestamps may be imprecise | High | Active | Breathing room buffer (0.15s) around cut points |
| On-device export performance on older iPhones | Medium | Active | 1080x1920 cap, AVAssetExportPreset1920x1080 |
| CoreGraphics caption rendering quality | Medium | Active | 5 tested styles, UIFont system fonts for consistency |
| Over-automation destroying meaning | Critical | Mitigated | MeaningPreservationEngine + ContinuityChecker + mandatory user review |
| Turkish filler word detection false positives | High | Mitigated | ContextAwareEditCommandDetector with content pattern analysis |
| Large video memory pressure | Medium | Active | Stream processing via AVAssetExportSession, no full video in memory |
| Take detection false grouping | Medium | Active | 0.4 word overlap threshold + 5s max gap + user review before export |
| Non-best take auto-cut may remove wanted content | Medium | Mitigated | User can restore any cut segment in RoughCutReviewScreen |
| Caption burn-in irreversible | Low | Active | Preview screen with quality gate before export |
| No offline Supabase sync | Low | Accepted | Local-first architecture, metadata sync is supplementary |
| AVMutableVideoComposition deprecated in macOS 26 | Low | Tracked | iOS 17+ target unaffected; monitor for iOS deprecation |
| No App Store screenshots or app icon | Low | Open | Needed before first TestFlight submission |
