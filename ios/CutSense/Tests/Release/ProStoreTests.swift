import XCTest
import StoreKit
import StoreKitTest
@testable import CutSense

@MainActor
final class ProStoreTests: XCTestCase {
    private var session: SKTestSession!

    override func setUp() async throws {
        executionTimeAllowance = 60
        session = try SKTestSession(configurationFileNamed: "Products")
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
        UserDefaults.standard.removeObject(forKey: ProEntitlement.key)
    }

    override func tearDown() async throws {
        session?.clearTransactions()
        session?.resetToDefaultState()
        session = nil
        UserDefaults.standard.removeObject(forKey: ProEntitlement.key)
    }

    func testProductLoadsFromConfiguration() async {
        let store = ProStore()
        await store.loadProduct()
        XCTAssertEqual(store.product?.id, ProStore.lifetimeID)
        XCTAssertEqual(store.product?.type, .nonConsumable)
        XCTAssertTrue(store.canOfferPro)
    }

    /// Buys through the SKTestSession control channel. On this machine (Xcode 26, iOS 26 simulator) every
    /// session control call logs SKInternalErrorDomain Code=3 and no transaction arrives, so only the purchase
    /// itself is tolerated (skip). Once a transaction arrives, every entitlement assertion runs un-suppressed.
    func testPurchaseUnlocksProAndClearingTransactionsLocksAgain() async throws {
        let store = ProStore()
        await store.loadProduct()
        XCTAssertNotNil(store.product)
        XCTAssertFalse(store.isPro)

        let box = ResultBox()
        let done = expectation(description: "buyProduct")
        Task {
            do { box.transaction = try await self.session.buyProduct(identifier: ProStore.lifetimeID) }
            catch { box.error = error }
            done.fulfill()
        }
        // XCTWaiter (not fulfillment(of:)) so a hung purchase is a skip, not a failure.
        _ = await XCTWaiter().fulfillment(of: [done], timeout: 20)
        guard let transaction = box.transaction else {
            throw XCTSkip("SKTestSession cannot purchase on this host: \(String(describing: box.error))")
        }
        await transaction.finish()
        await store.refresh()
        XCTAssertTrue(store.isPro)
        XCTAssertTrue(ProEntitlement.isPro)
        XCTAssertFalse(store.canOfferPro)

        session.clearTransactions()
        await store.refresh()
        XCTAssertFalse(store.isPro)
        XCTAssertFalse(ProEntitlement.isPro)
        XCTAssertTrue(store.canOfferPro)
    }

    func testOfferPriceRule() {
        func rule(_ offer: Decimal, _ regular: Decimal) -> ProStore.OfferPrices? {
            ProStore.offerPrices(offer: offer, offerDisplay: "o", regular: regular, regularDisplay: "r")
        }
        XCTAssertEqual(rule(Decimal(string: "3.99")!, Decimal(string: "7.99")!)?.percent, 50)
        XCTAssertEqual(rule(Decimal(string: "3.99")!, Decimal(string: "7.99")!),
                       ProStore.OfferPrices(offer: "o", regular: "r", percent: 50))
        XCTAssertEqual(rule(Decimal(string: "5.99")!, Decimal(string: "7.99")!)?.percent, 25)
        XCTAssertEqual(rule(9, 10)?.percent, 10)
        XCTAssertNil(rule(Decimal(string: "9.01")!, 10))   // 9.9% floors to 9
        XCTAssertNil(rule(10, 10))
        XCTAssertNil(rule(11, 10))
        XCTAssertNil(rule(0, 0))
    }

    /// On this host products come from the App Store sandbox (SKTestSession cannot load the local config, Code=3),
    /// so the offer SKU only resolves once it exists in App Store Connect; until then this skips.
    func testBothProductsLoadInOneCallWithOfferPrices() async throws {
        let store = ProStore()
        await store.loadProduct()
        XCTAssertEqual(store.product?.id, ProStore.lifetimeID)
        guard store.offerProduct != nil else {
            throw XCTSkip("\(ProStore.offerID) not served by the StoreKit backend on this host")
        }
        XCTAssertEqual(store.offerProduct?.id, ProStore.offerID)
        XCTAssertEqual(store.offerProduct?.type, .nonConsumable)
        XCTAssertEqual(store.offerPrices?.percent, 50)
        XCTAssertEqual(store.offerPrices?.regular, store.product?.displayPrice)
        XCTAssertEqual(store.offerPrices?.offer, store.offerProduct?.displayPrice)
    }

    func testWelcomeProductLoadsWithWelcomePrices() async throws {
        let store = ProStore()
        await store.loadProduct()
        guard store.welcomeProduct != nil else {
            throw XCTSkip("\(ProStore.welcomeID) not served by the StoreKit backend on this host")
        }
        XCTAssertEqual(store.welcomeProduct?.id, ProStore.welcomeID)
        XCTAssertEqual(store.welcomeProduct?.type, .nonConsumable)
        XCTAssertEqual(store.welcomePrices?.percent, 25)
        XCTAssertEqual(store.welcomePrices?.regular, store.product?.displayPrice)
        XCTAssertEqual(store.welcomePrices?.offer, store.welcomeProduct?.displayPrice)
    }

    func testMissingWelcomeProductHasNoWelcomePrices() async {
        let store = ProStore(welcomeID: "com.cutsense.app.does.not.exist")
        await store.loadProduct()
        XCTAssertNil(store.welcomeProduct)
        XCTAssertNil(store.welcomePrices)
        let outcome = await store.purchaseWelcome()
        XCTAssertEqual(outcome, .unavailable)
    }

    func testMissingOfferProductHasNoOfferPrices() async {
        let store = ProStore(offerID: "com.cutsense.app.does.not.exist")
        await store.loadProduct()
        XCTAssertNotNil(store.product)
        XCTAssertNil(store.offerProduct)
        XCTAssertNil(store.offerPrices)
        let outcome = await store.purchaseOffer()
        XCTAssertEqual(outcome, .unavailable)
    }

    func testMissingProductCannotBeOffered() async {
        let store = ProStore(productID: "com.cutsense.app.does.not.exist")
        await store.loadProduct()
        XCTAssertNil(store.product)
        XCTAssertFalse(store.canOfferPro)
        let outcome = await store.purchase()
        XCTAssertEqual(outcome, .unavailable)
    }
}

@MainActor
private final class ResultBox {
    var transaction: Transaction?
    var error: Error?
}
