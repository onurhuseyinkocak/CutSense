import { copyFile } from "node:fs/promises";
import { emptyManifest, type EditManifest, type JobStatus } from "./manifest.js";
import { makeCtx } from "./stages/ctx.js";
import { log } from "./lib/log.js";
import type { Store } from "./lib/store.js";
import { normalize } from "./stages/normalize.js";
import { extractAudio, detectSilence } from "./stages/audio.js";
import { transcribeStage } from "./stages/transcribe.js";
import { detectBadTakes } from "./stages/badtake.js";
import { planCuts } from "./stages/plan.js";
import { renderClean } from "./stages/renderClean.js";
import { realign } from "./stages/realign.js";
import { buildCaptions } from "./stages/captions.js";
import { planEffects } from "./stages/effects.js";
import { renderEffects } from "./stages/renderEffects.js";
import { renderCaptions } from "./stages/renderCaptions.js";
import { renderSfx } from "./stages/renderSfx.js";
import { qa } from "./stages/qa.js";

export interface JobResult {
  ok: boolean;
  manifest: EditManifest;
  error?: string;
}

/**
 * Run the full pipeline for one job. Persists manifest + progress after every
 * stage so the client can poll. Never throws — failures land in the manifest +
 * store.setError so the worker (GitHub Actions) can still exit 0.
 */
export async function runJob(store: Store, projectId: string | null): Promise<JobResult> {
  const m = emptyManifest(store.jobId, projectId);

  const step = async (status: JobStatus, progress: number, fn: () => Promise<void> | void) => {
    m.status = status;
    await store.setStatus(status, progress);
    log("stage", `${status} (${progress}%)`);
    await fn();
    m.updated_at = new Date().toISOString();
    await store.saveManifest(m);
  };

  try {
    const raw = await store.rawPath();
    const ctx = makeCtx(store.workDir, raw);

    await step("normalizing", 8, () => normalize(m, ctx));
    await step("transcribing", 30, async () => {
      await extractAudio(m, ctx);
      await transcribeStage(m, ctx);
    });
    await step("analyzing", 45, async () => {
      await detectSilence(m, ctx);
      await detectBadTakes(m, ctx);
    });
    await step("planning", 52, () => planCuts(m, ctx));
    await step("rendering_clean", 64, () => renderClean(m, ctx));
    await step("captioning", 74, () => {
      realign(m, ctx);
      buildCaptions(m, ctx);
      planEffects(m, ctx);
    });
    // visual FX (grade/zoom/flash/glitch) → burn captions → mix SFX. Each stage
    // falls back to a passthrough so effects never fail the whole job.
    await step("rendering_final", 88, async () => {
      try {
        await renderEffects(m, ctx);
      } catch (e) {
        log("fx", `visual fx failed, using clean: ${(e as Error).message}`);
        await copyFile(ctx.clean, ctx.effected);
      }
      await renderCaptions(m, ctx);
      await renderSfx(m, ctx);
    });
    await step("qa", 95, () => qa(m, ctx));
    await step("uploading", 98, async () => {
      m.render.final_r2_key = await store.uploadFinal(ctx.final);
    });

    m.status = "done";
    m.updated_at = new Date().toISOString();
    await store.setStatus("done", 100);
    await store.saveManifest(m);
    log("done", `clean=${m.clean_duration.toFixed(1)}s cuts=${m.cut_ranges.length} captions=${m.caption_events.length} qa=${m.qa_results?.passed}`);
    return { ok: true, manifest: m };
  } catch (e) {
    const error = (e as Error).message;
    m.status = "failed";
    log("failed", error);
    await store.setError(error).catch(() => {});
    await store.saveManifest(m).catch(() => {});
    return { ok: false, manifest: m, error };
  }
}
