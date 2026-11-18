import Foundation

enum AdMobIDs {
    static let applicationID = "ca-app-pub-6644397387275334~9083790273"
    static let bannerAdUnitID = "ca-app-pub-6644397387275334/7251833854"
    static let nativeAdUnitID = "ca-app-pub-6644397387275334/7112233050"
    static let rewardedInterstitialAdUnitID = "ca-app-pub-6644397387275334/8425314721"

    static let testBannerAdUnitID = "ca-app-pub-3940256099942544/2435281174"
    static let testNativeAdUnitID = "ca-app-pub-3940256099942544/3986624511"
    static let testRewardedInterstitialAdUnitID = "ca-app-pub-3940256099942544/6978759866"

    static var usesTestAds: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    static var activeBannerAdUnitID: String {
        usesTestAds ? testBannerAdUnitID : bannerAdUnitID
    }

    static var activeNativeAdUnitID: String {
        usesTestAds ? testNativeAdUnitID : nativeAdUnitID
    }

    static var activeRewardedInterstitialAdUnitID: String {
        usesTestAds ? testRewardedInterstitialAdUnitID : rewardedInterstitialAdUnitID
    }
}
