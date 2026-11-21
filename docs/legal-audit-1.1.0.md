# CutSense legal surface audit — 1.1.0 (2026-11-22)

Not legal advice. Engineering audit of code, the live site, and App Store Connect, done with what the tools could see. Items marked UNVERIFIED need a human check.

## 1. Live site before the change

| URL | Status | Content-Type | Notes |
|---|---|---|---|
| / | 200 | text/html | Static export (Cloudflare Worker `cutsense-site`). Meta description said "No account, no onboarding, no paywall"; home fact chip said "No onboarding wall" |
| /privacy | 200 | text/html | Real server-rendered text (10 h2 sections), EN by default, TR via client toggle. Effective date "June 29, 2026" |
| /terms | 200 | text/html | Same. Effective date "June 29, 2026" |
| /support | 200 | text/html | Same |
| /app-ads.txt | 200 | text/plain; charset=utf-8 | `google.com, pub-6644397387275334, DIRECT, f08c47fec0942fa0` — correct |
| /robots.txt | 200 | text/plain | Allows all, AdSense/ads.txt crawlers allowed, sitemap linked |
| /sitemap.xml | 200 | application/xml | lastmod 2026-06-29 on every URL |

Contact address used across the site: `info@vibecodingturkey.com` (kept; no new address invented).

## 2. Ground truth from code (release/1.1.0, app target per `ios/project.yml`)

- Ads: Google Mobile Ads SDK (SPM `from: 13.7.0`): adaptive banner, native ad during processing, rewarded interstitial at review with a 3 s skippable intro; a reward gives 24 h without banner/native ads, stacking to 72 h (`AdFreePass`, key `ad_free_until`).
- Consent: UMP `requestConsentInfoUpdate` + `loadAndPresentIfRequired` at start; SDK starts only when `canRequestAds`. Privacy options form in Settings > Ad privacy > Manage privacy choices (and a toolbar button), shown only when UMP says it's required **and** ads are on (not Pro).
- `setPublisherFirstPartyIDEnabled(false)`. No ATT: no `NSUserTrackingUsageDescription` in `project.yml` or `Info.plist`, no `ATTrackingManager`/`advertisingIdentifier` in the sources.
- Pro owners: `AdMobService.isEnabled` is false when `pro_unlocked` is set, so the SDK isn't started on launch.
- StoreKit 2, two NonConsumables: `com.cutsense.app.pro.lifetime` (7.99) and `com.cutsense.app.pro.lifetime.offer` (3.99), `familyShareable: false` in the local .storekit file. Entitlement comes from `Transaction.currentEntitlements`; a refund or revocation removes it. Restore = `AppStore.sync()` (Settings, Paywall, Offer).
- Offers (`OfferCenter.swift`, untracked file): welcome offer of 24 h starting at the first save; one flash offer of 15 min, at least 7 days after the welcome ends and at least 3 saves. Each fires once per install (UserDefaults), with clock-rollback protection.
- Media: system `PhotosPicker` (no full-library read permission requested in code); save uses `PHPhotoLibrary` `.addOnly`. Work copies go in Caches/CutSense/imports and tmp/cutsense-*; they're deleted after use and in `WorkFiles.sweepAtLaunch()`, and Settings > Storage > Clear deletes them too.
- No backend, account, or analytics: grep for URLSession/URLRequest/Firebase/Analytics/Crashlytics/Sentry/Mixpanel/Amplitude/TelemetryDeck in the app target found nothing. The only URLs are the site links and the iOS Settings URL.
- UserDefaults keys: `app_language`, `pro_unlocked`, `ad_free_until`, `offer_*` (kind, ends_at, welcome_done, flash_done, auto_shown, last_ended_at, clock_high), `stat_saves`, `onboarding_done_v1`, `review_prompt_version`.
- 9 UI languages (tr, en, es, pt, de, fr, it, ja, ko). The site has EN + TR only.

## 3. Findings: site vs truth vs requirements (before)

