import SwiftUI

// MARK: - Watch Status Glance View

struct StatusGlanceView: View {
    let viewModel: WatchViewModel

    private let accentColor = Color(red: 0.95, green: 0.65, blue: 0.25)

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Connection status
                connectionBanner

                // Stats grid
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                ], spacing: 8) {
                    statCard(
                        icon: "bolt.fill",
                        value: "\(viewModel.activeSessionCount)",
                        label: "Sessions",
                        color: .green
                    )

                    statCard(
                        icon: "dollarsign.circle",
                        value: viewModel.formattedTotalCost,
                        label: "Cost",
                        color: accentColor
                    )

                    statCard(
                        icon: "bell.badge",
                        value: "\(viewModel.pendingApprovalCount)",
                        label: "Approvals",
                        color: viewModel.hasPendingApprovals ? .red : .secondary
                    )

                    if let fleet = viewModel.fleetSummary {
                        statCard(
                            icon: "server.rack",
                            value: "\(fleet.healthyWorkers)/\(fleet.totalWorkers)",
                            label: "Fleet",
                            color: fleet.isHealthy ? .green : .yellow
                        )
                    } else {
                        statCard(
                            icon: "server.rack",
                            value: "--",
                            label: "Fleet",
                            color: .secondary
                        )
                    }
                }

                // Latest tool activity
                if let tool = viewModel.latestToolName {
                    HStack {
                        Image(systemName: "wrench.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(tool)
                            .font(.caption)
                            .lineLimit(1)
                        Spacer()
                        if let status = viewModel.latestToolStatus {
                            Text(status)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color(white: 0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("Status")
        .containerBackground(Color(red: 0.05, green: 0.05, blue: 0.07).gradient, for: .navigation)
    }

    @ViewBuilder
    private var connectionBanner: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(viewModel.isRelayConnected ? .green : .red)
                .frame(width: 6, height: 6)
            Text(viewModel.isRelayConnected ? "Connected" : "Disconnected")
                .font(.caption2)
                .foregroundStyle(viewModel.isRelayConnected ? .green : .red)
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func statCard(icon: String, value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
            Text(value)
                .font(.system(.body, design: .rounded, weight: .bold))
                .foregroundStyle(.white)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color(white: 0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
