import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { cwd, exit } from "node:process";

const root = cwd();
const failures = [];

function assert(condition, message) {
  if (!condition) {
    failures.push(message);
  }
}

function read(path) {
  return readFileSync(join(root, path), "utf8");
}

const nextConfig = read("next.config.ts");
const packageJson = JSON.parse(read("package.json"));

assert(existsSync(join(root, "public/app-icon.png")), "public/app-icon.png is missing");
assert(existsSync(join(root, "app/privacy/page.tsx")), "privacy page is missing");
assert(existsSync(join(root, "app/terms/page.tsx")), "terms page is missing");
assert(existsSync(join(root, "app/support/page.tsx")), "support page is missing");
assert(packageJson.scripts?.lint, "lint script is missing");
assert(packageJson.scripts?.typecheck, "typecheck script is missing");
assert(packageJson.pnpm?.overrides?.postcss === "8.5.10", "PostCSS override is missing");
assert(nextConfig.includes("poweredByHeader: false"), "poweredByHeader is not disabled");
assert(nextConfig.includes("Strict-Transport-Security"), "HSTS header is missing");
assert(nextConfig.includes("Cross-Origin-Opener-Policy"), "COOP header is missing");
assert(nextConfig.includes("Cross-Origin-Resource-Policy"), "CORP header is missing");
assert(!nextConfig.includes("'unsafe-eval'"), "CSP still allows unsafe-eval");

for (const path of ["app/layout.tsx", "app/robots.ts", "app/sitemap.ts"]) {
  assert(read(path).includes("siteUrl"), `${path} does not use shared siteUrl`);
}

if (failures.length > 0) {
  console.error(failures.map((failure) => `- ${failure}`).join("\n"));
  exit(1);
}

console.log("CutSense web smoke checks passed");
