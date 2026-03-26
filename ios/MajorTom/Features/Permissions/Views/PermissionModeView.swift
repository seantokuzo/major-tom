import SwiftUI

struct PermissionModeView: View {
    @State private var viewModel: PermissionViewModel

    init(relay: RelayService) {
        _viewModel = State(initialValue: PermissionViewModel(relay: relay))
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        VStack(spacing: MajorTomTheme.Spacing.md) {
            // Mode picker
            ModePickerView(currentMode: viewModel.currentMode) { mode in
                Task { await viewModel.setMode(mode) }
            }

            // Delay settings (only when delay mode active)
            if viewModel.currentMode == .delay {
                DelaySecondsPicker(selectedSeconds: viewModel.delaySeconds) { seconds in
                    Task { await viewModel.setDelaySeconds(seconds) }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Active countdowns
            if !viewModel.activeCountdowns.isEmpty {
                VStack(spacing: MajorTomTheme.Spacing.sm) {
                    ForEach(Array(viewModel.activeCountdowns.values)) { countdown in
                        DelayCountdownView(state: countdown) {
                            viewModel.cancelCountdown(for: countdown.requestId)
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // God mode sub-mode indicator
            if viewModel.currentMode == .god {
                godModeIndicator
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.spring(duration: 0.3), value: viewModel.currentMode)
        .animation(.spring(duration: 0.3), value: viewModel.activeCountdowns.count)
        .sheet(isPresented: $viewModel.isShowingGodConfirmation) {
            GodModeConfirmation(
                selectedSubMode: $viewModel.pendingGodSubMode,
                onConfirm: { subMode in
                    Task { await viewModel.confirmGodMode(subMode: subMode) }
                },
                onCancel: { viewModel.cancelGodMode() }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
            .presentationBackground(MajorTomTheme.Colors.background)
        }
    }

    private var godModeIndicator: some View {
        HStack(spacing: MajorTomTheme.Spacing.sm) {
            Image(systemName: viewModel.godSubMode == .yolo ? "flame.fill" : "bolt.fill")
                .font(.system(size: 12))
            Text(viewModel.godSubMode == .yolo ? "YOLO Mode" : "God Mode")
                .font(MajorTomTheme.Typography.caption)
            Text("All tools auto-approved")
                .font(MajorTomTheme.Typography.caption)
                .foregroundStyle(MajorTomTheme.Colors.textTertiary)
        }
        .foregroundStyle(MajorTomTheme.Colors.danger)
        .padding(.horizontal, MajorTomTheme.Spacing.md)
        .padding(.vertical, MajorTomTheme.Spacing.xs)
        .background(MajorTomTheme.Colors.danger.opacity(0.1))
        .clipShape(Capsule())
    }
}

// MARK: - Compact Permission Pill (for ChatView header)

struct PermissionModePill: View {
    let mode: PermissionMode
    let godSubMode: GodSubMode
    let isExpanded: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: MajorTomTheme.Spacing.xs) {
                Image(systemName: modeIcon)
                    .font(.system(size: 11, weight: .semibold))
                Text(modeLabel)
                    .font(.system(size: 12, weight: .medium))
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(modeColor)
            .padding(.horizontal, MajorTomTheme.Spacing.md)
            .padding(.vertical, MajorTomTheme.Spacing.xs)
            .background(modeColor.opacity(0.12))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var modeIcon: String {
        switch mode {
        case .manual: "hand.raised"
        case .smart: "brain"
        case .delay: "timer"
        case .god: godSubMode == .yolo ? "flame.fill" : "bolt.fill"
        }
    }

    private var modeLabel: String {
        switch mode {
        case .manual: "Manual"
        case .smart: "Smart"
        case .delay: "Delay"
        case .god: godSubMode == .yolo ? "YOLO" : "God"
        }
    }

    private var modeColor: Color {
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
        PermissionModeView(relay: RelayService())

        HStack(spacing: 12) {
            PermissionModePill(mode: .manual, godSubMode: .normal, isExpanded: false, onTap: {})
            PermissionModePill(mode: .smart, godSubMode: .normal, isExpanded: false, onTap: {})
            PermissionModePill(mode: .delay, godSubMode: .normal, isExpanded: true, onTap: {})
            PermissionModePill(mode: .god, godSubMode: .yolo, isExpanded: false, onTap: {})
        }
    }
    .padding()
    .background(MajorTomTheme.Colors.background)
}
