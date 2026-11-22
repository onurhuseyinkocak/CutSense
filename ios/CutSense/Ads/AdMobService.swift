import SwiftUI
import UIKit
import GoogleMobileAds
import UserMessagingPlatform
import StoreKit

private final class AdMobBoolContinuationBox: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Bool, Never>?

    init(_ continuation: CheckedContinuation<Bool, Never>) {
        self.continuation = continuation
    }

    @discardableResult
    func resume(_ value: Bool) -> Bool {
        lock.lock()
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        guard let continuation else { return false }
        continuation.resume(returning: value)
        return true
    }
}

/// KVKK: every ad request from Türkiye is sent as non-personalized.
enum AdRegion {
    /// Either signal is enough: a Turkish storefront (ISO 3166-1 alpha-3) or a TR device region.
    static func isTurkey(storefrontCountryCode: String?, localeRegion: String?) -> Bool {
        storefrontCountryCode == "TUR" || localeRegion == "TR"
    }
}

@MainActor
enum AdMobService {
    private static let consentTimeout: Duration = .seconds(8)
    private static var configureTask: Task<Void, Never>?
    private static var didStartSDK = false
    private static var requestsNonPersonalizedAds = AdRegion.isTurkey(
        storefrontCountryCode: nil,
        localeRegion: Locale.current.region?.identifier
    )

    /// Every banner, native and rewarded request goes through here.
    static func makeRequest() -> Request {
        let request = Request()
        if requestsNonPersonalizedAds {
            let extras = Extras()
            extras.additionalParameters = ["npa": "1"]
            request.register(extras)
        }
        return request
    }

    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
            && ProcessInfo.processInfo.environment["CUTSENSE_DISABLE_ADS"] != "1"
            && !ProEntitlement.isPro
    }

    static func start() {
        guard isEnabled else { return }
        configureIfNeeded()
    }

    static var canRequestAds: Bool {
        isEnabled && ConsentInformation.shared.canRequestAds && didStartSDK
    }

    static var isPrivacyOptionsRequired: Bool {
        ConsentInformation.shared.privacyOptionsRequirementStatus == .required
    }

    @discardableResult
    static func prepareForAdRequest() async -> Bool {
        guard isEnabled else { return false }
        configureIfNeeded()
        await configureTask?.value
        return canRequestAds
    }

    static func waitForConsentConfiguration() async {
        guard isEnabled else { return }
        configureIfNeeded()
        await configureTask?.value
    }

    static func presentPrivacyOptions() async {
        guard isEnabled else { return }
        do {
            try await ConsentForm.presentPrivacyOptionsForm(from: rootViewController)
            startMobileAdsIfAllowed()
        } catch {
            #if DEBUG
            print("[AdMob] Privacy options failed: \(error.localizedDescription)")
            #endif
        }
    }

    private static func configureIfNeeded() {
        guard configureTask == nil else { return }
        configureTask = Task { @MainActor in
            let storefrontTask = Task { await Storefront.current?.countryCode }
            await gatherConsent()
            // Don't let a stuck StoreKit lookup block every ad; fall back to the device region.
            let storefrontCountry = await withTaskGroup(of: String?.self) { group in
                group.addTask { await storefrontTask.value }
                group.addTask { try? await Task.sleep(for: consentTimeout); return nil }
                let first = await group.next() ?? nil
                group.cancelAll()
                return first
            }
            requestsNonPersonalizedAds = AdRegion.isTurkey(
                storefrontCountryCode: storefrontCountry,
                localeRegion: Locale.current.region?.identifier
            )
            startMobileAdsIfAllowed()
        }
    }

    private static func gatherConsent() async {
        let parameters = RequestParameters()

        let updated = await requestConsentInfoUpdate(parameters: parameters)
        guard updated else { return }

        let formCompleted = await loadAndPresentConsentFormIfRequired()
        if !formCompleted {
            #if DEBUG
            print("[AdMob] Consent form timed out; continuing without blocking processing.")
            #endif
        }
    }

    private static func requestConsentInfoUpdate(parameters: RequestParameters) async -> Bool {
        await withCheckedContinuation { continuation in
            let box = AdMobBoolContinuationBox(continuation)
            ConsentInformation.shared.requestConsentInfoUpdate(with: parameters) { error in
                Task { @MainActor in
                    if let error {
                        #if DEBUG
                        print("[AdMob] Consent info update failed: \(error.localizedDescription)")
                        #endif
                    }
                    box.resume(error == nil)
                }
            }
            Task { @MainActor in
                try? await Task.sleep(for: consentTimeout)
                guard box.resume(false) else { return }
                #if DEBUG
                print("[AdMob] Consent info update timed out; continuing without blocking processing.")
                #endif
            }
        }
    }

    private static func loadAndPresentConsentFormIfRequired() async -> Bool {
        await withCheckedContinuation { continuation in
            let box = AdMobBoolContinuationBox(continuation)
            Task { @MainActor in
                do {
                    try await ConsentForm.loadAndPresentIfRequired(from: rootViewController)
                } catch {
                    #if DEBUG
                    print("[AdMob] Consent form failed: \(error.localizedDescription)")
                    #endif
                }
                // The form can outlive the timeout; start ads as soon as it is answered.
                startMobileAdsIfAllowed()
                box.resume(true)
            }
            Task { @MainActor in
                try? await Task.sleep(for: consentTimeout)
                box.resume(false)
            }
        }
    }

    private static func startMobileAdsIfAllowed() {
        guard isEnabled else { return }
        guard ConsentInformation.shared.canRequestAds else { return }
        guard !didStartSDK else { return }
        didStartSDK = true
        MobileAds.shared.requestConfiguration.setPublisherFirstPartyIDEnabled(false)

        #if DEBUG
        if AdMobIDs.usesTestAds {
            MobileAds.shared.requestConfiguration.testDeviceIdentifiers = [ "SIMULATOR" ]
        }
        #endif

        MobileAds.shared.start()
    }

    static var rootViewController: UIViewController? {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive }

        let window = scenes
            .flatMap(\.windows)
            .first { $0.isKeyWindow }

        return topViewController(from: window?.rootViewController)
    }

    /// True when a sheet (share sheet, Photos picker, alert) covers the app.
    static var hasPresentedContent: Bool {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let root = scenes.flatMap(\.windows).first { $0.isKeyWindow }?.rootViewController
        return root?.presentedViewController != nil
    }

    private static func topViewController(from root: UIViewController?) -> UIViewController? {
        if let presented = root?.presentedViewController {
            return topViewController(from: presented)
        }
        if let nav = root as? UINavigationController {
            return topViewController(from: nav.visibleViewController)
        }
        if let tab = root as? UITabBarController {
            return topViewController(from: tab.selectedViewController)
        }
        return root
    }
}

