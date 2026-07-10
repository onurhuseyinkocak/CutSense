import type { NextConfig } from "next";

const canonicalHost = "cutsense.onarika.net";
const legacyHosts = [
  "cutsense.vercel.app",
  "cutsense-onurs-projects-d25c20cf.vercel.app",
  "web-seven-iota-53.vercel.app",
];

const appAdsHeaders = [
  { key: "Content-Type", value: "text/plain; charset=utf-8" },
  { key: "Cache-Control", value: "no-store, max-age=0, must-revalidate" },
  { key: "Access-Control-Allow-Origin", value: "*" },
];

const securityHeaders = [
  {
    key: "Content-Security-Policy",
    value: [
      "default-src 'self'",
      "base-uri 'self'",
      "frame-ancestors 'none'",
      "form-action 'self' mailto:",
      "object-src 'none'",
      "img-src 'self' data:",
      "font-src 'self'",
      "style-src 'self' 'unsafe-inline'",
      "script-src 'self' 'unsafe-inline'",
      "connect-src 'self'",
      "manifest-src 'self'",
      "worker-src 'self' blob:",
    ].join("; "),
  },
  {
    key: "Strict-Transport-Security",
    value: "max-age=63072000; includeSubDomains; preload",
  },
  { key: "Referrer-Policy", value: "strict-origin-when-cross-origin" },
  { key: "X-Content-Type-Options", value: "nosniff" },
  { key: "X-Frame-Options", value: "DENY" },
  { key: "Cross-Origin-Opener-Policy", value: "same-origin" },
  { key: "Cross-Origin-Resource-Policy", value: "same-site" },
  { key: "Origin-Agent-Cluster", value: "?1" },
  { key: "X-DNS-Prefetch-Control", value: "off" },
  { key: "X-Download-Options", value: "noopen" },
  { key: "X-Permitted-Cross-Domain-Policies", value: "none" },
  {
    key: "Permissions-Policy",
    value: "camera=(), microphone=(), geolocation=(), payment=(), usb=(), bluetooth=(), browsing-topics=()",
  },
];

const nextConfig: NextConfig = {
  poweredByHeader: false,
  async redirects() {
    return legacyHosts.map((host) => ({
      source: "/:path((?!app-ads\\.txt$|ads\\.txt$).*)",
      has: [{ type: "host", value: host }],
      destination: `https://${canonicalHost}/:path*`,
      permanent: true,
    }));
  },
  async headers() {
    return [
      {
        source: "/app-ads.txt",
        headers: appAdsHeaders,
      },
      {
        source: "/ads.txt",
        headers: appAdsHeaders,
      },
      {
        source: "/(.*)",
        headers: securityHeaders,
      },
    ];
  },
};

export default nextConfig;
