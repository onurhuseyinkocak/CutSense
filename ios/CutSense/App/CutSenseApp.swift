import SwiftUI
import AVFoundation

@main
struct CutSenseApp: App {
    @State private var authManager = AuthManager()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(authManager)
                .task {
                    Self.configurePlaybackAudioSession()
                    await CutSenseDebugBootstrap.configureOnLaunch()
                    await SubscriptionManager.shared.checkSubscriptionStatus()
                }
                .onOpenURL { url in
                    guard url.pathExtension == "cutsensetemplate" else { return }
                    let count = CustomTemplateStore.shared.importFile(at: url)
                    #if DEBUG
                    print("[CutSense] Imported \(count) template(s) from \(url.lastPathComponent)")
                    #endif
                }
        }
    }

    private static func configurePlaybackAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback)
            try session.setActive(true)
        } catch {
            #if DEBUG
            print("[CutSense] Playback audio session failed: \(error.localizedDescription)")
            #endif
        }
    }
}
