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
        session.clearTransactions()
        app = XCUIApplication()
        app.launchArguments += ["-app_language", "en", "-AppleLanguages", "(en)"]
        addUIInterruptionMonitor(withDescription: "System alerts") { alert in
            for label in ["Allow Full Access", "Allow Access to All Photos", "Allow", "OK", "Tam Erişime İzin Ver", "Tüm Fotoğraflara Erişim İzni Ver", "İzin Ver", "Tamam", "Not Now"] where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            return false
        }
    }

    override func tearDown() async throws {
        session?.clearTransactions()
    }

    // MARK: Onboarding

    func testOnboardingContinueToStartAndPersists() throws {
        app.launchEnvironment["CUTSENSE_RESET_ONBOARDING"] = "1"
        app.launch()
        let next = app.buttons["onboardingContinue"]
        XCTAssertTrue(next.waitForExistence(timeout: 15), "Onboarding not shown on a fresh install")
        snapshot("onboarding-1")
        next.tap(); sleep(1); snapshot("onboarding-2")
        next.tap(); next.tap() // double tap on page 2 must not skip past page 3's CTA into a broken state
        XCTAssertTrue(app.buttons["chooseVideoButton"].waitForExistence(timeout: 10) || next.exists)
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
        let restoredNothing = app.staticTexts["No purchase found to restore."].waitForExistence(timeout: 40)
        snapshot("restore-empty")
        XCTAssertTrue(restoredNothing, "No message for empty restore")

        // Cancel at the system sheet.
        unlock.tap()
        let cancel = springboard.buttons.matching(NSPredicate(format: "label IN {'Cancel', 'Vazgeç', 'İptal'}")).firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 20), "StoreKit sheet did not appear")
        cancel.tap()
        XCTAssertTrue(unlock.waitForExistence(timeout: 10), "Paywall gone after cancelling")
        snapshot("after-cancel")

        // Buy.
        unlock.tap()
        let buy = springboard.buttons.matching(NSPredicate(format: "label IN {'Purchase', 'Buy', 'Satın Al', 'Confirm'}")).firstMatch
        XCTAssertTrue(buy.waitForExistence(timeout: 20))
        buy.tap()
        let ok = springboard.buttons["OK"]
        if ok.waitForExistence(timeout: 10) { ok.tap() }
        XCTAssertTrue(capsule.waitForNonExistence(timeout: 20), "PRO capsule still visible after purchase")
        snapshot("after-purchase")

        // Restore with the purchase.
        app.buttons["settingsButton"].tap()
        let restore = app.buttons["Restore Purchases"]
        XCTAssertTrue(restore.waitForExistence(timeout: 10))
        restore.tap()
        sleep(3)
        snapshot("restored")
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Unlock'")).firstMatch.exists, "Unlock offered to an owner")
    }

    // MARK: Flash offer (10 min after onboarding; shortened here)

    func testFlashOfferStartsAfterOnboardingAndAutoOpensOnce() throws {
        app.launchEnvironment["CUTSENSE_RESET_ONBOARDING"] = "1"
        app.launchEnvironment["CUTSENSE_FLASH_DELAY_SECONDS"] = "8"
        app.launchEnvironment["CUTSENSE_OFFER_SECONDS"] = "90"
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
        app.launchEnvironment = ["CUTSENSE_OFFER_SECONDS": "90"]
        app.launchArguments += ["-onboarding_done_v1", "YES"]
        app.launch()
        XCTAssertTrue(pill.waitForExistence(timeout: 15), "Pill lost after relaunch")
        sleep(2)
        XCTAssertFalse(buy.exists, "Flash opened automatically a second time")
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

    private func snapshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
