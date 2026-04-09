import SwiftUI

/// Native SwiftUI keybar that sits above the iOS software keyboard.
///
/// Provides a scrollable row of specialty keys (Esc, Tab, Ctrl, arrows, etc.)
/// mirroring the PWA's MobileKeybar. Ctrl and Alt are sticky toggles: tap to
/// arm, next regular key press applies the modifier and disarms.
///
/// The trailing button toggles the `SpecialtyKeyGrid` overlay.
struct NativeKeybar: View {
    /// Callback to send raw bytes to the terminal web view.
    let onSendBytes: (String) -> Void

    /// Callback to toggle specialty grid visibility.
    let onToggleSpecialty: () -> Void

    /// Whether the specialty grid is currently showing.
    let specialtyGridVisible: Bool

    /// The keys to display in the accessory row.
    var keys: [KeySpec] = KeyLibrary.defaultBar

    /// Sticky modifier state: Ctrl is armed for the next keypress.
    @State private var ctrlArmed = false

    /// Sticky modifier state: Alt is armed for the next keypress.
    @State private var altArmed = false

    var body: some View {
        HStack(spacing: 0) {
            // Scrollable key row
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: MajorTomTheme.Spacing.xs) {
                    ForEach(keys) { key in
                        KeyButton(
                            spec: key,
                            isArmed: armedState(for: key),
                            action: { handleKeyTap(key) }
                        )
                    }
                }
                .padding(.horizontal, MajorTomTheme.Spacing.sm)
            }

            // Specialty grid toggle
            Button {
                HapticService.buttonTap()
                onToggleSpecialty()
            } label: {
                Image(systemName: specialtyGridVisible ? "keyboard.chevron.compact.down" : "keyboard")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(specialtyGridVisible ? MajorTomTheme.Colors.accent : MajorTomTheme.Colors.textSecondary)
                    .frame(width: 40, height: 36)
                    .contentShape(Rectangle())
            }
            .padding(.trailing, MajorTomTheme.Spacing.xs)
        }
        .frame(height: 44)
        .background(MajorTomTheme.Colors.surface)
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

        // Modifier toggle
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
            // Ctrl+letter -> ASCII control code
            let char = bytes.uppercased().unicodeScalars.first!
            if char.value >= 65 && char.value <= 90 { // A-Z
                bytes = String(UnicodeScalar(char.value - 64)!)
            }
        }

        if altArmed && !bytes.isEmpty {
            // Alt wraps with ESC prefix
            bytes = "\u{1b}" + bytes
        }

        // Disarm modifiers after use
        ctrlArmed = false
        altArmed = false

        onSendBytes(bytes)
    }
}

// MARK: - Key Button

/// Individual key button in the keybar row.
private struct KeyButton: View {
    let spec: KeySpec
    let isArmed: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if let icon = spec.icon, !spec.isModifier {
                    // Icon-based (arrows, etc.)
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                } else {
                    // Text-based
                    Text(spec.label)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                }
            }
            .foregroundStyle(foregroundColor)
            .frame(minWidth: minWidth, minHeight: 30)
            .padding(.horizontal, horizontalPadding)
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
        return MajorTomTheme.Colors.surfaceElevated
    }

    private var minWidth: CGFloat {
        // Wider for text labels, narrower for single-char symbols
        if spec.isModifier { return 36 }
        if spec.icon != nil { return 28 }
        if spec.label.count > 2 { return 36 }
        return 28
    }

    private var horizontalPadding: CGFloat {
        spec.label.count > 2 ? 6 : 4
    }
}
