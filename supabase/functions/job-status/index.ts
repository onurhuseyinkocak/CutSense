// Supabase Edge Function: job-status
// Poll endpoint for the iOS app. POST { job_id } + user JWT → verifies the
// caller owns the job and returns status/progress/error plus short-lived signed
// GET URLs for the raw and final videos (the storage bucket is private, so the
// client can't sign them itself).
//
// Env (auto-injected): SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY
// Optional: STORAGE_BUCKET (default "media")
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "method" }, 405);

  const url = Deno.env.get("SUPABASE_URL")!;
  const token = (req.headers.get("Authorization") || "").replace("Bearer ", "").trim();
  if (!token) return json({ error: "unauthorized" }, 401);

  const anon = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!);
  const { data: { user }, error: userErr } = await anon.auth.getUser(token);
  if (userErr || !user) return json({ error: "unauthorized" }, 401);

  const body = await req.json().catch(() => ({}));
  const jobId: string | null = typeof body.job_id === "string" ? body.job_id : null;
  if (!jobId) return json({ error: "job_id required" }, 400);

  const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const { data: job, error } = await admin
    .from("jobs")
    .select("user_id, status, progress, error, raw_r2_key, final_r2_key")
    .eq("id", jobId)
    .maybeSingle();
  if (error) return json({ error: error.message }, 500);
  if (!job) return json({ error: "not found" }, 404);
  if (job.user_id !== user.id) return json({ error: "forbidden" }, 403);

  const bucket = Deno.env.get("STORAGE_BUCKET") || "media";
  const sign = async (key: string | null): Promise<string | null> => {
    if (!key) return null;
    const { data } = await admin.storage.from(bucket).createSignedUrl(key, 3600);
    return data?.signedUrl ?? null;
  };

  return json({
    status: job.status,
    progress: job.progress,
    error: job.error,
    raw_url: await sign(job.raw_r2_key),
    final_url: await sign(job.final_r2_key),
  });
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
}
