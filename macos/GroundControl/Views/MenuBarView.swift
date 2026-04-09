import AppKit
import SwiftUI

/// Menu bar dropdown content for Ground Control.
struct MenuBarView: View {
    let relay: RelayProcess

    @Environment(\.openURL) private var openURL
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        // Status line
        statusSection

        Divider()

        // Actions
        actionSection

        Divider()

        // Links
        linkSection

        Divider()

        // Management & Quit
        footerSection
    }

    // MARK: - Sections

    @ViewBuilder
    private var statusSection: some View {
        HStack {
            statusIndicator
            Text(relay.state.statusText)
        }

        if relay.state.isRunning {
            Text("Port \(relay.state.port)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        if let error = relay.state.errorMessage {
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(3)
        }
    }

    @ViewBuilder
    private var actionSection: some View {
        if relay.state.canStart {
            Button("Start Relay") {
                Task { await relay.start() }
            }
            .keyboardShortcut("s", modifiers: [.command])
        }

        if relay.state.canStop {
            Button("Stop Relay") {
                Task { await relay.stop() }
            }
            .keyboardShortcut("x", modifiers: [.command])
        }

        if relay.state.isRunning {
            Button("Restart Relay") {
                Task { await relay.restart() }
            }
            .keyboardShortcut("r", modifiers: [.command])
        }
    }

    @ViewBuilder
    private var linkSection: some View {
        Button("Open PWA in Browser...") {
            let url = URL(string: "http://localhost:\(relay.state.port)")!
            openURL(url)
        }
        .disabled(!relay.state.isRunning)

        Button("Copy Tunnel URL...") {
            // Placeholder for future Cloudflare tunnel integration
        }
        .disabled(true)
    }

    @ViewBuilder
    private var footerSection: some View {
        Button("Management...") {
            openWindow(id: "management")
        }

        Divider()

        Button("Quit Ground Control") {
            // Stop the relay gracefully before quitting
            Task {
                if relay.state.isRunning {
                    await relay.stop()
                }
                NSApplication.shared.terminate(nil)
            }
        }
        .keyboardShortcut("q", modifiers: [.command])
    }

    // MARK: - Status Indicator

    @ViewBuilder
    private var statusIndicator: some View {
        switch relay.state.processState {
        case .running:
            Image(systemName: "circle.fill")
                .foregroundStyle(.green)
                .font(.caption2)
        case .starting, .stopping:
            Image(systemName: "circle.fill")
                .foregroundStyle(.yellow)
                .font(.caption2)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.caption2)
        case .idle:
            Image(systemName: "circle")
                .foregroundStyle(.secondary)
                .font(.caption2)
        }
    }
}
