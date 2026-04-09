import SwiftUI

/// Ground Control — macOS menu bar app for managing the Major Tom relay server.
///
/// Lives in the menu bar (no dock icon). Provides start/stop/restart controls,
/// quick links to the PWA, and a management window with live log viewer.
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

        // Management window — log viewer and management UI
        Window("Ground Control", id: "management") {
            ManagementWindow(relay: relay, logStore: relay.logStore)
                .frame(minWidth: 700, minHeight: 450)
        }
        .defaultSize(width: 900, height: 600)
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