struct AdBannerView: UIViewRepresentable {
    let adSize: AdSize

    func makeUIView(context: Context) -> BannerHostView {
        let host = BannerHostView(adSize: adSize)
        context.coordinator.configure(host: host, adSize: adSize)
        return host
    }

    func updateUIView(_ host: BannerHostView, context: Context) {
        context.coordinator.configure(host: host, adSize: adSize)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, BannerViewDelegate {
        private weak var host: BannerHostView?
        private var loadTask: Task<Void, Never>?
        private var loadedAdUnitID: String?
        private var loadedSize: CGSize?

        @MainActor
        func configure(host: BannerHostView, adSize: AdSize) {
            self.host = host
            host.banner.delegate = self
            host.banner.rootViewController = AdMobService.rootViewController
            let sizeChanged = host.update(adSize: adSize)

            if sizeChanged {
                loadedSize = nil
            }

            guard AdMobService.isEnabled else { return }
            let adUnitID = AdMobIDs.activeBannerAdUnitID
            guard loadedAdUnitID != adUnitID || loadedSize != adSize.size else { return }

            loadTask?.cancel()
            loadTask = Task { @MainActor [weak self] in
                guard await AdMobService.prepareForAdRequest() else { return }
                guard let self, let host = self.host else { return }
                host.banner.adUnitID = adUnitID
                host.banner.rootViewController = AdMobService.rootViewController
                host.banner.load(AdMobService.makeRequest())
                self.loadedAdUnitID = adUnitID
                self.loadedSize = adSize.size
            }
        }

        func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) {
            #if DEBUG
            print("[AdMob] Banner failed: \(error.localizedDescription)")
            #endif
        }
    }
}

final class BannerHostView: UIView {
    let banner: BannerView

    private var widthConstraint: NSLayoutConstraint?
    private var heightConstraint: NSLayoutConstraint?

