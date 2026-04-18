import SwiftUI
import UIKit

/// Main terminal view — hosts the WKWebView terminal and manages lifecycle.
///
/// Wave 2: Full keyboard input. The NativeKeybar sits above the iOS software
/// keyboard with specialty keys (Esc, Tab, Ctrl, arrows). The SpecialtyKeyGrid
/// slides up as an alternative to the iOS keyboard with function keys, Ctrl
/// combos, user-started-tmux shortcuts, and symbols.
///
/// Wave 3: Multi-tab support. The TerminalTabBar sits above the terminal area
/// and lets users create, switch, and close PTY sessions (tabs).
///
/// Wave 4: Settings sheet with theme picker, font size slider, and keybar
/// customization. Gear icon in the status bar presents TerminalSettingsView.
///
/// Wave 5: Copy/paste mode, orientation transitions, Live Activity and Watch
/// integration. Terminal is now the default tab on launch.
struct TerminalView: View {
    let auth: AuthService
    let liveActivityManager: LiveActivityManager
    let watchConnectivity: PhoneWatchConnectivityService

    @State private var viewModel: TerminalViewModel

    /// Whether the specialty key grid is visible.
    @State private var showSpecialtyGrid = false

    /// Whether the terminal settings sheet is presented.
    @State private var showSettings = false

    /// Whether copy mode is active (long-press to select text).
    @State private var copyModeActive = false

    /// Toast message for copy/paste feedback.
    @State private var toastMessage: String?

    /// Tracked task for toast auto-dismiss.
    @State private var toastTask: Task<Void, Never>?

    /// Tracked task for Live Activity updates.
    @State private var liveActivityTask: Task<Void, Never>?

    /// Stable session ID for Live Activity and Watch — doesn't drift with tab switches.
    /// There is one terminal session with multiple tabs inside it; identity is fixed.
    private let terminalSessionId = "terminal-session"

    /// Timestamp when the terminal first connected — set once, reused for Watch/Activity elapsed time.
    @State private var terminalStartedAt: Date?

