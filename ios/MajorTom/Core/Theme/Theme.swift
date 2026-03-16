import SwiftUI

// MARK: - Major Tom Design System

enum MajorTomTheme {

    // MARK: - Colors

    enum Colors {
        static let background = Color(red: 0.05, green: 0.05, blue: 0.07)
        static let surface = Color(red: 0.10, green: 0.10, blue: 0.13)
        static let surfaceElevated = Color(red: 0.15, green: 0.15, blue: 0.18)

        static let accent = Color(red: 0.95, green: 0.65, blue: 0.25) // Claude orange/amber
        static let accentSubtle = Color(red: 0.95, green: 0.65, blue: 0.25).opacity(0.2)

        static let allow = Color(red: 0.30, green: 0.85, blue: 0.45)
        static let deny = Color(red: 0.95, green: 0.30, blue: 0.30)
        static let skip = Color(red: 0.55, green: 0.55, blue: 0.60)

        static let textPrimary = Color.white
        static let textSecondary = Color(white: 0.65)
        static let textTertiary = Color(white: 0.40)

        static let userBubble = Color(red: 0.20, green: 0.35, blue: 0.55)
        static let assistantBubble = Color(red: 0.15, green: 0.15, blue: 0.20)
    }

    // MARK: - Typography

    enum Typography {
        static let codeFont = Font.system(.body, design: .monospaced)
        static let codeFontSmall = Font.system(.caption, design: .monospaced)

        static let title = Font.system(.title2, design: .default, weight: .bold)
        static let headline = Font.system(.headline, design: .default, weight: .semibold)
        static let body = Font.system(.body, design: .default)
        static let caption = Font.system(.caption, design: .default)
    }

    // MARK: - Spacing

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    // MARK: - Corner Radius

    enum Radius {
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 16
        static let pill: CGFloat = 100
    }
}

// MARK: - Glass Background Modifier

struct GlassBackground: ViewModifier {
    var cornerRadius: CGFloat = MajorTomTheme.Radius.medium

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

extension View {
    func glassBackground(cornerRadius: CGFloat = MajorTomTheme.Radius.medium) -> some View {
        modifier(GlassBackground(cornerRadius: cornerRadius))
    }
}
