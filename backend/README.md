# CutSense backend worker

Manifest-driven AI talking-head editing pipeline. Swift is the client; this
worker does the heavy processing. The **EditManifest** (`src/manifest.ts`) is the
single source of truth — every cut, caption, visual effect and SFX is derived
from it. The LLM may only propose/audit the manifest, never touch pixels.

## Pipeline (slice 1, FFmpeg-only)

`normalize → extract audio → transcribe (Groq) → detect silence → detect bad-takes
→ plan cuts → render clean cut → re-align transcript → build captions → burn
captions (ASS) → QA → upload`. Orchestrated by `src/orchestrator.ts`, persisted
per stage so the client can poll progress.

Later phases add Remotion (animated captions + influencer visual FX) and the
curated SFX library — both driven by the same manifest's `visual_events` /
`sfx_events`.

## Free stack

| Concern | Service | Free? |
|---|---|---|
| Storage | Cloudflare R2 | 10GB free |
| Jobs + manifest | Supabase (existing) | free |
| Transcription (word-level) | Groq `whisper-large-v3` | free tier |
| LLM audit | Groq `llama-3.3-70b` | free tier |
| Render compute | GitHub Actions | free minutes |
| Render engine | FFmpeg + (later) Remotion | OSS |

## Local dry-run (no cloud, no key needed)

```bash
cd backend && npm install
npx tsx src/cli.ts --local /path/to/video.mp4 /tmp/cutsense-out
# → /tmp/cutsense-out/final.mp4 + manifest.json
```
Without `GROQ_API_KEY` the worker still cuts silences and exports a 9:16 mp4
(no transcript → no captions/bad-take removal). Set the key for the full result.

## Going live — credentials to set (all free)

1. **Groq** — free key at https://console.groq.com → `GROQ_API_KEY`.
2. **Cloudflare R2** — create a bucket, an API token (Object Read/Write) →
   `R2_ACCOUNT_ID`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, `R2_BUCKET`.
3. **Supabase** — apply `supabase/migrations/20260517200000_jobs_manifests.sql`;
   deploy `supabase/functions/create-job` with its secrets (R2_*, GH_DISPATCH_TOKEN,
   GH_REPO, SUPABASE_*).
4. **GitHub** — add repo secrets: `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`,
   `R2_*`, `GROQ_API_KEY`. A classic PAT with `repo` scope → the edge function's
   `GH_DISPATCH_TOKEN`.

Flow: app → `create-job` (presigned R2 PUT + job row + `repository_dispatch`) →
GitHub Actions runs `src/cli.ts <jobId>` → worker fills the manifest, uploads
`final/<jobId>.mp4` to R2, sets `jobs.status=done`. The run always exits 0;
failures are written to `jobs.error`.

## Tuning (env)

`SILENCE_NOISE_DB` (-30), `MIN_SILENCE_DUR` (0.35), `CUT_SILENCE_PAD` (0.08),
`MIN_KEEP_DUR` (0.18), `CAPTION_MAX_WORDS` (5), `CAPTION_MAX_DUR` (2.4),
`GROQ_STT_MODEL`, `GROQ_LLM_MODEL`.
