import SwiftUI
import StoreKit

struct PaywallScreen: View {
    @Environment(\.dismiss) private var dismiss
    @State private var store = SubscriptionManager.shared
    @State private var isPurchasing = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 32) {
                        // Header
                        VStack(spacing: 12) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 44))
                                .foregroundStyle(.yellow)

                            Text("CutSense Pro")
                                .font(.largeTitle.bold())
                                .foregroundStyle(.white)

                            Text("Unlimited exports. No watermark.\nOn-device AI editing, always private.")
                                .font(.subheadline)
                                .foregroundStyle(.gray)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 40)

                        // Features
                        VStack(alignment: .leading, spacing: 14) {
                            featureRow("Unlimited exports per month", icon: "infinity")
                            featureRow("No watermark on videos", icon: "xmark.rectangle")
                            featureRow("Premium captions and sound design", icon: "waveform")
                            featureRow("Tech influencer edit style", icon: "bolt.fill")
                            featureRow("100% on-device — your data stays yours", icon: "lock.shield.fill")
                        }
                        .padding(.horizontal, 8)

                        // Products
                        if !store.products.isEmpty {
                            VStack(spacing: 12) {
                                ForEach(store.products.sorted { $0.price < $1.price }, id: \.id) { product in
                                    productButton(product)
                                }
                            }
                        } else {
                            switch store.productLoadState {
                            case .idle, .loading, .loaded:
                                ProgressView().tint(.white)
                            case .failed(let message):
                                VStack(spacing: 12) {
                                    Text(message)
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                        .multilineTextAlignment(.center)

                                    Button("Retry", systemImage: "arrow.clockwise") {
                                        Task { await store.loadProducts() }
                                    }
                                    .buttonStyle(.borderedProminent)
                                }
                            }
                        }

                        if let productLoadError = store.productLoadState.errorMessage,
                           !store.products.isEmpty {
                            Text(productLoadError)
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .multilineTextAlignment(.center)
                        }

                        if let error = errorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }

                        // Restore + terms
                        VStack(spacing: 8) {
                            Button("Restore Purchases") {
                                Task {
                                    switch await store.restorePurchases() {
                                    case .restored:
                                        dismiss()
                                    case .noActiveSubscription:
                                        errorMessage = "No active subscription was found for this Apple ID."
                                    case .failed(let message):
                                        errorMessage = message
                                    }
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.gray)

                            Text("Payment charged to Apple ID. Subscription auto-renews unless cancelled 24h before period end.")
                                .font(.caption2)
                                .foregroundStyle(.gray.opacity(0.6))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 16)
                        }
                        .padding(.bottom, 32)
                    }
                    .padding(.horizontal, 24)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.gray)
                    }
                }
            }
            .task {
                await store.loadProducts()
                await store.checkSubscriptionStatus()
                if store.isPro { dismiss() }
            }
        }
    }

    private func featureRow(_ text: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.yellow)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.white)
        }
    }

    private func productButton(_ product: Product) -> some View {
        let isYearly = product.id == SubscriptionManager.yearlyID
        return Button {
            Task {
                isPurchasing = true
                errorMessage = nil
                do {
                    let success = try await store.purchase(product)
                    if success { dismiss() }
                } catch {
                    errorMessage = error.localizedDescription
                }
                isPurchasing = false
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(isYearly ? "Yearly" : "Weekly")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(product.displayPrice + (isYearly ? "/year" : "/week"))
                        .font(.subheadline)
                        .foregroundStyle(.gray)
                }
                Spacer()
                if isYearly {
                    Text("BEST VALUE")
                        .font(.caption2.bold())
                        .foregroundStyle(.black)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.yellow)
                        .clipShape(Capsule())
                }
            }
            .padding()
            .background(isYearly ? Color.yellow.opacity(0.12) : Color.white.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isYearly ? Color.yellow.opacity(0.5) : Color.white.opacity(0.1), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .disabled(isPurchasing)
    }
}
