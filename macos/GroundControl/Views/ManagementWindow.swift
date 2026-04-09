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
/// Only the Logs section is functional in Wave 2.
/// Other sections show placeholder content.
struct ManagementWindow: View {
    let relay: RelayProcess
    let logStore: LogStore

    @State private var selectedSection: ManagementSection = .logs

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .navigationTitle("Ground Control")
    }

    // MARK: - Sidebar

    @ViewBuilder
    private var sidebar: some View {
        List(ManagementSection.allCases, selection: $selectedSection) { section in
            Label(section.rawValue, systemImage: section.sfSymbol)
                .tag(section)
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        switch selectedSection {
        case .logs:
            LogView(logStore: logStore)
        case .dashboard:
            placeholderView(
                icon: ManagementSection.dashboard.sfSymbol,
                title: "Dashboard",
                subtitle: "Relay status and metrics coming soon."
            )
        case .configuration:
            placeholderView(
                icon: ManagementSection.configuration.sfSymbol,
                title: "Configuration",
                subtitle: "Port, environment, and startup settings coming soon."
            )
        case .security:
            placeholderView(
                icon: ManagementSection.security.sfSymbol,
                title: "Security",
                subtitle: "Auth tokens and access control coming soon."
            )
        }
    }

    @ViewBuilder
    private func placeholderView(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)

            Text(title)
                .font(.title2)
                .fontWeight(.medium)

            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
