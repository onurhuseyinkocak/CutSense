/** Shared file paths produced across pipeline stages (inside the job work dir). */
export interface Ctx {
  workDir: string;
  raw: string; // input as downloaded/copied
  normalized: string; // 9:16 H.264/AAC
  audio: string; // 16k mono wav
  clean: string; // post-cut video (no captions)
  effected: string; // clean + visual FX (grade/zoom/flash/glitch)
  assPath: string; // generated subtitle file
  captioned: string; // effected + burned captions (no SFX yet)
  final: string; // captioned + SFX export
}

export function makeCtx(workDir: string, raw: string): Ctx {
  const p = (n: string) => `${workDir}/${n}`;
  return {
    workDir,
    raw,
    normalized: p("normalized.mp4"),
    audio: p("audio.wav"),
    clean: p("clean.mp4"),
    effected: p("effected.mp4"),
    assPath: p("captions.ass"),
    captioned: p("captioned.mp4"),
    final: p("final.mp4"),
  };
}
