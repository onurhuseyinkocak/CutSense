import StoreKitTest
import XCTest

/// Onboarding, purchase and the welcome offer on a real iPhone with the scheme's local StoreKit config.
/// Each test clears local transactions first, so a leftover test purchase never hides the Pro entry points.
@MainActor
final class OfferFlowUITests: XCTestCase {
    private var app: XCUIApplication!
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    private var session: SKTestSession!

    override func setUp() async throws {
        continueAfterFailure = false
        session = try SKTestSession(configurationFileNamed: "Products")
        session.disableDialogs = false
        if !keepTransactions { session.clearTransactions() }
        app = XCUIApplication()
        app.launchArguments += ["-app_language", "en", "-AppleLanguages", "(en)"]
        addUIInterruptionMonitor(withDescription: "System alerts") { alert in
            // Never answer an Apple Account sign-in: "OK"/"Tamam" there submits an empty password.
            if alert.label.contains("Apple") { return false }
            for label in ["Allow Full Access", "Allow Access to All Photos", "Allow", "OK", "Tam Erişime İzin Ver", "Tüm Fotoğraflara Erişim İzni Ver", "İzin Ver", "Tamam", "Not Now"] where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            return false
        }
    }

    override func tearDown() async throws {
        if !keepTransactions { session?.clearTransactions() }
    }

    /// TEST_RUNNER_QA_KEEP_TRANSACTIONS=1: the reinstall/restore run must keep the purchase between steps.
    private var keepTransactions: Bool { ProcessInfo.processInfo.environment["QA_KEEP_TRANSACTIONS"] == "1" }

    // MARK: Onboarding

    func testOnboardingContinueToStartAndPersists() throws {
        app.launchEnvironment["CUTSENSE_RESET_ONBOARDING"] = "1"
        app.launch()
        let next = app.buttons["onboardingContinue"]
        XCTAssertTrue(next.waitForExistence(timeout: 15), "Onboarding not shown on a fresh install")
        snapshot("onboarding-1")
        next.tap(); sleep(1); snapshot("onboarding-2")
        next.tap(); next.tap() // double tap on page 2 must not skip past page 3's CTA into a broken state
        // A fast double tap may also hit page 3's CTA and open the welcome offer: valid, not broken.
        XCTAssertTrue(app.buttons["chooseVideoButton"].waitForExistence(timeout: 10) || next.exists || app.buttons["offerNotNow"].exists)
        if next.exists { snapshot("onboarding-3"); next.tap() }
        // Welcome offer step (when the welcome SKU loads): Not now finishes onboarding.
        let notNow = app.buttons["offerNotNow"]
        if notNow.waitForExistence(timeout: 8) {
            snapshot("welcome-offer")
            XCTAssertTrue(app.buttons["Restore Purchases"].exists, "Restore missing on the welcome offer")
            notNow.tap()
        }
        XCTAssertTrue(app.buttons["chooseVideoButton"].waitForExistence(timeout: 10), "Start cutting did not open home")
        app.terminate()
        app.launchEnvironment["CUTSENSE_RESET_ONBOARDING"] = nil
        app.launch()
        XCTAssertTrue(app.buttons["chooseVideoButton"].waitForExistence(timeout: 15), "Onboarding shown again after finishing")
    }

    func testOnboardingSkipAndSwipe() throws {
        app.launchEnvironment["CUTSENSE_RESET_ONBOARDING"] = "1"
        app.launch()
        XCTAssertTrue(app.buttons["onboardingContinue"].waitForExistence(timeout: 15))
        app.swipeLeft()
        sleep(1)
        snapshot("onboarding-swiped")
        let skip = app.buttons["onboardingSkip"]
        skip.tap(); if skip.exists { skip.tap() }
        XCTAssertTrue(app.buttons["chooseVideoButton"].waitForExistence(timeout: 10), "Skip did not open home")
    }

    // MARK: Purchase

