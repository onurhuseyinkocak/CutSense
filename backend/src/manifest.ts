/**
 * EditManifest — the ONLY source of truth for the whole pipeline.
 *
 * Every cut, caption, visual effect and SFX is derived from (and stored in) this
 * document. Stages fill it incrementally. The LLM may only propose/audit it — it
 * never edits pixels. Captions/visual/SFX events are only valid once keep_ranges
 * + final_transcript exist (no effects before the final timeline exists).
 *
 * Time conventions:
 *  - `transcript`, `silence_ranges`, `bad_take_phrases`, `cut_ranges`, keep
 *    ranges' `source_*` fields are on the SOURCE (normalized) timeline.
 *  - `final_transcript`, `caption_events`, `visual_events`, `sfx_events` and keep
 *    ranges' `clean_start` are on the CLEAN (post-cut) timeline.
 */

export const MANIFEST_SCHEMA_VERSION = 1;

export type JobStatus =
  | "queued"
  | "normalizing"
  | "transcribing"
  | "analyzing"
  | "planning"
  | "rendering_clean"
  | "captioning"
  | "rendering_final"
  | "qa"
  | "uploading"
  | "done"
  | "failed";

export interface SourceInfo {
  r2_key: string;
  duration: number; // seconds
  fps: number;
  width: number;
  height: number;
  codec: string;
  has_audio: boolean;
}

export interface TranscriptWord {
  text: string;
  start: number;
  end: number;
  confidence: number; // 0..1
}

export interface Transcript {
  language: string; // "tr" | "en" | ...
  words: TranscriptWord[];
  full_text: string;
}

export interface TimeRange {
  start: number;
  end: number;
}

export type BadTakeKind = "edit_command" | "restart" | "duplicate" | "filler";

export interface BadTakePhrase {
  start: number; // source timeline
  end: number;
  text: string;
  kind: BadTakeKind;
  confidence: number; // 0..1
  reason: string;
}

export type CutReason = "silence" | "edit_command" | "restart" | "duplicate" | "filler" | "manual";

export interface CutRange {
  start: number; // source timeline, removed
  end: number;
  reason: CutReason;
}

/** A kept segment + its mapping into the clean timeline. */
export interface KeepRange {
  source_start: number;
  source_end: number;
  clean_start: number;
}

export type CaptionRole = "hook" | "regular" | "keyword" | "reveal" | "warning" | "transition" | "conclusion";

export interface CaptionWordTiming {
  word: string;
  start: number; // clean timeline
  duration: number;
}

export interface CaptionEvent {
  start: number; // clean timeline
  end: number;
  text: string;
  role: CaptionRole;
  style: string; // e.g. "boldCenterViral" (maps to a renderer style)
  scene_behavior: string; // e.g. "punchIn" | "subtleZoom" | "none"
  word_timings: CaptionWordTiming[];
}

export type VisualEventType =
  | "punch_in"
  | "slow_zoom_out"
  | "micro_zoom"
  | "word_pop"
  | "light_shake"
  | "flash"
  | "color_shift";

export interface VisualEvent {
  time: number; // clean timeline
  duration: number;
  type: VisualEventType;
  intensity: number; // 0..1
  reason: string;
}

export type SfxKind =
  | "pop"
  | "whoosh"
  | "impact"
  | "riser"
  | "click"
  | "cash"
  | "confirm"
  | "glitch"
  | "ping";

export interface SfxEvent {
  time: number; // clean timeline
  duration: number;
  kind: SfxKind;
  volume: number; // 0..1
  asset: string; // curated library filename
  reason: string;
}

export interface QaCheck {
  name: string;
  ok: boolean;
  detail?: string;
}

export interface QaResults {
  passed: boolean;
  checks: QaCheck[];
  final_duration: number;
}

export interface RenderInfo {
  final_r2_key: string | null;
  preview_r2_key: string | null;
  canvas: [number, number];
}

export interface EditManifest {
  schema_version: number;
  job_id: string;
  project_id: string | null;
  status: JobStatus;

  source: SourceInfo | null;
  transcript: Transcript | null;
  silence_ranges: TimeRange[];
  bad_take_phrases: BadTakePhrase[];
  cut_ranges: CutRange[];
  keep_ranges: KeepRange[];
  clean_duration: number;
  final_transcript: Transcript | null;
  caption_events: CaptionEvent[];
  visual_events: VisualEvent[];
  sfx_events: SfxEvent[];
  qa_results: QaResults | null;
  render: RenderInfo;

  created_at: string;
  updated_at: string;
}

export function emptyManifest(jobId: string, projectId: string | null): EditManifest {
  const now = new Date().toISOString();
  return {
    schema_version: MANIFEST_SCHEMA_VERSION,
    job_id: jobId,
    project_id: projectId,
    status: "queued",
    source: null,
    transcript: null,
    silence_ranges: [],
    bad_take_phrases: [],
    cut_ranges: [],
    keep_ranges: [],
    clean_duration: 0,
    final_transcript: null,
    caption_events: [],
    visual_events: [],
    sfx_events: [],
    qa_results: null,
    render: { final_r2_key: null, preview_r2_key: null, canvas: [1080, 1920] },
    created_at: now,
    updated_at: now,
  };
}

/** Map a SOURCE-timeline time to the CLEAN timeline; null if it falls in a cut. */
export function sourceToClean(t: number, keep: KeepRange[]): number | null {
  for (const r of keep) {
    if (t >= r.source_start && t <= r.source_end) {
      return r.clean_start + (t - r.source_start);
    }
  }
  return null;
}

/** Total duration covered by keep ranges (clean duration). */
export function cleanDurationOf(keep: KeepRange[]): number {
  return keep.reduce((sum, r) => sum + (r.source_end - r.source_start), 0);
}
