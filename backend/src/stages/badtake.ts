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

/**
 * Group words into sentences at TAKE boundaries. The primary, deterministic
 * boundary is the ffmpeg-detected silence (`silence_ranges`) — whisper word
 * end-times bleed into silences and vary run-to-run, so the raw word gap alone
 * merges separate takes into one giant sentence (then an edit command swallows
 * the good retake). A detected silence sitting in the inter-word gap is a hard
 * break; the word gap is only a fallback when no silence was detected.
 */
function segment(words: TranscriptWord[], silences: { start: number; end: number }[], gap = 0.6): Sentence[] {
  const out: Sentence[] = [];
  let cur: TranscriptWord[] = [];
  for (let i = 0; i < words.length; i++) {
    const w = words[i]!;
    if (cur.length) {
      const prevEnd = cur[cur.length - 1]!.end;
      // A silence range intersecting the gap between the previous word and this
      // one is an authoritative take boundary (tolerant to whisper bleed).
      const silenceBreak = silences.some((s) => s.start < w.start - 0.02 && s.end > prevEnd - 0.15);
      if (silenceBreak || w.start - prevEnd > gap) {
        out.push(toSentence(cur));
        cur = [];
      }
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
  const sentences = segment(words, m.silence_ranges ?? []);
  const flagged = new Set<number>(); // sentence indices already marked bad
  const bad: BadTakePhrase[] = [];
  const mark = (i: number, b: BadTakePhrase) => {
    if (i < 0 || i >= sentences.length || flagged.has(i)) return;
    flagged.add(i);
    bad.push(b);
  };

  for (let i = 0; i < sentences.length; i++) {
    const s = sentences[i]!;
    const n = norm(s.text);

    // 1) explicit edit command → this sentence is a bad take, AND so is the take
    //    it corrects: the immediately preceding speech sentence ("burası olmadı,
    //    tekrar alayım" means redo the previous attempt). Remove both, keep the retake.
    const cmd = EDIT_COMMANDS.find((c) => n.includes(c));
    if (cmd) {
      const prev = sentences[i - 1];
      if (prev && !flagged.has(i - 1)) {
        mark(i - 1, { start: prev.start, end: prev.end, text: prev.text, kind: "restart", confidence: 0.85, reason: `corrected take (followed by "${cmd}")` });
      }
      mark(i, { start: s.start, end: s.end, text: s.text, kind: "edit_command", confidence: 0.92, reason: `edit command "${cmd}"` });
      continue;
    }

    // 2) restart: this sentence is a truncated attempt re-said in the next.
    const next = sentences[i + 1];
    if (next && isRestart(s.text, next.text)) {
      mark(i, { start: s.start, end: s.end, text: s.text, kind: "restart", confidence: 0.8, reason: "restarted — re-said immediately" });
      continue;
    }

    // 3) near-duplicate: keep the later (usually the better/complete) take.
    if (next && jaccard(s.text, next.text) > 0.82 && s.words.length >= 3) {
      mark(i, { start: s.start, end: s.end, text: s.text, kind: "duplicate", confidence: 0.75, reason: "duplicate of the next take" });
    }
  }

  bad.sort((a, b) => a.start - b.start);
  m.bad_take_phrases = await llmAudit(sentences, bad);
}

/**
 * Coherence pass (Groq). Reads the WHOLE numbered transcript and decides which
 * sentences to REMOVE so the kept ones read as one clean, non-repetitive script.
 * This is what kills the "full of repeated/incoherent sentences" problem:
 * unscripted creators say the same line 2–4 times (retakes) without an explicit
 * "cut" command, so the heuristics miss it. The LLM keeps the best version of
 * each idea and drops the rest. Heuristic edit-commands stay as a floor.
 */
async function llmAudit(sentences: Sentence[], heuristic: BadTakePhrase[]): Promise<BadTakePhrase[]> {
  if (!groqConfigured() || sentences.length < 2) return heuristic;
  const numbered = sentences.map((s, i) => `${i}\t[${s.start.toFixed(2)}-${s.end.toFixed(2)}]\t${s.text}`).join("\n");
  const removeSet = new Set(heuristic.map((b) => b.start.toFixed(2)));

  const system =
    "You are a ruthless short-form video editor cleaning a raw, unscripted talking-head transcript (mostly Turkish). " +
    "Creators record the SAME line several times (retakes), make false starts, ramble, and repeat ideas. " +
    "Your job: choose the sentences to REMOVE so the KEPT sentences read as ONE coherent, non-repetitive script that flows naturally. Return JSON only.";
  const user =
    `Transcript sentences (index, time, text):\n${numbered}\n\n` +
    `Return {"remove":[{"index":N,"kind":"duplicate|restart|edit_command|filler|incoherent","reason":"..."}]}.\n` +
    `Rules:\n` +
    `- When the same idea/sentence is said more than once (a retake), KEEP only the single best version (usually the most complete / the LAST clean one) and REMOVE all the others.\n` +
    `- Remove false starts and fragments that are completed/repeated later.\n` +
    `- Remove explicit edit commands ("tekrar alayım", "burası olmadı", "şunu kes", "baştan").\n` +
    `- Remove pure filler/incoherent sentences that add nothing.\n` +
    `- Read the KEPT sequence in your head: it MUST make sense end-to-end with no obvious repetition. Be aggressive about repetition; when unsure between two near-identical takes, remove the earlier one.\n` +
    `- Do NOT remove distinct content just because it is similar in topic.`;

  try {
    const res = await chatJson<{ remove?: { index: number; kind?: string; reason?: string }[] }>(system, user);
    const removals = res?.remove ?? [];
    const out = [...heuristic];
    for (const item of removals) {
      const s = sentences[item.index];
      if (!s) continue;
      const key = s.start.toFixed(2);
      if (removeSet.has(key)) continue;
      removeSet.add(key);
      const kind = (["edit_command", "restart", "duplicate", "filler"].includes(item.kind ?? "") ? item.kind : "duplicate") as BadTakePhrase["kind"];
      out.push({ start: s.start, end: s.end, text: s.text, kind, confidence: 0.8, reason: item.reason ?? "coherence: repeated/incoherent" });
    }
    return out.sort((a, b) => a.start - b.start);
  } catch (e) {
    warn("badtake", `coherence pass failed: ${(e as Error).message}`);
    return heuristic;
  }
}
