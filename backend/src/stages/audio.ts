import { ffmpeg, silenceDetect } from "../lib/ffmpeg.js";
import type { EditManifest } from "../manifest.js";
import type { Ctx } from "./ctx.js";

// Mirrors AudioAnalysisService.swift: silence merged ≥0.2s, threshold tuned to a
// conservative floor so we never trim real (quiet) speech.
const NOISE_DB = Number(process.env.SILENCE_NOISE_DB ?? -30);
const MIN_SILENCE = Number(process.env.MIN_SILENCE_DUR ?? 0.35);

/** Extract a 16kHz mono wav for transcription. */
export async function extractAudio(m: EditManifest, ctx: Ctx): Promise<void> {
  if (!m.source?.has_audio) return;
  await ffmpeg(["-i", ctx.normalized, "-vn", "-ac", "1", "-ar", "16000", "-c:a", "pcm_s16le", ctx.audio]);
}

/** Detect silence ranges on the source (normalized) timeline. */
export async function detectSilence(m: EditManifest, ctx: Ctx): Promise<void> {
  if (!m.source?.has_audio) {
    m.silence_ranges = [];
    return;
  }
  const ranges = await silenceDetect(ctx.audio, NOISE_DB, MIN_SILENCE);
  // Clamp to media duration and drop degenerate ranges.
  const dur = m.source.duration;
  m.silence_ranges = ranges
    .map((r) => ({ start: Math.max(0, r.start), end: Math.min(dur, r.end) }))
    .filter((r) => r.end - r.start >= MIN_SILENCE);
}
