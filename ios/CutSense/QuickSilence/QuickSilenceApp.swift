import SwiftUI
import AVFoundation

@main
struct QuickSilenceApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        WorkFiles.sweepAtLaunch()
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                QuickSilenceView()
            }
            .modifier(DebugScreenClamp())
            .task {
                try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
                // Pro first: AdMobService.isEnabled reads the cached entitlement, so refresh it before ads start.
                await ProStore.shared.refresh()
                ProStore.shared.start()
                AdMobService.start()
            }
            .onChange(of: scenePhase) { _, phase in
                // A launch-time product load failure would otherwise hide every Pro entry point all session.
                guard phase == .active, ProStore.shared.product == nil else { return }
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
