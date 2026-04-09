import SwiftUI

/// Ground Control — macOS menu bar app for managing the Major Tom relay server.
///
/// Lives in the menu bar (no dock icon). Provides start/stop/restart controls,
/// quick links to the PWA, and a placeholder management window for future waves.
@main
struct GroundControlApp: App {
    @State private var relay = RelayProcess()

    var body: some Scene {
        // Menu bar extra — the primary UI
        MenuBarExtra {
            MenuBarView(relay: relay)
        } label: {
            menuBarLabel
        }

        // Management window — empty stub for future waves
        Window("Ground Control", id: "management") {
            ManagementPlaceholderView()
                .frame(minWidth: 600, minHeight: 400)
        }
        .defaultSize(width: 800, height: 600)
    }

    /// Menu bar icon with status-aware appearance.
    @ViewBuilder
    private var menuBarLabel: some View {
        switch relay.state.processState {
        case .running:
            Image(systemName: "antenna.radiowaves.left.and.right")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.green, .primary)
        case .error:
            Image(systemName: "antenna.radiowaves.left.and.right")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.red, .primary)
        case .starting, .stopping:
            Image(systemName: "antenna.radiowaves.left.and.right")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.yellow, .primary)
        case .idle:
            Image(systemName: "antenna.radiowaves.left.and.right")
        }
    }
}

/// Placeholder view for the management window (Wave 2+).
struct ManagementPlaceholderView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("Ground Control")
                .font(.title)

            Text("Management window coming in a future update.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
