import SwiftUI

/// Ground Control — macOS menu bar app for managing the Major Tom relay server.
///
/// Lives in the menu bar (no dock icon, LSUIElement = true). Provides start/stop/restart
/// controls, quick links to the PWA, and a management window with live logs, dashboard,
/// config, and security panel. Shows a first-run onboarding wizard on initial launch.
@main
struct GroundControlApp: App {
    @State private var configManager: ConfigManager
    @State private var relay: RelayProcess
    @State private var updateChecker = UpdateChecker()
    @State private var showOnboarding: Bool

    init() {
        let cm = ConfigManager()
        _configManager = State(initialValue: cm)
        _relay = State(initialValue: RelayProcess(configManager: cm))
        _showOnboarding = State(initialValue: !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding"))
    }

    var body: some Scene {
        // Menu bar extra — the primary UI
        MenuBarExtra {
            MenuBarView(relay: relay, updateChecker: updateChecker)
        } label: {
            menuBarLabel
        }

        // Management window — log viewer, dashboard, config, and security
        Window("Ground Control", id: "management") {
            ManagementWindow(
                relay: relay,
                logStore: relay.logStore,
                configManager: configManager,
                updateChecker: updateChecker
            )
            .frame(minWidth: 700, minHeight: 450)
            .onAppear {
                updateChecker.startChecking()
            }
        }
        .defaultSize(width: 900, height: 600)

        // Onboarding window — shown on first launch
        Window("Welcome", id: "onboarding") {
            OnboardingView(
                configManager: configManager,
                relay: relay,
                onComplete: {
                    showOnboarding = false
                }
            )
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }

    /// Menu bar icon — colored circle overlay indicates relay status.
    ///
    /// - Green: relay running
    /// - Red: relay error
    /// - Yellow: starting/stopping
    /// - Gray (no overlay): relay stopped
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

