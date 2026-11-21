export const dynamic = "force-static";
import type { MetadataRoute } from "next";
import { landingPages } from "./landing-data";
import { siteUrl } from "./site";

const lastModified = new Date("2026-06-29");

export default function sitemap(): MetadataRoute.Sitemap {
  return ["", "/privacy", "/terms", "/support", ...landingPages.map((p) => p.path)].map((path) => ({
    url: `${siteUrl}${path}`,
    lastModified,
    changeFrequency: "monthly",
    priority: path === "" ? 1 : 0.8,
  }));
}
