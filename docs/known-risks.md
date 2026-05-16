# CutSense Known Risks

| Risk | Severity | Mitigation |
|------|----------|------------|
| Apple Speech word-level timestamps may be imprecise | High | Approximate safely, add buffer |
| On-device export performance on older iPhones | Medium | Test on real device, optimize composition |
| Complex CALayer caption rendering in AVVideoComposition | High | Prototype early, have fallback renderer |
| Over-automation destroying meaning | Critical | MeaningPreservationEngine + mandatory review |
| Turkish filler word detection false positives | High | Context window analysis, never blind delete |
| Large video memory pressure | Medium | Stream processing, avoid loading full video in memory |
