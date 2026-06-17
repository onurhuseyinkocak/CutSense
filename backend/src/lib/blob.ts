import * as r2 from "./r2.js";
import * as sb from "./sbstorage.js";

/**
 * Blob backend selector. Defaults to Supabase Storage when its env is present
 * (reachable everywhere), falls back to R2. Force with STORAGE_BACKEND=r2|supabase.
 * Keys are backend-agnostic (raw/<id>, final/<id>.mp4, manifests/<id>.json).
 */
const forced = process.env.STORAGE_BACKEND;
const useSupabase = forced === "supabase" || (forced !== "r2" && sb.sbStorageConfigured());

const impl = useSupabase ? sb : r2;

export const downloadToFile = impl.downloadToFile;
export const uploadFile = impl.uploadFile;
export const uploadJson = impl.uploadJson;
export const presignGet = impl.presignGet;
export const presignPut = impl.presignPut;
export const backend: "supabase" | "r2" = useSupabase ? "supabase" : "r2";
export const configured = (): boolean => (useSupabase ? sb.sbStorageConfigured() : r2.r2Configured());
