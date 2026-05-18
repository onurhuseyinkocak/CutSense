import SwiftUI

@main
struct CutSenseApp: App {
    @State private var authManager = AuthManager()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(authManager)
                .task {
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
}