    func testPurchaseCancelThenBuyThenRestore() throws {
        app.launchArguments += ["-onboarding_done_v1", "YES"]
        app.launchEnvironment["CUTSENSE_RESET_ONBOARDING"] = "1" // clears offer state; the argument keeps onboarding done
        app.launch()
        let capsule = app.buttons["proCapsule"]
        XCTAssertTrue(capsule.waitForExistence(timeout: 20), "PRO capsule missing with no purchase")
        capsule.tap(); capsule.tap() // second tap while the sheet animates in
        let unlock = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Unlock for'")).firstMatch
        XCTAssertTrue(unlock.waitForExistence(timeout: 15), "Paywall price button missing")
        snapshot("paywall")

        // Restore with nothing bought.
        app.buttons["Restore Purchases"].tap()
        answerStoreKitSignIn()
        let restoredNothing = app.staticTexts["No purchase found to restore."].waitForExistence(timeout: 40)
        snapshot("restore-empty")
        XCTAssertTrue(restoredNothing, "No message for empty restore")

        // Cancel at the system sheet.
        unlock.tap()
        // iOS 26 hosts the StoreKit sheet in the app's own process (Xcode env: identifiers dismiss/footer).
        let cancel = storeKitButton(identifier: "dismiss", labels: ["Cancel", "Vazgeç", "İptal"])
        XCTAssertTrue(cancel.waitForExistence(timeout: 20), "StoreKit sheet did not appear")
        cancel.tap()
        XCTAssertTrue(unlock.waitForExistence(timeout: 10), "Paywall gone after cancelling")
        snapshot("after-cancel")

        // Buy.
        unlock.tap()
        let buy = storeKitButton(identifier: "footer", labels: ["Purchase", "Buy", "Satın Al", "Confirm"])
        XCTAssertTrue(buy.waitForExistence(timeout: 20))
        buy.tap()
        answerStoreKitSignIn()
        for source in [app!, springboard] where source.buttons["OK"].waitForExistence(timeout: 5) { source.buttons["OK"].tap(); break }
        XCTAssertTrue(capsule.waitForNonExistence(timeout: 20), "PRO capsule still visible after purchase")
        snapshot("after-purchase")

        // Restore with the purchase.
        app.buttons["settingsButton"].tap()
        let restore = app.buttons["Restore Purchases"]
        XCTAssertTrue(restore.waitForExistence(timeout: 10))
        restore.tap()
        answerStoreKitSignIn()
        sleep(3)
        snapshot("restored")
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Unlock'")).firstMatch.exists, "Unlock offered to an owner")
    }

    // MARK: Flash offer (10 min after onboarding; shortened here)

