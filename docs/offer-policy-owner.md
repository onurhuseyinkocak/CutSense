# Offer policy (owner decision, 1.1.0)

Overrides `docs/onboarding-offer-1.1.0.md` §3 wherever the two differ.

## Products (one Pro entitlement)

| SKU | Price | Where |
|---|---|---|
| `com.cutsense.app.pro.lifetime` | $7.99 | PaywallView, everywhere else |
| `com.cutsense.app.pro.lifetime.welcome` | $5.99 (-25%) | Onboarding offer step only |
| `com.cutsense.app.pro.lifetime.offer` | $3.99 (-50%) | Flash offer only |

## Flow

1. Onboarding has 3 pages. On page 3, "Start cutting" opens `OfferPanel(kind: .welcome)` when `ProStore.shared.welcomePrices != nil && !isPro`. Otherwise onboarding finishes. The welcome step shows a "Welcome offer" overline, no countdown, the regular price struck through, Buy, a "Not now" button, X, Restore, Terms and Privacy. Both Not now and X finish onboarding.
2. Skip on pages 1–3 finishes onboarding straight away, with no offer.
3. Every exit calls `OfferCenter.shared.noteOnboardingFinished(purchased: ProStore.shared.isPro)` and then `onFinish()`. When the user did not buy, the flash is scheduled to start at finish + 600 s and end at start + 900 s. The schedule is persisted in UserDefaults as absolute times and is armed once per install. It never re-arms.
4. During the window, `OfferCenter.shared.active` is `Active(kind: .flash, endsAt:)`. While the flash is still pending, `active` is nil and `pendingStart` holds the start time. Pro, the end time, or a clock rollback of more than 120 s ends the flash for good.
5. `OfferCenter` wakes itself at the start and end boundaries, so `active` flips mid-session without a scene change.

## API changes

- `OfferCenter`:
  - New: `noteOnboardingFinished(purchased:)`, `pendingStart`, `flashDelaySeconds` (600), `flashDelay()`.
  - Removed: `welcomeSeconds`, `flashGap`, `flashMinSaves`.
  - `noteSave()` now only counts saves (`stat_saves`).
  - `takeAutoPresent()` returns true exactly once per install while the flash is active and prices are loaded. It burns the flag, so call it only when the panel can actually open.
  - Keys: `offer_flash_armed`, `offer_flash_starts_at`, `offer_flash_ends_at`, `offer_auto_shown`, `offer_clock_high`, `stat_saves`. The old keys `offer_kind`, `offer_ends_at`, `offer_welcome_done`, `offer_flash_done` and `offer_last_ended_at` are no longer read.
- `ProStore`: new `welcomeID`, `welcomeProduct`, `welcomePrices` and `purchaseWelcome()`. `loadProduct()` loads all three SKUs in one call, and `refresh()` treats all three as owned.
- `OfferPanel.endsAt` is now `Date?`; pass nil for `.welcome`.
- DEBUG env:
  - `CUTSENSE_FAKE_PRICES=1` returns welcome $5.99/$7.99 -25% and flash $3.99/$7.99 -50%.
  - `CUTSENSE_FORCE_FLASH_OFFER=1` starts the flash now.
  - `CUTSENSE_FLASH_DELAY_SECONDS=N` overrides the 600 s delay.
  - `CUTSENSE_OFFER_SECONDS=N` overrides the 900 s duration.
  - `CUTSENSE_RESET_ONBOARDING=1` also clears every offer key.
  - `CUTSENSE_FORCE_WELCOME_OFFER` is removed.

## Integration snippets (QA-owned files)

### QuickSilenceApp.swift

`OnboardingView { ... }` needs no change. The view calls OfferCenter itself.

At `.onChange(of: scenePhase)`, add the welcome SKU to the reload guard:

```swift
guard ProStore.shared.product == nil || ProStore.shared.offerProduct == nil
        || ProStore.shared.welcomeProduct == nil else { return }
```

Keep the existing `OfferCenter.shared.refresh()` calls in `.task` and on `.active`.

### QuickSilenceView.swift

Replace the old first-save trigger (`onChange(of: phaseKey)` calling `takeAutoPresent`) with one check that runs on flash activation, on foreground, and when the screen goes idle. `initial: true` covers a cold launch into a window that is already active.

```swift
@Environment(\.scenePhase) private var scenePhase

private func autoPresentFlashIfPossible() {
    guard scenePhase == .active, isScreenVisible, offers.active?.kind == .flash,
          !showsPaywall, !showsFineTune, exportTask == nil,
          !AdMobService.hasPresentedContent else { return }
    if offers.takeAutoPresent() { showsPaywall = true }   // ProSheet shows OfferPanel(.flash) while active
}

.onChange(of: offers.active, initial: true) { _, _ in autoPresentFlashIfPossible() }
.onChange(of: scenePhase) { _, phase in if phase == .active { autoPresentFlashIfPossible() } }
.onChange(of: phaseKey) { _, key in if key == 0 { autoPresentFlashIfPossible() } }   // replaces the old line 153
```

Also restrict the check to the home and review screens. If other phases count as presented, add them to the guard, for example `isIdle || isReview`. If the screen is busy when the flash starts, only the pill shows, and the one auto-present happens at the next foreground or idle check while the window is still open.

`OfferCenter.shared.noteSave()` in `startSave()` can stay; it only counts.

The pill and ProSheet code are unchanged. `offers.active == nil` still hides the regular Pro capsule only during the flash window.

### Translations.swift (keys are the English strings)

New:

| EN | TR (call site) | es | pt | de | fr | it | ja | ko |
|---|---|---|---|---|---|---|---|---|
| `Not now` | Şimdi değil | Ahora no | Agora não | Nicht jetzt | Pas maintenant | Non ora | 今はしない | 나중에 |

Dead (no longer used by any view; safe to delete): `Welcome price until %@`.

Still used: `Welcome offer`, `15-minute offer`, `Regular price`, `Unlock for %@`, `Ends at %@`, `After that, the regular price applies.`

### UI tests (Tests/UI/OfferFlowUITests.swift)

- `testWelcomeOfferAfterFirstSaveOpensOnce` is obsolete. The welcome offer is no longer triggered by a save.
- The onboarding tests now land on the offer step after "Start cutting" when the welcome SKU loads. Tap `offerNotNow`, or the X labelled "Close", to reach the app.
- For the flash, run with `CUTSENSE_FLASH_DELAY_SECONDS=5` and `CUTSENSE_OFFER_SECONDS=60`.

## App Review honesty checklist

- Timers are real absolute times, and the flash runs once per install.
- The regular price is shown struck through on both offer screens.
- Restore, Terms and Privacy appear on every purchase screen.
- Pro owners never see an offer: the welcome step requires `!isPro`, and Pro ends the flash.
- The welcome offer makes no time claim.