| # | Severity | Finding |
|---|---|---|
| F1 | High | Privacy: "does not require ... subscription, or paywall" and Terms: "no account system, subscription, or paywall" are untrue: there's a Pro paywall plus offer sheets (1.1.0, and Pro is already advertised on the landing page). |
| F2 | High | Neither page mentioned in-app purchases, Apple as payment processor, refunds, restore, or limited-time offer terms (regular price, duration, one per install, not a subscription). |
| F3 | High | Privacy had no retention/deletion policy, no rights section, no consent-withdrawal path, no legal bases (GDPR), no US state notice (sale/share/opt-out), no "equal protection" statement for third parties (Apple 5.1.1(i)), and no data-controller identification. |
| F4 | Med | "asks for photo library access to import" is inaccurate: import uses the system picker. Add-only for save is correct. |
| F5 | Med | No mention of the rewarded ad / ad-free pass, or that Pro owners don't load the ad SDK. |
| F6 | Med | Terms had no Apple standard EULA reference, and no carve-out for mandatory consumer-law rights in the liability clause. |
| F7 | Low | Effective date was hardcoded English; sitemap lastmod was stale. |
| F8 | Low | Home meta "no onboarding, no paywall" and the chip "No onboarding wall" go stale with 1.1.0 onboarding + paywall. |
| OK | — | The policy did **not** claim "no data collected"; it already disclosed Google's processing (IP, device IDs, interactions, coarse location, crash/perf). Kept and expanded. |

## 4. Changes made (web/ only, deployed)