    func testFlashOfferStartsAfterOnboardingAndAutoOpensOnce() throws {
        app.launchEnvironment["CUTSENSE_RESET_ONBOARDING"] = "1"
        app.launchEnvironment["CUTSENSE_FLASH_DELAY_SECONDS"] = "8"
        app.launchEnvironment["CUTSENSE_OFFER_SECONDS"] = "300"
        app.launch()
        let skip = app.buttons["onboardingSkip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 15))
        skip.tap()
        XCTAssertTrue(app.buttons["chooseVideoButton"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["offerPill"].exists, "Pill before the flash starts")
        let buy = app.buttons["offerBuyButton"]
        XCTAssertTrue(buy.waitForExistence(timeout: 30), "Flash did not auto-open once it started")
        snapshot("flash-auto")
        app.buttons["Close"].tap()
        let pill = app.buttons["offerPill"]
        XCTAssertTrue(pill.waitForExistence(timeout: 5), "Pill missing during the flash")
        XCTAssertFalse(app.buttons["proCapsule"].exists, "PRO capsule shown during the flash")
        snapshot("flash-pill")
        app.terminate()
        app.launchEnvironment = ["CUTSENSE_OFFER_SECONDS": "300"]
        app.launchArguments += ["-onboarding_done_v1", "YES"]
        app.launch()
        var pillBack = pill.waitForExistence(timeout: 15)
        snapshot("flash-relaunch")
        if !pillBack {
            // Diagnose: late StoreKit load vs. never (scenePhase .active retries a failed load).
            pillBack = pill.waitForExistence(timeout: 45)
            snapshot("flash-relaunch-60s")
            if !pillBack {
                XCUIDevice.shared.press(.home); sleep(2); app.activate()
                pillBack = pill.waitForExistence(timeout: 15)
                snapshot("flash-relaunch-after-foreground")
                XCTFail("Pill missing 60 s after relaunch; after foreground: \(pillBack)")
            }
        }
        XCTAssertTrue(pillBack, "Pill lost after relaunch")
        sleep(2)
        XCTAssertFalse(buy.exists, "Flash opened automatically a second time")
    }

    /// Bug-hunt #9: the flash starts while the app is closed; a cold launch auto-opens it once prices load.
    func testFlashAutoOpensOnColdStart() throws {
        app.launchEnvironment["CUTSENSE_RESET_ONBOARDING"] = "1"
        app.launchEnvironment["CUTSENSE_FLASH_DELAY_SECONDS"] = "10"
        app.launchEnvironment["CUTSENSE_OFFER_SECONDS"] = "120"
        app.launch()
        let skip = app.buttons["onboardingSkip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 15))
        skip.tap()
        XCTAssertTrue(app.buttons["chooseVideoButton"].waitForExistence(timeout: 10))
        app.terminate()
        sleep(14)
        app.launchEnvironment = ["CUTSENSE_OFFER_SECONDS": "120"]
        app.launchArguments += ["-onboarding_done_v1", "YES"]
        app.launch()
        XCTAssertTrue(app.buttons["offerBuyButton"].waitForExistence(timeout: 20), "Flash did not auto-open on a cold start")
        snapshot("flash-cold-start")
    }

    func testFlashExpiryRestoresRegularEntry() throws {
        app.launchArguments += ["-onboarding_done_v1", "YES"]
        app.launchEnvironment["CUTSENSE_RESET_ONBOARDING"] = "1"
        app.launchEnvironment["CUTSENSE_FORCE_FLASH_OFFER"] = "1"
        app.launchEnvironment["CUTSENSE_OFFER_SECONDS"] = "25"
        app.launch()
        let pill = app.buttons["offerPill"]
        XCTAssertTrue(pill.waitForExistence(timeout: 15), "Pill missing for a forced flash")
        let buy = app.buttons["offerBuyButton"]
        if buy.waitForExistence(timeout: 5) { snapshot("flash-panel"); app.buttons["Close"].tap() }
        snapshot("flash-running")
        XCTAssertTrue(pill.waitForNonExistence(timeout: 40), "Pill still visible after the flash ended")
        XCTAssertTrue(app.buttons["proCapsule"].waitForExistence(timeout: 5), "PRO capsule not back after the flash")
        snapshot("flash-expired")
    }

    func testProOwnerNeverSeesOffers() throws {
        app.launchArguments += ["-onboarding_done_v1", "YES"]
        app.launchEnvironment["CUTSENSE_FORCE_PRO"] = "1"
        app.launchEnvironment["CUTSENSE_FORCE_FLASH_OFFER"] = "1"
        app.launch()
        XCTAssertTrue(app.buttons["chooseVideoButton"].waitForExistence(timeout: 15))
        sleep(3)
        snapshot("pro-owner-home")
        XCTAssertFalse(app.buttons["offerPill"].exists, "Pill shown to a Pro owner")
        XCTAssertFalse(app.buttons["offerBuyButton"].exists, "Offer opened for a Pro owner")
        XCTAssertFalse(app.buttons["proCapsule"].exists, "PRO capsule shown to a Pro owner")
    }

    // MARK: Pro pass (real local-StoreKit purchases, not CUTSENSE_FORCE_PRO)

    private var banner: XCUIElement { app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Advertisement'")).firstMatch }
    private var nativeBadge: XCUIElement { app.staticTexts.matching(NSPredicate(format: "label MATCHES '\\s*Ad\\s*'")).firstMatch }

    /// Free: native card while analyzing, ad break, banner, locked fine-tune → paywall. Buy $7.99 in the
    /// same session: banner and capsule go at once, fine-tune opens. Relaunch: still Pro, no ads, no prompts.
    func testProPurchaseRemovesAdsLiveAndUnlocksFineTune() throws {
        app.launchArguments += ["-onboarding_done_v1", "YES", "-ad_free_until", "0"]
        app.launchEnvironment["CUTSENSE_AUTORUN_VIDEO_URL"] = "qa-run/06_long_20min.mp4"
        app.launch()
        let save = app.buttons["saveButton"]
        let skip = app.buttons["skipAdButton"]
        let fullScreenAdUp = app.buttons["Close Advertisement"]  // the AdMob full-screen ad; the test banner also says "Test mode"
        var native = false, bannerWhileWorking = false
        let deadline = Date().addingTimeInterval(600)
        while Date() < deadline, !save.exists {
            if !native, nativeBadge.exists { native = true; snapshot("free-analyzing-native") }
            if !bannerWhileWorking, banner.exists { bannerWhileWorking = true; snapshot("free-analyzing-banner") }
            _ = save.waitForExistence(timeout: 1)
        }
        XCTAssertTrue(save.exists, "Review never appeared")
        // The 3-2-1 ad break starts ~1-4 s after review; Skip it like a user would.
        let adBreak = skip.waitForExistence(timeout: 6)
        if adBreak {
            snapshot("free-ad-break")
            _ = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: skip)], timeout: 2)
            if skip.exists { skip.tap() }
        }
        var fullScreenAd = false
        let adDeadline = Date().addingTimeInterval(45)
        while Date() < adDeadline, fullScreenAdUp.exists {
            if !fullScreenAd { fullScreenAd = true; snapshot("free-fullscreen-ad") }
            let close = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'close' AND isEnabled == true")).allElementsBoundByIndex.first { $0.isHittable }
            close?.tap()
            sleep(1)
        }
        XCTAssertTrue(save.exists, "Review never appeared")
        let bannerShown = banner.waitForExistence(timeout: 20)
        snapshot("free-review-banner")
        // The PRO capsule is home-only (isIdle); on review the locked fine-tune is the Pro entry.
        print("QA-PRO free native=\(native) bannerWhileWorking=\(bannerWhileWorking) adBreak=\(adBreak) fullScreenAd=\(fullScreenAd) banner=\(bannerShown)")

        app.buttons["fineTuneButton"].tap()
        let unlock = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Unlock for'")).firstMatch
        XCTAssertTrue(unlock.waitForExistence(timeout: 15), "Locked fine-tune did not open the paywall")
        snapshot("free-finetune-paywall")
        unlock.tap()
        let buy = storeKitButton(identifier: "footer", labels: ["Purchase", "Buy", "Satın Al", "Confirm"])
        XCTAssertTrue(buy.waitForExistence(timeout: 20), "StoreKit sheet did not appear")
        buy.tap()
        answerStoreKitSignIn()
        for source in [app!, springboard] where source.buttons["OK"].waitForExistence(timeout: 5) { source.buttons["OK"].tap(); break }
        XCTAssertTrue(unlock.waitForNonExistence(timeout: 20), "Paywall still open after buying")
        sleep(2)
        snapshot("pro-same-session")
        XCTAssertFalse(banner.exists, "Banner still shown right after buying Pro")
        XCTAssertFalse(app.buttons["proCapsule"].exists, "PRO capsule after buying")
        XCTAssertFalse(app.buttons["offerPill"].exists, "Offer pill after buying")
        app.buttons["fineTuneButton"].tap()
        XCTAssertTrue(app.buttons["fineTuneResetButton"].waitForExistence(timeout: 10), "Fine-tune still locked after buying")
        snapshot("pro-finetune-open")
        app.swipeDown(velocity: .fast)
        save.tap()
        app.tap()
        XCTAssertTrue(app.buttons["Saved to Photos"].waitForExistence(timeout: 600))
        XCTAssertFalse(skip.exists, "Ad break during a Pro save")
        snapshot("pro-saved")

        // Kill + relaunch on another video: still Pro, no native card, no ad break, no banner, no offer/consent.
        app.terminate()
        app.launchEnvironment["CUTSENSE_AUTORUN_VIDEO_URL"] = "qa-run/05_turkish.mov"
        app.launch()
        var nativeAfter = false
        while !save.exists { if nativeBadge.exists { nativeAfter = true }; _ = save.waitForExistence(timeout: 1) }
        XCTAssertFalse(nativeAfter, "Native ad for a Pro owner")
        XCTAssertFalse(skip.waitForExistence(timeout: 6), "Ad break for a Pro owner")
        XCTAssertFalse(banner.exists, "Banner for a Pro owner")
        XCTAssertFalse(app.buttons["proCapsule"].exists || app.buttons["offerPill"].exists, "Pro entry shown to an owner")
        snapshot("pro-relaunch-review")
        try fineTuneExtremes()
    }

    /// Minimum pause / breathing room extremes change the plan; Reset restores it; a custom value persists.
    private func fineTuneExtremes() throws {
        let cuts = app.buttons["reviewCutsButton"]
        let percent = app.staticTexts.matching(NSPredicate(format: "label MATCHES '^[0-9]{1,3}%$'")).firstMatch
        // A custom fine-tune from an earlier run persists (by design): start from the preset.
        app.buttons["fineTuneButton"].tap()
        let resetButton = app.buttons["fineTuneResetButton"]
        XCTAssertTrue(resetButton.waitForExistence(timeout: 10))
        if resetButton.isEnabled { resetButton.tap(); sleep(1) }
        app.swipeDown(velocity: .fast)
        sleep(2)
        let baseline = "\(cuts.label) \(percent.label)"
        func setSliders(_ minPause: CGFloat, _ pad: CGFloat, _ shot: String) -> String {
            app.buttons["fineTuneButton"].tap()
            XCTAssertTrue(app.buttons["fineTuneResetButton"].waitForExistence(timeout: 10))
            app.sliders.element(boundBy: 0).adjust(toNormalizedSliderPosition: minPause)
            app.sliders.element(boundBy: 1).adjust(toNormalizedSliderPosition: pad)
            sleep(1)
            snapshot(shot)
            app.swipeDown(velocity: .fast)
            sleep(2)
            return "\(cuts.label) \(percent.label)"
        }
        let aggressive = setSliders(0, 0, "finetune-min")
        let gentle = setSliders(1, 1, "finetune-max")
        snapshot("finetune-max-review")
        app.buttons["fineTuneButton"].tap()
        XCTAssertTrue(app.buttons["fineTuneResetButton"].waitForExistence(timeout: 10))
        app.buttons["fineTuneResetButton"].tap()
        sleep(1)
        app.swipeDown(velocity: .fast)
        sleep(2)
        let reset = "\(cuts.label) \(percent.label)"
        let custom = setSliders(0.5, 0.2, "finetune-custom")
        print("QA-PRO finetune baseline=[\(baseline)] min=[\(aggressive)] max=[\(gentle)] reset=[\(reset)] custom=[\(custom)]")
        XCTAssertNotEqual(aggressive, baseline, "Extreme short settings did not change the plan")
        XCTAssertNotEqual(gentle, aggressive, "Extreme long settings did not change the plan")
        XCTAssertEqual(reset, baseline, "Reset did not restore the preset plan")
        app.buttons["saveButton"].tap()
        app.tap()
        XCTAssertTrue(app.buttons["Saved to Photos"].waitForExistence(timeout: 600))
        let newLength = app.staticTexts.matching(NSPredicate(format: "label MATCHES '^[0-9]+:[0-9]{2}$'")).allElementsBoundByIndex.map(\.label)
        print("QA-PRO custom-saved lengths=\(newLength)")
        snapshot("finetune-custom-saved")

        // Relaunch: the custom fine-tune is still applied.
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["saveButton"].waitForExistence(timeout: 600))
        sleep(2)
        let again = "\(cuts.label) \(percent.label)"
        snapshot("finetune-after-relaunch")
        print("QA-PRO finetune relaunch=[\(again)]")
        XCTAssertEqual(again, custom, "Custom fine-tune not kept after relaunch")
    }

