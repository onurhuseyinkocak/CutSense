import { writeFile, copyFile } from "node:fs/promises";
import { ffmpeg, hasFilter } from "../lib/ffmpeg.js";
import { warn } from "../lib/log.js";
import type { CaptionEvent, EditManifest } from "../manifest.js";
import type { Ctx } from "./ctx.js";

// Reels safe area (CaptionModels.swift): 1080×1920, bottom inset 180. Captions
// sit in the lower third, above the progress bar; word-level karaoke highlight.
const PLAY_W = 1080;
const PLAY_H = 1920;
const MARGIN_V = 360; // distance from bottom (keeps captions out of the unsafe bottom 180px)
const MARGIN_H = 96;

function ts(sec: number): string {
  const s = Math.max(0, sec);
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  const cs = Math.round((s - Math.floor(s)) * 100);
  return `${h}:${String(m).padStart(2, "0")}:${String(Math.floor(s % 60)).padStart(2, "0")}.${String(cs).padStart(2, "0")}`;
}

function escapeAss(t: string): string {
  return t.replace(/[{}]/g, "").replace(/\\/g, " ");
}

// ASS colours are &HAABBGGRR. Bright fill (sung) vs dim (unsung) for karaoke.
function styleLine(name: string, size: number, primary: string, secondary: string, bold: number): string {
  // Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
  return `Style: ${name},Arial,${size},${primary},${secondary},&H00101010,&H64000000,${bold},0,0,0,100,100,0,0,1,4,3,2,${MARGIN_H},${MARGIN_H},${MARGIN_V},1`;
}

function dialogue(ev: CaptionEvent): string {
  const style = ev.role === "hook" ? "Hook" : ev.role === "keyword" ? "Keyword" : "Default";
  const karaoke = ev.word_timings
    .map((w) => `{\\k${Math.max(1, Math.round(w.duration * 100))}}${escapeAss(w.word)} `)
    .join("")
    .trim();
  return `Dialogue: 0,${ts(ev.start)},${ts(ev.end)},${style},,0,0,0,,${karaoke}`;
}

function buildAss(events: CaptionEvent[]): string {
  const head = [
    "[Script Info]",
    "ScriptType: v4.00+",
    "WrapStyle: 2",
    `PlayResX: ${PLAY_W}`,
    `PlayResY: ${PLAY_H}`,
    "ScaledBorderAndShadow: yes",
    "",
    "[V4+ Styles]",
    "Format: Name,Fontname,Fontsize,PrimaryColour,SecondaryColour,OutlineColour,BackColour,Bold,Italic,Underline,StrikeOut,ScaleX,ScaleY,Spacing,Angle,BorderStyle,Outline,Shadow,Alignment,MarginL,MarginR,MarginV,Encoding",
    // sung = white, unsung = dim grey
    styleLine("Default", 70, "&H00FFFFFF", "&H00BBBBBB", -1),
    // hook = bright yellow sung
    styleLine("Hook", 92, "&H0000F0FF", "&H00DDDDDD", -1),
    // keyword = cyan sung
    styleLine("Keyword", 78, "&H00F0E000", "&H00CCCCCC", -1),
    "",
    "[Events]",
    "Format: Layer,Start,End,Style,Name,MarginL,MarginR,MarginV,Effect,Text",
  ];
  return head.concat(events.map(dialogue)).join("\n") + "\n";
}

/** Burn captions onto the clean video → final.mp4. No captions → final == clean. */
export async function renderCaptions(m: EditManifest, ctx: Ctx): Promise<void> {
  if (m.caption_events.length === 0) {
    await copyFile(ctx.clean, ctx.final);
    return;
  }
  // The ass filter needs an ffmpeg built with libass. Prod (ubuntu apt ffmpeg)
  // has it; a libass-less local build would otherwise hard-fail the job. Fall
  // back to the clean (uncaptioned) cut so the job still completes.
  if (!(await hasFilter("ass"))) {
    warn("captions", "ffmpeg has no libass (ass filter) — shipping clean cut without burned captions");
    m.render.captions_burned = false;
    await copyFile(ctx.clean, ctx.final);
    return;
  }
  m.render.captions_burned = true;
  await writeFile(ctx.assPath, buildAss(m.caption_events));
  const args = ["-i", ctx.clean, "-vf", `ass=${ctx.assPath}`, "-c:v", "libx264", "-preset", "veryfast", "-crf", "20", "-pix_fmt", "yuv420p", "-movflags", "+faststart"];
  if (m.source?.has_audio) args.push("-c:a", "copy");
  else args.push("-an");
  args.push(ctx.final);
  await ffmpeg(args);
}
