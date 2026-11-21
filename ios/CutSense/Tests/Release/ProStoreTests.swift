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
