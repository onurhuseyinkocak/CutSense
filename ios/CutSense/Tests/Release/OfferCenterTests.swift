import XCTest
@testable import CutSense

@MainActor
final class OfferCenterTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var clock = Date(timeIntervalSince1970: 1_800_000_000)
    private var offerable = true
    private var foreground = true

    override func setUp() async throws {
        suiteName = "OfferCenterTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        clock = Date(timeIntervalSince1970: 1_800_000_000)
        offerable = true
        foreground = true
        UserDefaults.standard.removeObject(forKey: ProEntitlement.key)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func makeCenter() -> OfferCenter {
        OfferCenter(defaults: defaults, now: { [unowned self] in self.clock }, canOffer: { [unowned self] in self.offerable },
                    isForeground: { [unowned self] in self.foreground })
    }

    private func advance(_ seconds: TimeInterval) { clock = clock.addingTimeInterval(seconds) }

    private func finishOnboarding(_ center: OfferCenter, purchased: Bool = false) -> Date {
        center.noteOnboardingFinished(purchased: purchased)
        return clock
    }

    func testFlashStartsAt600AndLasts900() {
        let center = makeCenter()
        let finished = finishOnboarding(center)
        XCTAssertNil(center.active)
        XCTAssertEqual(center.pendingStart, finished.addingTimeInterval(600))
        advance(599)
        center.refresh()
        XCTAssertNil(center.active)
        advance(1)
        center.refresh()
        XCTAssertEqual(center.active, .init(kind: .flash, endsAt: finished.addingTimeInterval(1_500)))
        XCTAssertNil(center.pendingStart)
        advance(899)
        center.refresh()
        XCTAssertNotNil(center.active)
        advance(1)
        center.refresh()
        XCTAssertNil(center.active)
        XCTAssertNil(center.pendingStart)
    }

    func testOncePerInstall() {
        let center = makeCenter()
        _ = finishOnboarding(center)
        advance(1_500)
        center.refresh()                       // first foreground after the start: opens now
        XCTAssertNotNil(center.active)
        advance(900)
        center.refresh()
        XCTAssertNil(center.active)
        _ = finishOnboarding(center)
        XCTAssertNil(center.pendingStart)
        advance(600)
        center.refresh()
        XCTAssertNil(center.active)
        let reopened = makeCenter()
        reopened.noteOnboardingFinished(purchased: false)
        XCTAssertNil(reopened.pendingStart)
    }

    func testSecondFinishDoesNotReArmOrShift() {
        let center = makeCenter()
        let finished = finishOnboarding(center)
        advance(300)
        _ = finishOnboarding(center)
        XCTAssertEqual(center.pendingStart, finished.addingTimeInterval(600))
    }

    func testPurchaseAtFinishSchedulesNothing() {
        let center = makeCenter()
        _ = finishOnboarding(center, purchased: true)
        XCTAssertNil(center.pendingStart)
        advance(600)
        center.refresh()
        XCTAssertNil(center.active)
    }

    func testProAtFinishSchedulesNothing() {
        UserDefaults.standard.set(true, forKey: ProEntitlement.key)
        defer { UserDefaults.standard.removeObject(forKey: ProEntitlement.key) }
        let center = makeCenter()
        _ = finishOnboarding(center)
        XCTAssertNil(center.pendingStart)
    }

    func testRelaunchWhilePendingActiveAndAfter() {
        let finished = finishOnboarding(makeCenter())
        advance(100)
        XCTAssertEqual(makeCenter().pendingStart, finished.addingTimeInterval(600))
        advance(600)                           // first seen 700 s after finish
        XCTAssertEqual(makeCenter().active, .init(kind: .flash, endsAt: finished.addingTimeInterval(1_600)))
        advance(800)
        XCTAssertNotNil(makeCenter().active)
        advance(100)
        XCTAssertNil(makeCenter().active)
        advance(-100)                          // back inside the window, within tolerance: stays over
        XCTAssertNil(makeCenter().active)
    }

    func testOpensOnFirstForegroundAfterStartAndLasts900() {
        let center = makeCenter()
        let finished = finishOnboarding(center)
        foreground = false
        advance(2_000)                         // start passed while the app was away
        center.refresh()
        XCTAssertNil(center.active)
        XCTAssertNil(center.pendingStart)
        XCTAssertNil(makeCenter().active)      // cold launch in the background does not open it either
        foreground = true
        center.refresh()
        XCTAssertEqual(center.active, .init(kind: .flash, endsAt: finished.addingTimeInterval(2_900)))
        advance(899)
        center.refresh()
        XCTAssertNotNil(center.active)
        advance(1)
        center.refresh()
        XCTAssertNil(center.active)
    }

    func testDoesNotReopenAfterWindow() {
        let center = makeCenter()
        _ = finishOnboarding(center)
        advance(600)
        center.refresh()
        XCTAssertNotNil(center.active)
        advance(900)
        center.refresh()
        XCTAssertNil(center.active)
        foreground = false
        advance(5_000)
        center.refresh()
        foreground = true
        center.refresh()
        XCTAssertNil(center.active)
        XCTAssertNil(makeCenter().active)
        XCTAssertTrue(defaults.bool(forKey: OfferCenter.Key.opened))
    }

    func testBackgroundedDuringWindowStillExpiresByRealTime() {
        let center = makeCenter()
        let finished = finishOnboarding(center)
        advance(600)
        center.refresh()
        XCTAssertEqual(center.active, .init(kind: .flash, endsAt: finished.addingTimeInterval(1_500)))
        foreground = false
        advance(300)
        center.refresh()
        XCTAssertNotNil(center.active)         // still live while away, same end time
        advance(600)
        center.refresh()
        XCTAssertNil(center.active)
        foreground = true
        center.refresh()
        XCTAssertNil(center.active)
    }

    func testProNeverSeesFlashOnForeground() {
        let center = makeCenter()
        _ = finishOnboarding(center)
        foreground = false
        advance(700)
        center.refresh()
        UserDefaults.standard.set(true, forKey: ProEntitlement.key)
        defer { UserDefaults.standard.removeObject(forKey: ProEntitlement.key) }
        foreground = true
        center.refresh()
        XCTAssertNil(center.active)
        XCTAssertFalse(center.takeAutoPresent())
        UserDefaults.standard.removeObject(forKey: ProEntitlement.key)
        XCTAssertNil(makeCenter().active)
    }

    func testProEndsActiveFlash() {
        let center = makeCenter()
        _ = finishOnboarding(center)
        advance(700)
        center.refresh()
        XCTAssertNotNil(center.active)
        UserDefaults.standard.set(true, forKey: ProEntitlement.key)
        defer { UserDefaults.standard.removeObject(forKey: ProEntitlement.key) }
        center.refresh()
        XCTAssertNil(center.active)
        UserDefaults.standard.removeObject(forKey: ProEntitlement.key)
        XCTAssertNil(makeCenter().active)
    }

    func testClockRollbackEndsActiveFlash() {
        let center = makeCenter()
        _ = finishOnboarding(center)
        advance(600)
        center.refresh()                       // opens at 600
        advance(400)
        center.refresh()
        advance(-100)                          // within tolerance
        center.refresh()
        XCTAssertNotNil(center.active)
        advance(-200)                          // 300 s behind the high-water mark
        center.refresh()
        XCTAssertNil(center.active)
        advance(300)
        XCTAssertNil(makeCenter().active)
    }

    func testClockRollbackCancelsPendingFlash() {
        let center = makeCenter()
        _ = finishOnboarding(center)
        advance(-300)
        center.refresh()
        XCTAssertNil(center.pendingStart)
        advance(1_000)
        center.refresh()
        XCTAssertNil(center.active)
    }

    func testAutoPresentOnlyOnceWhileActive() {
        let center = makeCenter()
        XCTAssertFalse(center.takeAutoPresent())
        _ = finishOnboarding(center)
        XCTAssertFalse(center.takeAutoPresent())   // pending
        advance(600)
        offerable = false
        XCTAssertFalse(center.takeAutoPresent())   // prices not loaded: flag not burnt
        offerable = true
        XCTAssertTrue(center.takeAutoPresent())
        XCTAssertFalse(center.takeAutoPresent())
        XCTAssertFalse(makeCenter().takeAutoPresent())
    }

    func testSaveOnlyCounts() {
        let center = makeCenter()
        center.noteSave()
        center.noteSave()
        XCTAssertEqual(defaults.integer(forKey: OfferCenter.Key.saves), 2)
        XCTAssertNil(center.active)
        XCTAssertNil(center.pendingStart)
    }

    func testUnitTestHostBypassesOnboarding() {
        XCTAssertTrue(OnboardingGate.bypass)
    }
}
