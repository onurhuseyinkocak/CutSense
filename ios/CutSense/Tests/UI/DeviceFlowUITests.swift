import XCTest

/// End-to-end flows meant for a real iPhone (run with -destination id=<device>).
/// Env passed through TEST_RUNNER_* is forwarded to the app via launchEnvironment.
@MainActor
final class DeviceFlowUITests: XCTestCase {
    private var app: XCUIApplication!
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-app_language", "en", "-AppleLanguages", "(en)", "-onboarding_done_v1", "YES"]
        let env = ProcessInfo.processInfo.environment
        for key in ["CUTSENSE_AUTORUN_VIDEO_URL", "CUTSENSE_FORCE_PRO", "CUTSENSE_FORCE_PREVIEW_FALLBACK"] {
            if let value = env[key] { app.launchEnvironment[key] = value }
        }
        addUIInterruptionMonitor(withDescription: "System alerts") { alert in
            for label in ["Allow Full Access", "Allow Access to All Photos", "Allow", "OK", "Tam Erişime İzin Ver", "Tüm Fotoğraflara Erişim İzni Ver", "İzin Ver", "Tamam", "Not Now"] where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            return false
        }
    }

    /// Autorun (file copied into Documents) → review → restore one cut → save to Photos.
    func testAutorunReviewRestoreSave() throws {
        app.launch()
        try reviewRestoreSave()
    }

    /// Real picker path: Photos → first video → review → save.
    func testPickFromPhotosAndSave() throws {
        app.launch()
        let choose = app.buttons["chooseVideoButton"]
        XCTAssertTrue(choose.waitForExistence(timeout: 15))
        choose.tap()
        let cells = app.images.matching(identifier: "PXGGridLayout-Info")
        XCTAssertTrue(cells.firstMatch.waitForExistence(timeout: 20), "Photos picker did not show any item")
        snapshot("picker")
        // Prefer the owner's minutes-long clip (picker labels follow the system language).
        let ownerClip = cells.matching(NSPredicate(format: "label CONTAINS 'dört dakika otuz dört' OR label CONTAINS[c] '4 minutes, 34'")).firstMatch
        let target = ownerClip.exists ? ownerClip : cells.firstMatch
        target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        try reviewRestoreSave()
    }

    /// Settings shows zero temporary storage after a finished session.
    func testSettingsStorageIsEmptyAfterNewVideo() throws {
        app.launch()
        let settings = app.buttons["settingsButton"]
        XCTAssertTrue(settings.waitForExistence(timeout: 15))
        settings.tap()
        let row = app.descendants(matching: .any)["storageUsageRow"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        snapshot("settings")
        XCTAssertTrue(row.label.contains("Zero") || row.label.contains("0 "), "Storage row: \(row.label)")
    }

    /// Local StoreKit config (scheme): buy Pro, ads/Pro entry points disappear, Restore keeps Pro.
    func testPurchaseProAndRestore() throws {
        app.launch()
        let capsule = app.buttons["proCapsule"]
        XCTAssertTrue(capsule.waitForExistence(timeout: 20), "Pro entry point missing (product not loaded?)")
        capsule.tap()
        let unlock = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Unlock for'")).firstMatch
        XCTAssertTrue(unlock.waitForExistence(timeout: 15), "Paywall price button missing")
        snapshot("paywall")
        unlock.tap()
        // StoreKit confirmation sheet runs out of process.
        let buy = springboard.buttons.matching(NSPredicate(format: "label IN {'Purchase', 'Buy', 'Satın Al', 'Confirm'}")).firstMatch
        if buy.waitForExistence(timeout: 20) { buy.tap() }
        let ok = springboard.buttons["OK"]
        if ok.waitForExistence(timeout: 10) { ok.tap() }
        XCTAssertTrue(capsule.waitForNonExistence(timeout: 20), "PRO capsule still visible after purchase")
        snapshot("after-purchase")

        app.buttons["settingsButton"].tap()
        let restore = app.buttons["Restore Purchases"]
        XCTAssertTrue(restore.waitForExistence(timeout: 10))
        snapshot("settings-pro")
        restore.tap()
        sleep(3)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Unlock'")).firstMatch.exists, "Unlock offered after restore")
    }

    private func reviewRestoreSave() throws {
        let save = app.buttons["saveButton"]
        XCTAssertTrue(save.waitForExistence(timeout: 600), "Review screen never appeared")
        skipAdBreakIfShown()
        snapshot("review")

        let reviewCuts = app.buttons["reviewCutsButton"]
        XCTAssertTrue(reviewCuts.waitForExistence(timeout: 10))
        let lengthBefore = newLengthText()
        reviewCuts.tap()
        let toggle = app.switches.firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        // Tap the knob side; a centered tap on a labeled SwiftUI toggle can land on the label.
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        snapshot("cut-sheet")
        app.swipeDown(velocity: .fast)
        if reviewCuts.waitForExistence(timeout: 2), !save.isHittable { app.swipeDown(velocity: .fast) }
        let lengthAfter = newLengthText()
        XCTAssertNotEqual(lengthBefore, lengthAfter, "Restoring a cut did not change the new length")

        save.tap()
        app.tap() // lets the interruption monitor handle the Photos permission alert
        let saved = app.buttons["Saved to Photos"]
        XCTAssertTrue(saved.waitForExistence(timeout: 600), "Save did not finish")
        snapshot("saved")
        dismissRatingPromptIfShown()

        let newVideo = app.buttons["newVideoButton"]
        XCTAssertTrue(newVideo.waitForExistence(timeout: 10))
        newVideo.tap()
        snapshot("after-new-video-0s")
        let home = app.buttons["chooseVideoButton"].waitForExistence(timeout: 10)
        snapshot("after-new-video-10s")
        XCTAssertTrue(home, "New Video did not return to the home screen")
    }

    private func skipAdBreakIfShown() {
        let skip = app.buttons["skipAdButton"]
        if skip.waitForExistence(timeout: 6) { skip.tap() }
        // A full-screen ad (if the countdown already elapsed) is closed by its own button.
        let close = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'close'")).firstMatch
        if close.waitForExistence(timeout: 3) { close.tap() }
    }

    private func dismissRatingPromptIfShown() {
        for source in [app!, springboard] {
            let notNow = source.buttons["Not Now"]
            if notNow.waitForExistence(timeout: 3) { notNow.tap(); return }
        }
    }

    private func newLengthText() -> String {
        app.staticTexts.matching(NSPredicate(format: "label MATCHES '^[0-9]+:[0-9]{2}$'")).allElementsBoundByIndex.map(\.label).joined(separator: "|")
    }

    private func snapshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
