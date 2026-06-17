import { mkdir, copyFile, writeFile } from "node:fs/promises";
import { join } from "node:path";
import type { EditManifest, JobStatus } from "../manifest.js";
import { log } from "./log.js";
import * as r2 from "./r2.js";
import * as db from "./supabase.js";

/**
 * Persistence abstraction so the same orchestrator runs in the cloud
 * (Supabase + R2) or locally (a working directory) for dry-runs.
 */
export interface Store {
  mode: "cloud" | "local";
  jobId: string;
  workDir: string;
  /** Local path to the raw input video (downloaded in cloud mode). */
  rawPath(): Promise<string>;
  setStatus(status: JobStatus, progress: number): Promise<void>;
  saveManifest(m: EditManifest): Promise<void>;
  setError(msg: string): Promise<void>;
  /** Persist the final mp4; returns the stored key (cloud) or path (local). */
  uploadFinal(localPath: string): Promise<string>;
}

export async function cloudStore(jobId: string, workDir: string): Promise<Store> {
  await mkdir(workDir, { recursive: true });
  if (!r2.r2Configured()) throw new Error("R2 env not configured (R2_ACCOUNT_ID/...)");
  if (!db.supabaseConfigured()) throw new Error("Supabase env not configured (SUPABASE_URL/...)");
  let rawLocal: string | null = null;
  return {
    mode: "cloud",
    jobId,
    workDir,
    async rawPath() {
      if (rawLocal) return rawLocal;
      const key = await db.getJobRawKey(jobId);
      if (!key) throw new Error(`job ${jobId} has no raw_r2_key`);
      rawLocal = join(workDir, "raw.mp4");
      await r2.downloadToFile(key, rawLocal);
      return rawLocal;
    },
    async setStatus(status, progress) {
      await db.updateJob(jobId, { status, progress });
    },
    async saveManifest(m) {
      await db.saveManifest(jobId, m);
      await r2.uploadJson(`manifests/${jobId}.json`, m);
    },
    async setError(msg) {
      await db.updateJob(jobId, { status: "failed", error: msg.slice(0, 4000) });
    },
    async uploadFinal(localPath) {
      const key = `final/${jobId}.mp4`;
      await r2.uploadFile(key, localPath, "video/mp4");
      await db.updateJob(jobId, { final_r2_key: key });
      return key;
    },
  };
}

export async function localStore(jobId: string, srcVideo: string, workDir: string): Promise<Store> {
  await mkdir(workDir, { recursive: true });
  return {
    mode: "local",
    jobId,
    workDir,
    async rawPath() {
      const p = join(workDir, "raw" + (srcVideo.endsWith(".mov") ? ".mov" : ".mp4"));
      await copyFile(srcVideo, p);
      return p;
    },
    async setStatus(status, progress) {
      log("status", `${status} ${progress}%`);
    },
    async saveManifest(m) {
      await writeFile(join(workDir, "manifest.json"), JSON.stringify(m, null, 2));
    },
    async setError(msg) {
      log("error", msg);
    },
    async uploadFinal(localPath) {
      const p = join(workDir, "final.mp4");
      await copyFile(localPath, p);
      log("upload", `final → ${p}`);
      return p;
    },
  };
}
