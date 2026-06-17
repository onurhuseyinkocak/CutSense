import { createWriteStream } from "node:fs";
import { pipeline } from "node:stream/promises";
import { Readable } from "node:stream";
import { readFile } from "node:fs/promises";

/**
 * Supabase Storage blob backend (REST). Mirrors r2.ts so the Store can use
 * either. Picked when R2 is unreachable (e.g. ISP SNI-filters
 * *.r2.cloudflarestorage.com) — Supabase's own host stays reachable.
 *
 * Env: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, STORAGE_BUCKET (default "media").
 * Free tier caps objects at 50MB; raw uploads must be compressed client-side.
 */
export function sbStorageConfigured(): boolean {
  return !!(process.env.SUPABASE_URL && process.env.SUPABASE_SERVICE_ROLE_KEY && (process.env.STORAGE_BUCKET || "media"));
}

const base = () => `${process.env.SUPABASE_URL!.replace(/\/$/, "")}/storage/v1`;
const bucket = () => process.env.STORAGE_BUCKET || "media";
const auth = () => {
  const k = process.env.SUPABASE_SERVICE_ROLE_KEY!;
  return { Authorization: `Bearer ${k}`, apikey: k };
};

export async function downloadToFile(key: string, destPath: string): Promise<void> {
  const res = await fetch(`${base()}/object/${bucket()}/${encodeKey(key)}`, { headers: auth() });
  if (!res.ok || !res.body) throw new Error(`sbstorage download ${key}: ${res.status} ${await safeText(res)}`);
  await pipeline(Readable.fromWeb(res.body as Parameters<typeof Readable.fromWeb>[0]), createWriteStream(destPath));
}

export async function uploadFile(key: string, localPath: string, contentType: string): Promise<void> {
  const body = await readFile(localPath);
  await put(key, body, contentType);
}

export async function uploadJson(key: string, value: unknown): Promise<void> {
  await put(key, Buffer.from(JSON.stringify(value)), "application/json");
}

async function put(key: string, body: Buffer, contentType: string): Promise<void> {
  // POST creates, but with x-upsert we overwrite on re-runs.
  const res = await fetch(`${base()}/object/${bucket()}/${encodeKey(key)}`, {
    method: "POST",
    headers: { ...auth(), "Content-Type": contentType, "x-upsert": "true" },
    body,
  });
  if (!res.ok) throw new Error(`sbstorage upload ${key}: ${res.status} ${await safeText(res)}`);
}

/** Signed GET URL (absolute) for the client to download the final video. */
export async function presignGet(key: string, expiresSeconds = 3600): Promise<string> {
  const res = await fetch(`${base()}/object/sign/${bucket()}/${encodeKey(key)}`, {
    method: "POST",
    headers: { ...auth(), "Content-Type": "application/json" },
    body: JSON.stringify({ expiresIn: expiresSeconds }),
  });
  if (!res.ok) throw new Error(`sbstorage sign ${key}: ${res.status} ${await safeText(res)}`);
  const { signedURL } = (await res.json()) as { signedURL: string };
  return `${base()}${signedURL}`;
}

/**
 * Signed upload token URL (absolute) for the client to PUT the raw video to,
 * without exposing the service key. Returns the URL the client PUTs to.
 */
export async function presignPut(key: string, _contentType: string, _expiresSeconds = 3600): Promise<string> {
  const res = await fetch(`${base()}/object/upload/sign/${bucket()}/${encodeKey(key)}`, {
    method: "POST",
    headers: { ...auth(), "Content-Type": "application/json" },
    body: JSON.stringify({}),
  });
  if (!res.ok) throw new Error(`sbstorage upload-sign ${key}: ${res.status} ${await safeText(res)}`);
  const { url } = (await res.json()) as { url: string };
  return `${base()}${url}`;
}

function encodeKey(key: string): string {
  return key.split("/").map(encodeURIComponent).join("/");
}
async function safeText(res: Response): Promise<string> {
  try {
    return (await res.text()).slice(0, 200);
  } catch {
    return "";
  }
}
