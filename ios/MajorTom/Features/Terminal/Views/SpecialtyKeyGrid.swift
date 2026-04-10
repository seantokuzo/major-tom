import SwiftUI

/// Expanded grid of specialty keys that slides up when the user taps the
/// keyboard toggle on the NativeKeybar.
///
/// Replaces the iOS software keyboard with a grid containing function keys,
/// Ctrl combos, tmux shortcuts, symbols, and navigation keys. Mirrors the
/// PWA's specialty keyboard mode from Shell.svelte.
///
/// Tapping a key sends its bytes and optionally dismisses the grid (only
/// sticky modifiers keep the grid open).
struct SpecialtyKeyGrid: View {
    /// Callback to send raw bytes to the terminal.
    let onSendBytes: (String) -> Void

    /// Callback to dismiss the grid.
    let onDismiss: () -> Void

    /// The keys to display in the grid.
    var keys: [KeySpec] = KeyLibrary.defaultGrid

    /// Sticky Ctrl state (shared with keybar conceptually, but local here).
    @State private var ctrlArmed = false
    @State private var altArmed = false

    /// Adaptive grid columns -- 6 columns on compact width.
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 6)

    var body: some View {
        VStack(spacing: 0) {
            // Drag handle
            RoundedRectangle(cornerRadius: 2)
                .fill(MajorTomTheme.Colors.textTertiary)
                .frame(width: 36, height: 4)
                .padding(.top, MajorTomTheme.Spacing.sm)
                .padding(.bottom, MajorTomTheme.Spacing.xs)

            // Scrollable key grid
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(keys) { key in
                        GridKeyButton(
                            spec: key,
                            isArmed: armedState(for: key),
                            action: { handleKeyTap(key) }
                        )
                    }
                }
                .padding(.horizontal, MajorTomTheme.Spacing.sm)
                .padding(.bottom, MajorTomTheme.Spacing.md)
            }
            .frame(maxHeight: 280)
        }
        .background(MajorTomTheme.Colors.surface)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: MajorTomTheme.Radius.medium,
                topTrailingRadius: MajorTomTheme.Radius.medium
            )
        )
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Key Handling

    private func armedState(for key: KeySpec) -> Bool {
        switch key.id {
        case "ctrl": return ctrlArmed
        case "alt": return altArmed
        default: return false
        }
    }

    private func handleKeyTap(_ key: KeySpec) {
        HapticService.buttonTap()

        // Modifier toggle -- don't dismiss
        if key.isModifier {
            switch key.id {
            case "ctrl":
                ctrlArmed.toggle()
            case "alt":
                altArmed.toggle()
            default:
                break
            }
            return
        }

        // Regular key -- apply armed modifiers
        var bytes = key.bytes

        if ctrlArmed && bytes.count == 1 {
            if let char = bytes.uppercased().unicodeScalars.first,
               char.value >= 65,
               char.value <= 90,
               let controlScalar = UnicodeScalar(char.value - 64) {
                bytes = String(controlScalar)
            }
        }

        if altArmed && !bytes.isEmpty {
            bytes = "\u{1b}" + bytes
        }

        // Disarm modifiers after use
        ctrlArmed = false
        altArmed = false

        onSendBytes(bytes)
        onDismiss()
    }
}

// MARK: - Grid Key Button

/// Individual key button in the specialty grid. Slightly larger than the
/// keybar buttons to be easier to tap accurately.
private struct GridKeyButton: View {
    let spec: KeySpec
    let isArmed: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                // Label
                Text(spec.label)
                    .font(.system(size: fontSize, weight: .semibold, design: .monospaced))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                // Description subtitle for Ctrl combos
                if let desc = spec.description, spec.group == .ctrl {
                    Text(desc)
                        .font(.system(size: 8, weight: .regular))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .foregroundStyle(MajorTomTheme.Colors.textTertiary)
                }
            }
            .foregroundStyle(foregroundColor)
            .frame(maxWidth: .infinity)
            .frame(height: cellHeight)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private var foregroundColor: Color {
        if isArmed {
            return MajorTomTheme.Colors.background
        }
        return MajorTomTheme.Colors.textPrimary
    }

    private var backgroundColor: Color {
        if isArmed {
            return MajorTomTheme.Colors.accent
        }
        // Color-code by group for visual grouping
        switch spec.group {
        case .ctrl:
            return Color(red: 0.18, green: 0.14, blue: 0.14) // subtle red tint
        case .tmux:
            return Color(red: 0.14, green: 0.17, blue: 0.14) // subtle green tint
        case .function:
            return Color(red: 0.14, green: 0.14, blue: 0.18) // subtle blue tint
        default:
            return MajorTomTheme.Colors.surfaceElevated
        }
    }

    private var fontSize: CGFloat {
        if spec.label.count > 3 { return 11 }
        if spec.label.count > 2 { return 12 }
        return 14
    }

    private var cellHeight: CGFloat {
        spec.group == .ctrl && spec.description != nil ? 44 : 36
    }
}
