// Supabase Edge Function: create-job
// 1) verify caller, 2) create a Supabase Storage signed upload URL for the raw
// video, 3) insert a queued jobs row. The local poller (npx tsx src/poll.ts on
// the Mac) claims and renders it — no GitHub Actions (paid on private repos) and
// no R2 (ISP SNI-filters *.r2.cloudflarestorage.com in some regions).
//
// Storage uses Supabase's own host (always reachable). Free tier caps objects at
// 50MB, so the client must compress the raw before upload.
//
// Env (auto-injected by Supabase): SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY
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
  const authHeader = req.headers.get("Authorization") || "";
  const token = authHeader.replace("Bearer ", "").trim();
  if (!token) return json({ error: "unauthorized" }, 401);

  // identify caller
  const anon = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!);
  const { data: { user }, error: userErr } = await anon.auth.getUser(token);
  if (userErr || !user) return json({ error: "unauthorized" }, 401);

  const body = await req.json().catch(() => ({}));
  const projectId: string | null = typeof body.project_id === "string" ? body.project_id : null;
  const ext = typeof body.ext === "string" && /^[a-z0-9]{1,5}$/.test(body.ext) ? body.ext : "mp4";

  const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const bucket = Deno.env.get("STORAGE_BUCKET") || "media";
  const jobId = crypto.randomUUID();
  const rawKey = `raw/${jobId}.${ext}`;

  // signed upload URL (the client PUTs the raw video here; no service key exposed)
  const { data: signed, error: signErr } = await admin.storage.from(bucket).createSignedUploadUrl(rawKey);
  if (signErr || !signed) return json({ error: signErr?.message || "sign failed" }, 500);

  // insert as awaiting_upload — the client flips it to "queued" only AFTER the
  // raw upload finishes, so the poller never claims a job whose raw isn't there.
  const { error: insErr } = await admin.from("jobs").insert({
    id: jobId,
    user_id: user.id,
    project_id: projectId,
    status: "awaiting_upload",
    raw_r2_key: rawKey,
  });
  if (insErr) return json({ error: insErr.message }, 500);

  return json({
    job_id: jobId,
    raw_key: rawKey,
    bucket,
    upload_url: signed.signedUrl, // PUT the raw video here
    upload_token: signed.token,   // or use supabase-js uploadToSignedUrl(path, token, file)
    storage: "supabase",
  });
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
}
