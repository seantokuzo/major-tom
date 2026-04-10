import SwiftUI

/// Terminal settings sheet — font size, theme picker, and keybar customization entry point.
///
/// Presented as a sheet from TerminalView (gear icon). Changes apply immediately
/// so the user gets live preview in the terminal behind the sheet.
struct TerminalSettingsView: View {
    let keybarViewModel: KeybarViewModel
    let onFontSizeChange: (Int) -> Void
    let onThemeChange: (TerminalTheme) -> Void

    @State private var showKeybarCustomizer = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                fontSizeSection
                themeSection
                keybarSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Terminal Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(MajorTomTheme.Colors.accent)
                }
            }
            .scrollContentBackground(.hidden)
            .background(MajorTomTheme.Colors.background)
        }
        .sheet(isPresented: $showKeybarCustomizer) {
            KeybarCustomizer(keybarViewModel: keybarViewModel)
        }
    }

    // MARK: - Font Size Section

    private var fontSizeSection: some View {
        Section {
            VStack(spacing: MajorTomTheme.Spacing.md) {
                HStack {
                    Text("Font Size")
                        .font(MajorTomTheme.Typography.body)
                        .foregroundStyle(MajorTomTheme.Colors.textPrimary)

                    Spacer()

                    Text("\(keybarViewModel.fontSize)pt")
                        .font(MajorTomTheme.Typography.codeFontSmall)
                        .foregroundStyle(MajorTomTheme.Colors.accent)
                        .padding(.horizontal, MajorTomTheme.Spacing.sm)
                        .padding(.vertical, MajorTomTheme.Spacing.xs)
                        .background(MajorTomTheme.Colors.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: MajorTomTheme.Radius.small))
                }

                HStack(spacing: MajorTomTheme.Spacing.md) {
                    // Decrease button
                    Button {
                        HapticService.buttonTap()
                        let newSize = keybarViewModel.fontSize - 1
                        keybarViewModel.setFontSize(newSize)
                        onFontSizeChange(keybarViewModel.fontSize)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(keybarViewModel.fontSize <= 8 ? MajorTomTheme.Colors.textTertiary : MajorTomTheme.Colors.accent)
                    }
                    .disabled(keybarViewModel.fontSize <= 8)

                    // Slider
                    Slider(
                        value: Binding(
                            get: { Double(keybarViewModel.fontSize) },
                            set: { newValue in
                                let intValue = Int(newValue.rounded())
                                keybarViewModel.setFontSize(intValue)
                                onFontSizeChange(keybarViewModel.fontSize)
                            }
                        ),
                        in: 8...32,
                        step: 1
                    )
                    .tint(MajorTomTheme.Colors.accent)

                    // Increase button
                    Button {
                        HapticService.buttonTap()
                        let newSize = keybarViewModel.fontSize + 1
                        keybarViewModel.setFontSize(newSize)
                        onFontSizeChange(keybarViewModel.fontSize)
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(keybarViewModel.fontSize >= 32 ? MajorTomTheme.Colors.textTertiary : MajorTomTheme.Colors.accent)
                    }
                    .disabled(keybarViewModel.fontSize >= 32)
                }

                // Preview text
                Text("AaBbCc 0123 ~/code $")
                    .font(.system(size: CGFloat(keybarViewModel.fontSize), design: .monospaced))
                    .foregroundStyle(Color(hex: keybarViewModel.selectedTheme.foreground) ?? MajorTomTheme.Colors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(MajorTomTheme.Spacing.sm)
                    .background(Color(hex: keybarViewModel.selectedTheme.background) ?? MajorTomTheme.Colors.background)
                    .clipShape(RoundedRectangle(cornerRadius: MajorTomTheme.Radius.small))
            }
        } header: {
            Text("Font")
        }
        .listRowBackground(MajorTomTheme.Colors.surface)
    }

    // MARK: - Theme Section

    private var themeSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: MajorTomTheme.Spacing.md) {
                    ForEach(TerminalTheme.all) { theme in
                        ThemeCard(
                            theme: theme,
                            isSelected: theme.id == keybarViewModel.selectedThemeId,
                            onSelect: {
                                HapticService.buttonTap()
                                keybarViewModel.setTheme(theme)
                                onThemeChange(theme)
                            }
                        )
                    }
                }
                .padding(.vertical, MajorTomTheme.Spacing.xs)
            }
        } header: {
            Text("Theme")
        }
        .listRowBackground(MajorTomTheme.Colors.surface)
    }

    // MARK: - Keybar Section

    private var keybarSection: some View {
        Section {
            Button {
                HapticService.buttonTap()
                showKeybarCustomizer = true
            } label: {
                HStack {
                    Label("Customize Keybar", systemImage: "keyboard.badge.ellipsis")
                        .foregroundStyle(MajorTomTheme.Colors.textPrimary)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(MajorTomTheme.Colors.textTertiary)
                }
            }
        } header: {
            Text("Keybar")
        } footer: {
            Text("Reorder, add, or remove keys from the accessory row and specialty grid.")
                .foregroundStyle(MajorTomTheme.Colors.textTertiary)
        }
        .listRowBackground(MajorTomTheme.Colors.surface)
    }
}

