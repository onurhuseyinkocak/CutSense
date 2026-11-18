import XCTest

final class CutSenseSmokeUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    @MainActor
    func testHomeLaunchesAndLanguageSwitcherWorks() {
        let app = XCUIApplication()
        app.launchEnvironment["CUTSENSE_DISABLE_ADS"] = "1"
        app.launch()
        dismissOnboardingIfNecessary(in: app)

        let studio = app.buttons["openUGCStudioButton"]
        XCTAssertTrue(studio.waitForExistence(timeout: 8), app.debugDescription)
        studio.tap()
        XCTAssertTrue(
            app.staticTexts["Auto UGC Düzenleyici"].waitForExistence(timeout: 8) ||
            app.staticTexts["Auto UGC Editor"].exists,
            app.debugDescription
        )
        XCTAssertTrue(app.buttons["Video Seç"].exists || app.buttons["Choose Video"].exists, app.debugDescription)
    }

    @MainActor
    func testFiveMinuteAutorunReachesResultScreen() {
        let app = XCUIApplication()
        app.launchEnvironment["CUTSENSE_DISABLE_ADS"] = "1"
        app.launchEnvironment["CUTSENSE_AUTORUN_VIDEO_URL"] = "/tmp/cutsense-stress/cutsense_5min_speech_silence.mp4"
        app.launch()
        dismissOnboardingIfNecessary(in: app)

        XCTAssertTrue(app.buttons["newVideoButton"].waitForExistence(timeout: 120), app.debugDescription)
    }

    @MainActor
    private func dismissOnboardingIfNecessary(in app: XCUIApplication) {
        let skip = app.buttons["Skip"]
        if skip.waitForExistence(timeout: 2) {
            skip.tap()
        }
    }
}
