import type { CutRange, EditManifest, KeepRange } from "../manifest.js";
import { cleanDurationOf } from "../manifest.js";
import type { Ctx } from "./ctx.js";

const SILENCE_PAD = Number(process.env.CUT_SILENCE_PAD ?? 0.08); // breathing room kept around speech
const MIN_KEEP = Number(process.env.MIN_KEEP_DUR ?? 0.18); // drop slivers shorter than this
const COALESCE_GAP = 0.06; // merge cuts separated by tiny gaps

interface RawCut {
  start: number;
  end: number;
  reason: CutRange["reason"];
}

/**
 * Build cut_ranges + keep_ranges from silence + bad-take phrases.
 * Mirrors AutoCutPlanner: pad silence inward so speech isn't clipped, remove
 * bad takes fully, coalesce, then derive keep ranges (the complement) with the
 * source→clean mapping.
 */
export function planCuts(m: EditManifest, _ctx: Ctx): void {
  const dur = m.source?.duration ?? 0;
  if (dur <= 0) {
    m.cut_ranges = [];
    m.keep_ranges = [];
    m.clean_duration = 0;
    return;
  }

  const raw: RawCut[] = [];
  for (const s of m.silence_ranges) {
    const start = s.start + SILENCE_PAD;
    const end = s.end - SILENCE_PAD;
    if (end - start > 0.05) raw.push({ start, end, reason: "silence" });
  }
  for (const b of m.bad_take_phrases) {
    raw.push({ start: Math.max(0, b.start - 0.02), end: Math.min(dur, b.end + 0.05), reason: b.kind });
  }

  // sort + coalesce overlapping/adjacent cuts (bad-take reason wins on merge).
  raw.sort((a, b) => a.start - b.start);
  const merged: RawCut[] = [];
  for (const c of raw) {
    const last = merged[merged.length - 1];
    if (last && c.start - last.end <= COALESCE_GAP) {
      last.end = Math.max(last.end, c.end);
      if (c.reason !== "silence") last.reason = c.reason;
    } else {
      merged.push({ ...c });
    }
  }

  // keep = complement of cuts over [0, dur]
  const keep: KeepRange[] = [];
  let cursor = 0;
  let cleanStart = 0;
  const pushKeep = (a: number, b: number) => {
    if (b - a >= MIN_KEEP) {
      keep.push({ source_start: a, source_end: b, clean_start: cleanStart });
      cleanStart += b - a;
    }
  };
  for (const c of merged) {
    if (c.start > cursor) pushKeep(cursor, c.start);
    cursor = Math.max(cursor, c.end);
  }
  if (cursor < dur) pushKeep(cursor, dur);

  // recompute cut_ranges as the true complement of the (sliver-dropped) keeps so
  // the rendered cut matches keep_ranges exactly.
  const cuts: CutRange[] = [];
  let prevEnd = 0;
  for (const k of keep) {
    if (k.source_start > prevEnd) {
      const reason = merged.find((c) => c.start <= k.source_start && c.end >= prevEnd)?.reason ?? "silence";
      cuts.push({ start: prevEnd, end: k.source_start, reason });
    }
    prevEnd = k.source_end;
  }
  if (prevEnd < dur) cuts.push({ start: prevEnd, end: dur, reason: "silence" });

  m.cut_ranges = cuts;
  m.keep_ranges = keep.length ? keep : [{ source_start: 0, source_end: dur, clean_start: 0 }];
  m.clean_duration = cleanDurationOf(m.keep_ranges);
}
