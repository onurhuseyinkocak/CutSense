import XCTest

/// End-to-end flows meant for a real iPhone (run with -destination id=<device>).
/// Env passed through TEST_RUNNER_* is forwarded to the app via launchEnvironment.
final class DeviceFlowUITests: XCTestCase {
    private var app: XCUIApplication!
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-app_language", "en", "-AppleLanguages", "(en)"]
        let env = ProcessInfo.processInfo.environment
        for key in ["CUTSENSE_AUTORUN_VIDEO_URL", "CUTSENSE_FORCE_PRO", "CUTSENSE_FORCE_PREVIEW_FALLBACK"] {
            if let value = env[key] { app.launchEnvironment[key] = value }
        }
        addUIInterruptionMonitor(withDescription: "System alerts") { alert in
            for label in ["Allow Full Access", "Allow Access to All Photos", "Allow", "OK", "Not Now"] where alert.buttons[label].exists {
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
        let firstVideo = app.images.firstMatch
        XCTAssertTrue(firstVideo.waitForExistence(timeout: 20), "Photos picker did not show any item")
        snapshot("picker")
        firstVideo.tap()
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

    private func reviewRestoreSave() throws {
        let save = app.buttons["saveButton"]
        XCTAssertTrue(save.waitForExistence(timeout: 600), "Review screen never appeared")
        skipAdBreakIfShown()
        snapshot("review")

        let reviewCuts = app.buttons["reviewCutsButton"]
        XCTAssertTrue(reviewCuts.waitForExistence(timeout: 10))
        let lengthBefore = newLengthText()
        reviewCuts.tap()
        let toggle = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'cutToggle_'")).firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        toggle.tap()
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
        XCTAssertTrue(app.buttons["chooseVideoButton"].waitForExistence(timeout: 10))
    }

    private func skipAdBreakIfShown() {
        let skip = app.buttons["Skip"]
        if skip.waitForExistence(timeout: 6) { skip.tap() }
        // A full-screen ad (if the countdown already elapsed) is closed by its own button.
        let close = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'close'")).firstMatch
        if close.waitForExistence(timeout: 3) { close.tap() }
    }

    private func dismissRatingPromptIfShown() {
        let notNow = springboard.buttons["Not Now"]
        if notNow.waitForExistence(timeout: 4) { notNow.tap() }
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
