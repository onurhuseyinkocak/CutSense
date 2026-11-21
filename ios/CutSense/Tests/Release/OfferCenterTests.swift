import XCTest
@testable import CutSense

@MainActor
final class OfferCenterTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var clock = Date(timeIntervalSince1970: 1_800_000_000)
    private var offerable = true

    override func setUp() async throws {
        suiteName = "OfferCenterTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        clock = Date(timeIntervalSince1970: 1_800_000_000)
        offerable = true
        UserDefaults.standard.removeObject(forKey: ProEntitlement.key)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func makeCenter() -> OfferCenter {
        OfferCenter(defaults: defaults, now: { [unowned self] in self.clock }, canOffer: { [unowned self] in self.offerable })
    }

    private func advance(_ seconds: TimeInterval) { clock = clock.addingTimeInterval(seconds) }

    func testFirstSaveStartsWelcome() {
        let center = makeCenter()
        XCTAssertNil(center.active)
        center.noteSave()
        XCTAssertEqual(center.active, .init(kind: .welcome, endsAt: clock.addingTimeInterval(86_400)))
    }

    func testNewInstanceSeesSameEnd() {
        let center = makeCenter()
        center.noteSave()
        advance(3_600)
        let reopened = makeCenter()
        XCTAssertEqual(reopened.active, center.active)
    }

    func testWelcomeEndsAfter24Hours() {
        let center = makeCenter()
        center.noteSave()
        advance(86_399)
        center.refresh()
        XCTAssertNotNil(center.active)
        advance(1)
        center.refresh()
        XCTAssertNil(center.active)
    }

    func testFlashNeedsSevenDaysAndThreeSaves() {
        let center = makeCenter()
        center.noteSave()                      // save 1: welcome
        advance(86_400)
        center.refresh()
        XCTAssertNil(center.active)
        center.noteSave()                      // save 2, day 1
        center.noteSave()                      // save 3, still < 7 days after welcome end
        XCTAssertNil(center.active)
        advance(7 * 86_400 - 1)
        center.noteSave()                      // save 4, 1 s short of the gap
        XCTAssertNil(center.active)
        advance(1)
        center.noteSave()
        XCTAssertEqual(center.active?.kind, .flash)
    }

    func testFlashNeedsThreeSavesEvenAfterGap() {
        let center = makeCenter()
        center.noteSave()
        advance(86_400 + 8 * 86_400)
        center.noteSave()                      // save 2 only
        XCTAssertNil(center.active)
        center.noteSave()                      // save 3
        XCTAssertEqual(center.active?.kind, .flash)
    }

    func testFlashLasts900SecondsAndNeverRepeats() {
        let center = makeCenter()
        center.noteSave()
        advance(86_400 + 7 * 86_400)
        center.noteSave()
        center.noteSave()
        let started = clock
        XCTAssertEqual(center.active, .init(kind: .flash, endsAt: started.addingTimeInterval(900)))
        advance(899)
        center.refresh()
        XCTAssertNotNil(center.active)
        advance(1)
        center.refresh()
        XCTAssertNil(center.active)
        advance(30 * 86_400)
        center.noteSave()
        center.noteSave()
        XCTAssertNil(center.active)
    }

    func testClockRollbackEndsOffer() {
        let center = makeCenter()
        center.noteSave()
        advance(1_000)
        center.refresh()
        advance(-100)                          // within tolerance
        center.refresh()
        XCTAssertNotNil(center.active)
        advance(-200)                          // 300 s behind the high-water mark
        center.refresh()
        XCTAssertNil(center.active)
        XCTAssertNil(makeCenter().active)
    }

    func testNoRightSpentWhileCannotOffer() {
        offerable = false
        let center = makeCenter()
        center.noteSave()
        XCTAssertNil(center.active)
        XCTAssertFalse(defaults.bool(forKey: OfferCenter.Key.welcomeDone))
        offerable = true
        center.noteSave()
        XCTAssertEqual(center.active?.kind, .welcome)
    }

    func testAutoPresentOnlyOnce() {
        let center = makeCenter()
        XCTAssertFalse(center.takeAutoPresent())
        center.noteSave()
        XCTAssertTrue(center.takeAutoPresent())
        XCTAssertFalse(center.takeAutoPresent())
        XCTAssertFalse(makeCenter().takeAutoPresent())
    }

    func testProOwnerEndsOffer() {
        let center = makeCenter()
        center.noteSave()
        UserDefaults.standard.set(true, forKey: ProEntitlement.key)
        defer { UserDefaults.standard.removeObject(forKey: ProEntitlement.key) }
        center.refresh()
        XCTAssertNil(center.active)
    }

    func testUnitTestHostBypassesOnboarding() {
        XCTAssertTrue(OnboardingGate.bypass)
    }
}
