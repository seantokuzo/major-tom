import SwiftUI

// MARK: - Haptic View Modifiers

extension View {
    /// Trigger a haptic on tap gesture. Wraps content in a simultaneous tap gesture.
    func hapticOnTap(
        _ style: UIImpactFeedbackGenerator.FeedbackStyle = .light
    ) -> some View {
        self.sensoryFeedback(.impact(flexibility: .solid, intensity: feedbackIntensity(for: style)), trigger: false)
            .modifier(HapticTapModifier(style: style))
    }

    /// Trigger a haptic when the view appears.
    func hapticOnAppear(
        _ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium
    ) -> some View {
        self.onAppear {
            HapticService.impact(style)
        }
    }

    /// Selection haptic — ideal for tab switches, picker changes.
    func hapticSelection() -> some View {
        self.modifier(HapticSelectionModifier())
    }

    /// Trigger success haptic feedback.
    func hapticOnSuccess(trigger: Bool) -> some View {
        self.sensoryFeedback(.success, trigger: trigger)
    }

    /// Trigger error haptic feedback.
    func hapticOnError(trigger: Bool) -> some View {
        self.sensoryFeedback(.error, trigger: trigger)
    }

    /// Trigger warning haptic feedback.
    func hapticOnWarning(trigger: Bool) -> some View {
        self.sensoryFeedback(.warning, trigger: trigger)
    }

    /// Impact haptic with configurable intensity.
    func hapticImpact(
        _ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium,
        trigger: Bool
    ) -> some View {
        self.onChange(of: trigger) { _, newValue in
            if newValue {
                HapticService.impact(style)
            }
        }
    }

    /// Convenience: light impact for pull-to-refresh completion.
    func hapticOnRefresh(trigger: Bool) -> some View {
        self.hapticImpact(.light, trigger: trigger)
    }

    /// Convenience: medium impact for sheet present/dismiss.
    func hapticOnSheet(isPresented: Bool) -> some View {
        self.onChange(of: isPresented) { _, _ in
            HapticService.impact(.medium)
        }
    }

    private func feedbackIntensity(
        for style: UIImpactFeedbackGenerator.FeedbackStyle
    ) -> Double {
        switch style {
        case .light: return 0.4
        case .medium: return 0.6
        case .heavy: return 0.9
        case .rigid: return 1.0
        case .soft: return 0.3
        @unknown default: return 0.5
        }
    }
}

// MARK: - Haptic Tap Modifier

private struct HapticTapModifier: ViewModifier {
    let style: UIImpactFeedbackGenerator.FeedbackStyle

    func body(content: Content) -> some View {
        content
            .simultaneousGesture(
                TapGesture().onEnded {
                    HapticService.impact(style)
                }
            )
    }
}

// MARK: - Haptic Selection Modifier

/// Fires a selection haptic whenever the provided value changes.
private struct HapticSelectionModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .simultaneousGesture(
                TapGesture().onEnded {
                    HapticService.selection()
                }
            )
    }
}

// MARK: - Haptic Button Style

/// A ButtonStyle that fires haptic feedback on press.
struct HapticButtonStyle: ButtonStyle {
    var feedbackStyle: UIImpactFeedbackGenerator.FeedbackStyle = .light

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed {
                    HapticService.impact(feedbackStyle)
                }
            }
    }
}

extension ButtonStyle where Self == HapticButtonStyle {
    /// Convenience: `.haptic` button style with light impact.
    static var haptic: HapticButtonStyle { HapticButtonStyle() }

    /// Convenience: `.haptic` button style with custom feedback.
    static func haptic(
        _ style: UIImpactFeedbackGenerator.FeedbackStyle
    ) -> HapticButtonStyle {
        HapticButtonStyle(feedbackStyle: style)
    }
}