    /// Free: three keeps, the 4th toggle and Keep all open the paywall after the list closes and change nothing.
    /// Buying in the same session lifts the limit at once.
    func testFreeKeepLimitOpensPaywallAndProUnlocks() throws {
        app.launchArguments += ["-onboarding_done_v1", "YES", "-ad_free_until", "\(Date.now.addingTimeInterval(3600).timeIntervalSince1970)"]
        app.launchEnvironment["CUTSENSE_AUTORUN_VIDEO_URL"] = "qa-run/01_talk_1080p30.mp4"
        app.launch()
        let save = app.buttons["saveButton"]
        XCTAssertTrue(save.waitForExistence(timeout: 300), "Review never appeared")
        skipAdBreak()
        let review = app.buttons["reviewCutsButton"]
        func cutCount() -> Int { Int(review.label.filter(\.isNumber)) ?? 0 }
        if cutCount() < 4 {
            app.buttons["Tight"].tap()
            sleep(2)
        }
        XCTAssertGreaterThanOrEqual(cutCount(), 4, "Fixture needs 4+ cuts: \(review.label)")

        review.tap()
        let counter = app.buttons["keepLimitButton"]
        XCTAssertTrue(counter.waitForExistence(timeout: 10), "Keep counter missing for a free user")
        for i in 0..<3 {
            tapToggle(i)
            sleep(1)
        }
        XCTAssertTrue(counter.label.hasPrefix("Kept 3 of 3"), "Counter: \(counter.label)")
        snapshot("free-keep-3-of-3")
        let removingBefore = removingLabel()

        tapToggle(3)
        let unlock = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Unlock for'")).firstMatch
        XCTAssertTrue(unlock.waitForExistence(timeout: 15), "4th keep did not open the paywall")
        XCTAssertFalse(counter.exists, "Paywall stacked on the cut list")
        snapshot("free-keep-limit-paywall")
        app.buttons["Close"].firstMatch.tap()
        XCTAssertTrue(unlock.waitForNonExistence(timeout: 10))

        // Reopen: the three keeps stayed, the 4th is still cut; Keep all is locked too.
        review.tap()
        XCTAssertTrue(counter.waitForExistence(timeout: 10))
        XCTAssertTrue(counter.label.hasPrefix("Kept 3 of 3"), "Keeps lost after the paywall: \(counter.label)")
        XCTAssertEqual(removingLabel(), removingBefore, "Refused keep changed the plan")
        XCTAssertEqual(keepToggle(3).value as? String, "Cut", "4th cut was kept after the refusal")
        app.buttons["keepAllCutsButton"].tap()
        XCTAssertTrue(unlock.waitForExistence(timeout: 15), "Locked Keep all did not open the paywall")
        buyThroughSheet(unlock)
        XCTAssertTrue(unlock.waitForNonExistence(timeout: 20), "Paywall still open after buying")
        sleep(2)

        review.tap()
        XCTAssertTrue(keepToggle(3).waitForExistence(timeout: 10))
        XCTAssertFalse(counter.exists, "Keep counter shown to a Pro owner")
        tapToggle(3)
        sleep(1)
        XCTAssertEqual(keepToggle(3).value as? String, "Keep", "Pro could not keep a 4th pause")
        app.buttons["keepAllCutsButton"].tap()
        sleep(1)
        XCTAssertFalse(app.buttons["keepAllCutsButton"].isEnabled, "Keep all did not keep every cut for Pro")
        snapshot("pro-keep-all")
    }

