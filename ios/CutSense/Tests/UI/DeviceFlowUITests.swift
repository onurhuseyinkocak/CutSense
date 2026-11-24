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
        // No `-cut_intensity` here: the argument domain overrides @AppStorage writes, so level taps bounced back.
        app.launchArguments += ["-app_language", "en", "-AppleLanguages", "(en)", "-onboarding_done_v1", "YES",
                               "-finetune_active", "NO"]
        // Clean offer state: a flash left due by an earlier test opens on the first foreground and covers the screen.
        app.launchEnvironment["CUTSENSE_RESET_ONBOARDING"] = "1"
        let env = ProcessInfo.processInfo.environment
        for key in ["CUTSENSE_AUTORUN_VIDEO_URL", "CUTSENSE_FORCE_PRO", "CUTSENSE_FORCE_PREVIEW_FALLBACK", "CUTSENSE_DISABLE_ADS", "CUTSENSE_QA_SEED_PHOTOS"] {
            if let value = env[key] { app.launchEnvironment[key] = value }
        }
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

    /// Autorun (file copied into Documents) → review → restore one cut → save to Photos.
    func testAutorunReviewRestoreSave() throws {
        app.launch()
        try reviewRestoreSave()
    }

    /// Real picker path: Photos → the owner's clip → review → save.
    /// TEST_RUNNER_QA_PICK_LABEL=<text in the cell label> picks another video (labels follow the system language).
    func testPickFromPhotosAndSave() throws {
        app.launch()
        try pickFromPhotos(ProcessInfo.processInfo.environment["QA_PICK_LABEL"])
        try reviewRestoreSave(shareAndOpenPhotos: true)
    }

    private func pickFromPhotos(_ label: String?) throws {
        let choose = app.buttons["chooseVideoButton"]
        XCTAssertTrue(choose.waitForExistence(timeout: 15))
        choose.tap()
        let cells = app.images.matching(identifier: "PXGGridLayout-Info")
        XCTAssertTrue(cells.firstMatch.waitForExistence(timeout: 20), "Photos picker did not show any item")
        snapshot("picker")
        let predicate = label.map { NSPredicate(format: "label CONTAINS %@", $0) }
            ?? NSPredicate(format: "label CONTAINS 'dört dakika otuz dört' OR label CONTAINS[c] '4 minutes, 34'")
        let clip = cells.matching(predicate).firstMatch
        // Picker cells live in another process and never report isHittable: check the frame instead,
        // clear of the picker's top bar and bottom toolbar.
        let visible = app.windows.firstMatch.frame.insetBy(dx: 0, dy: 140)
        func onScreen() -> Bool { clip.exists && visible.contains(CGPoint(x: clip.frame.midX, y: clip.frame.midY)) }
        // The grid opens at the newest item (bottom); older ones are above.
        for _ in 0..<40 where !onScreen() { app.swipeDown(velocity: .slow) }
        for _ in 0..<40 where !onScreen() { app.swipeUp(velocity: .slow) }
        print("QA-PICK want=\(label ?? "owner 4:34") found=\(clip.exists) frame=\(clip.exists ? clip.frame : .zero) label=\(clip.exists ? clip.label : "-")")
        XCTAssertTrue(onScreen(), "Video \(label ?? "owner 4:34") not found in the picker")
        snapshot("picker-clip")
        clip.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    /// One fixture seeded into Photos by DebugQASeed (copy it to Documents/qa/ first), picked as the newest item.
    /// TEST_RUNNER_QA_EXPECT = review | nospeech | noaudio | unreadable.
    func testSeededFixtureViaPicker() throws {
        let expect = ProcessInfo.processInfo.environment["QA_EXPECT"] ?? "review"
        app.launchEnvironment["CUTSENSE_QA_SEED_PHOTOS"] = "1"
        app.launch()
        let choose = app.buttons["chooseVideoButton"]
        XCTAssertTrue(choose.waitForExistence(timeout: 30))
        sleep(4) // seeding runs in the app's launch task
        choose.tap()
        let cells = app.images.matching(identifier: "PXGGridLayout-Info")
        XCTAssertTrue(cells.firstMatch.waitForExistence(timeout: 20))
        snapshot("picker-seeded")
        cells.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let save = app.buttons["saveButton"]
        let failed = app.staticTexts["This video couldn't be processed"]
        let deadline = Date().addingTimeInterval(300)
        while Date() < deadline, !save.exists, !failed.exists { _ = save.waitForExistence(timeout: 2) }
        snapshot("seeded-outcome")
        switch expect {
        case "review":
            XCTAssertTrue(save.exists, "Seeded fixture did not reach review")
            let skip = app.buttons["skipAdButton"]
            if skip.waitForExistence(timeout: 5) { skip.tap() }
            save.tap()
            app.tap()
            XCTAssertTrue(app.buttons["Saved to Photos"].waitForExistence(timeout: 300), "Seeded fixture save did not finish")
            snapshot("seeded-saved")
        default:
            XCTAssertTrue(failed.exists, "Expected a failure (\(expect))")
        }
    }

    /// Real-video metrics: TEST_RUNNER_CUTSENSE_AUTORUN_VIDEO_URL=qa-run/<file>. Prints one "QA-REAL" line;
    /// the Balanced export stays in the app's tmp until the next launch so it can be pulled for review.
    func testRealVideoMetrics() throws {
        let started = Date()
        app.launch()
        let save = app.buttons["saveButton"]
        let failed = app.staticTexts["This video couldn't be processed"]
        let deadline = Date().addingTimeInterval(900)
        while Date() < deadline, !save.exists, !failed.exists { _ = save.waitForExistence(timeout: 1) }
        var metrics = ["analyze=\(Int(Date().timeIntervalSince(started)))s"]
        guard save.exists else {
            snapshot("real-failed")
            XCTFail("No review: \(app.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " / "))")
            return
        }
        skipAdBreakIfShown()
        let percent = app.staticTexts.matching(NSPredicate(format: "label MATCHES '^[0-9]{1,3}%$'")).firstMatch
        for level in ["Tight", "Hardcore", "Balanced"] {
            let segment = app.buttons[level]
            if !segment.isSelected { segment.tap() }
            sleep(2)
            metrics.append("\(level): \(percent.label) \(app.buttons["reviewCutsButton"].label) new=\(segment.value as? String ?? "?")")
            snapshot("real-\(level)")
        }
        save.tap()
        app.tap() // Photos permission prompt, if any
        let exportStart = Date()
        XCTAssertTrue(app.buttons["Saved to Photos"].waitForExistence(timeout: 900), "Save did not finish")
        metrics.append("export+save=\(Int(Date().timeIntervalSince(exportStart)))s")
        snapshot("real-saved")
        dismissRatingPromptIfShown()
        app.buttons["historyButton"].tap()
        sleep(2)
        snapshot("real-history")
        print("QA-REAL " + metrics.joined(separator: " | "))
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

    private func reviewRestoreSave(shareAndOpenPhotos: Bool = false) throws {
        let save = app.buttons["saveButton"]
        XCTAssertTrue(save.waitForExistence(timeout: 600), "Review screen never appeared")
        skipAdBreakIfShown()
        let balanced = app.buttons["Balanced"]
        if balanced.exists, !balanced.isSelected { balanced.tap(); sleep(2) }
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

        if shareAndOpenPhotos { try exploreReview() }

        save.tap()
        app.tap() // lets the interruption monitor handle the Photos permission alert
        let saved = app.buttons["Saved to Photos"]
        XCTAssertTrue(saved.waitForExistence(timeout: 600), "Save did not finish")
        snapshot("saved")
        dismissRatingPromptIfShown()

        if shareAndOpenPhotos {
            // Share reuses the finished export; the sheet must open and close cleanly.
            app.buttons["Share"].tap()
            let sheet = app.otherElements["ActivityListView"]
            XCTAssertTrue(sheet.waitForExistence(timeout: 120), "Share sheet did not open after save")
            snapshot("share-after-save")
            sheet.swipeDown(velocity: .fast)
            XCTAssertTrue(sheet.waitForNonExistence(timeout: 10))
            let openPhotos = app.buttons["openPhotosButton"]
            XCTAssertTrue(openPhotos.waitForExistence(timeout: 5), "Open Photos missing after save")
            openPhotos.tap()
            let photos = XCUIApplication(bundleIdentifier: "com.apple.mobileslideshow")
            XCTAssertTrue(photos.wait(for: .runningForeground, timeout: 10), "Photos did not open")
            sleep(2)
            snapshot("photos-opened")
            app.activate()
        }

        let newVideo = app.buttons["newVideoButton"]
        XCTAssertTrue(newVideo.waitForExistence(timeout: 10))
        newVideo.tap()
        // A restored cut is a manual change: New Video asks first.
        let discard = app.buttons["Discard and start new"]
        if discard.waitForExistence(timeout: 3) { snapshot("discard-dialog"); discard.tap() }
        snapshot("after-new-video-0s")
        let home = app.buttons["chooseVideoButton"].waitForExistence(timeout: 10)
        snapshot("after-new-video-10s")
        XCTAssertTrue(home, "New Video did not return to the home screen")
    }

    /// Owner's clip: kept pause survives Tight (bug-hunt #1), audition Before/After rows, hold-to-compare.
    private func exploreReview() throws {
        let tight = app.buttons["Tight"]
        XCTAssertTrue(tight.waitForExistence(timeout: 5))
        let cutsBefore = app.buttons["reviewCutsButton"].label
        tight.tap()
        let replanned = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@", cutsBefore),
                                                                        object: app.buttons["reviewCutsButton"])], timeout: 3) == .completed
        snapshot("owner-tight")
        XCTAssertTrue(replanned, "Tight did not re-plan (still \(cutsBefore))")
        app.buttons["reviewCutsButton"].tap()
        let row = app.buttons["cutRow_0"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        sleep(1)
        snapshot("owner-tight-cuts")
        let kept = app.switches.allElementsBoundByIndex.filter { ($0.value as? String) == "0" }
        XCTAssertFalse(kept.isEmpty, "Kept pause lost after switching to Tight")
        row.tap()
        sleep(1)
        snapshot("owner-audition-before")
        app.buttons["auditionAfter"].tap()
        app.buttons["cutRow_1"].tap()
        XCTAssertTrue(app.staticTexts["Edited version"].waitForExistence(timeout: 4), "After mode overlay missing")
        snapshot("owner-audition-after")
        app.buttons["cutRow_1"].tap()
        app.swipeDown(velocity: .fast)
        let hold = app.buttons["holdOriginalButton"]
        XCTAssertTrue(hold.waitForExistence(timeout: 5), "Hold-to-compare missing")
        hold.press(forDuration: 2)
        snapshot("owner-after-hold")
        XCTAssertTrue(app.buttons["saveButton"].isHittable)
    }

    private func skipAdBreakIfShown() {
        let skip = app.buttons["skipAdButton"]
        if skip.waitForExistence(timeout: 6) {
            _ = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: skip)], timeout: 2)
            if skip.exists && skip.isHittable { skip.tap() }  // the break may end on its own meanwhile
        }
        // A full-screen ad (if the countdown already elapsed): its "Close Advertisement" stays disabled until the end card.
        let save = app.buttons["saveButton"]
        let close = app.buttons.matching(NSPredicate(format: "(label CONTAINS[c] 'close' OR label CONTAINS[c] 'kapat') AND isEnabled == true"))
        let deadline = Date().addingTimeInterval(45)
        while Date() < deadline, !(save.exists && save.isHittable) {
            // Zero-frame ad web elements throw on isHittable: filter them out first.
            if let button = close.allElementsBoundByIndex.first(where: { $0.frame.width > 0 && $0.isHittable }) { snapshot("ad-close"); button.tap() }
            sleep(1)
        }
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
