import SwiftUI

// MARK: - Widget Color Palette

/// Matches MajorTomTheme colors from the main app.
/// Widget extension runs in a separate process, so we duplicate the palette here.
enum WidgetColors {
    static let background = Color(red: 0.04, green: 0.04, blue: 0.07)     // #0a0a12
    static let surface = Color(red: 0.10, green: 0.10, blue: 0.13)
    static let surfaceElevated = Color(red: 0.15, green: 0.15, blue: 0.18)

    static let accent = Color(red: 0.95, green: 0.65, blue: 0.10)         // Claude amber #f2a619
    static let accentSubtle = Color(red: 0.95, green: 0.65, blue: 0.10).opacity(0.2)

    static let textPrimary = Color.white
    static let textSecondary = Color(red: 0.53, green: 0.53, blue: 0.67)  // #8888aa
    static let textTertiary = Color(white: 0.40)

    static let statusGreen = Color(red: 0.29, green: 0.85, blue: 0.50)    // #4ade80
    static let statusYellow = Color(red: 0.96, green: 0.62, blue: 0.04)   // #f59e0b
    static let statusRed = Color(red: 0.97, green: 0.44, blue: 0.44)      // #f87171

    /// Gradient for the widget background.
    static var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [
                background,
                Color(red: 0.06, green: 0.06, blue: 0.10),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
