import SwiftUI
import WidgetKit

// MARK: - Large Widget View — Fleet Dashboard

struct FleetDashboardWidgetView: View {
    let snapshot: WidgetSnapshot

    private var displaySessions: [WidgetSessionEntry] {
        Array(snapshot.sessions.prefix(6))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Image(systemName: "bolt.fill")
                    .font(.caption)
                    .foregroundStyle(WidgetColors.accent)
                Text("Major Tom Fleet")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(WidgetColors.textPrimary)
                Spacer()
                Circle()
                    .fill(healthColor)
                    .frame(width: 8, height: 8)
                Text(snapshot.fleetHealth.capitalized)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(WidgetColors.textSecondary)
            }

            Divider()
                .background(WidgetColors.surface)

            // Session list or empty state
            if displaySessions.isEmpty {
                Spacer()
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "antenna.radiowaves.left.and.right.slash")
                            .font(.title2)
                            .foregroundStyle(WidgetColors.textTertiary)
                        Text("No active sessions")
                            .font(.caption)
                            .foregroundStyle(WidgetColors.textTertiary)
                    }
                    Spacer()
                }
                Spacer()
            } else {
                ForEach(displaySessions) { session in
                    FleetSessionRowWidget(session: session)
                }

                // Fill remaining rows to keep consistent layout
                if displaySessions.count < 6 {
                    ForEach(0..<(6 - displaySessions.count), id: \.self) { _ in
                        HStack {
                            Circle()
                                .fill(WidgetColors.surface.opacity(0.3))
                                .frame(width: 8, height: 8)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(WidgetColors.surface.opacity(0.2))
                                .frame(height: 4)
                            Spacer()
                        }
                        .padding(.vertical, 3)
                    }
                }
            }

            Spacer(minLength: 0)

            // Footer
            Divider()
                .background(WidgetColors.surface)

            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Image(systemName: "dollarsign.circle")
                        .font(.caption2)
                    Text(snapshot.formattedTotalCost)
                        .font(.system(.caption2, design: .monospaced).weight(.semibold))
                }

                HStack(spacing: 4) {
                    Image(systemName: "bolt.fill")
                        .font(.caption2)
                    Text("\(snapshot.totalSessionCount) sessions")
                        .font(.caption2)
                }

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: "server.rack")
                        .font(.caption2)
                    Text("\(snapshot.totalAgentCount) agents")
                        .font(.caption2)
                }
            }
            .foregroundStyle(WidgetColors.textTertiary)
        }
        .padding(14)
    }

    private var healthColor: Color {
        switch snapshot.fleetHealth {
        case "healthy": return WidgetColors.statusGreen
        case "degraded": return WidgetColors.statusYellow
        default: return WidgetColors.statusRed
        }
    }
}

// MARK: - Fleet Session Row

struct FleetSessionRowWidget: View {
    let session: WidgetSessionEntry

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            Text(session.name)
                .font(.caption.weight(.medium))
                .foregroundStyle(WidgetColors.textPrimary)
                .lineLimit(1)

            if session.agentCount > 0 {
                Text("\(session.agentCount)")
                    .font(.system(.caption2, design: .rounded).weight(.bold))
                    .foregroundStyle(WidgetColors.background)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(WidgetColors.accent)
                    .clipShape(Capsule())
            }

            Spacer()

            Text(session.formattedCost)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(WidgetColors.accent)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 8)
        .background(WidgetColors.surface.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var statusColor: Color {
        switch session.status {
        case "active": return WidgetColors.statusGreen
        case "error": return WidgetColors.statusRed
        default: return WidgetColors.statusYellow
        }
    }
}
