import type { EditManifest, SfxEvent, VisualEvent } from "../manifest.js";
import type { Ctx } from "./ctx.js";

/**
 * Plan SFX + visual effects on the CLEAN timeline, at MEANINGFUL moments only
 * (cuts, the hook, keywords, money words). Kept deliberately sparse — random
 * effects everywhere is what made the old output feel amateur. Rendered later
 * by renderEffects (visual) + renderSfx (audio).
 */

// Money / sales words → cash register. Turkish + a few English.
const MONEY_RE =
  /(para|kazan|gelir|satış|satis|ücret|ucret|fiyat|indirim|bedava|ücretsiz|ucretsiz|dolar|lira|kâr|kar\b|bütçe|butce|yatırım|yatirim|milyon|milyar|bin\b|yüzde|yuzde|₺|\$|tl\b|money|sales|revenue|profit|free|price|cash)/i;

const MAX_CASH = 3;
const MAX_POP = 4;

export function planEffects(m: EditManifest, _ctx: Ctx): void {
  const sfx: SfxEvent[] = [];
  const vis: VisualEvent[] = [];
  const clean = m.clean_duration ?? 0;
  if (clean <= 0) {
    m.sfx_events = [];
    m.visual_events = [];
    return;
  }

  // 1) Cut points (clean timeline) = where a removed range was stitched out.
  //    Mask each with a whoosh + a quick flash + a punch to hide the jump.
  const keeps = m.keep_ranges ?? [];
  let glitches = 0;
  for (let i = 1; i < keeps.length; i++) {
    const t = keeps[i]!.clean_start;
    if (t <= 0.05 || t >= clean - 0.05) continue;
    sfx.push({ time: Math.max(0, t - 0.06), duration: 0.6, kind: "whoosh", volume: 0.5, asset: "whoosh.mp3", reason: "cut transition" });
    vis.push({ time: Math.max(0, t - 0.04), duration: 0.16, type: "flash", intensity: 0.45, reason: "cut" });
    vis.push({ time: t, duration: 0.5, type: "punch_in", intensity: 0.5, reason: "cut punch" });
    // Glitch every other cut (sparse) for a CapCut-style transition accent.
    if (i % 2 === 1 && glitches < 2) {
      glitches++;
      vis.push({ time: Math.max(0, t - 0.02), duration: 0.16, type: "color_shift", intensity: 0.7, reason: "cut glitch" });
    }
  }

  // 2) Captions: hook gets an impact + strong punch-in; keywords get pop + micro-zoom.
  let pops = 0;
  for (const c of m.caption_events) {
    if (c.role === "hook") {
      sfx.push({ time: c.start, duration: 2.0, kind: "impact", volume: 0.55, asset: "impact.mp3", reason: "hook" });
      vis.push({ time: c.start, duration: Math.min(0.9, c.end - c.start), type: "punch_in", intensity: 0.75, reason: "hook" });
      vis.push({ time: c.start, duration: 0.4, type: "light_shake", intensity: 0.6, reason: "hook impact" });
    } else if (c.role === "keyword" && pops < MAX_POP) {
      pops++;
      sfx.push({ time: c.start, duration: 0.6, kind: "pop", volume: 0.5, asset: "pop.mp3", reason: "keyword" });
      vis.push({ time: c.start, duration: Math.min(0.7, c.end - c.start), type: "micro_zoom", intensity: 0.45, reason: "keyword" });
    }
  }

  // 3) Money words → cash register (sparse).
  let cash = 0;
  const words = m.final_transcript?.words ?? [];
  for (const w of words) {
    if (cash >= MAX_CASH) break;
    if (MONEY_RE.test(w.text)) {
      // de-dupe: don't stack a cash within 1.5s of the previous one
      const last = sfx.filter((s) => s.kind === "cash").at(-1);
      if (last && Math.abs(last.time - w.start) < 1.5) continue;
      cash++;
      sfx.push({ time: w.start, duration: 1.4, kind: "cash", volume: 0.5, asset: "cash.mp3", reason: `money word "${w.text}"` });
      vis.push({ time: w.start, duration: 0.5, type: "micro_zoom", intensity: 0.4, reason: "money emphasis" });
    }
  }

  // Sort + cap visual events so they never overlap into a strobe.
  sfx.sort((a, b) => a.time - b.time);
  vis.sort((a, b) => a.time - b.time);
  m.sfx_events = sfx;
  m.visual_events = dedupeVisual(vis);
}

/** Drop visual events that start within 0.25s of a prior one (avoid strobing). */
function dedupeVisual(events: VisualEvent[]): VisualEvent[] {
  const out: VisualEvent[] = [];
  for (const e of events) {
    const last = out.at(-1);
    if (last && e.time - last.time < 0.25 && e.type !== "flash") continue;
    out.push(e);
  }
  return out;
}
