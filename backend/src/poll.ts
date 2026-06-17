import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { runJob } from "./orchestrator.js";
import { cloudStore } from "./lib/store.js";
import { claimNextQueuedJob } from "./lib/supabase.js";
import { backend } from "./lib/blob.js";
import { log, warn } from "./lib/log.js";

/**
 * Local render worker. Polls Supabase for queued jobs and runs the pipeline on
 * this machine — the free alternative to GitHub Actions (which needs paid
 * minutes on a private repo). Run: `npx tsx src/poll.ts`. Keep it running.
 */
const INTERVAL = Number(process.env.POLL_INTERVAL_MS ?? 4000);
let running = true;
process.on("SIGINT", () => {
  running = false;
  log("poll", "stopping…");
});

async function processOne(): Promise<boolean> {
  const job = await claimNextQueuedJob();
  if (!job) return false;
  const workDir = mkdtempSync(join(tmpdir(), "cutsense-"));
  log("poll", `claimed ${job.id} (storage=${backend})`);
  try {
    const store = await cloudStore(job.id, workDir);
    const res = await runJob(store, job.project_id);
    log("poll", res.ok ? `done ${job.id}` : `failed ${job.id}: ${res.error}`);
  } catch (e) {
    warn("poll", `job ${job.id} crashed: ${(e as Error).message}`);
  } finally {
    try {
      rmSync(workDir, { recursive: true, force: true });
    } catch {
      /* ignore */
    }
  }
  return true;
}

async function loop() {
  log("poll", `worker up — storage=${backend}, interval=${INTERVAL}ms`);
  while (running) {
    let didWork = false;
    try {
      didWork = await processOne();
    } catch (e) {
      warn("poll", `tick error: ${(e as Error).message}`);
    }
    if (!didWork) await sleep(INTERVAL);
  }
  process.exit(0);
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
loop();
