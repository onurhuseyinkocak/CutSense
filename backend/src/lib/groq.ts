import { createReadStream } from "node:fs";
import Groq from "groq-sdk";
import type { TranscriptWord } from "../manifest.js";

/** Env: GROQ_API_KEY (free at console.groq.com). */
export function groqConfigured(): boolean {
  return !!process.env.GROQ_API_KEY;
}

let _client: Groq | null = null;
function client(): Groq {
  if (!_client) _client = new Groq({ apiKey: process.env.GROQ_API_KEY! });
  return _client;
}

const STT_MODEL = process.env.GROQ_STT_MODEL || "whisper-large-v3";
const LLM_MODEL = process.env.GROQ_LLM_MODEL || "llama-3.3-70b-versatile";

export interface TranscribeResult {
  language: string;
  full_text: string;
  words: TranscriptWord[];
}

/** Word-level transcription via Groq Whisper (verbose_json + word granularity). */
export async function transcribe(audioFile: string): Promise<TranscribeResult> {
  const res = (await client().audio.transcriptions.create({
    file: createReadStream(audioFile),
    model: STT_MODEL,
    response_format: "verbose_json",
    timestamp_granularities: ["word", "segment"],
    temperature: 0,
  })) as unknown as {
    language?: string;
    text?: string;
    words?: Array<{ word: string; start: number; end: number }>;
    segments?: Array<{ text: string; start: number; end: number; avg_logprob?: number }>;
  };

  const words: TranscriptWord[] = (res.words ?? []).map((w) => ({
    text: w.word.trim(),
    start: w.start,
    end: w.end,
    confidence: 0.9, // Groq word objects don't expose per-word confidence; segment logprob used as a floor elsewhere
  }));

  return {
    language: res.language || "tr",
    full_text: (res.text || "").trim(),
    words,
  };
}

/** Generic JSON-returning chat call (manifest audit / coherence). Returns parsed JSON or null. */
export async function chatJson<T>(system: string, user: string): Promise<T | null> {
  const res = await client().chat.completions.create({
    model: LLM_MODEL,
    temperature: 0,
    response_format: { type: "json_object" },
    messages: [
      { role: "system", content: system },
      { role: "user", content: user },
    ],
  });
  const content = res.choices[0]?.message?.content;
  if (!content) return null;
  try {
    return JSON.parse(content) as T;
  } catch {
    return null;
  }
}
