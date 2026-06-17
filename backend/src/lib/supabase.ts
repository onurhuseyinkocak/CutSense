import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import type { EditManifest, JobStatus } from "../manifest.js";

/**
 * Service-role Supabase client (server-only). Env:
 *   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
 */
export function supabaseConfigured(): boolean {
  return !!(process.env.SUPABASE_URL && process.env.SUPABASE_SERVICE_ROLE_KEY);
}

let _client: SupabaseClient | null = null;
function client(): SupabaseClient {
  if (!_client) {
    _client = createClient(process.env.SUPABASE_URL!, process.env.SUPABASE_SERVICE_ROLE_KEY!, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
  }
  return _client;
}

export async function updateJob(jobId: string, patch: { status?: JobStatus; progress?: number; error?: string | null; final_r2_key?: string | null }): Promise<void> {
  await client()
    .from("jobs")
    .update({ ...patch, updated_at: new Date().toISOString() })
    .eq("id", jobId);
}

export async function getJobRawKey(jobId: string): Promise<string | null> {
  const { data } = await client().from("jobs").select("raw_r2_key").eq("id", jobId).maybeSingle();
  return (data?.raw_r2_key as string | undefined) ?? null;
}

export async function saveManifest(jobId: string, manifest: EditManifest): Promise<void> {
  // Upsert latest version row (one current manifest per job; versions append).
  await client().from("edit_manifests").insert({ job_id: jobId, manifest });
}

/**
 * Atomically claim the oldest queued job for the local poller (the Mac is the
 * render worker; GitHub Actions needs paid minutes). The conditional update on
 * status='queued' guards against double-claiming.
 */
export async function claimNextQueuedJob(): Promise<{ id: string; project_id: string | null } | null> {
  const c = client();
  const { data } = await c.from("jobs").select("id, project_id").eq("status", "queued").order("created_at", { ascending: true }).limit(1).maybeSingle();
  if (!data) return null;
  const { data: claimed } = await c
    .from("jobs")
    .update({ status: "normalizing", progress: 1, updated_at: new Date().toISOString() })
    .eq("id", data.id)
    .eq("status", "queued")
    .select("id, project_id")
    .maybeSingle();
  return claimed ? { id: claimed.id as string, project_id: (claimed.project_id as string | null) ?? null } : null;
}
