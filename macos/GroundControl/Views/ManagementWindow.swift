import AppKit
import SwiftUI

/// Sidebar navigation items for the management window.
enum ManagementSection: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case logs = "Logs"
    case configuration = "Configuration"
    case security = "Security"

    var id: String { rawValue }

    var sfSymbol: String {
        switch self {
        case .dashboard: "gauge.with.dots.needle.bottom.50percent"
        case .logs: "text.line.last.and.arrowtriangle.forward"
        case .configuration: "gearshape"
        case .security: "lock.shield"
        }
    }
}

/// Management window with sidebar navigation.
///
/// All four tabs are functional: Dashboard, Logs, Configuration, and Security.
/// Shows a non-intrusive update banner when a new version is available.
struct ManagementWindow: View {
    let relay: RelayProcess
    let logStore: LogStore
    let configManager: ConfigManager
    let updateChecker: UpdateChecker

    @State private var selectedSection: ManagementSection = .dashboard

    var body: some View {
        VStack(spacing: 0) {
            // Update available banner
            if updateChecker.updateAvailable, let version = updateChecker.latestVersion {
                updateBanner(version: version)
            }

            NavigationSplitView {
                sidebar
            } detail: {
                detail
            }
        }
        .navigationTitle("Ground Control")
        .onReceive(NotificationCenter.default.publisher(for: .switchToSection)) { notification in
            if let section = notification.object as? ManagementSection {
                selectedSection = section
            }
        }
    }

    // MARK: - Update Banner

    @ViewBuilder
    private func updateBanner(version: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(.blue)

            Text("Version \(version) is available")
                .font(.callout)

            Spacer()

            if let url = updateChecker.releaseURL {
                Button("View Release") {
                    NSWorkspace.shared.open(url)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.blue.opacity(0.08))
    }

    // MARK: - Sidebar

    @ViewBuilder
    private var sidebar: some View {
        List(ManagementSection.allCases, selection: $selectedSection) { section in
            sidebarRow(for: section)
                .tag(section)
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
    }

    @ViewBuilder
    private func sidebarRow(for section: ManagementSection) -> some View {
        Label(section.rawValue, systemImage: section.sfSymbol)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        switch selectedSection {
        case .dashboard:
            DashboardView(relay: relay)
        case .logs:
            LogView(logStore: logStore)
        case .configuration:
            ConfigView(relay: relay, configManager: configManager)
        case .security:
            SecurityView(relay: relay, configManager: configManager)
        }
    }
}
