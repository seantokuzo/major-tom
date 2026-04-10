import SwiftUI

/// Main terminal view — hosts the WKWebView terminal and manages lifecycle.
///
/// Wave 2: Full keyboard input. The NativeKeybar sits above the iOS software
/// keyboard with specialty keys (Esc, Tab, Ctrl, arrows). The SpecialtyKeyGrid
/// slides up as an alternative to the iOS keyboard with function keys, Ctrl
/// combos, tmux shortcuts, and symbols.
///
/// Wave 3: Multi-tab support. The TerminalTabBar sits above the terminal area
/// and lets users create, switch, and close tmux windows (tabs).
struct TerminalView: View {
    let auth: AuthService

    @State private var viewModel: TerminalViewModel

    /// Whether the specialty key grid is visible.
    @State private var showSpecialtyGrid = false

    init(auth: AuthService) {
        self.auth = auth
        self._viewModel = State(initialValue: TerminalViewModel(auth: auth))
    }

    var body: some View {
        ZStack {
            // Background matching the terminal theme
            Color(red: 0.05, green: 0.05, blue: 0.07)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Status bar
                statusBar

                // Tab bar for multi-tab support
                TerminalTabBar(
                    tabs: viewModel.tabs,
                    onSelectTab: { id in
                        viewModel.switchTab(id: id)
                    },
                    onCloseTab: { id in
                        viewModel.requestCloseTab(id: id)
                    },
                    onCreateTab: {
                        viewModel.createTab()
                    }
                )

                // Terminal web view (fills available space)
                terminalContent

                // Specialty key grid (slides up from bottom)
                if showSpecialtyGrid {
                    SpecialtyKeyGrid(
                        onSendBytes: { bytes in
                            viewModel.sendBytes(bytes)
                        },
                        onDismiss: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showSpecialtyGrid = false
                            }
                        }
                    )
                }

                // Native keybar — always visible when terminal is active.
                //
                // Positioned as a bottom-pinned VStack element (not a keyboard
                // inputAccessoryView) intentionally: the keybar must remain
                // visible even when no iOS keyboard is showing (e.g., when the
                // specialty grid replaces the keyboard). This matches the PWA's
                // mobile-first layout where the keybar is always on screen.
                if viewModel.connectionState == .connected || viewModel.isReady {
                    NativeKeybar(
                        onSendBytes: { bytes in
                            viewModel.sendBytes(bytes)
                        },
                        onToggleSpecialty: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showSpecialtyGrid.toggle()
                            }
                        },
                        specialtyGridVisible: showSpecialtyGrid
                    )
                }
            }
        }
        .closeTabConfirmation(
            isPresented: $viewModel.showCloseConfirmation,
            tabTitle: viewModel.tabs.first(where: { $0.id == viewModel.pendingCloseTabId })?.title ?? "Terminal",
            onConfirm: {
                viewModel.confirmCloseTab()
            }
        )
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack(spacing: MajorTomTheme.Spacing.sm) {
            // Connection indicator
            Circle()
                .fill(connectionColor)
                .frame(width: 8, height: 8)

            Text(viewModel.terminalTitle)
                .font(MajorTomTheme.Typography.caption)
                .foregroundStyle(MajorTomTheme.Colors.textSecondary)
                .lineLimit(1)

            Spacer()

            if viewModel.connectionState == .connected {
                Text("\(viewModel.cols)x\(viewModel.rows)")
                    .font(MajorTomTheme.Typography.codeFontSmall)
                    .foregroundStyle(MajorTomTheme.Colors.textTertiary)
            }
        }
        .padding(.horizontal, MajorTomTheme.Spacing.md)
        .padding(.vertical, MajorTomTheme.Spacing.xs)
        .background(MajorTomTheme.Colors.surface)
    }

    // MARK: - Terminal Content

    @ViewBuilder
    private var terminalContent: some View {
        switch viewModel.connectionState {
        case .error(let message):
            errorView(message: message)
        default:
            ZStack {
                TerminalWebView(viewModel: viewModel)

                if viewModel.didTerminate {
                    recoveryOverlay
                }

                if !viewModel.isReady {
                    loadingOverlay
                }
            }
        }
    }

    // MARK: - Loading State

    private var loadingOverlay: some View {
        VStack(spacing: MajorTomTheme.Spacing.md) {
            ProgressView()
                .tint(MajorTomTheme.Colors.accent)
                .scaleEffect(1.2)

            Text("Initializing terminal...")
                .font(MajorTomTheme.Typography.caption)
                .foregroundStyle(MajorTomTheme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.05, green: 0.05, blue: 0.07).opacity(0.9))
        .allowsHitTesting(false)
    }

    // MARK: - Error State

    private func errorView(message: String) -> some View {
        VStack(spacing: MajorTomTheme.Spacing.lg) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(MajorTomTheme.Colors.warning)

            Text("Terminal Error")
                .font(MajorTomTheme.Typography.headline)
                .foregroundStyle(MajorTomTheme.Colors.textPrimary)

            Text(message)
                .font(MajorTomTheme.Typography.caption)
                .foregroundStyle(MajorTomTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, MajorTomTheme.Spacing.xl)

            Button {
                viewModel.connectionState = .disconnected
                viewModel.isReady = false
                viewModel.didTerminate = true // triggers reload in updateUIView
            } label: {
                Label("Reconnect", systemImage: "arrow.clockwise")
                    .font(MajorTomTheme.Typography.body)
            }
            .buttonStyle(.bordered)
            .tint(MajorTomTheme.Colors.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.05, green: 0.05, blue: 0.07))
    }

    // MARK: - Recovery Overlay

    private var recoveryOverlay: some View {
        VStack(spacing: MajorTomTheme.Spacing.md) {
            Image(systemName: "arrow.clockwise.circle")
                .font(.system(size: 36))
                .foregroundStyle(MajorTomTheme.Colors.accent)

            Text("Terminal reloading...")
                .font(MajorTomTheme.Typography.caption)
                .foregroundStyle(MajorTomTheme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.05, green: 0.05, blue: 0.07).opacity(0.85))
        .allowsHitTesting(false)
    }

    // MARK: - Helpers

    private var connectionColor: Color {
        switch viewModel.connectionState {
        case .disconnected:
            MajorTomTheme.Colors.textTertiary
        case .connecting:
            MajorTomTheme.Colors.warning
        case .connected:
            MajorTomTheme.Colors.allow
        case .error:
            MajorTomTheme.Colors.deny
        }
    }
}
