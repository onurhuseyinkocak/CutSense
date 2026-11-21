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
        /// `failed(nil)` means no system message; the paywall shows its own localized text.
        case purchased, cancelled, pending, unavailable, failed(String?)
    }

    static let shared = ProStore()
    static let lifetimeID = "com.cutsense.app.pro.lifetime"
    static let offerID = "com.cutsense.app.pro.lifetime.offer"
    static let welcomeID = "com.cutsense.app.pro.lifetime.welcome"

    struct OfferPrices: Equatable, Sendable { let offer: String; let regular: String; let percent: Int }

    private(set) var product: Product?
    private(set) var offerProduct: Product?
    private(set) var welcomeProduct: Product?
    private(set) var isPro: Bool = ProEntitlement.isPro
    var canOfferPro: Bool { product != nil && !isPro }

    /// Flash prices: nil unless both products loaded and the offer is a real discount of at least 10% (floored).
    var offerPrices: OfferPrices? { prices(offerProduct, fake: OfferPrices(offer: "$3.99", regular: "$7.99", percent: 50)) }
    /// Onboarding welcome prices, same rule.
    var welcomePrices: OfferPrices? { prices(welcomeProduct, fake: OfferPrices(offer: "$5.99", regular: "$7.99", percent: 25)) }

    private func prices(_ discounted: Product?, fake: OfferPrices) -> OfferPrices? {
        guard let product, let discounted else {
            #if DEBUG
            if ProcessInfo.processInfo.environment["CUTSENSE_FAKE_PRICES"] == "1" { return fake }
            #endif
            return nil
        }
        return Self.offerPrices(offer: discounted.price, offerDisplay: discounted.displayPrice,
                                regular: product.price, regularDisplay: product.displayPrice)
    }

    /// The discount rule, separate from `Product` so it is testable without StoreKit.
    nonisolated static func offerPrices(offer: Decimal, offerDisplay: String,
                                        regular: Decimal, regularDisplay: String) -> OfferPrices? {
        guard regular > 0, offer < regular else { return nil }
        var raw = (1 - offer / regular) * 100
        var floored = Decimal()
        NSDecimalRound(&floored, &raw, 0, .down)
        let percent = NSDecimalNumber(decimal: floored).intValue
        guard percent >= 10 else { return nil }
        return OfferPrices(offer: offerDisplay, regular: regularDisplay, percent: percent)
    }

    private let productID: String
    private let offerID: String
    private let welcomeID: String
    @ObservationIgnored private var updatesTask: Task<Void, Never>?

    /// IDs are injectable only so tests can simulate a product that fails to load.
    init(productID: String = ProStore.lifetimeID, offerID: String = ProStore.offerID,
         welcomeID: String = ProStore.welcomeID) {
        self.productID = productID
        self.offerID = offerID
        self.welcomeID = welcomeID
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
            // Entitlements first (local, fast) so a returning owner never sees ad gating flip.
            await refresh()
            await loadProduct()
        }
    }

    func loadProduct() async {
        let products = (try? await Product.products(for: [productID, offerID, welcomeID])) ?? []
        product = products.first { $0.id == productID }
        offerProduct = products.first { $0.id == offerID }
        welcomeProduct = products.first { $0.id == welcomeID }
    }

    /// Rebuilds the flag from StoreKit; a refunded or revoked purchase drops out of currentEntitlements.
    func refresh() async {
        var owned = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               [productID, offerID, welcomeID].contains(transaction.productID),
               transaction.revocationDate == nil {
                owned = true
            }
        }
        UserDefaults.standard.set(owned, forKey: ProEntitlement.key)
        isPro = ProEntitlement.isPro
    }

    func purchase() async -> Outcome { await purchase(\.product) }
    func purchaseOffer() async -> Outcome { await purchase(\.offerProduct) }
    func purchaseWelcome() async -> Outcome { await purchase(\.welcomeProduct) }

    private func purchase(_ sku: KeyPath<ProStore, Product?>) async -> Outcome {
        // Every SKU unlocks the same entitlement; StoreKit would happily sell another one to an owner.
        await refresh()
        guard !isPro else { return .purchased }
        if self[keyPath: sku] == nil { await loadProduct() }
        return await buy(self[keyPath: sku])
    }

    private func buy(_ product: Product?) async -> Outcome {
        guard let product else { return .unavailable }
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
                return .failed(nil)
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
