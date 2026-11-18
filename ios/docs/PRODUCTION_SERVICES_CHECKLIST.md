# Production services checklist

## AdMob

- The iOS target uses the production AdMob application and ad-unit identifiers in Release.
- Debug builds deliberately use Google's test ad-unit IDs. Do not change this: requesting live ads during development can violate AdMob policy.
- Before submitting, create or confirm the app entry in AdMob and complete its iOS app-ads.txt check.

## app-ads.txt

The repository already publishes the required record at `web/public/app-ads.txt`:

```text
google.com, pub-6644397387275334, DIRECT, f08c47fec0942fa0
```

The configured marketing domain is `https://cutsense.onarika.net`. It currently returns `DEPLOYMENT_DISABLED` (HTTP 402), so AdMob cannot crawl the record until the Vercel deployment is re-enabled and a public `200 text/plain` response is confirmed.

## Zero-cost AI policy

The production build does not use a paid cloud AI provider. iPhone 15 Pro Max and later use Apple’s on-device Foundation Models only when Apple Intelligence is available. All other devices use the local deterministic edit pipeline.

The dormant `ai-completion` function is intentionally not deployed. Never add an API key to `Info.plist`, an xcconfig that ships in the app, or source control. The previously shared key should be revoked or rotated because it was disclosed outside a secret manager.