// MARK: - Theme Card

/// A small preview card showing a terminal theme's colors.
private struct ThemeCard: View {
    let theme: TerminalTheme
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: MajorTomTheme.Spacing.xs) {
                // Color preview swatch
                VStack(spacing: 2) {
                    // Background + foreground preview
                    HStack(spacing: 2) {
                        colorDot(theme.red)
                        colorDot(theme.green)
                        colorDot(theme.yellow)
                        colorDot(theme.blue)
                    }
                    HStack(spacing: 2) {
                        colorDot(theme.magenta)
                        colorDot(theme.cyan)
                        colorDot(theme.brightRed)
                        colorDot(theme.brightGreen)
                    }
                }
                .padding(MajorTomTheme.Spacing.sm)
                .frame(width: 80, height: 50)
                .background(Color(hex: theme.background) ?? Color.black)
                .clipShape(RoundedRectangle(cornerRadius: MajorTomTheme.Radius.small))
                .overlay(
                    RoundedRectangle(cornerRadius: MajorTomTheme.Radius.small)
                        .stroke(isSelected ? MajorTomTheme.Colors.accent : Color.clear, lineWidth: 2)
                )

                // Theme name
                Text(theme.name)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(isSelected ? MajorTomTheme.Colors.accent : MajorTomTheme.Colors.textSecondary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }

    private func colorDot(_ hex: String) -> some View {
        Circle()
            .fill(Color(hex: hex) ?? Color.gray)
            .frame(width: 8, height: 8)
    }
}

// MARK: - Color Hex Extension

extension Color {
    /// Create a Color from a hex string (e.g., "#ff5555" or "#ff555580").
    init?(hex: String) {
        var hexString = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if hexString.hasPrefix("#") {
            hexString = String(hexString.dropFirst())
        }

        // Handle 6-char (RGB) and 8-char (RGBA) hex strings
        var rgbValue: UInt64 = 0
        guard Scanner(string: hexString).scanHexInt64(&rgbValue) else { return nil }

        switch hexString.count {
        case 6:
            let r = Double((rgbValue & 0xFF0000) >> 16) / 255.0
            let g = Double((rgbValue & 0x00FF00) >> 8) / 255.0
            let b = Double(rgbValue & 0x0000FF) / 255.0
            self.init(red: r, green: g, blue: b)
        case 8:
            let r = Double((rgbValue & 0xFF000000) >> 24) / 255.0
            let g = Double((rgbValue & 0x00FF0000) >> 16) / 255.0
            let b = Double((rgbValue & 0x0000FF00) >> 8) / 255.0
            let a = Double(rgbValue & 0x000000FF) / 255.0
            self.init(red: r, green: g, blue: b, opacity: a)
        default:
            return nil
        }
    }
}
