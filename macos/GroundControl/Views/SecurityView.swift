import AppKit
import SwiftUI

/// Security panel showing connected devices with session revocation,
/// and an audit log viewer when multi-user mode is enabled.
///
/// Feeds from `RelayClient` which polls the relay's `/api/admin/status` endpoint.
struct SecurityView: View {
    let relay: RelayProcess
    let configManager: ConfigManager

    @State private var relayClient = RelayClient()
    @State private var revokeConfirmation: ConnectedClient?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                connectedDevicesSection
                if configManager.config.multiUserEnabled {
                    auditLogSection
                }
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            relayClient.port = relay.state.port
            relayClient.startPolling()
        }
        .onDisappear {
            relayClient.stopPolling()
        }
        .onChange(of: relay.state.processState) {
            relayClient.port = relay.state.port
            Task { await relayClient.fetchStatus() }
        }
        .alert("Revoke Session", isPresented: .init(
            get: { revokeConfirmation != nil },
            set: { if !$0 { revokeConfirmation = nil } }
        )) {
            Button("Revoke", role: .destructive) {
                if let client = revokeConfirmation {
                    Task { await revokeSession(for: client) }
                }
                revokeConfirmation = nil
            }
            Button("Cancel", role: .cancel) {
                revokeConfirmation = nil
            }
        } message: {
            if let client = revokeConfirmation {
                Text("Disconnect \(client.deviceSummary) (\(client.ip))? They will need to reconnect and re-authenticate.")
            }
        }
    }

    // MARK: - Connected Devices

    @ViewBuilder
    private var connectedDevicesSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Connected Devices", systemImage: "network")
                        .font(.headline)

                    Spacer()

                    if relayClient.isConnected {
                        Text("\(relayClient.healthData.clients.count) connected")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if !relay.state.isRunning {
                    offlineState(message: "Relay is not running. Start the relay to see connected devices.")
                } else if !relayClient.isConnected {
                    offlineState(message: "Connecting to relay...")
                } else if relayClient.healthData.clients.isEmpty {
                    emptyState(
                        icon: "checkmark.shield",
                        title: "No Connected Devices",
                        subtitle: "No clients are currently connected to the relay."
                    )
                } else {
                    deviceList
                }
            }
            .padding(4)
        }
    }

    @ViewBuilder
    private var deviceList: some View {
        ForEach(relayClient.healthData.clients) { client in
            HStack(spacing: 12) {
                // Device icon
                Image(systemName: deviceIcon(for: client))
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 28, alignment: .center)

                // Client details
                VStack(alignment: .leading, spacing: 3) {
                    Text(client.deviceSummary)
                        .font(.body)
                        .fontWeight(.medium)

                    HStack(spacing: 8) {
                        Text(client.ip)
                            .font(.caption)
                            .monospaced()
                            .foregroundStyle(.secondary)

                        Text("Connected \(client.connectionDuration)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()

                // Revoke button — disabled until the relay exposes /api/admin/revoke
                Button(role: .destructive) {
                    revokeConfirmation = client
                } label: {
                    Label("Revoke", systemImage: "xmark.circle")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(true)
                .help("Coming soon — requires relay endpoint")
            }
            .padding(.vertical, 4)

            if client.id != relayClient.healthData.clients.last?.id {
                Divider()
            }
        }
    }

    // MARK: - Audit Log

    @ViewBuilder
    private var auditLogSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Label("Audit Log", systemImage: "list.bullet.clipboard")
                    .font(.headline)

                Text("Connection and authentication events are recorded in the relay logs. Use the Logs tab for real-time monitoring, or check the relay log files for historical audit data.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    // Link to logs tab
                    Button {
                        // Post notification to switch to logs tab
                        NotificationCenter.default.post(
                            name: .switchToSection,
                            object: ManagementSection.logs
                        )
                    } label: {
                        Label("Open Logs", systemImage: "text.line.last.and.arrowtriangle.forward")
                    }

                    // Link to log directory
                    Button {
                        let logDir = ConfigManager.configDirURL.appendingPathComponent("logs")
                        if FileManager.default.fileExists(atPath: logDir.path) {
                            NSWorkspace.shared.open(logDir)
                        } else {
                            // Open the config dir instead
                            NSWorkspace.shared.open(ConfigManager.configDirURL)
                        }
                    } label: {
                        Label("Open Log Directory", systemImage: "folder")
                    }
                }
            }
            .padding(4)
        }
    }

    // MARK: - Revoke Action
    // TODO: The relay does not yet expose /api/admin/revoke — this function is a
    // placeholder for when that endpoint is added. Until then the Revoke button is
    // disabled in the UI.

    private func revokeSession(for client: ConnectedClient) async {
        guard let url = URL(string: "http://127.0.0.1:\(relay.state.port)/api/admin/revoke") else {
            print("[SecurityView] Revoke failed: invalid URL")
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = ["ip": client.ip]
        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            print("[SecurityView] Revoke failed: could not encode body — \(error)")
            return
        }

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                // Refresh the client list immediately
                await relayClient.fetchStatus()
            }
        } catch {
            print("[SecurityView] Revoke failed: \(error)")
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func offlineState(message: String) -> some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func emptyState(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)

            Text(title)
                .font(.callout)
                .fontWeight(.medium)

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
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
}

// MARK: - Notification for Section Switching

extension Notification.Name {
    static let switchToSection = Notification.Name("switchToSection")
}
