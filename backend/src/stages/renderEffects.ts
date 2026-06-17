import { copyFile } from "node:fs/promises";
import { ffmpeg } from "../lib/ffmpeg.js";
import type { EditManifest, VisualEvent } from "../manifest.js";
import type { Ctx } from "./ctx.js";

const W = 1080;
const H = 1920;
const FPS = 30;

/**
 * Apply a CapCut-style visual layer to the clean cut, driven by visual_events:
 *  - always-on: gentle push-in (keeps the frame alive), vivid color grade,
 *    vignette, subtle film grain.
 *  - timed: white flash on cuts, RGB/chromatic glitch on emphasis, hand-held
 *    shake on impacts, extra zoom-punch on hook/keyword.
 * One FFmpeg pass. Output → ctx.effected (captions burn on top of this).
 */
export async function renderEffects(m: EditManifest, ctx: Ctx): Promise<void> {
  const events = m.visual_events ?? [];
  if (events.length === 0 && !m.source?.has_audio) {
    // still grade even with no events
  }

  const flashWins = events.filter((e) => e.type === "flash");
  const glitchWins = events.filter((e) => e.type === "color_shift");
  const shakeWins = events.filter((e) => e.type === "light_shake");
  const zoomWins = events.filter((e) => e.type === "punch_in" || e.type === "micro_zoom" || e.type === "slow_zoom_out");

  // zoompan: continuous slow push-in + per-event zoom punch + shake jitter.
  // Variables: `on` = output frame index → t = on/FPS.
  const tExpr = `(on/${FPS})`;
  const punch = zoomWins.length
    ? "+" + zoomWins.map((e) => `${(0.06 * (e.intensity || 0.5)).toFixed(3)}*exp(-pow((${tExpr}-${e.time.toFixed(2)})/0.22,2))`).join("+")
    : "";
  const zExpr = `min(1.02+0.0006*on${punch},1.14)`;
  const shakeX = shakeWins.length
    ? shakeWins.map((e) => `sin(${tExpr}*70)*7*between(${tExpr},${e.time.toFixed(2)},${(e.time + (e.duration || 0.4)).toFixed(2)})`).join("+")
    : "0";
  const shakeY = shakeWins.length
    ? shakeWins.map((e) => `cos(${tExpr}*64)*7*between(${tExpr},${e.time.toFixed(2)},${(e.time + (e.duration || 0.4)).toFixed(2)})`).join("+")
    : "0";

  const zoompan =
    `zoompan=z='${zExpr}':d=1:` +
    `x='iw/2-(iw/zoom/2)+(${shakeX})':` +
    `y='ih/2-(ih/zoom/2)+(${shakeY})':` +
    `s=${W}x${H}:fps=${FPS}`;

  const grade = "eq=contrast=1.10:saturation=1.26:brightness=0.015:gamma=0.97";
  const vignette = "vignette=PI/4.6";
  const grain = "noise=alls=7:allf=t+u";

  const filters = [zoompan, grade, vignette, grain];

  // Flash: white-ish brightness pulse on cut frames.
  const flashEnable = enableOf(flashWins, 0.12);
  if (flashEnable) filters.push(`eq=brightness=0.6:saturation=0.85:enable='${flashEnable}'`);

  // Glitch: chromatic aberration on emphasis windows.
  const glitchEnable = enableOf(glitchWins, 0.16);
  if (glitchEnable) filters.push(`rgbashift=rh=7:bh=-7:gv=3:enable='${glitchEnable}'`);

  const vf = filters.join(",");
  const args = ["-i", ctx.clean, "-vf", vf, "-c:v", "libx264", "-preset", "veryfast", "-crf", "20", "-pix_fmt", "yuv420p", "-r", String(FPS)];
  if (m.source?.has_audio) args.push("-c:a", "copy");
  else args.push("-an");
  args.push(ctx.effected);

  try {
    await ffmpeg(args);
  } catch (e) {
    // Effects must never break the job — fall back to the clean cut.
    await copyFile(ctx.clean, ctx.effected);
    throw e;
  }
}

function enableOf(events: VisualEvent[], dur: number): string | null {
  if (!events.length) return null;
  return events.map((e) => `between(t,${e.time.toFixed(2)},${(e.time + (e.duration || dur)).toFixed(2)})`).join("+");
}
