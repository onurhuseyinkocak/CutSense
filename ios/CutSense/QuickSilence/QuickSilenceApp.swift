import SwiftUI
import AVFoundation

@main
struct QuickSilenceApp: App {
    init() {
        QuickSilenceEngine.sweepTemporaryFiles()
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                QuickSilenceView()
            }
                .task {
                    try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
                    AdMobService.start()
                }
        }
    }
}