    /// Current device orientation — used to trigger resize on rotation.
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    init(auth: AuthService, liveActivityManager: LiveActivityManager, watchConnectivity: PhoneWatchConnectivityService, titleStore: TabTitleStore) {
        self.auth = auth
        self.liveActivityManager = liveActivityManager
        self.watchConnectivity = watchConnectivity
        self._viewModel = State(initialValue: TerminalViewModel(auth: auth, titleStore: titleStore))
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
                    titleStore: viewModel.titleStore,
                    onSelectTab: { id in
                        viewModel.switchTab(id: id)
                    },
                    onCloseTab: { id in
                        viewModel.requestCloseTab(id: id)
                    },
                    onCreateTab: {
                        viewModel.createTab()
                    },
                    onRenameTab: { id, newTitle in
                        viewModel.renameTab(id: id, to: newTitle)
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
                        },
                        keys: viewModel.keybarViewModel.specialtyKeys
                    )
                }

                // Native keybar — always visible when terminal is active.
                //
                // Positioned as a bottom-pinned VStack element (not a keyboard
                // inputAccessoryView) intentionally: the keybar must remain
                // visible even when no iOS keyboard is showing (e.g., when the
                // specialty grid replaces the keyboard). This matches the PWA's
                // mobile-first layout where the keybar is always on screen.
                //
                // Long-press on the keybar area pastes clipboard content.
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
                        specialtyGridVisible: showSpecialtyGrid,
                        keys: viewModel.keybarViewModel.accessoryKeys
                    )
                    .onLongPressGesture(minimumDuration: 0.5) {
                        pasteFromClipboard()
                    }
                }
            }
        }
        .closeTabConfirmation(
            isPresented: $viewModel.showCloseConfirmation,
            tabTitle: {
                guard let tab = viewModel.tabs.first(where: { $0.id == viewModel.pendingCloseTabId }) else {
                    return "Terminal"
                }
                return viewModel.titleStore.title(for: tab.tabId) ?? tab.title
            }(),
            onConfirm: {
                viewModel.confirmCloseTab()
            }
        )
        .sheet(isPresented: $showSettings) {
            TerminalSettingsView(
                keybarViewModel: viewModel.keybarViewModel,
                onFontSizeChange: { size in
                    viewModel.applyFontSize(size)
                },
                onThemeChange: { theme in
                    viewModel.applyTheme(theme)
                }
            )
            .presentationDetents([.medium, .large])
        }
        .overlay(alignment: .bottom) {
            // Toast feedback for copy/paste actions
            if let message = toastMessage {
                Text(message)
                    .font(MajorTomTheme.Typography.caption)
                    .foregroundStyle(MajorTomTheme.Colors.textPrimary)
                    .padding(.horizontal, MajorTomTheme.Spacing.md)
                    .padding(.vertical, MajorTomTheme.Spacing.sm)
                    .background(MajorTomTheme.Colors.surfaceElevated)
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                    .padding(.bottom, 80)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: toastMessage)
        // Trigger terminal resize on orientation change
        .onChange(of: horizontalSizeClass) { _, _ in
            viewModel.triggerResize()
        }
        // Wire terminal state into Live Activity on connection changes
        .onChange(of: viewModel.connectionState) { _, newState in
            updateLiveActivity(for: newState)
            updateWatchTerminalState()
        }
        .onChange(of: viewModel.terminalTitle) { _, _ in
            updateWatchTerminalState()
        }
        .onChange(of: viewModel.tabs.count) { _, _ in
            updateWatchTerminalState()
        }
        .onDisappear {
            toastTask?.cancel()
            liveActivityTask?.cancel()
        }
        .task {
            // Reconcile persisted tab IDs with the relay's live PTY sessions
            // so stale tabs are pruned early. Note: the WebView may already
            // be connecting concurrently (SwiftUI does not guarantee .task
            // ordering vs view body rendering). Stale tab IDs still work —
            // the relay spawns a fresh PTY on connect — so the race is
            // benign; reconciliation just cleans up the local tab list for
            // the next launch.
            await viewModel.reconcileWithRelay()

            await viewModel.keybarViewModel.syncFromRelay()
            // Wait for the JS terminal to initialize before applying synced preferences,
            // otherwise setFontSize/setTheme no-op because `term` is nil in the webview.
            while !viewModel.isReady {
                if Task.isCancelled { return }
                try? await Task.sleep(for: .milliseconds(50))
            }
            viewModel.applyFontSize(viewModel.keybarViewModel.fontSize)
            viewModel.applyTheme(viewModel.keybarViewModel.selectedTheme)
        }
    }

    // MARK: - Copy/Paste

    /// Paste clipboard content into the terminal.
    private func pasteFromClipboard() {
        guard let text = UIPasteboard.general.string, !text.isEmpty else { return }
        viewModel.pasteText(text)
        HapticService.impact(.light)
        showToast("Pasted")
    }

    /// Toggle copy mode on the terminal web view.
    private func toggleCopyMode() {
        copyModeActive.toggle()
        viewModel.setCopyMode(copyModeActive)
        HapticService.impact(.medium)
        showToast(copyModeActive ? "Copy mode ON" : "Copy mode OFF")
    }

    private func showToast(_ message: String) {
        toastMessage = message
        toastTask?.cancel()
        toastTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            if toastMessage == message {
                toastMessage = nil
            }
        }
    }

    // MARK: - Live Activity Integration

    /// Start or end a Live Activity based on terminal connection state.
    private func updateLiveActivity(for state: TerminalConnectionState) {
        liveActivityTask?.cancel()
        liveActivityTask = Task {
            guard !Task.isCancelled else { return }
            switch state {
            case .connected:
                let sessionInfo = SessionInfo(
                    sessionId: terminalSessionId,
                    sessionName: viewModel.terminalTitle,
                    workingDir: "~"
                )
                await liveActivityManager.startActivity(for: sessionInfo)
            case .disconnected:
                await liveActivityManager.endActivity(for: terminalSessionId)
            case .error:
                await liveActivityManager.endActivity(for: terminalSessionId)
            case .connecting:
                break
            }
        }
    }

    // MARK: - Watch Integration

    /// Push terminal session state to the Apple Watch via WatchConnectivity.
    private func updateWatchTerminalState() {
        let isConnected = viewModel.connectionState == .connected
        let tabCount = viewModel.tabs.count

        // Set startedAt once on connect, clear on disconnect.
        if isConnected && terminalStartedAt == nil {
            terminalStartedAt = Date()
        } else if !isConnected {
            terminalStartedAt = nil
        }

        // Send only terminal-specific keys — don't overwrite relay context.
        watchConnectivity.updateTerminalContext(
            isActive: isConnected,
            tabCount: tabCount,
            title: viewModel.terminalTitle
        )

        // Keep the Live Activity in sync with title/tab changes.
        if isConnected {
            liveActivityManager.updateTerminalSession(
                sessionId: terminalSessionId,
                sessionName: viewModel.terminalTitle,
                tabCount: tabCount
            )
        }
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

            // Copy mode toggle
            Button {
                toggleCopyMode()
            } label: {
                Image(systemName: copyModeActive ? "text.cursor" : "selection.pin.in.out")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(copyModeActive ? MajorTomTheme.Colors.accent : MajorTomTheme.Colors.textSecondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(copyModeActive ? "Disable copy mode" : "Enable copy mode")

            // Paste button
            Button {
                pasteFromClipboard()
            } label: {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(MajorTomTheme.Colors.textSecondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Paste from clipboard")

            // Settings gear
            Button {
                HapticService.buttonTap()
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(MajorTomTheme.Colors.textSecondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Terminal settings")
        }
        .padding(.horizontal, MajorTomTheme.Spacing.md)
        .padding(.vertical, MajorTomTheme.Spacing.xs)
        .background(MajorTomTheme.Colors.surface)
    }

    // MARK: - Terminal Content

    @ViewBuilder
    private var terminalContent: some View {
        if viewModel.tabs.isEmpty {
            emptyTabsView
        } else {
            switch viewModel.connectionState {
            case .error(let message):
                errorView(message: message)
            default:
                ZStack {
                    TerminalWebView(viewModel: viewModel)
                        .onLongPressGesture(minimumDuration: 0.5) {
                            toggleCopyMode()
                        }

                    if viewModel.didTerminate {
                        recoveryOverlay
                    }

                    if !viewModel.isReady {
                        loadingOverlay
                    }

                    // Copy mode indicator overlay
                    if copyModeActive {
                        VStack {
                            HStack {
                                Spacer()
                                Text("COPY MODE")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundStyle(MajorTomTheme.Colors.background)
                                    .padding(.horizontal, MajorTomTheme.Spacing.sm)
                                    .padding(.vertical, 2)
                                    .background(MajorTomTheme.Colors.accent)
                                    .clipShape(Capsule())
                                    .padding(MajorTomTheme.Spacing.sm)
                            }
                            Spacer()
                        }
                        .allowsHitTesting(false)
                    }
                }
            }
        }
    }

    // MARK: - Empty Tabs State (Wave 4)

    /// Shown when there are no terminal tabs — cold launch, after closing
    /// the last tab, or after `reconcileWithRelay` prunes every local tab.
    /// The user explicitly creates every terminal from here; we never
    /// auto-spawn a PTY the user didn't ask for.
    private var emptyTabsView: some View {
        ContentUnavailableView {
            Label("No Terminal Tabs", systemImage: "apple.terminal")
                .foregroundStyle(MajorTomTheme.Colors.textSecondary)
        } description: {
            Text("Open a tab to start a shell session. Running `claude` inside it will surface an Office.")
                .foregroundStyle(MajorTomTheme.Colors.textTertiary)
        } actions: {
            Button {
                HapticService.buttonTap()
                viewModel.createTab()
            } label: {
                Label("New Terminal", systemImage: "plus")
                    .font(MajorTomTheme.Typography.body)
            }
            .buttonStyle(.borderedProminent)
            .tint(MajorTomTheme.Colors.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.05, green: 0.05, blue: 0.07))
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
