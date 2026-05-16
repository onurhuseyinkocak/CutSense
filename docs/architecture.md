# CutSense Architecture

## Overview

Local-first AI video editing on iOS with Supabase metadata sync.

## Data Flow

```
Raw Video (local)
  → AudioAnalysisService (waveform, silence, energy)
  → SpeechTranscriptionService (Apple Speech → timestamped transcript)
  → ContextAwareEditCommandDetector (edit command vs content)
  → TranscriptCleanupAnalyzer (filler, restarts, self-corrections)
  → TakeDetectionEngine (group repeated attempts)
  → BestTakeSelector (score 0-100, pick winner)
  → MeaningPreservationEngine (verify coherence)
  → ContinuityChecker (verify transitions)
  → RoughCutDecisionEngine (keep/cut/trim/review decisions)
  → CleanTimelineBuilder (AVMutableComposition)
  → CaptionEngine (role + style + scene events)
  → EditDecisionEngine (SFX + motion + effects with reason)
  → ExportService (1080x1920 MP4 → Photos)
```

## iOS Architecture

MVVM with service layer.

- **Views**: SwiftUI screens
- **ViewModels**: @Observable classes
- **Services**: Business logic (auth, video, rough cut, captions, export)
- **Repositories**: Supabase CRUD with RLS

## Database

Supabase Postgres with RLS. Tables:
- profiles, projects, transcripts, transcript_segments
- rough_cut_decisions, take_groups, takes
- caption_segments, edit_decisions, exports

All tables have user_id FK + RLS policies (own rows only).

## Web

Minimal Next.js on Vercel. Landing page + future admin dashboard.
Not used for video processing.

## Security

- Anon key in iOS client (safe with RLS)
- Service role key server-side only (Vercel env)
- Raw video stays local, never uploaded by default
- Sign in with Apple + email/password auth
