# CutSense market research (as of 2026-11-21)

Method: iTunes Search/Lookup API and RSS review feeds for ratings and recent reviews, apps.apple.com pages for IAP lists, and web search for the rest. Reddit was blocked for the crawler, so there is no Reddit data (UNVERIFIED). Screenshot and onboarding content could not be read: the fetch returns images only, no caption text.

## 0. Headline findings
- **Crowded niche.** I found about 25 silence-remover apps. 22 of them were released in 2026 and every one has under 31 ratings. The largest direct rival, Smooth Talker, has 30 ratings (3.1 stars). No incumbent has traction.
- **Your keyword rank is weak where it matters.** CutSense is #2 for "silence cutter", but it is not in the top 20 for "silence remover", "remove silence from video", "jump cut", "auto cut" or "remove pauses" (US iTunes search). The top slots go to apps whose name is the exact phrase.
- **Nobody monetizes with ads.** Every competitor with a visible model uses a subscription, a lifetime purchase or a one-time unlock. You are the only free+AdMob app I found. That is a real differentiator, but only if people can find you.
- **Instagram "First Draft"** (iPhone, rolled out Aug 2026) auto-trims clips and removes pauses inside the Instagram camera and Reels gallery. It is free and has no export step. This is a structural threat to the single-feature use case. [TechCrunch](https://techcrunch.com/2026/08/25/instagrams-first-draft-feature-aims-to-make-editing-reels-less-tedious/)
- **Competitors converge on a bundle.** Silence removal plus captions, filler words, 9:16 reframe, a review timeline and a teleprompter. CutSense has none of these.

## 1. Direct iOS competitors
Prices are from the apps.apple.com listings. Ratings are US values from the iTunes API.

| App (URL) | Price / IAP | Rating (count) | Key features and notes |
|---|---|---|---|
| [Video Silence Remover: Jumpcut](https://apps.apple.com/us/app/id6737282879) (id6737282879) | Free; weekly $3.99, Premium $4.99, yearly $49.99, lifetime $69.99 | 4.36 (28) | Subtitle "Cut Pauses in Audio & Podcasts". On-device captions, presets, 300% volume boost, batch. #1 for "jump cut". |
| [Smooth Talker](https://apps.apple.com/us/app/id1577655183) (id1577655183) | Free; monthly $9.99, yearly $18.99, lifetime $39.99, plus a separate "Export to Camera Roll" purchase ($18.99/$28.99) | 3.13 (30) | Threshold, min-length and padding controls, preview, audio export. Last update June 2024. |
| [Auto Cut: AI Video Editor](https://apps.apple.com/us/app/id6745358014) (id6745358014, formerly "Remove Silence: Video Trimmer") | Monthly $8.99, yearly $49.99. Free 1080p export carries a watermark. | 4.22 (9) | Cut Less/Balanced/Cut More, waveform review, captions, zoom, motionless-moment removal. |
| [Silence Remover - Auto Cut](https://apps.apple.com/us/app/id6761766657) (id6761766657, Mobixoft) | Weekly $1.99, annual $14.99, lifetime $24.99. Free tier capped at 2 minutes. | 5.0 (1) | -60 to -20 dB threshold, 3 modes, crossfades, 4K export. |
| [AutoCut: Silence Remover](https://apps.apple.com/us/app/id6760603574) (id6760603574) | Weekly $1.99, monthly $4.99, yearly $29.99; ads and watermark removed by Premium | 5.0 (7) | Waveform stats, before/after view. |
| [Silence Remover](https://apps.apple.com/us/app/id6762064214) (id6762064214) | Free, 720p; $4.99 one-time for 1080p/4K (reportedly now included for new users too, unclear) | 4.0 (4) | Auto/Adjust mode, live preview, stats panel. |
| [Pauseless](https://apps.apple.com/us/app/id6795894692) (id6795894692) | First export free, then $5.99 one-time | none yet | Per-gap restore, protects quiet consonants, HDR preserved, no watermark, no network. |
| [JumpCut AI](https://apps.apple.com/us/app/id6761694407) (id6761694407) | $1.99 weekly; saving or sharing needs Pro | 4.5 (2) | Silence cutting plus auto-subtitles, 9:16, teleprompter, stabilization. |
| [HushCut: Silence & Filler](https://apps.apple.com/us/app/id6792566913) (id6792566913) | Monthly $5.99, yearly $29.99. Free: videos up to 10 minutes, one export per 7 days. | 5.0 (1) | "um/uh" filler cleanup, 3 styles. |
| [Cut AI](https://apps.apple.com/us/app/id6819031729) (id6819031729) | Weekly $7.99, yearly $39.99; watermark on free | 4.69 (13) | Silences, fillers and repeated takes; 4 aspect ratios; direct share to TikTok, Reels and Shorts. One reviewer calls it an imitation of CutAI. |
| [Chopper](https://apps.apple.com/us/app/id1560947520) (id1560947520) | $1.99 paid upfront | 4.0 (23) | Voice-detection AI, on-device. |
| 5cut (id6758529319) | Monthly $1.99, lifetime $6.99; free is 10 exports per month with a watermark (web search snippet only, UNVERIFIED on the page) | not checked | Subscription with a free watermarked tier. |

Other tiny entrants with 0 to 2 ratings: QuellCut ($3.99 per the search snippet, but the API now shows free), ClipFlow, PauseSnip, MediaSilenceCutter, HushCut (Shota Yamada), NoRetakes AI (Nov 2026), Hooky, Hushly, SilenceCut, QuietCut.

**What 1-3 star reviewers complain about** (RSS reviews, apps.apple.com):
- **Over-cutting:** a Jumpcut reviewer reports a 3:48 video cut to 10 seconds on "Balanced", and an 8-minute video cut to 45 seconds. This is directly relevant to your Balanced/Tight/Hardcore presets.
- **Quality loss:** "quality of the edited video is horrible, no option to change resolution" (Jumpcut). "Video quality downgraded when exported" (Smooth Talker).
- **Reliability:** Smooth Talker has crashes, "did not export to photos" and a dead support link. Chopper reviewers say it "rarely works" and leaves seconds of silence after an update.
- **Paywall resentment:** "should be a one-time purchase not a recurring subscription" and "used to be free before update, now watermark" (Auto Cut). CapCut gets "pay to export" complaints.
- **Cutting-style complaint:** one reviewer says silence-cut videos make YouTube painful to watch.
- **Captions (Captions app, 1-3 star):** subscription required to export, which was not disclosed upfront, plus forced ads and lost work.
- **CutAI (2.2K ratings):** reviewers report high storage use and low-quality exports.

**Screenshots and onboarding:** not readable via fetch (images only). UNVERIFIED. The listing text shows a consistent pattern: "pick video, choose strength, preview, export". Pauseless sells "instant preview, one purchase". Several lead with stats ("time saved").

**Adjacent big apps**
- **CapCut** ([id1500855883](https://apps.apple.com/us/app/id1500855883)): 4.61 (1.13M). IAP is $7.99 or $9.99 monthly, $19.99 Pro monthly, $89.99 yearly. The listing does not mention silence removal. Sources conflict on whether it is Pro-only or mobile-available. [BlitzCut](https://blitzcutai.com/blog/capcut-remove-silence) says it is unverified. UNVERIFIED.
- **Captions** ([id1541407007](https://apps.apple.com/us/app/id1541407007)): 4.74 (39K). Weekly $5.99, monthly $9.99, yearly $64.99, Max $24.99. The listing mentions no silence removal.
- **VEED Lite** (id1634439688): 4.84 (20K). Only the web tool was documented; it "removes only complete silence", per [BlitzCut](https://blitzcutai.com/blog/best-silence-remover-apps-2026).
- **Edits by Instagram** ([id6738967378](https://apps.apple.com/us/app/id6738967378)): 4.79 (107K), free, 4K export with no watermark, auto-captions. A cut-silences preset is reported by secondary sources only. UNVERIFIED.
- **Descript:** from $16/month annual, with silence removal capped at 20 uses on the Hobbyist plan ([Descript](https://www.descript.com/blog/article/best-silence-remover-tools)). Its iPhone app was not verified, since search returned look-alikes.
- **CutAI** ([id6775648274](https://apps.apple.com/us/app/id6775648274)): 4.88 (2.2K). Subscription only: $19.99, $49.99 or $89.99 per month. Ranked #143 in Photo & Video; this is the one directly adjacent app with real momentum.
- **Desktop:** Recut $99 one-time per [Kapwing](https://www.kapwing.com/resources/the-best-way-to-remove-silences-from-videos-automatically/), but $149 or $19/month per BlitzCut, so sources disagree. TimeBolt is $17/month, $97/year or $347 once, plus extra for filler cleanup. Gling's paid plans start around $15-20/month, with a 1-hour free tier and watermark (aggregators disagree). AutoCut for Premiere is $9.90/month or $79/year.
- **Not verified:** Submagic and Vmaker iOS apps. Search returned only look-alikes.

## 2. Top 20 US/EN keyword phrases
Ordered by how the field targets them:
1. silence remover
2. remove silence from video
3. jump cut / jump cut video
4. auto jump cut
5. remove pauses
6. silence cutter
7. dead air remover
8. auto cut / auto cut video
9. cut silence
10. video silence remover
11. remove dead air
12. cut pauses
13. silence trimmer
14. remove silence audio / podcast silence remover
15. filler word remover (um/uh)
16. auto captions + silence
17. talking head video editor
18. AI video editor
19. jumpcut for TikTok / Reels / Shorts
20. UGC ad editor

Competitor title and subtitle wording seen: "Cut Pauses in Audio & Podcasts", "Remove Pauses in Video & Audio", "Auto Cut Pauses & Dead Air", "Auto cut pauses from videos", "Captions, Remove Silence, Zoom", "Instant preview, one purchase".

**Localized terms** (CutSense already has a Spanish title: "CutSense: Eliminar Silencios", ranking #9 for "eliminar silencios video" in Spain):
- **Spanish:** quitar silencios, eliminar silencios, cortar pausas.
- **Portuguese:** remover silêncio, cortar silêncio.
- **Turkish:** sessizlik silme, sessizlik kaldırıcı, jump cut. Competition is thin: only 5 results for "sessizlik silme video" and none for "sessizlik kaldırıcı".

## 3. Monetization norms
- **Dominant model:** freemium with a subscription (weekly, monthly or yearly), with the free tier made unattractive by a watermark, a length cap or an export cap.
  - Weekly prices run $1.99 to $7.99, with $3.99 on Jumpcut.
  - Yearly runs $14.99 to $49.99.
  - Lifetime runs $6.99 to $69.99, typically $24.99 to $39.99.
- **Growing counter-trend:** one-time unlocks ($4.99 to $5.99) and "no subscription" as a selling point (Pauseless, Silence Remover, Chopper at $1.99).
- **Locked behind the paywall:** export itself, watermark removal, resolution above 720p or 1080p, length beyond 2 to 10 minutes, captions, filler removal, and batch.
- **Ads:** no direct competitor uses them. The only ad mention is AutoCut ("contains advertising"). Free+ads means you compete on price, but at about 16 downloads there is almost no ad revenue. UNVERIFIED which approach would earn more.

## 4. Feature gaps users ask for
Evidence is thin: reviews are few and Reddit was inaccessible.
- **Preview and manual control of cuts.** Present in most rivals (restore-a-cut timelines, per-gap restore). Over-cutting complaints make this the top trust issue.
- **Quality-preserving export.** Original resolution with no downgrade. Pauseless markets HDR and original resolution.
- **Reliable export and save to Photos.**
- **Auto captions.** Bundled by Jumpcut, JumpCut AI, Auto Cut, Cut AI and Captions.
- **Filler word removal** ("um/uh"). HushCut, Cut AI, AutoCut and ClipFlow.
- **9:16 reframe and platform export.** Cut AI shares directly to TikTok, Reels and Shorts.
- **Teleprompter.** Requested by a CutAI reviewer and shipped by JumpCut AI.
- **Batch and multi-clip import.**
- **Noise removal.** Captions has Denoise and Edits has Enhance.
- **No watermark or subscription.** This is the loudest pricing sentiment in reviews.

CutSense has only three presets, no preview and no manual adjustment. That is the gap to close first, because over-cutting is the most-repeated complaint.

## 5. Growth channels with $0 budget
- **ASO (highest leverage).** Rename the title and subtitle around "Silence Remover". "Silence Cutter" currently ranks #2 only because few apps use it. The thin Turkish, Portuguese and Spanish results are the easiest rankings to win.
- **TikTok and Reels demos.** Before/after videos with a hook and a visible payoff.
  - Dumbphone reportedly got 20K downloads and about $9K MRR in 78 days with about 2.4M TikTok views ([Shortimize](https://shortimize.com/blog/20k-downloads-and-9k-mrr-in-78-days-how-this-indie-app-turned-minimalism-into-millions-of-views)).
  - Another founder reports TikTok converting best among channels ([Indie Hackers](https://www.indiehackers.com/post/3-000-app-users-in-20-days-with-no-paid-ads-52c4a2f870)).
  - Counter-example: one Product Hunt poster got 621 views from 6 TikToks ([Product Hunt](https://www.producthunt.com/p/general/what-actually-moves-distribution-in-the-first-weeks-after-shipping-two-week-observation)).
  - All of these are self-reports and UNVERIFIED.
- **Product Hunt.** The one silence app I checked, ClipFlow, got 4 points and no reviews about 5 months after launch ([Product Hunt](https://www.producthunt.com/products/clipflow-ai-silence-remover/reviews)). Expect little traffic from it.
- **Reddit.** r/NewTubers and r/videoediting are the obvious subs, but there is no data on what has worked there (UNVERIFIED). Do not self-promote without checking each sub's rules.
- **Reviews.** All competitors have under 31 ratings, so each added rating is a visible ranking and conversion signal. An in-app review prompt after a successful export is the cheapest lever.

**Not checked:** Spanish and Portuguese keyword volumes, which are unknown without a paid tool. Screenshot and onboarding design. Real-device behavior of the competitors. Whether CapCut and Edits actually offer mobile silence removal.