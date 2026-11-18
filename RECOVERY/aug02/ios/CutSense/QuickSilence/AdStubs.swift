import SwiftUI

// MARK: - AdMob stubs for QuickSilence module
// These are minimal no-op implementations so QuickSilenceView compiles
// without the GoogleMobileAds SDK. Replace with real AdMob integration later.

@MainActor
enum AdMobService {
    static var isEnabled: Bool { false }
    static var isPrivacyOptionsRequired: Bool { false }
    static func start() {}
    static func waitForConsentConfiguration() async {}
    static func presentPrivacyOptions() async {}
    static var rootViewController: UIViewController? { nil }
}

@MainActor
enum RewardedInterstitialAdResult: Sendable {
    case unavailable
    case presented(rewarded: Bool)

    var wasPresented: Bool {
        if case .presented = self { return true }
        return false
    }
}

@MainActor
final class RewardedInterstitialAdController: ObservableObject {
    @Published private(set) var isReady = false

    func preload() {}
    func load() async {}
    func showIfAvailable() async -> RewardedInterstitialAdResult { .unavailable }
}

struct AdBannerSlot: View {
    var body: some View { EmptyView() }
}

struct NativeAdCard: View {
    var body: some View { EmptyView() }
}
