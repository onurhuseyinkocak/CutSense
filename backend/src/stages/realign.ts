import type { EditManifest, Transcript, TranscriptWord } from "../manifest.js";
import { sourceToClean } from "../manifest.js";
import type { Ctx } from "./ctx.js";

/**
 * Re-align the source transcript onto the CLEAN timeline using keep_ranges.
 * Words fully inside a cut are dropped; words straddling a boundary are clamped.
 * This avoids a second (costly) transcription while keeping captions in sync
 * with the cut video (mirrors TimelineMapper.remapCaptions).
 */
export function realign(m: EditManifest, _ctx: Ctx): void {
  const src = m.transcript?.words ?? [];
  const keep = m.keep_ranges;
  if (src.length === 0 || keep.length === 0) {
    m.final_transcript = { language: m.transcript?.language ?? "tr", words: [], full_text: "" };
    return;
  }

  const words: TranscriptWord[] = [];
  for (const w of src) {
    const mid = (w.start + w.end) / 2;
    const cleanMid = sourceToClean(mid, keep);
    if (cleanMid === null) continue; // word lives inside a cut
    const cs = sourceToClean(w.start, keep);
    const ce = sourceToClean(w.end, keep);
    const start = cs ?? cleanMid - (w.end - w.start) / 2;
    const end = ce ?? cleanMid + (w.end - w.start) / 2;
    if (end > start) words.push({ text: w.text, start, end, confidence: w.confidence });
  }

  const final: Transcript = {
    language: m.transcript?.language ?? "tr",
    words,
    full_text: words.map((w) => w.text).join(" "),
  };
  m.final_transcript = final;
}
