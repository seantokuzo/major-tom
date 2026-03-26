import SwiftUI

struct ModePickerView: View {
    let currentMode: PermissionMode
    let onModeSelected: (PermissionMode) -> Void

    private let modes: [(PermissionMode, String, String)] = [
        (.manual, "hand.raised", "Manual"),
        (.smart, "brain", "Smart"),
        (.delay, "timer", "Delay"),
        (.god, "bolt.fill", "God"),
    ]

    var body: some View {
        HStack(spacing: MajorTomTheme.Spacing.xs) {
            ForEach(modes, id: \.0) { mode, icon, label in
                modeButton(mode: mode, icon: icon, label: label)
            }
        }
        .padding(MajorTomTheme.Spacing.xs)
        .background(MajorTomTheme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: MajorTomTheme.Radius.medium))
    }

    private func modeButton(mode: PermissionMode, icon: String, label: String) -> some View {
        let isSelected = currentMode == mode

        return Button {
            onModeSelected(mode)
        } label: {
            VStack(spacing: MajorTomTheme.Spacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                Text(label)
                    .font(MajorTomTheme.Typography.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, MajorTomTheme.Spacing.sm)
            .foregroundStyle(isSelected ? modeColor(mode) : MajorTomTheme.Colors.textTertiary)
            .background(
                isSelected
                    ? modeColor(mode).opacity(0.15)
                    : Color.clear
            )
            .clipShape(RoundedRectangle(cornerRadius: MajorTomTheme.Radius.small))
        }
        .buttonStyle(.plain)
    }

    private func modeColor(_ mode: PermissionMode) -> Color {
        switch mode {
        case .manual: MajorTomTheme.Colors.accent
        case .smart: Color(red: 0.40, green: 0.70, blue: 0.95)
        case .delay: MajorTomTheme.Colors.warning
        case .god: MajorTomTheme.Colors.danger
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        ModePickerView(currentMode: .manual) { _ in }
        ModePickerView(currentMode: .smart) { _ in }
        ModePickerView(currentMode: .delay) { _ in }
        ModePickerView(currentMode: .god) { _ in }
    }
    .padding()
    .background(MajorTomTheme.Colors.background)
}
