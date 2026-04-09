import SwiftUI

/// Main terminal view — hosts the WKWebView terminal and manages lifecycle.
///
/// Wave 1: Read-only terminal rendering. The terminal connects to the relay's
/// `/shell/:tabId` WebSocket and displays live output. No keyboard input yet
/// (Wave 2 adds the native keybar and iOS keyboard integration).
struct TerminalView: View {
    let auth: AuthService

    @State private var viewModel: TerminalViewModel

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

                // Terminal web view (full bleed)
                terminalContent
                    .ignoresSafeArea(.container, edges: .bottom)
            }
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
