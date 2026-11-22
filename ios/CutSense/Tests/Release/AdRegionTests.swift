import XCTest
@testable import CutSense

final class AdRegionTests: XCTestCase {
    func testTurkishStorefrontIsTurkey() {
        XCTAssertTrue(AdRegion.isTurkey(storefrontCountryCode: "TUR", localeRegion: "US"))
    }

    func testOtherStorefrontWinsOverTurkishLocale() {
        XCTAssertFalse(AdRegion.isTurkey(storefrontCountryCode: "USA", localeRegion: "TR"))
    }

    func testFallsBackToLocaleWithoutStorefront() {
        XCTAssertTrue(AdRegion.isTurkey(storefrontCountryCode: nil, localeRegion: "TR"))
        XCTAssertFalse(AdRegion.isTurkey(storefrontCountryCode: nil, localeRegion: "DE"))
        XCTAssertFalse(AdRegion.isTurkey(storefrontCountryCode: nil, localeRegion: nil))
    }
}
