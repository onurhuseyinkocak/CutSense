import { chatJson, groqConfigured } from "../lib/groq.js";
import { warn } from "../lib/log.js";
import type { BadTakePhrase, EditManifest, TranscriptWord } from "../manifest.js";
import type { Ctx } from "./ctx.js";

/**
 * Self-correction / bad-take detection. Ported from CutSense's on-device
 * TranscriptCleanupAnalyzer + SmartTranscriptAnalyzer:
 *  - explicit edit commands (phrase list, TR + EN)
 *  - restarts (a truncated attempt immediately re-said)
 *  - near-duplicates (same sentence repeated)
 * Optionally refined by a Groq LLM audit (proposes only — never edits pixels).
 */

// Explicit creator edit-commands (the user's spec list + Swift prompt phrases).
const EDIT_COMMANDS = [
  "burasi olmadi",
  "burayi kes",
  "sunu kes",
  "bunu kes",
  "tekrar alayim",
  "bastan alayim",
  "bastan aliyorum",
  "bastan",
  "olmadi",
  "yanlis oldu",
  "kes burayi",
  "cut this",
  "cut that",
  "remove this",
  "let me say that again",
  "let me redo that",
  "take two",
];

function norm(s: string): string {
  return s
    .toLocaleLowerCase("tr-TR")
    .replace(/ı/g, "i")
    .replace(/[^\p{L}\p{N}\s]/gu, " ")
    .replace(/\s+/g, " ")
    .trim();
}

interface Sentence {
  words: TranscriptWord[];
  start: number;
  end: number;
  text: string;
}

/** Group words into sentences by silence gaps (mirrors AutoCutPlanner phrasing). */
function segment(words: TranscriptWord[], gap = 0.45): Sentence[] {
  const out: Sentence[] = [];
  let cur: TranscriptWord[] = [];
  for (let i = 0; i < words.length; i++) {
    const w = words[i]!;
    if (cur.length && w.start - cur[cur.length - 1]!.end > gap) {
      out.push(toSentence(cur));
      cur = [];
    }
    cur.push(w);
  }
  if (cur.length) out.push(toSentence(cur));
  return out;
}

function toSentence(words: TranscriptWord[]): Sentence {
  return {
    words,
    start: words[0]!.start,
    end: words[words.length - 1]!.end,
    text: words.map((w) => w.text).join(" "),
  };
}

function jaccard(a: string, b: string): number {
  const sa = new Set(norm(a).split(" ").filter(Boolean));
  const sb = new Set(norm(b).split(" ").filter(Boolean));
  if (!sa.size || !sb.size) return 0;
  let inter = 0;
  for (const t of sa) if (sb.has(t)) inter++;
  return inter / (sa.size + sb.size - inter);
}

/** Is `a` a truncated prefix attempt of `b` (restart)? */
function isRestart(a: string, b: string): boolean {
  const wa = norm(a).split(" ").filter(Boolean);
  const wb = norm(b).split(" ").filter(Boolean);
  if (wa.length < 3 || wb.length < wa.length) return false;
  let match = 0;
  for (let i = 0; i < wa.length; i++) if (wa[i] === wb[i]) match++;
  return match >= 3 && match / wa.length > 0.6;
}

export async function detectBadTakes(m: EditManifest, _ctx: Ctx): Promise<void> {
  const words = m.transcript?.words ?? [];
  if (words.length === 0) {
    m.bad_take_phrases = [];
    return;
  }
  const sentences = segment(words);
  const bad: BadTakePhrase[] = [];

  for (let i = 0; i < sentences.length; i++) {
    const s = sentences[i]!;
    const n = norm(s.text);

    // 1) explicit edit command anywhere in the sentence → this sentence is a bad take.
    const cmd = EDIT_COMMANDS.find((c) => n.includes(c));
    if (cmd) {
      bad.push({ start: s.start, end: s.end, text: s.text, kind: "edit_command", confidence: 0.92, reason: `edit command "${cmd}"` });
      continue;
    }

    // 2) restart: this sentence is a truncated attempt re-said in the next.
    const next = sentences[i + 1];
    if (next && isRestart(s.text, next.text)) {
      bad.push({ start: s.start, end: s.end, text: s.text, kind: "restart", confidence: 0.8, reason: "restarted — re-said immediately" });
      continue;
    }

    // 3) near-duplicate: keep the later (usually the better/complete) take.
    if (next && jaccard(s.text, next.text) > 0.82 && s.words.length >= 3) {
      bad.push({ start: s.start, end: s.end, text: s.text, kind: "duplicate", confidence: 0.75, reason: "duplicate of the next take" });
    }
  }

  m.bad_take_phrases = await llmAudit(sentences, bad);
}

/**
 * Optional Groq audit: the LLM may add edit-commands the phrase list missed and
 * flag false positives. It proposes spans only; we keep heuristic spans as the
 * floor so we never depend on the LLM being available.
 */
async function llmAudit(sentences: Sentence[], heuristic: BadTakePhrase[]): Promise<BadTakePhrase[]> {
  if (!groqConfigured() || sentences.length === 0) return heuristic;
  const numbered = sentences.map((s, i) => `${i}\t[${s.start.toFixed(2)}-${s.end.toFixed(2)}]\t${s.text}`).join("\n");
  const system =
    "You audit a talking-head transcript for BAD TAKES the creator wants removed: explicit edit commands (e.g. 'tekrar alayım', 'burası olmadı', 'cut that'), false starts/restarts re-said right after, and near-duplicate repeats. Keep real content. Return JSON only.";
  const user = `Sentences (index, time, text):\n${numbered}\n\nReturn {"bad":[{"index":N,"kind":"edit_command|restart|duplicate","confidence":0..1,"reason":"..."}]}. Only sentences that are clearly a bad take. Do NOT flag normal content, discourse markers (yani, aslında, mesela) or single fillers.`;
  try {
    const res = await chatJson<{ bad?: { index: number; kind: string; confidence?: number; reason?: string }[] }>(system, user);
    if (!res?.bad) return heuristic;
    const byStart = new Map(heuristic.map((b) => [b.start.toFixed(2), b]));
    for (const item of res.bad) {
      const s = sentences[item.index];
      if (!s) continue;
      const key = s.start.toFixed(2);
      if (byStart.has(key)) continue; // heuristic already has it
      const kind = (["edit_command", "restart", "duplicate", "filler"].includes(item.kind) ? item.kind : "edit_command") as BadTakePhrase["kind"];
      byStart.set(key, { start: s.start, end: s.end, text: s.text, kind, confidence: Math.min(1, item.confidence ?? 0.7), reason: item.reason ?? "llm audit" });
    }
    return [...byStart.values()].sort((a, b) => a.start - b.start);
  } catch (e) {
    warn("badtake", `llm audit failed: ${(e as Error).message}`);
    return heuristic;
  }
}
