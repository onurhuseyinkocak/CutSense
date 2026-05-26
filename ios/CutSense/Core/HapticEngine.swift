import UIKit

@MainActor
enum HapticEngine {
    private static let impactGen = UIImpactFeedbackGenerator(style: .medium)
    private static let lightGen = UIImpactFeedbackGenerator(style: .light)
    private static let heavyGen = UIImpactFeedbackGenerator(style: .heavy)
    private static let selectionGen = UISelectionFeedbackGenerator()
    private static let notificationGen = UINotificationFeedbackGenerator()

    static func tap() {
        lightGen.prepare()
        lightGen.impactOccurred()
    }

    static func impact() {
        impactGen.prepare()
        impactGen.impactOccurred()
    }

    static func heavy() {
        heavyGen.prepare()
        heavyGen.impactOccurred()
    }

    static func select() {
        selectionGen.prepare()
        selectionGen.selectionChanged()
    }

    static func success() {
        notificationGen.prepare()
        notificationGen.notificationOccurred(.success)
    }

    static func error() {
        notificationGen.prepare()
        notificationGen.notificationOccurred(.error)
    }

    static func warning() {
        notificationGen.prepare()
        notificationGen.notificationOccurred(.warning)
    }
}
