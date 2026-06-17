// Supabase Edge Function: create-job
// 1) verify caller, 2) presign an R2 PUT for the raw upload, 3) insert a jobs
// row, 4) fire a GitHub repository_dispatch to run the render worker.
//
// Env (Supabase function secrets):
//   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, SUPABASE_ANON_KEY
//   R2_ACCOUNT_ID, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY, R2_BUCKET
//   GH_DISPATCH_TOKEN (PAT with repo scope), GH_REPO (e.g. onurhuseyinkocak/CutSense)
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { AwsClient } from "https://esm.sh/aws4fetch@1.0.20";

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
  const jobId = crypto.randomUUID();
  const rawKey = `raw/${jobId}.${ext}`;

  // presign R2 PUT (1h)
  const r2 = new AwsClient({
    accessKeyId: Deno.env.get("R2_ACCESS_KEY_ID")!,
    secretAccessKey: Deno.env.get("R2_SECRET_ACCESS_KEY")!,
    region: "auto",
    service: "s3",
  });
  const bucket = Deno.env.get("R2_BUCKET")!;
  const endpoint = `https://${Deno.env.get("R2_ACCOUNT_ID")}.r2.cloudflarestorage.com/${bucket}/${rawKey}`;
  const signed = await r2.sign(new Request(`${endpoint}?X-Amz-Expires=3600`, { method: "PUT" }), { aws: { signQuery: true } });
  const uploadUrl = signed.url;

  // insert job
  const { error: insErr } = await admin.from("jobs").insert({
    id: jobId,
    user_id: user.id,
    project_id: projectId,
    status: "queued",
    raw_r2_key: rawKey,
  });
  if (insErr) return json({ error: insErr.message }, 500);

  // fire GitHub render worker (best-effort; the row is queued either way)
  const ghToken = Deno.env.get("GH_DISPATCH_TOKEN");
  const ghRepo = Deno.env.get("GH_REPO");
  if (ghToken && ghRepo) {
    await fetch(`https://api.github.com/repos/${ghRepo}/dispatches`, {
      method: "POST",
      headers: { Authorization: `Bearer ${ghToken}`, Accept: "application/vnd.github+json", "Content-Type": "application/json" },
      body: JSON.stringify({ event_type: "render-job", client_payload: { job_id: jobId, project_id: projectId } }),
    }).catch(() => {});
  }

  return json({ job_id: jobId, upload_url: uploadUrl, raw_key: rawKey });
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
}