- `web/app/privacy/privacy-content.tsx`: full rewrite, EN+TR, effective date November 22, 2026. Sections: Summary, Who we are, Videos stay on device (picker, on-device processing, temp-file deletion, add-only), Settings stored on device (key list in plain words), Data we collect (none via app; support email use and deletion), Advertising: Google AdMob (data types from Google's disclosure, purposes, Google as independent processor, policy links, equal-protection statement, Pro = no SDK), Tracking and IDFA, EEA/UK/CH consent and legal bases + withdrawal path, US state privacy rights (sale/share, categories, opt-out routes, non-discrimination), Purchases (Apple processes, no card data, refunds via Apple), Retention and deletion, Your rights (30-day reply), International transfers and security, Children (under 13), Changes, Contact. Sections now support multiple paragraphs.
- `web/app/terms/terms-content.tsx`: rewrite, EN+TR. Adds Apple Standard EULA reference and precedence, Free version and ads (rewarded = 24 h pause, 72 h cap), CutSense Pro (non-consumable, no renewal, US$7.99 with local price shown by the App Store, restore), Limited-time offers (US$3.99 vs US$7.99 regular, 24 h welcome after first save, single 15-min offer after 7 days and 3 saves, once per installation, regular price after, no double charge, no cash value, may change without affecting past purchases), Payment and refunds (Apple, reportaproblem.apple.com, refund turns Pro off), a liability cap plus consumer-law carve-out, and conduct now covers purchase-system bypass.
- `web/app/support/support-content.tsx`: ad privacy item now names the exact path (Settings > Ad privacy > Manage privacy choices); new items "Restoring Pro" and "Refunds".
- `web/app/layout.tsx`: meta description is now "No account, no subscription, optional one-time Pro upgrade."
- `web/app/page.tsx`: chip "No onboarding wall" replaced with "Optional one-time Pro" (TR "İsteğe bağlı tek seferlik Pro").
- `web/app/sitemap.ts`: lastModified is now 2026-11-22.
- Second pass, after checking ASC (see §7): Pro and price text is now conditional ("Where available in the app"), because neither IAP is approved yet. Settings paths are marked "(CutSense 1.1 and later)". I couldn't confirm that the 1.0.3 build has those screens: tag `v1.0.3` is a different (UGC) tree, so the diff wasn't possible.

## 5. Verification (live evidence, after deploy)

- Gates: `pnpm lint` (no issues), `pnpm typecheck` (clean), `pnpm test` (smoke passed), `STATIC_EXPORT=1 pnpm build` (13 static routes).
- Before deploying, `out/app-ads.txt` and `out/robots.txt` were byte-identical to live (diff empty).
- `npx wrangler deploy` → worker `cutsense-site`, custom domain cutsense.onarika.net. First deploy Version ID `c90b7303-a7d6-4211-a848-5a17cd285e36`; final (conditional Pro wording) `ee8de3a5-811f-4760-b9e5-84dc8cff80f7`.
- TR text is live: "22 Kasım 2026" appears in the /privacy JS chunk `/_next/static/chunks/3n_8ylsfi0--4.js` (the TR version renders client-side through the language toggle; SSR HTML is EN).
- Re-curl: `/`, `/privacy`, `/terms`, `/support` 200 text/html; `/app-ads.txt` 200 text/plain with the exact line `google.com, pub-6644397387275334, DIRECT, f08c47fec0942fa0`; `/robots.txt` 200; `/sitemap.xml` 200 with lastmod 2026-11-22. The live HTML contains "November 22, 2026", "Advertising: Google AdMob", "US state privacy rights", "Manage privacy choices", "Limited-time offers", "US$3.99", "US$7.99", "reportaproblem.apple.com", "Restoring Pro", "Refunds", and "Optional one-time Pro".
- `web/node_modules`, `.next`, `out` deleted.
- UNVERIFIED: visual check of the TR toggle and the mobile layout. No browser was opened (per the user's no-browser rule). The layout and CSS classes are unchanged; only text and multi-paragraph rendering were added.

## 6. App Store privacy label ("nutrition label")

**How it was read:** `asc web privacy pull` failed with "Session expired. --apple-id is required" (an unofficial web-session API that needs an Apple ID login + 2FA, which isn't available). BLOCKED for the CLI path. I read the label from the public App Store page instead (`apps.apple.com/us/app/id6770024868`, page title "CutSense: Silence Cutter App", privacy link → cutsense.onarika.net/privacy).

**Current (live, 1.0.3 listing):**

- Data Used to Track You: none
- Data Linked to You — App Functionality: Purchases › Purchase History; Contact Info › Email Address; User Content › Other User Content; Identifiers › User ID
- Data Not Linked to You:
  - Third-Party Advertising: Coarse Location, Device ID, Advertising Data, Crash Data, Performance Data
  - Analytics: Coarse Location, Product Interaction, Advertising Data, Crash Data, Performance Data
  - App Functionality: Product Interaction

**Google's disclosure** (developers.google.com/admob/ios/privacy/data-disclosure, last updated 2026-11-18), quoted verbatim: "The Google Mobile Ads SDK may collect certain data like IP address, crash logs, performance data, device ID, advertising data, and user interactions to improve performance." It also says: "Device ID, such as the device's advertising identifier or other app- or developer-bounded device identifiers, which may be used for the purpose of third-party advertising and analytics"; "Coarse location, including location derived from IP address or collected from the Approximate Location Services API, if allowed by users"; and "Other user product interactions like app launch taps, and interaction information, like video views, may be used to improve advertising performance." The page doesn't say whether data is linked or used for tracking.

**Required / proposed (NOT applied — lead decides):**

1. **Remove the whole "Data Linked to You / App Functionality" block** (Purchase History, Email Address, Other User Content, User ID). The app target has no account, backend, or user-content upload. Purchase history is held by Apple (UNVERIFIED citation: Apple's App Privacy Details guidance says data collected only by Apple through StoreKit need not be declared; confirm on developer.apple.com/app-store/app-privacy-details). These look like leftovers from the old UGC/account build. Over-declaring is wrong, though not a rejection risk.
2. Keep "Data Not Linked to You":
   - Third-Party Advertising: Coarse Location, Device ID, Product Interaction (add), Advertising Data, Crash Data, Performance Data
   - Analytics: Coarse Location, Device ID (add), Product Interaction, Advertising Data, Crash Data, Performance Data
   - App Functionality: Product Interaction → can be dropped (no first-party functionality uses it). Keeping it is harmless.
3. Tracking: keep "No". There's no ATT/IDFA, and `setPublisherFirstPartyIDEnabled(false)`. UNVERIFIED: Google labels its own "performance data" "user-associated". A conservative reading puts Performance Data under "Linked to You (Third-Party Advertising/Analytics)". Lead's call.
4. Apply path: App Store Connect web UI > App Privacy (or `asc web privacy plan/apply/publish` after `asc web auth login --apple-id …` with 2FA). The label is app-level, so it changes the live listing as soon as it's published.

## 7. Other App Store Connect findings (read via official API, not changed)

- **Custom EULA is stale (High).** `asc eula view --app 6770024868` returns a custom EULA: "…Terms of Service at https://cutsense.vercel.app/terms and Privacy Policy at https://cutsense.vercel.app/privacy. CutSense is a free, ad-supported iPhone app with no account, no subscription, **no in-app purchase, and no paywall** in this submitted build…". This is false for 1.1.0 (and for any build that sells Pro), and `cutsense.vercel.app` didn't answer (curl 000). Proposed: delete the custom EULA so Apple's Standard EULA applies (`asc eula delete --id ca3de9e2-c8cd-4895-9c1a-bb9b5224ec74 --confirm`), or replace the text with: "CutSense is licensed under Apple's Standard Licensed Application End User License Agreement, supplemented by the CutSense Terms of Service at https://cutsense.onarika.net/terms. Privacy Policy: https://cutsense.onarika.net/privacy." Not applied.
- Privacy Policy URL in all 13 app-info localizations (both READY_FOR_DISTRIBUTION and the WAITING_FOR_REVIEW app info) = `https://cutsense.onarika.net/privacy`. OK. `privacyChoicesUrl` is empty (optional; could point to /privacy).
- Version state: 1.0.4 is WAITING_FOR_REVIEW and 1.0.3 is READY_FOR_SALE.
- **IAPs (VERIFIED via `asc iap list` / `asc iap pricing summary`):** `com.cutsense.app.pro.lifetime` NON_CONSUMABLE, state **READY_TO_SUBMIT**, US price 7.99 USD. `com.cutsense.app.pro.lifetime.offer` NON_CONSUMABLE, state **MISSING_METADATA**, US price 3.99 USD. Neither is on sale yet (the public page has no IAP section). The offer SKU needs metadata (localization/review screenshot) before it can go into review with 1.1.0. The landing pages (`landing-data.ts`, all 4 locales) already describe Pro as available. That's marketing copy, left as is; it becomes true once 1.1.0 ships.
- Ad-free pass: `NativeAdCard` and `QuickSilenceView` both check `!AdFreePass.isActive`, so banner **and** native ads pause (matches the Terms). The in-app copy says only "banner ads", which understates it. Harmless.

## 8. PrivacyInfo.xcprivacy (report only, not edited)

- Declares FileTimestamp C617.1 and UserDefaults CA92.1. Tracking false, no domains, empty collected-data types.
- **Missing DiskSpace (Med, ITMS-91053 risk):** `Storage/WorkFiles.swift:45` reads `volumeAvailableCapacityForImportantUsageKey`, which is in Apple's DiskSpace required-reason list. Add `NSPrivacyAccessedAPICategoryDiskSpace` with reason `E174.1` (check there's enough space before writing files). UNVERIFIED against Apple's current reason list wording.
- Empty `NSPrivacyCollectedDataTypes` can be defended, because the GoogleMobileAds/UMP xcframeworks ship their own manifests and Xcode aggregates them into the privacy report. The developer collects nothing itself. Recommended: generate the Xcode Privacy Report from the 1.1.0 archive and check that it matches the label in section 6.

## 9. Remaining risks

- UNVERIFIED: whether a US-states (CCPA/IAB GPP) message and/or Restricted Data Processing is configured in the AdMob console. The policy words the in-app US option conditionally. If it isn't configured, US users' opt-out routes are Google's My Ad Center or Pro. Recommended: enable the US states message in AdMob > Privacy & messaging.
- UNVERIFIED: whether Family Sharing is off for the ASC products. The site makes no claim either way.
- UNVERIFIED: whether a GDPR (EEA/UK/CH) message is published in AdMob > Privacy & messaging. The policy says the UMP form shows in those regions, which only happens if the message is configured.
- New commitments now live that weren't in the brief, for the lead's sign-off: privacy requests answered within 30 days; liability capped at the amount paid in the last 12 months (with a consumer-law carve-out); US non-discrimination; support emails deleted once resolved unless the law requires keeping them.
- Controller identity: the policy refers to "the independent developer listed as the seller on the App Store". It has no legal name or postal address. Some EU regulators expect a named controller and address. Lead decides whether to add the seller name.
- Pro owners who bought mid-session: the SDK may already be running until the next launch, and the privacy-options row is hidden once Pro is set. Low impact (no ads are requested), noted for iOS owners.
- The privacy-options toolbar button and Settings row only appear when UMP reports `required`. Outside EEA/UK/CH (or without a US message) there's no in-app consent control. This matches the policy text.
- Site language: EN + TR only, while the app has 9 languages. Not required, but non-EN/TR users get the English policy.
- US prices are stated as US prices. Other storefronts use Apple's local tier. If ASC prices change, terms must be updated.
- Not legal advice; a lawyer should review before relying on this for GDPR/CCPA compliance.
