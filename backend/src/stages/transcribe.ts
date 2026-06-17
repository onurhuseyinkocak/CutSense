import { transcribe as groqTranscribe, groqConfigured } from "../lib/groq.js";
import { warn } from "../lib/log.js";
import type { EditManifest, Transcript } from "../manifest.js";
import type { Ctx } from "./ctx.js";

/**
 * Word-level transcription. Uses Groq whisper-large-v3 (free, fast, good Turkish).
 * If GROQ_API_KEY is missing, the manifest gets an empty transcript and the
 * downstream plan falls back to silence-only cutting (still produces a video).
 */
export async function transcribeStage(m: EditManifest, ctx: Ctx): Promise<void> {
  if (!m.source?.has_audio) {
    m.transcript = { language: "tr", words: [], full_text: "" };
    return;
  }
  if (!groqConfigured()) {
    warn("transcribe", "GROQ_API_KEY missing — skipping transcription (silence-only cut). Set GROQ_API_KEY for bad-take removal + captions.");
    m.transcript = { language: "tr", words: [], full_text: "" };
    return;
  }
  const res = await groqTranscribe(ctx.audio);
  const transcript: Transcript = {
    language: res.language,
    words: res.words,
    full_text: res.full_text,
  };
  m.transcript = transcript;
}
