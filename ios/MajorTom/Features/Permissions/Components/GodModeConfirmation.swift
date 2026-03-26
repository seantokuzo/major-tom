import SwiftUI

struct GodModeConfirmation: View {
    @Binding var selectedSubMode: GodSubMode
    let onConfirm: (GodSubMode) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: MajorTomTheme.Spacing.lg) {
            // Warning icon
            Image(systemName: "bolt.trianglebadge.exclamationmark.fill")
                .font(.system(size: 40))
                .foregroundStyle(MajorTomTheme.Colors.danger)
                .padding(.top, MajorTomTheme.Spacing.md)

            // Title
            Text("Enable God Mode?")
                .font(MajorTomTheme.Typography.title)
                .foregroundStyle(MajorTomTheme.Colors.textPrimary)

            // Warning text
            Text("This will auto-approve ALL tool executions without manual review.")
                .font(MajorTomTheme.Typography.body)
                .foregroundStyle(MajorTomTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, MajorTomTheme.Spacing.md)

            // Sub-mode picker
            VStack(spacing: MajorTomTheme.Spacing.md) {
                subModeOption(
                    mode: .normal,
                    icon: "bolt.fill",
                    title: "Normal",
                    description: "Auto-approves with standard safety checks"
                )

                subModeOption(
                    mode: .yolo,
                    icon: "flame.fill",
                    title: "YOLO",
                    description: "Bypasses ALL safety checks"
                )

                // Extra YOLO warning
                if selectedSubMode == .yolo {
                    HStack(spacing: MajorTomTheme.Spacing.sm) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 12))
                        Text("YOLO mode disables all safety guards. Use at your own risk.")
                            .font(MajorTomTheme.Typography.caption)
                    }
                    .foregroundStyle(MajorTomTheme.Colors.danger)
                    .padding(MajorTomTheme.Spacing.md)
                    .background(MajorTomTheme.Colors.danger.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: MajorTomTheme.Radius.small))
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.horizontal, MajorTomTheme.Spacing.md)

            // Action buttons
            HStack(spacing: MajorTomTheme.Spacing.md) {
                Button {
                    HapticService.buttonTap()
                    onCancel()
                } label: {
                    Text("Cancel")
                        .font(MajorTomTheme.Typography.headline)
                        .foregroundStyle(MajorTomTheme.Colors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, MajorTomTheme.Spacing.md)
                        .background(MajorTomTheme.Colors.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: MajorTomTheme.Radius.medium))
                }
                .buttonStyle(.plain)

                Button {
                    HapticService.modeSwitch()
                    onConfirm(selectedSubMode)
                } label: {
                    HStack(spacing: MajorTomTheme.Spacing.sm) {
                        Image(systemName: selectedSubMode == .yolo ? "flame.fill" : "bolt.fill")
                        Text("Enable")
                    }
                    .font(MajorTomTheme.Typography.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, MajorTomTheme.Spacing.md)
                    .background(MajorTomTheme.Colors.danger)
                    .clipShape(RoundedRectangle(cornerRadius: MajorTomTheme.Radius.medium))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, MajorTomTheme.Spacing.md)
            .padding(.bottom, MajorTomTheme.Spacing.lg)
        }
        .background(MajorTomTheme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: MajorTomTheme.Radius.large))
        .padding(.horizontal, MajorTomTheme.Spacing.xl)
        .animation(.spring(duration: 0.3), value: selectedSubMode)
    }

    private func subModeOption(mode: GodSubMode, icon: String, title: String, description: String) -> some View {
        let isSelected = selectedSubMode == mode

        return Button {
            HapticService.selection()
            selectedSubMode = mode
        } label: {
            HStack(spacing: MajorTomTheme.Spacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? modeColor(mode) : MajorTomTheme.Colors.textTertiary)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(MajorTomTheme.Typography.headline)
                        .foregroundStyle(isSelected ? MajorTomTheme.Colors.textPrimary : MajorTomTheme.Colors.textSecondary)
                    Text(description)
                        .font(MajorTomTheme.Typography.caption)
                        .foregroundStyle(MajorTomTheme.Colors.textTertiary)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? modeColor(mode) : MajorTomTheme.Colors.textTertiary)
            }
            .padding(MajorTomTheme.Spacing.md)
            .background(
                isSelected
                    ? modeColor(mode).opacity(0.1)
                    : MajorTomTheme.Colors.surfaceElevated
            )
            .clipShape(RoundedRectangle(cornerRadius: MajorTomTheme.Radius.small))
            .overlay(
                RoundedRectangle(cornerRadius: MajorTomTheme.Radius.small)
                    .stroke(isSelected ? modeColor(mode).opacity(0.4) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func modeColor(_ mode: GodSubMode) -> Color {
        switch mode {
        case .normal: MajorTomTheme.Colors.danger
        case .yolo: Color(red: 1.0, green: 0.45, blue: 0.0)
        }
    }
}

#Preview {
    ZStack {
        MajorTomTheme.Colors.background
            .ignoresSafeArea()

        GodModeConfirmation(
            selectedSubMode: .constant(.normal),
            onConfirm: { _ in },
            onCancel: {}
        )
    }
}
