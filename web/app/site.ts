const fallbackSiteUrl = "https://cutsense.onarika.net";

function normalizeSiteUrl(value: string | undefined) {
  if (!value) {
    return fallbackSiteUrl;
  }

  try {
    const url = new URL(value);
    url.pathname = "";
    url.search = "";
    url.hash = "";
    return url.toString().replace(/\/$/, "");
  } catch {
    return fallbackSiteUrl;
  }
}

export const siteUrl = normalizeSiteUrl(process.env.NEXT_PUBLIC_SITE_URL);
