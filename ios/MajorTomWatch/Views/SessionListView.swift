import SwiftUI

// MARK: - Watch Session List View

struct WatchSessionListView: View {
    let viewModel: WatchViewModel

    var body: some View {
        List {
            if viewModel.hasPendingApprovals {
                NavigationLink {
                    WatchApprovalView(
                        viewModel: ApprovalViewModel(connectivity: viewModel.connectivity)
                    )
                } label: {
                    HStack {
                        Image(systemName: "bell.badge.fill")
                            .foregroundStyle(.red)
                        Text("\(viewModel.pendingApprovalCount) Pending")
                            .font(.headline)
                        Spacer()
                    }
                }
                .listRowBackground(Color.red.opacity(0.15))
            }

            if viewModel.sessions.isEmpty {
                ContentUnavailableView {
                    Label("No Sessions", systemImage: "bolt.slash")
                } description: {
                    if !viewModel.isRelayConnected {
                        Text("Not connected to relay")
                    } else {
                        Text("No active sessions")
                    }
                }
            } else {
                ForEach(viewModel.sessions) { session in
                    NavigationLink {
                        WatchSessionDetailView(session: session, viewModel: viewModel)
                    } label: {
                        sessionRow(session)
                    }
                }
            }
        }
        .navigationTitle("Sessions")
    }

    @ViewBuilder
    private func sessionRow(_ session: WatchSession) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor(for: session.status))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.name)
                    .font(.headline)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if session.agentCount > 0 {
                        Label("\(session.agentCount)", systemImage: "person.2.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text(session.formattedCost)
                        .font(.caption2)
                        .foregroundStyle(Color(red: 0.95, green: 0.65, blue: 0.25))
                }
            }

            Spacer()
        }
    }

    private func statusColor(for status: WatchSessionStatus) -> Color {
        switch status {
        case .active: .green
        case .waiting: .yellow
        case .error: .red
        case .idle: .gray
        }
    }
}
