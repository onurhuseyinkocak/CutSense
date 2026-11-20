import SwiftUI
import UIKit
import GoogleMobileAds
import UserMessagingPlatform

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

@MainActor
enum AdMobService {
    private static let consentTimeout: Duration = .seconds(8)
    private static var configureTask: Task<Void, Never>?
    private static var didStartSDK = false

    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
            && ProcessInfo.processInfo.environment["CUTSENSE_DISABLE_ADS"] != "1"
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
            await gatherConsent()
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
                    box.resume(true)
                } catch {
                    #if DEBUG
                    print("[AdMob] Consent form failed: \(error.localizedDescription)")
                    #endif
                    box.resume(true)
                }
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
                host.banner.load(Request())
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

/// Bottom-anchored adaptive banner sized to the available width.
struct AdBannerSlot: View {
    var body: some View {
        GeometryReader { proxy in
            let size = largeAnchoredAdaptiveBanner(width: max(proxy.size.width, 320))
            AdBannerView(adSize: size)
                .frame(width: size.size.width, height: size.size.height)
                .frame(maxWidth: .infinity)
        }
        .frame(height: largeAnchoredAdaptiveBanner(width: 375).size.height)
        .accessibilityLabel("Advertisement")
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
                request: Request()
            )
            guard loadToken == token, isLoading else { return }
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
