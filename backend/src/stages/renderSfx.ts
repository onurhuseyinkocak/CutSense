import { copyFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { join } from "node:path";
import { ffmpeg } from "../lib/ffmpeg.js";
import { warn } from "../lib/log.js";
import type { EditManifest } from "../manifest.js";
import type { Ctx } from "./ctx.js";

// backend/assets/sfx (this file lives in backend/src/stages/)
const SFX_DIR = fileURLToPath(new URL("../../assets/sfx", import.meta.url));

/**
 * Mix the curated SFX (whoosh on cuts, cash on money words, impact on the hook,
 * pop on keywords) into the captioned video's audio at each event time. Each is
 * delayed to its moment and volume-scaled, then amix'd over the dialogue.
 */
export async function renderSfx(m: EditManifest, ctx: Ctx): Promise<void> {
  const events = (m.sfx_events ?? []).filter((e) => existsSync(join(SFX_DIR, e.asset)));
  if (events.length === 0 || !m.source?.has_audio) {
    await copyFile(ctx.captioned, ctx.final);
    return;
  }

  const args = ["-i", ctx.captioned];
  for (const e of events) args.push("-i", join(SFX_DIR, e.asset));

  const parts: string[] = [];
  events.forEach((e, i) => {
    const ms = Math.max(0, Math.round(e.time * 1000));
    const vol = Math.max(0.05, Math.min(1, e.volume || 0.5));
    // adelay both channels; apad so a short SFX doesn't truncate the mix early.
    parts.push(`[${i + 1}:a]volume=${vol.toFixed(2)},adelay=${ms}|${ms}[s${i}]`);
  });
  const mixIn = ["[0:a]", ...events.map((_, i) => `[s${i}]`)].join("");
  const filter = `${parts.join(";")};${mixIn}amix=inputs=${events.length + 1}:duration=first:normalize=0[aout]`;

  const out = [
    "-filter_complex", filter,
    "-map", "0:v", "-map", "[aout]",
    "-c:v", "copy", "-c:a", "aac", "-b:a", "192k",
    "-movflags", "+faststart",
    ctx.final,
  ];

  try {
    await ffmpeg([...args, ...out]);
  } catch (e) {
    warn("sfx", `mix failed, shipping without SFX: ${(e as Error).message}`);
    await copyFile(ctx.captioned, ctx.final);
  }
}
