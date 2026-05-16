# CutSense Development Phases

## Phase 0 — Repo/Foundation (CURRENT)
- [x] Project structure
- [x] CLAUDE.md
- [x] README.md
- [x] docs/
- [x] Supabase migrations
- [x] iOS project scaffold
- [x] Next.js web scaffold
- [x] GitHub repo
- [x] Vercel deploy

## Phase 1 — Supabase + Auth
- [ ] iOS Supabase client
- [ ] Sign in with Apple
- [ ] Email/password auth
- [ ] Session persistence
- [ ] Auth screen UI
- [ ] Projects screen empty state

## Phase 2 — Project CRUD
- [ ] ProjectRepository
- [ ] Create/list/update/delete projects
- [ ] Metadata sync to Supabase

## Phase 3 — Video Import + Basic Export
- [ ] VideoImportService (PhotosPicker)
- [ ] VideoMetadataService
- [ ] VideoPreviewEngine
- [ ] ExportService (normalized 1080x1920 MP4)

## Phase 4 — Audio Analysis + Transcription
- [ ] AudioAnalysisService
- [ ] SpeechTranscriptionService
- [ ] Silence/pause detection

## Phase 5 — Rough Cut Engine
- [ ] ContextAwareEditCommandDetector
- [ ] TakeDetectionEngine + BestTakeSelector
- [ ] MeaningPreservationEngine
- [ ] ContinuityChecker
- [ ] RoughCutDecisionEngine

## Phase 6 — Rough Cut Review + Clean Timeline
- [ ] RoughCutReviewScreen
- [ ] CleanTimelineBuilder
- [ ] Audio fade at cut boundaries

## Phase 7 — Caption Engine
- [ ] CaptionEngine + role classifier
- [ ] 5 caption styles (Hook Impact, Bold Center Viral, Premium Lower Third, Focus Statement, Minimal Wellness)
- [ ] CaptionReadabilityGuard

## Phase 8 — Caption Scene Events
- [ ] hookImpact, focusBlur, underlineReveal, keywordLockOn, transitionWhoosh, conclusionHold

## Phase 9 — Edit Decisions + SFX
- [ ] EditDecisionEngine
- [ ] IntensityLimiter + OverEditingGuard
- [ ] AudioMixService + AudioQualityGuard

## Phase 10 — Templates
- [ ] Premium Founder
- [ ] Viral Caption
- [ ] Clean Expert

## Phase 11 — Quality Gate + Device QA
- [ ] QualityGateService
- [ ] Real device testing matrix
- [ ] Edge case handling
