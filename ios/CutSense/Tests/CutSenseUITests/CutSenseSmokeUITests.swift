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

        XCTAssertTrue(app.buttons["chooseVideoButton"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.buttons["language_en"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.buttons["language_tr"].waitForExistence(timeout: 5), app.debugDescription)

        let englishTitle = app.staticTexts["Cut Silence"]
        let turkishTitle = app.staticTexts["Sessizlik Kes"]
        XCTAssertTrue(
            englishTitle.waitForExistence(timeout: 5) || turkishTitle.waitForExistence(timeout: 5),
            app.debugDescription
        )

        if englishTitle.exists {
            app.buttons["language_tr"].tap()
            XCTAssertTrue(turkishTitle.waitForExistence(timeout: 8), app.debugDescription)
            app.buttons["language_en"].tap()
            XCTAssertTrue(englishTitle.waitForExistence(timeout: 8), app.debugDescription)
        } else {
            app.buttons["language_en"].tap()
            XCTAssertTrue(englishTitle.waitForExistence(timeout: 8), app.debugDescription)
            app.buttons["language_tr"].tap()
            XCTAssertTrue(turkishTitle.waitForExistence(timeout: 8), app.debugDescription)
        }
    }

    @MainActor
    func testFiveMinuteAutorunReachesResultScreen() {
        let app = XCUIApplication()
        app.launchEnvironment["CUTSENSE_DISABLE_ADS"] = "1"
        app.launchEnvironment["CUTSENSE_AUTORUN_VIDEO_URL"] = "/tmp/cutsense-stress/cutsense_5min_speech_silence.mp4"
        app.launch()

        XCTAssertTrue(app.buttons["newVideoButton"].waitForExistence(timeout: 120), app.debugDescription)
    }
}
