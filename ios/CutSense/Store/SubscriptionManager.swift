import StoreKit

@MainActor
@Observable
final class SubscriptionManager {
    static let shared = SubscriptionManager()

    // Product IDs — must match App Store Connect
    static let weeklyID = "com.cutsense.app.pro.weekly"
    static let yearlyID = "com.cutsense.app.pro.yearly"

    private(set) var products: [Product] = []
    #if DEBUG
    private(set) var isPro = true
    #else
    private(set) var isPro = false
    #endif
    private(set) var currentSubscription: StoreKit.Transaction?

    /// Monthly export count for free tier (resets each calendar month)
    private(set) var exportsThisMonth: Int = 0

    private let exportsKey = "cutsense_exports_month"
    private let exportsMonthKey = "cutsense_exports_month_id"

    static let freeExportLimit = 3

    @ObservationIgnored
    private var updateTask: Task<Void, Never>?

    private init() {
        loadExportCount()
        updateTask = Task { @MainActor [weak self] in
            for await result in StoreKit.Transaction.updates {
                guard let self else { return }
                if let transaction = try? result.payloadValue {
                    await self.handleVerified(transaction)
                }
            }
        }
    }

    // MARK: - Public API

    func loadProducts() async {
        do {
            products = try await Product.products(for: [
                Self.weeklyID,
                Self.yearlyID
            ])
        } catch {
            #if DEBUG
            print("[Store] Failed to load products: \(error)")
            #endif
        }
    }

    func purchase(_ product: Product) async throws -> Bool {
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            if let transaction = try? verification.payloadValue {
                await handleVerified(transaction)
                return true
            }
            return false
        case .userCancelled:
            return false
        case .pending:
            return false
        @unknown default:
            return false
        }
    }

    func restorePurchases() async {
        try? await AppStore.sync()
        await checkSubscriptionStatus()
    }

    func checkSubscriptionStatus() async {
        var foundActive = false
        for await result in StoreKit.Transaction.currentEntitlements {
            if let transaction = try? result.payloadValue {
                if transaction.productID == Self.weeklyID || transaction.productID == Self.yearlyID {
                    if transaction.revocationDate == nil {
                        foundActive = true
                        currentSubscription = transaction
                    }
                }
            }
        }
        isPro = foundActive
        if !foundActive {
            currentSubscription = nil
        }
    }

    /// Whether user can export (pro = always, free = under limit)
    var canExport: Bool {
        isPro || exportsThisMonth < Self.freeExportLimit
    }

    /// Remaining free exports this month
    var remainingFreeExports: Int {
        max(0, Self.freeExportLimit - exportsThisMonth)
    }

    /// Call after successful export
    func recordExport() {
        guard !isPro else { return }
        exportsThisMonth += 1
        saveExportCount()
    }

    // MARK: - Private

    private func handleVerified(_ transaction: StoreKit.Transaction) async {
        await transaction.finish()
        await checkSubscriptionStatus()
    }

    private func loadExportCount() {
        let currentMonth = currentMonthID()
        let storedMonth = UserDefaults.standard.string(forKey: exportsMonthKey) ?? ""
        if storedMonth == currentMonth {
            exportsThisMonth = UserDefaults.standard.integer(forKey: exportsKey)
        } else {
            // New month — reset
            exportsThisMonth = 0
            UserDefaults.standard.set(currentMonth, forKey: exportsMonthKey)
            UserDefaults.standard.set(0, forKey: exportsKey)
        }
    }

    private func saveExportCount() {
        UserDefaults.standard.set(currentMonthID(), forKey: exportsMonthKey)
        UserDefaults.standard.set(exportsThisMonth, forKey: exportsKey)
    }

    private func currentMonthID() -> String {
        let now = Date()
        let cal = Calendar.current
        let year = cal.component(.year, from: now)
        let month = cal.component(.month, from: now)
        return "\(year)-\(month)"
    }
}
