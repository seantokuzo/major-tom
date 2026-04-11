import SwiftUI

/// Dashboard overview showing server status, clients, sessions, and resource usage.
///
/// Designed for the macOS management window sidebar detail area.
/// Polls the relay's admin status endpoint via `RelayClient` and
/// displays live metrics in a card-based layout.
struct DashboardView: View {
    let relay: RelayProcess
    @State private var relayClient = RelayClient()

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 16),
                GridItem(.flexible(), spacing: 16),
            ], spacing: 16) {
                statusCard
                resourcesCard
                clientsCard
                sessionsCard
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .onAppear {
            relayClient.port = relay.state.port
            relayClient.startPolling()
        }
        .onDisappear {
            relayClient.stopPolling()
        }
        .onChange(of: relay.state.processState) {
            relayClient.port = relay.state.port
            // Trigger an immediate fetch when state changes
            Task { await relayClient.fetchStatus() }
        }
    }

    // MARK: - Status Card

    @ViewBuilder
    private var statusCard: some View {
        DashboardCard(title: "Server Status", sfSymbol: "server.rack") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    statusIndicator
                    Text(statusLabel)
                        .font(.headline)
                }

                if relayClient.isConnected {
                    LabeledContent("Uptime") {
                        Text(formatUptime(relayClient.healthData.uptime))
                            .monospacedDigit()
                    }

                    LabeledContent("Port") {
                        Text("\(relay.state.port)")
                            .monospacedDigit()
                    }

                    LabeledContent("tmux Windows") {
                        Text("\(relayClient.healthData.tmuxWindowCount)")
                            .monospacedDigit()
                    }
                }
            }
        }
    }

    // MARK: - Resources Card

    @ViewBuilder
    private var resourcesCard: some View {
        DashboardCard(title: "Memory", sfSymbol: "memorychip") {
            if relayClient.isConnected {
                let mem = relayClient.healthData.memory
                VStack(alignment: .leading, spacing: 10) {
                    LabeledContent("RSS") {
                        Text(mem.rssFormatted)
                            .monospacedDigit()
                    }

                    LabeledContent("Heap") {
                        Text("\(mem.heapUsedFormatted) / \(mem.heapTotalFormatted)")
                            .monospacedDigit()
                    }

                    ProgressView(value: mem.heapUtilization)
                        .tint(heapColor(mem.heapUtilization))

                    LabeledContent("External") {
                        Text(formatBytesSimple(mem.external))
                            .monospacedDigit()
                    }
                }
            } else {
                Text("No data")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Clients Card

    @ViewBuilder
    private var clientsCard: some View {
        DashboardCard(title: "Clients", sfSymbol: "person.2") {
            if relayClient.isConnected {
                let clients = relayClient.healthData.clients
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("\(clients.count)")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .monospacedDigit()
                        Text(clients.count == 1 ? "client connected" : "clients connected")
                            .foregroundStyle(.secondary)
                    }

                    if clients.isEmpty {
                        Text("No clients connected")
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                    } else {
                        ForEach(clients.prefix(3)) { client in
                            HStack(spacing: 6) {
                                Image(systemName: deviceIcon(for: client))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 16)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(client.deviceSummary)
                                        .font(.callout)
                                    Text(client.ip)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(client.connectionDuration)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }

                        if clients.count > 3 {
                            Text("+\(clients.count - 3) more")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                Text("No data")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Sessions Card

    @ViewBuilder
    private var sessionsCard: some View {
        DashboardCard(title: "Sessions", sfSymbol: "terminal") {
            if relayClient.isConnected {
                let sessions = relayClient.healthData.sessions
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("\(sessions.count)")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .monospacedDigit()
                        Text(sessions.count == 1 ? "active session" : "active sessions")
                            .foregroundStyle(.secondary)
                    }

                    if sessions.isEmpty {
                        Text("No active sessions")
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                    } else {
                        ForEach(sessions.prefix(4)) { session in
                            HStack(spacing: 6) {
                                statusDot(for: session.status)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(session.workDirName)
                                        .font(.callout)
                                        .lineLimit(1)
                                    Text(String(session.sessionId.prefix(8)) + "...")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .monospaced()
                                }
                                Spacer()
                                Text(session.status)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if sessions.count > 4 {
                            Text("+\(sessions.count - 4) more")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                Text("No data")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Helpers

    private var statusLabel: String {
        switch relay.state.processState {
        case .running:
            relayClient.isConnected ? "Running" : "Starting..."
        case .starting:
            "Starting..."
        case .stopping:
            "Stopping..."
        case .idle:
            "Stopped"
        case .error(let msg):
            "Error: \(msg)"
        case .restarting(let attempt):
            "Restarting (attempt \(attempt)/5)..."
        }
    }

    @ViewBuilder
    private var statusIndicator: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 10, height: 10)
            .shadow(color: statusColor.opacity(0.5), radius: 3)
            .animation(.easeInOut(duration: 0.3), value: relay.state.processState)
    }

    private var statusColor: Color {
        switch relay.state.processState {
        case .running:
            relayClient.isConnected ? .green : .yellow
        case .starting, .stopping:
            .yellow
        case .restarting:
            .yellow
        case .idle:
            .gray
        case .error:
            .red
        }
    }

    private func formatUptime(_ seconds: Double) -> String {
        let totalSeconds = Int(seconds)
        let days = totalSeconds / 86400
        let hours = (totalSeconds % 86400) / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60

        if days > 0 {
            return "\(days)d \(hours)h \(minutes)m"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m \(secs)s"
        } else if minutes > 0 {
            return "\(minutes)m \(secs)s"
        } else {
            return "\(secs)s"
        }
    }

    private func heapColor(_ utilization: Double) -> Color {
        if utilization < 0.6 { return .green }
        if utilization < 0.8 { return .yellow }
        return .red
    }

    private func deviceIcon(for client: ConnectedClient) -> String {
        if client.userAgent.contains("iPhone") { return "iphone" }
        if client.userAgent.contains("iPad") { return "ipad" }
        if client.userAgent.contains("Macintosh") || client.userAgent.contains("Mac OS") {
            return "desktopcomputer"
        }
        if client.userAgent.contains("Android") { return "candybarphone" }
        return "display"
    }

    private func formatBytesSimple(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        let kb = Double(bytes) / 1024
        if kb < 1024 { return String(format: "%.0f KB", kb) }
        let mb = kb / 1024
        return String(format: "%.1f MB", mb)
    }

    @ViewBuilder
    private func statusDot(for status: String) -> some View {
        Circle()
            .fill(sessionStatusColor(status))
            .frame(width: 8, height: 8)
    }

    private func sessionStatusColor(_ status: String) -> Color {
        switch status {
        case "active": .green
        case "idle": .yellow
        case "closed": .gray
        default: .gray
        }
    }
}

// MARK: - Dashboard Card

/// Reusable card container for the dashboard grid.
private struct DashboardCard<Content: View>: View {
    let title: String
    let sfSymbol: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: sfSymbol)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)

            content()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .animation(.easeInOut(duration: 0.25), value: title)
    }
}
