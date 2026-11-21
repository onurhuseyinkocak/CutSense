import Foundation
import Observation
import StoreKit

/// Nonisolated read of the cached Pro flag, so ad gating can check it from any context.
enum ProEntitlement {
    static let key = "pro_unlocked"

    static var isPro: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["CUTSENSE_FORCE_PRO"] == "1" { return true }
        #endif
        return UserDefaults.standard.bool(forKey: key)
    }
}

@MainActor @Observable
final class ProStore {
    enum Outcome: Equatable, Sendable {
        case purchased, cancelled, pending, failed(String)
    }

    static let shared = ProStore()
    static let lifetimeID = "com.cutsense.app.pro.lifetime"

    private(set) var product: Product?
    private(set) var isPro: Bool = ProEntitlement.isPro
    var canOfferPro: Bool { product != nil && !isPro }

    private let productID: String
    @ObservationIgnored private var updatesTask: Task<Void, Never>?

    /// `productID` is injectable only so tests can simulate a product that fails to load.
    init(productID: String = ProStore.lifetimeID) {
        self.productID = productID
    }

    func start() {
        guard updatesTask == nil else { return }
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result { await transaction.finish() }
                await self?.refresh()
            }
        }
        Task {
            await loadProduct()
            await refresh()
        }
    }

    func loadProduct() async {
        product = try? await Product.products(for: [productID]).first
    }

    /// Rebuilds the flag from StoreKit; a refunded or revoked purchase drops out of currentEntitlements.
    func refresh() async {
        var owned = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == productID,
               transaction.revocationDate == nil {
                owned = true
            }
        }
        UserDefaults.standard.set(owned, forKey: ProEntitlement.key)
        isPro = ProEntitlement.isPro
    }

    func purchase() async -> Outcome {
        if product == nil { await loadProduct() }
        guard let product else { return .failed("Product unavailable") }
        do {
            switch try await product.purchase() {
            case .success(.verified(let transaction)):
                await transaction.finish()
                await refresh()
                return .purchased
            case .success(.unverified(_, let error)):
                return .failed(error.localizedDescription)
            case .pending:
                return .pending
            case .userCancelled:
                return .cancelled
            @unknown default:
                return .failed("Unknown purchase result")
            }
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    func restore() async {
        try? await AppStore.sync()
        await refresh()
    }
}
