import { spawn } from "node:child_process";

const FFMPEG = process.env.FFMPEG_BIN || "ffmpeg";
const FFPROBE = process.env.FFPROBE_BIN || "ffprobe";

export interface RunResult {
  code: number;
  stdout: string;
  stderr: string;
}

/** Run a binary, capturing stdout/stderr. Rejects on non-zero exit. */
export function run(bin: string, args: string[]): Promise<RunResult> {
  return new Promise((resolve, reject) => {
    const child = spawn(bin, args, { stdio: ["ignore", "pipe", "pipe"] });
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (d) => (stdout += d.toString()));
    child.stderr.on("data", (d) => (stderr += d.toString()));
    child.on("error", reject);
    child.on("close", (code) => {
      if (code === 0) resolve({ code: 0, stdout, stderr });
      else reject(new Error(`${bin} exited ${code}\n${stderr.slice(-2000)}`));
    });
  });
}

export const ffmpeg = (args: string[]) => run(FFMPEG, ["-hide_banner", "-loglevel", "error", "-y", ...args]);
export const ffprobe = (args: string[]) => run(FFPROBE, ["-hide_banner", ...args]);

// Whether this ffmpeg build exposes a given filter (e.g. "ass" needs libass).
// Cached — the answer can't change within a run. Prod (ubuntu apt ffmpeg) has
// libass; some local/brew builds don't, so callers fall back gracefully.
const filterCache = new Map<string, boolean>();
export async function hasFilter(name: string): Promise<boolean> {
  const cached = filterCache.get(name);
  if (cached !== undefined) return cached;
  let ok = false;
  try {
    const { stdout } = await run(FFMPEG, ["-hide_banner", "-filters"]);
    ok = new RegExp(`\\s${name}\\s`).test(stdout);
  } catch {
    ok = false;
  }
  filterCache.set(name, ok);
  return ok;
}

export interface ProbeResult {
  duration: number;
  fps: number;
  width: number;
  height: number;
  codec: string;
  has_audio: boolean;
}

/** ffprobe → normalized media metadata. */
export async function probe(file: string): Promise<ProbeResult> {
  const { stdout } = await ffprobe([
    "-v",
    "error",
    "-print_format",
    "json",
    "-show_format",
    "-show_streams",
    file,
  ]);
  const json = JSON.parse(stdout) as {
    format?: { duration?: string };
    streams?: Array<{
      codec_type?: string;
      codec_name?: string;
      width?: number;
      height?: number;
      r_frame_rate?: string;
      avg_frame_rate?: string;
    }>;
  };
  const streams = json.streams ?? [];
  const v = streams.find((s) => s.codec_type === "video");
  const a = streams.find((s) => s.codec_type === "audio");
  const fpsStr = v?.avg_frame_rate || v?.r_frame_rate || "30/1";
  const [num, den] = fpsStr.split("/").map(Number);
  const fps = den && num ? num / den : 30;
  return {
    duration: Number(json.format?.duration ?? 0),
    fps: Math.round(fps * 1000) / 1000 || 30,
    width: v?.width ?? 0,
    height: v?.height ?? 0,
    codec: v?.codec_name ?? "unknown",
    has_audio: !!a,
  };
}

/**
 * Run silencedetect and parse silence intervals.
 * `noiseDb` is the threshold (e.g. -28dB), `minDur` seconds (e.g. 0.2).
 */
export async function silenceDetect(audioFile: string, noiseDb: number, minDur: number): Promise<{ start: number; end: number }[]> {
  // silencedetect writes to stderr at info level.
  const { stderr } = await run(FFMPEG, [
    "-hide_banner",
    "-i",
    audioFile,
    "-af",
    `silencedetect=noise=${noiseDb}dB:d=${minDur}`,
    "-f",
    "null",
    "-",
  ]);
  const ranges: { start: number; end: number }[] = [];
  let pendingStart: number | null = null;
  for (const line of stderr.split(/\r?\n/)) {
    const startM = line.match(/silence_start:\s*(-?[\d.]+)/);
    const endM = line.match(/silence_end:\s*(-?[\d.]+)/);
    if (startM) pendingStart = Math.max(0, Number(startM[1]));
    else if (endM && pendingStart !== null) {
      ranges.push({ start: pendingStart, end: Number(endM[1]) });
      pendingStart = null;
    }
  }
  return ranges;
}
