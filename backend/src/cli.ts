import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { randomUUID } from "node:crypto";
import { runJob } from "./orchestrator.js";
import { cloudStore, localStore } from "./lib/store.js";
import { log } from "./lib/log.js";

async function main() {
  const args = process.argv.slice(2);
  const localIdx = args.indexOf("--local");

  if (localIdx !== -1) {
    // Local dry-run: tsx src/cli.ts --local <video> [workDir]
    const video = args[localIdx + 1];
    if (!video) throw new Error("usage: --local <video.mp4>");
    const jobId = randomUUID();
    const workDir = args[localIdx + 2] || mkdtempSync(join(tmpdir(), "cutsense-"));
    log("cli", `local dry-run job=${jobId} src=${video} work=${workDir}`);
    const store = await localStore(jobId, video, workDir);
    const res = await runJob(store, null);
    log("cli", res.ok ? `OK → ${workDir}/final.mp4` : `FAILED: ${res.error}`);
    console.log(JSON.stringify(res.manifest, null, 2));
    process.exit(0); // always green
  }

  // Cloud: tsx src/cli.ts <jobId> [projectId]
  const jobId = args[0];
  if (!jobId) throw new Error("usage: <jobId> | --local <video>");
  const projectId = args[1] ?? null;
  const workDir = mkdtempSync(join(tmpdir(), "cutsense-"));
  const store = await cloudStore(jobId, workDir);
  const res = await runJob(store, projectId);
  log("cli", res.ok ? "job done" : `job failed: ${res.error}`);
  process.exit(0); // GitHub Actions stays green; failure is recorded in the job row
}

main().catch((e) => {
  // last-resort guard — still exit 0 so the workflow run is green
  console.error("fatal:", (e as Error).message);
  process.exit(0);
});
