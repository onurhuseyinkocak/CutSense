/** Shared file paths produced across pipeline stages (inside the job work dir). */
export interface Ctx {
  workDir: string;
  raw: string; // input as downloaded/copied
  normalized: string; // 9:16 H.264/AAC
  audio: string; // 16k mono wav
  clean: string; // post-cut video (no captions)
  assPath: string; // generated subtitle file
  final: string; // captioned export
}

export function makeCtx(workDir: string, raw: string): Ctx {
  const p = (n: string) => `${workDir}/${n}`;
  return {
    workDir,
    raw,
    normalized: p("normalized.mp4"),
    audio: p("audio.wav"),
    clean: p("clean.mp4"),
    assPath: p("captions.ass"),
    final: p("final.mp4"),
  };
}