    private func keepToggle(_ i: Int) -> XCUIElement { app.switches["cutToggle_\(i)"] }

    /// Taps the switch itself; the row's centre is the audition button.
    private func tapToggle(_ i: Int) { keepToggle(i).coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap() }

    private func removingLabel() -> String {
        app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Removing'")).firstMatch.label
    }

    private func skipAdBreak() {
        let skip = app.buttons["skipAdButton"]
        if skip.waitForExistence(timeout: 6) {
            _ = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: skip)], timeout: 2)
            if skip.exists && skip.isHittable { skip.tap() }  // the break may end on its own meanwhile
        }
        let close = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'close' AND isEnabled == true"))
        let deadline = Date().addingTimeInterval(45)
        while Date() < deadline, app.buttons["Close Advertisement"].exists {
            close.allElementsBoundByIndex.first { $0.isHittable }?.tap()
            sleep(1)
        }
    }

    /// Welcome $5.99 at the end of onboarding grants the same Pro.
    func testWelcomePurchaseGrantsPro() throws {
        app.launchEnvironment["CUTSENSE_RESET_ONBOARDING"] = "1"
        app.launch()
        let next = app.buttons["onboardingContinue"]
        XCTAssertTrue(next.waitForExistence(timeout: 15))
        for _ in 0..<3 where next.exists { next.tap(); sleep(1) }
        let buy = app.buttons["offerBuyButton"]
        XCTAssertTrue(buy.waitForExistence(timeout: 15), "Welcome offer missing")
        XCTAssertTrue(buy.label.contains("5.99"), "Welcome price: \(buy.label)")
        buyThroughSheet(buy)
        XCTAssertTrue(app.buttons["chooseVideoButton"].waitForExistence(timeout: 20))
        sleep(2)
        snapshot("welcome-bought")
        XCTAssertFalse(app.buttons["proCapsule"].exists || app.buttons["offerPill"].exists, "Still free after the welcome purchase")
    }

    /// Flash $3.99 grants the same Pro.
    func testFlashPurchaseGrantsPro() throws {
        app.launchArguments += ["-onboarding_done_v1", "YES"]
        app.launchEnvironment["CUTSENSE_RESET_ONBOARDING"] = "1"
        app.launchEnvironment["CUTSENSE_FORCE_FLASH_OFFER"] = "1"
        app.launch()
        let buy = app.buttons["offerBuyButton"]
        if !buy.waitForExistence(timeout: 10) {
            XCTAssertTrue(app.buttons["offerPill"].waitForExistence(timeout: 15))
            app.buttons["offerPill"].tap()
        }
        XCTAssertTrue(buy.waitForExistence(timeout: 10))
        XCTAssertTrue(buy.label.contains("3.99"), "Flash price: \(buy.label)")
        buyThroughSheet(buy)
        sleep(3)
        snapshot("flash-bought")
        XCTAssertFalse(app.buttons["proCapsule"].exists || app.buttons["offerPill"].exists, "Still free after the flash purchase")
    }

    /// Revoked purchase (transactions cleared): Pro locks again; banner and capsule come back on relaunch.
    func testRevokedPurchaseLocksProAgain() throws {
        app.launchArguments += ["-onboarding_done_v1", "YES", "-ad_free_until", "0"]
        app.launch()
        let capsule = app.buttons["proCapsule"]
        XCTAssertTrue(capsule.waitForExistence(timeout: 20))
        capsule.tap()
        let unlock = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Unlock for'")).firstMatch
        XCTAssertTrue(unlock.waitForExistence(timeout: 15))
        buyThroughSheet(unlock)
        XCTAssertTrue(capsule.waitForNonExistence(timeout: 20), "Purchase did not unlock Pro")
        snapshot("revoke-before")
        session.clearTransactions()
        app.terminate()
        app.launch()
        XCTAssertTrue(capsule.waitForExistence(timeout: 30), "PRO capsule not back after the purchase was revoked")
        let bannerBack = banner.waitForExistence(timeout: 20)
        snapshot("revoke-after")
        XCTAssertTrue(bannerBack, "Banner not back after revoke")
    }

    /// Step 1 of restore-after-reinstall (run with QA_KEEP_TRANSACTIONS=1): buy and keep.
    func testBuyAndKeepForReinstall() throws {
        guard keepTransactions else { throw XCTSkip("needs TEST_RUNNER_QA_KEEP_TRANSACTIONS=1") }
        app.launchArguments += ["-onboarding_done_v1", "YES"]
        app.launch()
        let capsule = app.buttons["proCapsule"]
        XCTAssertTrue(capsule.waitForExistence(timeout: 20))
        capsule.tap()
        let unlock = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Unlock for'")).firstMatch
        XCTAssertTrue(unlock.waitForExistence(timeout: 15))
        buyThroughSheet(unlock)
        XCTAssertTrue(capsule.waitForNonExistence(timeout: 20))
        snapshot("reinstall-bought")
    }

    /// Step 2, after `devicectl device uninstall app` + reinstall: Restore Purchases brings Pro back.
    func testRestoreAfterReinstall() throws {
        guard keepTransactions else { throw XCTSkip("needs TEST_RUNNER_QA_KEEP_TRANSACTIONS=1") }
        app.launchArguments += ["-onboarding_done_v1", "YES"]
        app.launch()
        XCTAssertTrue(app.buttons["chooseVideoButton"].waitForExistence(timeout: 20))
        sleep(3)
        snapshot("reinstall-launch")
        let freshLooksPro = !app.buttons["proCapsule"].exists
        app.buttons["settingsButton"].tap()
        let restore = app.buttons["Restore Purchases"]
        XCTAssertTrue(restore.waitForExistence(timeout: 10))
        restore.tap()
        answerStoreKitSignIn()
        sleep(4)
        snapshot("reinstall-restored")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["chooseVideoButton"].waitForExistence(timeout: 10))
        sleep(2)
        print("QA-PRO reinstall proBeforeRestore=\(freshLooksPro) proAfterRestore=\(!app.buttons["proCapsule"].exists)")
        XCTAssertFalse(app.buttons["proCapsule"].exists, "Restore did not bring Pro back")
        app.buttons["historyButton"].tap()
        sleep(2)
        snapshot("reinstall-history")
        session.clearTransactions()
    }

    private func buyThroughSheet(_ button: XCUIElement) {
        button.tap()
        let buy = storeKitButton(identifier: "footer", labels: ["Purchase", "Buy", "Satın Al", "Confirm"])
        XCTAssertTrue(buy.waitForExistence(timeout: 20), "StoreKit sheet did not appear")
        buy.tap()
        answerStoreKitSignIn()
        for source in [app!, springboard] where source.buttons["OK"].waitForExistence(timeout: 5) { source.buttons["OK"].tap(); break }
    }

    /// AppStore.sync() in the Xcode StoreKit environment asks to "sign in"; waits don't trigger interruption monitors.
    private func answerStoreKitSignIn() {
        for source in [app!, springboard] {
            let ok = source.alerts.buttons["OK"]
            if ok.waitForExistence(timeout: 4) { ok.tap(); return }
        }
    }

    /// First match in the app or SpringBoard, whichever hosts the StoreKit sheet.
    private func storeKitButton(identifier: String, labels: [String]) -> XCUIElement {
        let predicate = NSPredicate(format: "identifier == %@ OR label IN %@", identifier, labels)
        let inApp = app.buttons.matching(predicate).firstMatch
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            if inApp.exists { return inApp }
            let inBoard = springboard.buttons.matching(predicate).firstMatch
            if inBoard.exists { return inBoard }
            sleep(1)
        }
        return inApp
    }

    private func snapshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
