import SwiftUI
import UIKit
import GoogleMobileAds

/// Native ad shown while a video is processing. Renders nothing until an ad loads.
struct NativeAdCard: View {
    @StateObject private var loader = NativeAdLoader()

    var body: some View {
        Group {
            if let ad = loader.nativeAd {
                NativeAdRepresentable(nativeAd: ad)
                    .frame(height: 236)
                    // Never above 12: a larger radius clips the SDK's AdChoices corner.
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .task { await loader.loadIfNeeded() }
    }
}

@MainActor
final class NativeAdLoader: NSObject, ObservableObject, NativeAdLoaderDelegate {
    @Published private(set) var nativeAd: NativeAd?
    private var adLoader: AdLoader?

    func loadIfNeeded() async {
        guard AdMobService.isEnabled, !AdFreePass.isActive, nativeAd == nil, adLoader == nil else { return }
        guard await AdMobService.prepareForAdRequest() else { return }
        let loader = AdLoader(
            adUnitID: AdMobIDs.activeNativeAdUnitID,
            rootViewController: AdMobService.rootViewController,
            adTypes: [.native],
            options: nil
        )
        loader.delegate = self
        adLoader = loader
        loader.load(Request())
    }

    nonisolated func adLoader(_ adLoader: AdLoader, didReceive nativeAd: NativeAd) {
        nonisolated(unsafe) let ad = nativeAd
        Task { @MainActor in self.nativeAd = ad }
    }

    nonisolated func adLoader(_ adLoader: AdLoader, didFailToReceiveAdWithError error: Error) {
        #if DEBUG
        print("[AdMob] Native ad failed: \(error.localizedDescription)")
        #endif
    }
}

private struct NativeAdRepresentable: UIViewRepresentable {
    let nativeAd: NativeAd

    func makeUIView(context: Context) -> NativeAdView {
        CutSenseNativeAdView()
    }

    func updateUIView(_ view: NativeAdView, context: Context) {
        (view as? CutSenseNativeAdView)?.populate(with: nativeAd)
    }
}

/// Programmatic layout: "Ad" badge, icon, headline, media, body, call to action.
/// The SDK places the AdChoices icon in a corner automatically.
private final class CutSenseNativeAdView: NativeAdView {
    private let badge = UILabel()
    private let icon = UIImageView()
    private let headline = UILabel()
    private let bodyLabel = UILabel()
    private let media = MediaView()
    private let cta = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(white: 23 / 255, alpha: 1)
        layer.borderWidth = 1
        layer.borderColor = UIColor.white.withAlphaComponent(0.1).cgColor
        layer.cornerRadius = 12
        layer.cornerCurve = .continuous

        badge.text = " \(appText(AppLanguage.current, "Reklam", "Ad")) "
        badge.font = .systemFont(ofSize: 10, weight: .bold)
        badge.textColor = .white
        badge.textAlignment = .center
        badge.layer.borderWidth = 1
        badge.layer.borderColor = UIColor.white.withAlphaComponent(0.5).cgColor
        badge.layer.cornerRadius = 8

        icon.contentMode = .scaleAspectFill
        icon.layer.cornerRadius = 6
        icon.clipsToBounds = true

        headline.font = .preferredFont(forTextStyle: .subheadline).withWeight(.semibold)
        headline.textColor = .white
        headline.numberOfLines = 1
        headline.adjustsFontForContentSizeCategory = true

        bodyLabel.font = .preferredFont(forTextStyle: .caption1)
        bodyLabel.textColor = UIColor(white: 163 / 255, alpha: 1)
        bodyLabel.numberOfLines = 2
        bodyLabel.adjustsFontForContentSizeCategory = true

        media.contentMode = .scaleAspectFill
        media.clipsToBounds = true

        var config = UIButton.Configuration.filled()
        config.baseBackgroundColor = .white
        config.baseForegroundColor = .black
        config.cornerStyle = .capsule
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
            var attributes = $0
            attributes.font = .systemFont(ofSize: 15, weight: .semibold)
            return attributes
        }
        cta.configuration = config
        cta.isUserInteractionEnabled = false // SDK handles the tap

        // Badge on the left; the SDK puts AdChoices in the top-right corner.
        let header = UIStackView(arrangedSubviews: [badge, icon, headline])
        header.spacing = 8
        header.alignment = .center
        let footer = UIStackView(arrangedSubviews: [bodyLabel, cta])
        footer.spacing = 10
        footer.alignment = .center
        let stack = UIStackView(arrangedSubviews: [header, media, footer])
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            icon.widthAnchor.constraint(equalToConstant: 28),
            icon.heightAnchor.constraint(equalToConstant: 28),
            badge.widthAnchor.constraint(greaterThanOrEqualToConstant: 26),
            badge.heightAnchor.constraint(equalToConstant: 16),
            cta.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            media.heightAnchor.constraint(greaterThanOrEqualToConstant: 120)
        ])
        cta.setContentHuggingPriority(.required, for: .horizontal)
        badge.setContentCompressionResistancePriority(.required, for: .horizontal)
        cta.setContentCompressionResistancePriority(.required, for: .horizontal)
        headline.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        iconView = icon
        headlineView = headline
        bodyView = bodyLabel
        mediaView = media
        callToActionView = cta
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func populate(with ad: NativeAd) {
        headline.text = ad.headline
        bodyLabel.text = ad.body
        bodyLabel.isHidden = ad.body == nil
        icon.image = ad.icon?.image
        icon.isHidden = ad.icon == nil
        media.mediaContent = ad.mediaContent
        cta.configuration?.title = ad.callToAction
        cta.isHidden = ad.callToAction == nil
        nativeAd = ad
    }
}

private extension UIFont {
    func withWeight(_ weight: UIFont.Weight) -> UIFont {
        let descriptor = fontDescriptor.addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: weight]])
        return UIFont(descriptor: descriptor, size: 0)
    }
}
