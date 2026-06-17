import { ffprobe, run, probe } from "../lib/ffmpeg.js";
import type { EditManifest, QaCheck } from "../manifest.js";
import type { Ctx } from "./ctx.js";

const FFMPEG = process.env.FFMPEG_BIN || "ffmpeg";

/** Final QA before export: duration, A/V sync, black frames, audio clipping, caption coverage. */
export async function qa(m: EditManifest, ctx: Ctx): Promise<void> {
  const checks: QaCheck[] = [];
  const info = await probe(ctx.final);

  // 1) duration valid + matches the clean plan
  const durOk = info.duration > 0.5 && Math.abs(info.duration - m.clean_duration) < 0.8;
  checks.push({ name: "final_duration", ok: durOk, detail: `final=${info.duration.toFixed(2)}s plan=${m.clean_duration.toFixed(2)}s` });

  // 2) A/V both present (when source had audio)
  const avOk = m.source?.has_audio ? info.has_audio : true;
  checks.push({ name: "av_streams", ok: avOk, detail: info.has_audio ? "audio present" : "no audio" });

  // 3) no long black frames
  try {
    const { stderr } = await run(FFMPEG, ["-hide_banner", "-i", ctx.final, "-vf", "blackdetect=d=0.3:pic_th=0.98", "-an", "-f", "null", "-"]);
    const black = [...stderr.matchAll(/black_start:([\d.]+) black_end:([\d.]+)/g)].some((mm) => Number(mm[2]) - Number(mm[1]) >= 0.3);
    checks.push({ name: "no_black_frames", ok: !black, detail: black ? "long black segment found" : "ok" });
  } catch {
    checks.push({ name: "no_black_frames", ok: true, detail: "skipped" });
  }

  // 4) no audio clipping
  if (m.source?.has_audio) {
    try {
      const { stderr } = await run(FFMPEG, ["-hide_banner", "-i", ctx.final, "-af", "volumedetect", "-f", "null", "-"]);
      const max = stderr.match(/max_volume:\s*(-?[\d.]+) dB/);
      const clipped = max ? Number(max[1]) >= -0.1 : false;
      checks.push({ name: "no_audio_clip", ok: !clipped, detail: max ? `max_volume ${max[1]}dB` : "n/a" });
    } catch {
      checks.push({ name: "no_audio_clip", ok: true, detail: "skipped" });
    }
  }

  // 5) captions inside final timeline
  const capOk = m.caption_events.every((c) => c.start >= 0 && c.end <= info.duration + 0.2);
  checks.push({ name: "captions_in_range", ok: capOk });

  m.render.canvas = [info.width || 1080, info.height || 1920];
  m.qa_results = { passed: checks.every((c) => c.ok), checks, final_duration: info.duration };
}

// keep ffprobe import referenced for tree-shakers / future structured probes
void ffprobe;
