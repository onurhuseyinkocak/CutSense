import SwiftUI
import AVFoundation

@main
struct QuickSilenceApp: App {
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage(OnboardingGate.key) private var onboardingDone = false
    private var showsMain: Bool { onboardingDone || OnboardingGate.bypass }

    init() {
        OnboardingGate.applyDebugHooks()
        WorkFiles.sweepAtLaunch()
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                if showsMain {
                    NavigationStack {
                        QuickSilenceView()
                    }
                    .transition(.opacity)
                } else {
                    OnboardingView {
                        withAnimation(.easeInOut(duration: 0.45)) { onboardingDone = true }
                    }
                    .transition(.opacity)
                }
            }
            .modifier(DebugScreenClamp())
            .task(id: showsMain) {
                try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
                #if DEBUG // QA-SEED: env CUTSENSE_QA_SEED_PHOTOS=1 imports Documents/qa/* into Photos
                await DebugQASeed.seedPhotosIfRequested()
                #endif
                // Pro first: AdMobService.isEnabled reads the cached entitlement, so refresh it before ads start.
                await ProStore.shared.refresh()
                ProStore.shared.start()
                OfferCenter.shared.refresh()
                // UMP consent waits until onboarding is done.
                if showsMain { AdMobService.start() }
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                OfferCenter.shared.refresh()
                // A launch-time product load failure would otherwise hide every Pro entry point all session.
                guard ProStore.shared.product == nil || ProStore.shared.offerProduct == nil
                        || ProStore.shared.welcomeProduct == nil else { return }
                Task { await ProStore.shared.loadProduct() }
            }
        }
    }
}

/// DEBUG only: CUTSENSE_CLAMP_16E=1 squeezes the UI into an iPhone 16e safe area (390 x 763 pt)
/// so layout fit can be checked on the only allowed simulator.
private struct DebugScreenClamp: ViewModifier {
    func body(content: Content) -> some View {
        #if DEBUG
        if ProcessInfo.processInfo.environment["CUTSENSE_CLAMP_16E"] == "1" {
            content
                .frame(width: 390, height: 763)
                .border(.red)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.ignoresSafeArea())
        } else {
            content
        }
        #else
        content
        #endif
    }
}
