import SwiftUI
import WidgetKit

// MARK: - Medium Widget View — Active Sessions

struct ActiveSessionsView: View {
    let snapshot: WidgetSnapshot

    private var topSessions: [WidgetSessionEntry] {
        Array(snapshot.sessions.prefix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header
            HStack {
                Image(systemName: "bolt.fill")
                    .font(.caption2)
                    .foregroundStyle(WidgetColors.accent)
                Text("Active Sessions")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WidgetColors.textPrimary)
                Spacer()
                Circle()
                    .fill(snapshot.isConnected ? WidgetColors.statusGreen : WidgetColors.statusRed)
                    .frame(width: 6, height: 6)
            }

            // Session rows
            if topSessions.isEmpty {
                Spacer()
                HStack {
                    Spacer()
                    Text("No active sessions")
                        .font(.caption)
                        .foregroundStyle(WidgetColors.textTertiary)
                    Spacer()
                }
                Spacer()
            } else {
                ForEach(topSessions) { session in
                    SessionRowWidget(session: session)
                }

                // Fill remaining slots with placeholder rows
                if topSessions.count < 3 {
                    ForEach(0..<(3 - topSessions.count), id: \.self) { _ in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(WidgetColors.surface)
                                .frame(width: 8, height: 8)
                            Text("--")
                                .font(.caption)
                                .foregroundStyle(WidgetColors.textTertiary)
                            Spacer()
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            Spacer(minLength: 0)

            // Footer
            HStack {
                Image(systemName: "server.rack")
                    .font(.caption2)
                Text("\(snapshot.totalAgentCount) agents")
                    .font(.caption2)
                Spacer()
                Text(snapshot.formattedTotalCost)
                    .font(.system(.caption2, design: .monospaced, weight: .semibold))
            }
            .foregroundStyle(WidgetColors.textTertiary)
        }
        .padding(12)
    }
}

// MARK: - Session Row (shared between medium/large)

struct SessionRowWidget: View {
    let session: WidgetSessionEntry

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            Text(session.name)
                .font(.caption.weight(.medium))
                .foregroundStyle(WidgetColors.textPrimary)
                .lineLimit(1)

            Spacer()

            Text(session.formattedCost)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(WidgetColors.accent)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 6)
        .background(WidgetColors.surface.opacity(0.5))
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
