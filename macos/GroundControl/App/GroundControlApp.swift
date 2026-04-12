import AppKit
import SwiftUI

/// `NSApplicationDelegate` that hooks the Dock-reopen event.
///
/// With `LSUIElement = true`, Ground Control has no persistent Dock icon
/// while running — but the user can still drag the `.app` to the Dock as a
/// launcher shortcut. When they click that Dock icon and we're already
/// running, macOS calls `applicationShouldHandleReopen(_:hasVisibleWindows:)`.
/// We open the Management window in response so the click feels like
/// "show me the dashboard" instead of doing nothing.
final class GroundControlAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows _: Bool
    ) -> Bool {
        // If the management window is already open, just activate us.
        NSApp.activate(ignoringOtherApps: true)

        // Raise any existing management window, or ask SwiftUI to open one
        // by name (the Window scene below declares id "management").
        if let existing = NSApp.windows.first(where: { $0.identifier?.rawValue == "management" }) {
            existing.makeKeyAndOrderFront(nil)
        } else {
            // Posting an NSEvent-free URL via Launch Services would work but
            // is overkill; the supported SwiftUI path is `openWindow`, which
            // we can't call from an AppDelegate. The cleanest fallback is
            // the URL scheme `x-swiftui-window://` — but since we haven't
            // registered one, we emit a notification that `GroundControlApp`
            // observes to trigger `openWindow(id:)` from the scene body.
            NotificationCenter.default.post(name: .openManagementWindow, object: nil)
        }

        // Returning true tells AppKit "we handled the reopen, don't run
        // default behavior" (which for LSUIElement apps is a no-op anyway).
        return true
    }
}

extension Notification.Name {
    /// Posted by the app delegate when the user clicks the Dock icon of a
    /// running instance. `GroundControlApp` listens for this and opens the
    /// management window via the SwiftUI environment.
    static let openManagementWindow = Notification.Name("com.majortom.groundcontrol.openManagementWindow")
}

/// Ground Control — macOS menu bar app for managing the Major Tom relay server.
///
/// Lives in the menu bar (no dock icon, LSUIElement = true). Provides start/stop/restart
/// controls, quick links to the PWA, and a management window with live logs, dashboard,
/// config, and security panel. Shows a first-run onboarding wizard on initial launch.
@main
struct GroundControlApp: App {
    @NSApplicationDelegateAdaptor(GroundControlAppDelegate.self) private var appDelegate

    @State private var configManager: ConfigManager
    @State private var relay: RelayProcess
    @State private var updateChecker = UpdateChecker()
    @State private var showOnboarding: Bool

    init() {
        let cm = ConfigManager()
        _configManager = State(initialValue: cm)
        _relay = State(initialValue: RelayProcess(configManager: cm))
        _showOnboarding = State(initialValue: !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding"))

        // Start checking for updates at launch so the menu bar can show availability
        // even if the user never opens the Management window.
        updateChecker.startChecking()

        // Sync Login Item state with config — handles drift if the user
        // toggled the Login Item from System Settings independently.
        LoginItemManager.syncWithConfig(launchAtLogin: cm.config.launchAtLogin)
    }

    var body: some Scene {
        // Menu bar extra — the primary UI
        MenuBarExtra {
            MenuBarExtraContent(
                relay: relay,
                updateChecker: updateChecker,
                showOnboarding: showOnboarding
            )
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

    /// Menu bar content wrapper — gives us access to `@Environment(\.openWindow)`
    /// so the Dock-reopen notification can be routed into SwiftUI's scene API.
    private struct MenuBarExtraContent: View {
        let relay: RelayProcess
        let updateChecker: UpdateChecker
        let showOnboarding: Bool

        @Environment(\.openWindow) private var openWindow

        var body: some View {
            MenuBarView(relay: relay, updateChecker: updateChecker)
                .onAppear {
                    // Open onboarding window on first launch.
                    if showOnboarding {
                        NSApplication.shared.activate(ignoringOtherApps: true)
                        for window in NSApplication.shared.windows where window.identifier?.rawValue == "onboarding" {
                            window.makeKeyAndOrderFront(nil)
                            return
                        }
                        for window in NSApplication.shared.windows where window.title == "Welcome" {
                            window.makeKeyAndOrderFront(nil)
                            return
                        }
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .openManagementWindow)) { _ in
                    // User clicked the Dock icon of a running instance — show
                    // the management window as the visible "I'm running" surface.
                    openWindow(id: "management")
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
        }
    }

    /// Menu bar icon — colored circle overlay indicates relay status.
    ///
    /// - Green: relay running
    /// - Red: relay error
    /// - Yellow: starting/stopping
    /// - Orange: restarting (auto-recovery pending)
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
        case .restarting:
            Image(systemName: "antenna.radiowaves.left.and.right")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.orange, .primary)
        case .idle:
            Image(systemName: "antenna.radiowaves.left.and.right")
        }
    }
}

