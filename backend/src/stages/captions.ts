import type { CaptionEvent, CaptionRole, EditManifest, TranscriptWord } from "../manifest.js";
import type { Ctx } from "./ctx.js";

const MAX_WORDS = Number(process.env.CAPTION_MAX_WORDS ?? 5);
const MAX_DUR = Number(process.env.CAPTION_MAX_DUR ?? 2.4);
const GAP_BREAK = 0.5;

// Keyword triggers ported from CaptionSceneEventPlanner.swift (TR + EN).
const KEYWORDS = [
  "yapay zeka",
  "vibe coding",
  "kod",
  "hata",
  "neden",
  "ücretsiz",
  "free",
  "mvp",
  "build",
  "ai",
  "prompt",
  "para",
  "gelir",
  "satış",
  "revenue",
  "money",
  "sales",
];

function norm(s: string): string {
  return s.toLocaleLowerCase("tr-TR").replace(/ı/g, "i").replace(/[^\p{L}\p{N}\s]/gu, " ").trim();
}

function chunk(words: TranscriptWord[]): TranscriptWord[][] {
  const out: TranscriptWord[][] = [];
  let cur: TranscriptWord[] = [];
  for (const w of words) {
    const prev = cur[cur.length - 1];
    const span = cur.length ? w.end - cur[0]!.start : 0;
    const gap = prev ? w.start - prev.end : 0;
    if (cur.length >= MAX_WORDS || span > MAX_DUR || gap > GAP_BREAK) {
      if (cur.length) out.push(cur);
      cur = [];
    }
    cur.push(w);
  }
  if (cur.length) out.push(cur);
  return out;
}

/** Build caption_events on the CLEAN timeline (only after final_transcript exists). */
export function buildCaptions(m: EditManifest, _ctx: Ctx): void {
  const words = m.final_transcript?.words ?? [];
  const groups = chunk(words);
  const events: CaptionEvent[] = groups.map((g, i) => {
    const start = g[0]!.start;
    const end = g[g.length - 1]!.end;
    const text = g.map((w) => w.text).join(" ");
    const hasKeyword = KEYWORDS.some((k) => norm(text).includes(k));
    let role: CaptionRole = "regular";
    if (i === 0) role = "hook";
    else if (i === groups.length - 1) role = "conclusion";
    else if (hasKeyword) role = "keyword";
    const style = role === "hook" ? "boldCenterViral" : role === "keyword" ? "focusStatement" : "cleanCenter";
    const scene_behavior = role === "hook" ? "punchIn" : role === "keyword" ? "subtleZoom" : "none";
    return {
      start,
      end,
      text,
      role,
      style,
      scene_behavior,
      word_timings: g.map((w) => ({ word: w.text, start: w.start, duration: Math.max(0.05, w.end - w.start) })),
    };
  });

  // Clamp to the clean timeline. Whisper pads the final word's end into trailing
  // silence that the cut removed, so an unclamped caption can run past the end of
  // the rendered clip (fails QA `captions_in_range` and shows a caption over black).
  const limit = m.clean_duration && m.clean_duration > 0 ? m.clean_duration : events.at(-1)?.end ?? 0;
  for (const e of events) {
    e.start = Math.min(Math.max(0, e.start), limit);
    e.end = Math.min(e.end, limit);
    for (const wt of e.word_timings) {
      wt.start = Math.min(Math.max(0, wt.start), limit);
      wt.duration = Math.min(wt.duration, Math.max(0.05, limit - wt.start));
    }
  }
  m.caption_events = events.filter((e) => e.end - e.start > 0.05);
}
