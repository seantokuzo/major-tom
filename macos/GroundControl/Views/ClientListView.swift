import SwiftUI

/// Full-detail view of connected WebSocket clients.
///
/// Shows each client's IP, user agent, and connection duration.
/// Designed as a standalone detail view or sheet for the Dashboard.
struct ClientListView: View {
    let clients: [ConnectedClient]

    var body: some View {
        Group {
            if clients.isEmpty {
                emptyState
            } else {
                clientList
            }
        }
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.2.slash")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)

            Text("No Connected Clients")
                .font(.title3)
                .fontWeight(.medium)

            Text("Clients will appear here when they connect to the relay.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Client List

    @ViewBuilder
    private var clientList: some View {
        List {
            Section {
                ForEach(clients) { client in
                    clientRow(client)
                }
            } header: {
                Text("\(clients.count) Connected Client\(clients.count == 1 ? "" : "s")")
            }
        }
    }

    @ViewBuilder
    private func clientRow(_ client: ConnectedClient) -> some View {
        HStack(spacing: 12) {
            // Device icon
            Image(systemName: deviceIcon(for: client))
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .center)

            // Client details
            VStack(alignment: .leading, spacing: 3) {
                Text(client.ip)
                    .font(.body)
                    .fontWeight(.medium)
                    .monospaced()

                Text(client.userAgent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }

            Spacer()

            // Connection duration
            VStack(alignment: .trailing, spacing: 2) {
                Text(client.connectionDuration)
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)

                Text("connected")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Helpers

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
