# CutSense Architecture

## Overview

Local-first AI video editing on iOS with Supabase metadata sync.

## Data Flow

```
Raw Video (local)
  → AudioAnalysisService (waveform, silence, energy, clipping)
  → SpeechTranscriptionService (Apple Speech → timestamped transcript)
  → TranscriptCleanupAnalyzer (fillers, restarts, duplicates)
  → TakeDetectionEngine (group repeated attempts)
  → BestTakeSelector (score 0-100, pick winner)
  → ContextAwareEditCommandDetector (edit command vs content)
  → RoughCutDecisionEngine (keep/cut/trim/review decisions)
  → MeaningPreservationEngine (verify coherence)
  → ContinuityChecker (verify transitions)
  → [User Review — RoughCutReviewScreen]
  → [Template Selection — TemplateSelectionScreen]
  → CaptionEngine (role + style + scene events)
  → CaptionRoleClassifier (hook/reveal/warning/keyword/transition/conclusion)
  → CaptionSceneEventPlanner (behaviors per intensity)
  → CaptionReadabilityGuard (40 chars, 0.8s min, 10 words max)
  → EditDecisionEngine (SFX + zoom + shake + effects)
  → IntensityLimiter (window-based cap)
  → OverEditingGuard (per-minute cap, same-type gap)
  → QualityGateService (7 checks, scoring)
  → [User Preview — CaptionPreviewScreen]
  → CleanTimelineBuilder (AVMutableComposition)
  → CaptionOverlayCompositor (burn captions into frames)
  → AudioMixService (voice boost + fades)
  → ExportService (1080x1920 MP4 → Photos)
```

## iOS Architecture

MVVM with service layer. 43 Swift files.

- **App/** — Entry point, root navigation
- **Auth/** — AuthManager (@Observable), AuthScreen (Apple + email)
- **Core/** — Supabase client
- **Database/** — Models, ProjectRepository
- **Video/** — Import (PhotosPicker), metadata extraction, preview
- **RoughCut/** — Audio analysis, transcription, edit detection, takes, continuity
- **Captions/** — Role classification, scene events, readability guard
- **Editing/** — Templates, edit decisions, intensity/over-editing guards, audio mix/quality
- **Export/** — Timeline builder, caption compositor, export service
- **UI/** — All screens (7 screens in navigation flow)
- **Tests/** — 29 tests across 10 suites

## Navigation Flow

```
AuthScreen → ProjectsScreen → VideoImportScreen → AnalysisScreen
  → RoughCutReviewScreen → TemplateSelectionScreen → CaptionPreviewScreen
  → ExportScreen (sheet)
```

## Templates

| Template | Intensity | Hook Style | Default Style |
|----------|-----------|------------|---------------|
| Premium Founder | Low | Hook Impact | Premium Lower Third |
| Viral Caption | High | Hook Impact | Bold Center Viral |
| Clean Expert | Medium | Focus Statement | Minimal Wellness |

## Database

Supabase Postgres with RLS. 10 tables:
- profiles, projects, transcripts, transcript_segments
- rough_cut_decisions, take_groups, takes
- caption_segments, edit_decisions, exports

All tables have user_id FK + RLS policies (own rows only).

## Web

Minimal Next.js on Vercel. Landing page + future admin dashboard.
Deployed at: web-eta-five-14.vercel.app

## Security

- Anon key in iOS client (safe with RLS)
- Service role key server-side only (Vercel env)
- Raw video stays local, never uploaded by default
- Sign in with Apple + email/password auth
- Swift 6 strict concurrency (SWIFT_STRICT_CONCURRENCY: complete)
- All data types are Sendable
