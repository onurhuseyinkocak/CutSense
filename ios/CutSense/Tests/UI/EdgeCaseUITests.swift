import XCTest

/// Edge cases on a real iPhone. Fixtures are copied into the app's Documents/qa-run/ with
/// `devicectl device copy to` and opened through the DEBUG autorun path (analyze → review → export);
/// the PhotosPicker copy itself is covered by DeviceFlowUITests / the picker tests below.
@MainActor
final class EdgeCaseUITests: XCTestCase {
    private var app: XCUIApplication!
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    /// Label the system-alert monitor taps; tests that deny Photos set it to "Don't Allow".
    private var alertChoice = ["Allow Full Access", "Allow Access to All Photos", "Allow", "OK", "Tam Erişime İzin Ver", "Tüm Fotoğraflara Erişim İzni Ver", "İzin Ver", "Tamam"]

    override func setUp() async throws {
        continueAfterFailure = false
        // No SKTestSession here: on device it terminated the freshly launched app ~4 s in (r2).
        // Entitlement state = whatever OfferFlowUITests.tearDown left (cleared → free user).
        app = XCUIApplication()
        // No `-cut_intensity`: the argument domain overrides @AppStorage writes, so level taps bounced back.
        // skipAdBreakIfShown selects Balanced instead.
        app.launchArguments += ["-app_language", "en", "-AppleLanguages", "(en)", "-onboarding_done_v1", "YES",
                               "-finetune_active", "NO"]
        addUIInterruptionMonitor(withDescription: "System alerts") { [unowned self] alert in
            for label in alertChoice + ["Not Now"] where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            return false
        }
    }

    // MARK: - Fixtures that must reach review and save

    func testFixture01Talk1080() throws { try reviewAndSave("01_talk_1080p30.mp4", expectCuts: true) }
    func testFixture02HEVC4K60() throws { try reviewAndSave("02_4k_hevc60.mp4", expectCuts: true) }
    func testFixture03Rotated() throws { try reviewAndSave("03_rotated.mov", expectCuts: true) }
    func testFixture04Portrait() throws { try reviewAndSave("04_portrait.mp4", expectCuts: true) }
    func testFixture10Quiet() throws { try reviewOrNoSpeech("10_quiet_minus40.mp4") }
    func testFixture11Clipping() throws { try reviewAndSave("11_clipping.mp4", expectCuts: true) }
    func testFixture12VFR() throws { try reviewAndSave("12_vfr.mp4", expectCuts: true) }
    func testFixture13Mono8k() throws { try reviewAndSave("13_8khz_mono.mp4", expectCuts: true) }
    func testFixture14MultiAudio() throws { try reviewAndSave("14_multi_audio.mov", expectCuts: true) }
    func testFixture15OddResolution() throws { try reviewAndSave("15_odd_1082x1922.mp4", expectCuts: true) }
    func testFixture16HighFPS() throws { try reviewAndSave("16_120fps.mp4", expectCuts: true) }

    // MARK: - Fixtures with an expected failure or nothing to cut

    func testFixture05OneSecond() throws { try reviewOrNoSpeech("05_one_second.mp4") }
    func testFixture07Music() throws { try reviewOrNoSpeech("07_music.mp4") }

    func testFixture08SilentTrack() throws {
        launch(autorun: "08_silent_track.mp4")
        try expectFailure(containing: "No speech")
    }

    func testFixture09NoAudio() throws {
        launch(autorun: "09_no_audio.mp4")
        try expectFailure(containing: "audio")
    }

    func testFixture17Truncated() throws {
        launch(autorun: "17_truncated.mp4")
        try expectFailure(containing: nil)
    }

    // MARK: - Long video: progress, cancel, background

