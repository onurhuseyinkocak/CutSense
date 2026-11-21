import UIKit

/// System share sheet for one exported file. `onFinish` runs once when the sheet closes
/// (shared, cancelled or failed), so the caller can delete the file.
@MainActor
enum ShareSheet {
    static func present(_ url: URL, onFinish: @escaping @MainActor () -> Void) {
        guard let root = AdMobService.rootViewController else {
            onFinish()
            return
        }
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in
            MainActor.assumeIsolated { onFinish() }
        }
        controller.popoverPresentationController?.sourceView = root.view
        root.present(controller, animated: true)
    }
}
