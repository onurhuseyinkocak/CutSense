import { ffmpeg, probe } from "../lib/ffmpeg.js";
import type { EditManifest, SourceInfo } from "../manifest.js";
import type { Ctx } from "./ctx.js";

const CANVAS_W = 1080;
const CANVAS_H = 1920;
const TARGET_FPS = 30;

/**
 * Normalize any input to a vertical 9:16 1080×1920 H.264 / AAC mp4 at a fixed
 * fps. Scale-to-cover then center-crop (talking-head face stays centered).
 * Fills manifest.source from the NORMALIZED file (all later timings reference it).
 */
export async function normalize(m: EditManifest, ctx: Ctx): Promise<void> {
  const inProbe = await probe(ctx.raw);
  const vf = `scale=${CANVAS_W}:${CANVAS_H}:force_original_aspect_ratio=increase,crop=${CANVAS_W}:${CANVAS_H},fps=${TARGET_FPS},format=yuv420p`;
  const args = ["-i", ctx.raw, "-vf", vf];
  if (inProbe.has_audio) {
    args.push("-c:a", "aac", "-b:a", "160k", "-ac", "2", "-ar", "48000");
  } else {
    args.push("-an");
  }
  args.push(
    "-c:v",
    "libx264",
    "-preset",
    "veryfast",
    "-crf",
    "20",
    "-pix_fmt",
    "yuv420p",
    "-movflags",
    "+faststart",
    ctx.normalized,
  );
  await ffmpeg(args);

  const out = await probe(ctx.normalized);
  const source: SourceInfo = {
    r2_key: m.source?.r2_key ?? "",
    duration: out.duration,
    fps: out.fps,
    width: out.width,
    height: out.height,
    codec: out.codec,
    has_audio: out.has_audio,
  };
  m.source = source;
}