    func testLongVideoCancelDuringAnalysis() throws {
        launch(autorun: "06_long_20min.mp4")
        let cancel = app.buttons["Cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 30), "No Cancel while analyzing")
        sleep(2)
        snapshot("long-analyzing")
        tapRepeatedly(cancel, times: 2) // second tap lands on whatever is there now; must not crash
        XCTAssertTrue(app.buttons["chooseVideoButton"].waitForExistence(timeout: 10), "Cancel did not return home")
        try assertStorageZero()
    }

    func testLongVideoBackgroundDuringAnalysis() throws {
        launch(autorun: "06_long_20min.mp4")
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 30))
        sleep(2)
        XCUIDevice.shared.press(.home)
        sleep(8)
        app.activate()
        snapshot("long-after-background-analyze")
        try waitForReviewOrFailure(timeout: 600)
        snapshot("long-analyze-outcome")
    }

    func testLongVideoBackgroundDuringExport() throws {
        launch(autorun: "06_long_20min.mp4")
        try waitForReview(timeout: 600)
        app.buttons["saveButton"].tap()
        sleep(3)
        snapshot("long-exporting")
        XCUIDevice.shared.press(.home)
        sleep(10)
        app.activate()
        snapshot("long-after-background-export")
        // Either the save finished or the review shows an error notice with Save available again.
        let saved = app.buttons["Saved to Photos"]
        let deadline = Date().addingTimeInterval(600)
        while Date() < deadline {
            if saved.exists { break }
            if app.buttons["saveButton"].exists, app.buttons["saveButton"].isHittable, !isExportOverlayShown { break }
            sleep(2)
        }
        snapshot("long-export-outcome")
        XCTAssertTrue(saved.exists || app.buttons["saveButton"].isHittable, "UI stuck after backgrounding the export")
    }

    func testTerminateDuringExportLeavesNoFiles() throws {
        launch(autorun: "06_long_20min.mp4")
        try waitForReview(timeout: 600)
        app.buttons["saveButton"].tap()
        sleep(4)
        app.terminate()
        app.launchEnvironment["CUTSENSE_AUTORUN_VIDEO_URL"] = nil
        app.launch()
        try assertStorageZero()
    }

    // MARK: - Review actions and user errors (fixture 01)

    func testIntensityKeepAllCutAllAndDoubleTaps() throws {
        app.launchEnvironment["CUTSENSE_FORCE_PRO"] = "1"  // Keep all is Pro; free users get the 3-keep limit
        launch(autorun: "01_talk_1080p30.mp4")
        try waitForReview(timeout: 120)
        skipAdBreakIfShown(doubleTap: true)
        let initial = newLength()
        for name in ["Tight", "Hardcore", "Balanced"] {
            let segment = app.buttons[name]
            XCTAssertTrue(segment.waitForExistence(timeout: 5), "\(name) segment missing")
            tapRepeatedly(segment, times: 2)
            sleep(1)
            snapshot("intensity-\(name)")
        }
        XCTAssertEqual(newLength(), initial, "Back to Balanced should restore the first plan")

        app.buttons["reviewCutsButton"].tap()
        let keepAll = app.buttons["keepAllCutsButton"]
        XCTAssertTrue(keepAll.waitForExistence(timeout: 5))
        tapRepeatedly(keepAll, times: 2)
        snapshot("keep-all")
        let cutAll = app.buttons["cutAllButton"]
        XCTAssertTrue(cutAll.waitForExistence(timeout: 5))
        tapRepeatedly(cutAll, times: 2)
        snapshot("cut-all")
        // Dismiss mid-animation, then immediately act on review.
        app.swipeDown(velocity: .fast)
        app.swipeDown(velocity: .fast)
        XCTAssertTrue(app.buttons["saveButton"].waitForExistence(timeout: 5))
        XCTAssertEqual(newLength(), initial, "Cut all after Keep all should give the original plan")
    }

    func testCutAuditionBeforeAfter() throws {
        launch(autorun: "01_talk_1080p30.mp4")
        try waitForReview(timeout: 120)
        skipAdBreakIfShown(doubleTap: false)
        app.buttons["reviewCutsButton"].tap()
        let row = app.buttons["cutRow_0"]
        XCTAssertTrue(row.waitForExistence(timeout: 10), "Cut rows are not tappable buttons")
        sleep(1)
        snapshot("cuts-sheet")
        XCTAssertTrue(app.staticTexts["Tap a pause to hear it. Turn it off to keep it."].exists, "Guidance line missing")
        row.tap()
        sleep(1)
        snapshot("audition-before-lead-in")
        XCTAssertTrue(app.staticTexts["This pause will be cut"].waitForExistence(timeout: 4), "No in-cut overlay while auditioning")
        snapshot("audition-before-in-cut")
        // Restore it while it plays: the overlay must say it is kept.
        app.switches["cutToggle_0"].coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        sleep(1)
        snapshot("audition-after-restore")
        app.buttons["auditionAfter"].tap()
        app.buttons["cutRow_1"].tap()
        sleep(1)
        XCTAssertTrue(app.staticTexts["Edited version"].waitForExistence(timeout: 4), "After mode overlay missing")
        snapshot("audition-after-mode")
        app.buttons["cutRow_1"].tap() // tap again stops
        XCTAssertTrue(app.staticTexts["Edited version"].waitForNonExistence(timeout: 4), "Second tap did not stop the audition")
        app.swipeDown(velocity: .fast)
        XCTAssertTrue(app.buttons["saveButton"].waitForExistence(timeout: 5))
        snapshot("review-after-audition")
    }

    /// Bug-hunt #1: a restored pause stays kept when the intensity changes.
    func testKeptPauseSurvivesIntensityChange() throws {
        launch(autorun: "01_talk_1080p30.mp4")
        try waitForReview(timeout: 120)
        skipAdBreakIfShown(doubleTap: false)
        app.buttons["reviewCutsButton"].tap()
        let toggle = app.switches["cutToggle_0"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        sleep(1)
        app.swipeDown(velocity: .fast)
        XCTAssertTrue(app.buttons["Tight"].waitForExistence(timeout: 5))
        app.buttons["Tight"].tap()
        sleep(2)
        XCTAssertTrue(app.buttons["Tight"].isSelected, "Tight tap did not apply")
        app.buttons["reviewCutsButton"].tap()
        sleep(1)
        snapshot("tight-after-keep")
        let kept = app.switches.allElementsBoundByIndex.filter { ($0.value as? String) == "0" }
        XCTAssertFalse(kept.isEmpty, "The kept pause was lost when switching to Tight")
        app.swipeDown(velocity: .fast)
    }

    /// Bug-hunt #4: Save right after Share reuses the export and shows a busy state, never a dead button.
    func testShareThenSaveShowsBusyThenSaved() throws {
        launch(autorun: "01_talk_1080p30.mp4")
        try waitForReview(timeout: 120)
        skipAdBreakIfShown(doubleTap: false)
        app.buttons["Share"].tap()
        let sheet = app.otherElements["ActivityListView"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 60))
        sheet.swipeDown(velocity: .fast)
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 10))
        app.buttons["saveButton"].tap()
        snapshot("save-after-share-0s")
        app.tap()
        XCTAssertTrue(app.buttons["Saved to Photos"].waitForExistence(timeout: 60), "Save after Share did not finish")
        snapshot("save-after-share-done")
        dismissRatingPromptIfShown()
    }

    /// Bug-hunt #6: leave the app long enough for iOS to end the background grace period mid-export.
    func testBackgroundExportExpiryMessage() throws {
        launch(autorun: "06_long_20min.mp4")
        try waitForReview(timeout: 600)
        skipAdBreakIfShown(doubleTap: false)
        app.buttons["saveButton"].tap()
        sleep(2)
        app.tap()
        sleep(2)
        XCUIDevice.shared.press(.home)
        sleep(70)
        app.activate()
        sleep(3)
        snapshot("export-after-long-background")
        let saved = app.buttons["Saved to Photos"].exists
        let stopped = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'in the background'")).firstMatch.exists
        XCTAssertTrue(saved || stopped || isExportOverlayShown, "No outcome after a long background")
        if !saved, !stopped {
            XCTAssertTrue(app.buttons["Saved to Photos"].waitForExistence(timeout: 300), "Export never finished after returning")
        }
    }

    func testHoldToCompare() throws {
        launch(autorun: "01_talk_1080p30.mp4")
        try waitForReview(timeout: 120)
        skipAdBreakIfShown(doubleTap: false)
        let hold = app.buttons["holdOriginalButton"]
        XCTAssertTrue(hold.waitForExistence(timeout: 5), "Hold-to-compare control missing")
        snapshot("compare-before")
        hold.press(forDuration: 2.5)
        snapshot("compare-after-release")
        tapRepeatedly(hold, times: 3)
        XCTAssertTrue(app.buttons["saveButton"].isHittable)
    }

    func testDoubleTapSaveThenShare() throws {
        // 4K HEVC: the 1080p fixture exports and saves in ~1 s on device, before Share can land mid-export.
        launch(autorun: "02_4k_hevc60.mp4")
        try waitForReview(timeout: 120)
        skipAdBreakIfShown(doubleTap: false)
        let save = app.buttons["saveButton"]
        tapRepeatedly(save, times: 3)
        app.tap() // first save: lets the interruption monitor answer the Photos prompt
        let share = app.buttons["Share"]
        let busyAtShare = isExportOverlayShown
        if share.exists { share.tap() } // while exporting: must be ignored
        let saved = app.buttons["Saved to Photos"]
        XCTAssertTrue(saved.waitForExistence(timeout: 120), "Save did not finish")
        snapshot("double-save")
        dismissRatingPromptIfShown()
        let sheet = app.otherElements["ActivityListView"]
        if busyAtShare {
            XCTAssertFalse(sheet.exists, "Share sheet opened during save")
        } else if sheet.exists {
            sheet.swipeDown(velocity: .fast) // Share after a finished save is allowed
        }
    }

    func testDoubleTapShareThenCancel() throws {
        launch(autorun: "01_talk_1080p30.mp4")
        try waitForReview(timeout: 120)
        skipAdBreakIfShown(doubleTap: false)
        let share = app.buttons["Share"]
        XCTAssertTrue(share.waitForExistence(timeout: 5))
        tapRepeatedly(share, times: 2)
        let sheet = app.otherElements["ActivityListView"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 60), "Share sheet did not open")
        snapshot("share-sheet")
        let close = sheet.buttons.matching(NSPredicate(format: "label IN {'Close', 'Cancel', 'Kapat'}")).firstMatch
        if close.exists { close.tap() } else { sheet.swipeDown(velocity: .fast) }
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 10), "Share sheet did not close")
        XCTAssertTrue(app.buttons["saveButton"].waitForExistence(timeout: 10))
        sleep(1)
        XCTAssertTrue(app.buttons["saveButton"].isHittable, "Review not usable after cancelling share")
        snapshot("after-share-cancel")
    }

    func testDoubleTapNewVideoAndChooseVideo() throws {
        launch(autorun: "01_talk_1080p30.mp4")
        try waitForReview(timeout: 120)
        skipAdBreakIfShown(doubleTap: false)
        let newVideo = app.buttons["newVideoButton"]
        tapRepeatedly(newVideo, times: 2)
        let choose = app.buttons["chooseVideoButton"]
        XCTAssertTrue(choose.waitForExistence(timeout: 10))
        try assertStorageZero()
        app.navigationBars.buttons.firstMatch.tap()
        tapRepeatedly(choose, times: 3)
        let cells = app.images.matching(identifier: "PXGGridLayout-Info")
        // A late tap may land on a grid cell and pick a video, as it would for a user: both are fine.
        let working = app.buttons["Cancel"]
        _ = cells.firstMatch.waitForExistence(timeout: 20)
        snapshot("picker-after-triple-tap")
        if cells.firstMatch.exists {
            let cancel = app.buttons.matching(NSPredicate(format: "label IN {'Cancel', 'Vazgeç', 'İptal'}")).firstMatch
            if cancel.exists { cancel.tap() } else { app.swipeDown(velocity: .fast) }
            XCTAssertTrue(choose.waitForExistence(timeout: 10), "Home not back after cancelling picker")
        } else {
            XCTAssertTrue(working.exists || app.buttons["saveButton"].exists, "Neither picker nor processing after triple tap")
        }
    }

    func testPhotosPermissionDeniedShowsOpenSettings() throws {
        app.resetAuthorizationStatus(for: .photos)
        alertChoice = ["Don’t Allow", "Don't Allow", "İzin Verme"]
        launch(autorun: "01_talk_1080p30.mp4")
        try waitForReview(timeout: 120)
        skipAdBreakIfShown(doubleTap: false)
        app.buttons["saveButton"].tap()
        sleep(3)
        app.tap()
        let openSettings = app.buttons["Open Settings"]
        let shown = openSettings.waitForExistence(timeout: 30)
        snapshot("photos-denied-state")
        XCTAssertTrue(shown, "No Open Settings notice after denying Photos")
        snapshot("photos-denied")
        app.resetAuthorizationStatus(for: .photos)
    }

    func testLanguageSwitchMidReview() throws {
        launch(autorun: "01_talk_1080p30.mp4")
        try waitForReview(timeout: 120)
        skipAdBreakIfShown(doubleTap: false)
        let before = newLength()
        app.buttons["settingsButton"].tap()
        let picker = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'App language'")).firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 10), "Language picker missing")
        picker.tap()
        let german = app.buttons["Deutsch"]
        XCTAssertTrue(german.waitForExistence(timeout: 5))
        german.tap()
        snapshot("settings-de")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["saveButton"].waitForExistence(timeout: 10), "Review lost after language switch")
        snapshot("review-de")
        XCTAssertEqual(newLength(), before, "Plan changed after language switch")
    }

    func testDynamicTypeAccessibilityXXXL() throws {
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        launch(autorun: nil)
        XCTAssertTrue(app.buttons["chooseVideoButton"].waitForExistence(timeout: 15))
        snapshot("home-xxxl")
        XCTAssertTrue(app.buttons["chooseVideoButton"].isHittable, "Choose Video not hittable at XXXL")
        app.terminate()
        launch(autorun: "01_talk_1080p30.mp4")
        try waitForReview(timeout: 120)
        skipAdBreakIfShown(doubleTap: false)
        snapshot("review-xxxl")
        XCTAssertTrue(app.buttons["saveButton"].isHittable, "Save not hittable at XXXL")
    }

    func testAccessibilityAudit() throws {
        launch(autorun: nil)
        XCTAssertTrue(app.buttons["chooseVideoButton"].waitForExistence(timeout: 15))
        try audit("home")
        app.terminate()
        launch(autorun: "01_talk_1080p30.mp4")
        try waitForReview(timeout: 120)
        skipAdBreakIfShown(doubleTap: false)
        sleep(2)
        try audit("review")
        app.buttons["settingsButton"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["storageUsageRow"].waitForExistence(timeout: 10))
        try audit("settings")
    }

    // MARK: - Helpers

    /// User-style repeated taps on one spot; later taps hit whatever replaced the element.
    private func tapRepeatedly(_ element: XCUIElement, times: Int) {
        // Screen-absolute point: an element-relative coordinate re-resolves (and fails) once the element is gone.
        let frame = element.frame
        let point = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: frame.midX, dy: frame.midY))
        for _ in 0..<times { point.tap() }
    }

    private func launch(autorun file: String?) {
        if let file { app.launchEnvironment["CUTSENSE_AUTORUN_VIDEO_URL"] = "qa-run/\(file)" }
        app.launch()
    }

    private func reviewAndSave(_ file: String, expectCuts: Bool) throws {
        launch(autorun: file)
        try waitForReview(timeout: 300)
        skipAdBreakIfShown(doubleTap: false)
        snapshot("review-\(file)")
        if expectCuts {
            let summary = app.buttons["reviewCutsButton"].label
            XCTAssertFalse(summary.hasPrefix("0 ") || summary.contains("No cuts"), "\(file): no cuts found (\(summary))")
        }
        app.buttons["saveButton"].tap()
        app.tap()
        let saved = app.buttons["Saved to Photos"]
        XCTAssertTrue(saved.waitForExistence(timeout: 300), "\(file): save did not finish")
        snapshot("saved-\(file)")
        dismissRatingPromptIfShown()
    }

    /// Nothing or little to cut: either review (then save must work) or the no-speech failure.
    private func reviewOrNoSpeech(_ file: String) throws {
        launch(autorun: file)
        try waitForReviewOrFailure(timeout: 300)
        snapshot("outcome-\(file)")
        if app.buttons["saveButton"].exists {
            skipAdBreakIfShown(doubleTap: false)
            app.buttons["saveButton"].tap()
            app.tap()
            XCTAssertTrue(app.buttons["Saved to Photos"].waitForExistence(timeout: 300), "\(file): save did not finish")
            dismissRatingPromptIfShown()
        } else {
            XCTAssertTrue(failureText()?.contains("No speech") == true, "\(file): unexpected failure \(failureText() ?? "-")")
            try tapTryAgain()
        }
    }

    private func expectFailure(containing text: String?) throws {
        let title = app.staticTexts["This video couldn't be processed"]
        XCTAssertTrue(title.waitForExistence(timeout: 120), "No failed state")
        snapshot("failed")
        let message = failureText() ?? ""
        if let text { XCTAssertTrue(message.localizedCaseInsensitiveContains(text), "Failure message: \(message)") }
        XCTAssertFalse(message.isEmpty)
        try tapTryAgain()
    }

    private func tapTryAgain() throws {
        let again = app.buttons["Try Again"]
        XCTAssertTrue(again.waitForExistence(timeout: 5))
        tapRepeatedly(again, times: 2)
        XCTAssertTrue(app.buttons["chooseVideoButton"].waitForExistence(timeout: 10), "Try Again did not return home")
    }

    private func failureText() -> String? {
        let title = app.staticTexts["This video couldn't be processed"]
        guard title.exists else { return nil }
        // The message is the static text right below the title.
        let texts = app.staticTexts.allElementsBoundByIndex.filter { $0.frame.minY > title.frame.maxY }
        return texts.min { $0.frame.minY < $1.frame.minY }?.label
    }

    private func waitForReview(timeout: TimeInterval) throws {
        try waitForReviewOrFailure(timeout: timeout)
        XCTAssertTrue(app.buttons["saveButton"].exists, "Failed instead of review: \(failureText() ?? "-")")
    }

    private func waitForReviewOrFailure(timeout: TimeInterval) throws {
        let save = app.buttons["saveButton"]
        let failed = app.staticTexts["This video couldn't be processed"]
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if save.exists || failed.exists { return }
            _ = save.waitForExistence(timeout: 2)
        }
        snapshot("timeout")
        XCTFail("Neither review nor failure within \(Int(timeout)) s")
    }

    private var isExportOverlayShown: Bool {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Creating video'")).firstMatch.exists
    }

    private func assertStorageZero() throws {
        let settings = app.buttons["settingsButton"]
        XCTAssertTrue(settings.waitForExistence(timeout: 15))
        settings.tap()
        let row = app.descendants(matching: .any)["storageUsageRow"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        snapshot("storage")
        XCTAssertTrue(row.label.contains("Zero") || row.label.contains("0 "), "Storage row: \(row.label)")
    }

    private func skipAdBreakIfShown(doubleTap: Bool) {
        let skip = app.buttons["skipAdButton"]
        if skip.waitForExistence(timeout: 5) {
            // The card slides in from the top; a tap during the transition resolves to {-1,-1} and is lost.
            _ = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: skip)], timeout: 2)
            skip.tap()
            if doubleTap, skip.exists { skip.tap() }
        }
        // A Skip tap that lands as the 3-2-1 countdown ends is too late: the full-screen ad opens (by design).
        // The test ad's "Close Advertisement" stays disabled until its end card, which has its own enabled Close.
        let save = app.buttons["saveButton"]
        let close = app.buttons.matching(NSPredicate(format: "(label CONTAINS[c] 'close' OR label CONTAINS[c] 'kapat') AND isEnabled == true"))
        let deadline = Date().addingTimeInterval(45)
        var shot = false
        while Date() < deadline, !(save.exists && save.isHittable) {
            if !shot, close.firstMatch.exists { snapshot("ad-presented"); shot = true }
            if let button = close.allElementsBoundByIndex.first(where: { $0.isHittable }) { button.tap() }
            sleep(1)
        }
        let balanced = app.buttons["Balanced"]
        if balanced.exists, !balanced.isSelected { balanced.tap(); sleep(1) }
    }

    private func dismissRatingPromptIfShown() {
        for source in [app!, springboard] {
            let notNow = source.buttons["Not Now"]
            if notNow.waitForExistence(timeout: 2) { notNow.tap(); return }
        }
    }

    private func newLength() -> String {
        app.staticTexts.matching(NSPredicate(format: "label MATCHES '^[0-9]+:[0-9]{2}$'")).allElementsBoundByIndex.map(\.label).joined(separator: "|")
    }

    private func audit(_ name: String) throws {
        snapshot("audit-\(name)")
        var issues: [String] = []
        try app.performAccessibilityAudit { issue in
            issues.append("\(issue.auditType.rawValue) | \(issue.compactDescription) | \(issue.element?.label ?? "-")")
            return true // collect, don't fail: reviewed by hand
        }
        let attachment = XCTAttachment(string: issues.joined(separator: "\n"))
        attachment.name = "audit-\(name)-issues"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func snapshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