    init(adSize: AdSize) {
        banner = BannerView(adSize: adSize)
        super.init(frame: .zero)
        clipsToBounds = true
        backgroundColor = .clear

        banner.translatesAutoresizingMaskIntoConstraints = false
        banner.clipsToBounds = true
        addSubview(banner)

        widthConstraint = banner.widthAnchor.constraint(equalToConstant: adSize.size.width)
        heightConstraint = banner.heightAnchor.constraint(equalToConstant: adSize.size.height)
        NSLayoutConstraint.activate([
            banner.centerXAnchor.constraint(equalTo: centerXAnchor),
            banner.topAnchor.constraint(equalTo: topAnchor),
            widthConstraint,
            heightConstraint
        ].compactMap { $0 })
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(adSize: AdSize) -> Bool {
        let sizeChanged = banner.adSize.size != adSize.size
        widthConstraint?.constant = adSize.size.width
        heightConstraint?.constant = adSize.size.height
        return sizeChanged
    }
}

/// Bottom-anchored adaptive banner. `height` is also used as the content inset.
struct AdBannerSlot: View {
    static var adSize: AdSize {
        let width = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.screen.bounds.width }
            .first ?? 390
        return largeAnchoredAdaptiveBanner(width: width)
    }

    static var height: CGFloat { adSize.size.height }

    var body: some View {
        let size = Self.adSize
        AdBannerView(adSize: size)
            .frame(width: size.size.width, height: size.size.height)
            .frame(maxWidth: .infinity)
            .accessibilityLabel(appText(AppLanguage.current, "Reklam", "Advertisement"))
    }
}

/// Reward for watching a rewarded interstitial: no banner/native ads for 24 h
/// (stackable, capped at 72 h).
enum AdFreePass {
    private static let key = "ad_free_until"
    private static let grant: TimeInterval = 24 * 3600
    private static let cap: TimeInterval = 72 * 3600

    static var expiry: Date? {
        let value = UserDefaults.standard.double(forKey: key)
        guard value > 0 else { return nil }
        let date = Date(timeIntervalSince1970: value)
        return date > .now ? date : nil
    }

    static var isActive: Bool { expiry != nil }

    static func grantReward() {
        let base = max(expiry ?? .now, .now)
        let until = min(base.addingTimeInterval(grant), Date.now.addingTimeInterval(cap))
        UserDefaults.standard.set(until.timeIntervalSince1970, forKey: key)
    }
}

enum RewardedInterstitialAdResult: Sendable {
    case unavailable
    case presented(rewarded: Bool)

    var wasPresented: Bool {
        if case .presented = self { return true }
        return false
    }
}

/// Loads one rewarded interstitial at a time and presents it on demand.
/// `showIfAvailable` suspends until the ad is dismissed so processing can resume.
@MainActor
final class RewardedInterstitialAdController: NSObject, ObservableObject, FullScreenContentDelegate {
    @Published private(set) var isReady = false

    private var ad: RewardedInterstitialAd?
    private var isLoading = false
    private var loadToken = UUID()
    private var earnedReward = false
    private var dismissContinuation: CheckedContinuation<RewardedInterstitialAdResult, Never>?
    private static let loadTimeout: Duration = .seconds(10)

    func preload() {
        guard ad == nil, !isReady, !isLoading else { return }
        Task { await load() }
    }

    func load() async {
        guard AdMobService.isEnabled else { return }
        guard !isLoading else {
            // Another caller is loading; wait for it instead of starting a second request.
            while isLoading && !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
            }
            return
        }
        guard ad == nil else { return }
        guard await AdMobService.prepareForAdRequest() else { return }

        isLoading = true
        let token = UUID()
        loadToken = token
        let timeout = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.loadTimeout)
            guard let self, self.isLoading, self.loadToken == token else { return }
            self.isLoading = false
        }
        defer { timeout.cancel() }

        do {
            let loaded = try await RewardedInterstitialAd.load(
                with: AdMobIDs.activeRewardedInterstitialAdUnitID,
                request: AdMobService.makeRequest()
            )
            guard ad == nil else { return }
            loaded.fullScreenContentDelegate = self
            ad = loaded
            isReady = true
        } catch {
            #if DEBUG
            print("[AdMob] Rewarded interstitial failed to load: \(error.localizedDescription)")
            #endif
        }
        if loadToken == token { isLoading = false }
    }

    func showIfAvailable() async -> RewardedInterstitialAdResult {
        guard let ad, isReady, dismissContinuation == nil else { return .unavailable }
        guard let root = AdMobService.rootViewController else { return .unavailable }
        earnedReward = false
        isReady = false
        return await withCheckedContinuation { continuation in
            dismissContinuation = continuation
            ad.present(from: root) { [weak self] in
                self?.earnedReward = true
            }
        }
    }

    private func finish(presented: Bool) {
        ad = nil
        isReady = false
        let continuation = dismissContinuation
        dismissContinuation = nil
        continuation?.resume(returning: presented ? .presented(rewarded: earnedReward) : .unavailable)
        preload()
    }

    nonisolated func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        Task { @MainActor in self.finish(presented: true) }
    }

    nonisolated func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        Task { @MainActor in self.finish(presented: false) }
    }
}
