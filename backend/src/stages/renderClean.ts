import { copyFile } from "node:fs/promises";
import { ffmpeg } from "../lib/ffmpeg.js";
import type { EditManifest } from "../manifest.js";
import type { Ctx } from "./ctx.js";

/**
 * Render the clean cut by trimming each keep_range and concatenating, frame-
 * accurate via the concat filter (re-encode). Audio kept in sync per segment.
 */
export async function renderClean(m: EditManifest, ctx: Ctx): Promise<void> {
  const keeps = m.keep_ranges;
  const hasAudio = !!m.source?.has_audio;

  // Whole video kept → clean == normalized.
  if (keeps.length === 1 && keeps[0]!.source_start <= 0.001 && Math.abs(keeps[0]!.source_end - (m.source?.duration ?? 0)) < 0.05) {
    await copyFile(ctx.normalized, ctx.clean);
    return;
  }

  const parts: string[] = [];
  const labels: string[] = [];
  keeps.forEach((k, i) => {
    parts.push(`[0:v]trim=start=${k.source_start.toFixed(3)}:end=${k.source_end.toFixed(3)},setpts=PTS-STARTPTS[v${i}]`);
    labels.push(`[v${i}]`);
    if (hasAudio) {
      parts.push(`[0:a]atrim=start=${k.source_start.toFixed(3)}:end=${k.source_end.toFixed(3)},asetpts=PTS-STARTPTS[a${i}]`);
      labels.push(`[a${i}]`);
    }
  });
  const n = keeps.length;
  const concat = `${labels.join("")}concat=n=${n}:v=1:a=${hasAudio ? 1 : 0}${hasAudio ? "[v][a]" : "[v]"}`;
  const filter = `${parts.join(";")};${concat}`;

  const args = ["-i", ctx.normalized, "-filter_complex", filter, "-map", "[v]"];
  if (hasAudio) args.push("-map", "[a]", "-c:a", "aac", "-b:a", "160k");
  args.push("-c:v", "libx264", "-preset", "veryfast", "-crf", "20", "-pix_fmt", "yuv420p", "-movflags", "+faststart", ctx.clean);
  await ffmpeg(args);
}
