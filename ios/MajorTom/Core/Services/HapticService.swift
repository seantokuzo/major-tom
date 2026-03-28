import UIKit

enum HapticService {
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }

    static func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(type)
    }

    static func selection() {
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
    }

    // Convenience methods for common interactions
    static func approve() { notification(.success) }
    static func deny() { notification(.error) }
    static func skip() { impact(.light) }
    static func modeSwitch() { impact(.medium) }
    static func buttonTap() { impact(.light) }
    static func celebrate() { notification(.success) }
}
