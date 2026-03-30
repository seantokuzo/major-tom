import SwiftUI

struct FleetSessionRow: View {
    let session: FleetSession
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: MajorTomTheme.Spacing.md) {
                // Status dot
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)

                // Session ID (truncated)
                Text(session.sessionId.prefix(8).description)
                    .font(MajorTomTheme.Typography.caption)
                    .foregroundStyle(MajorTomTheme.Colors.textPrimary)
                    .monospaced()

                // Status label
                Text(session.status.capitalized)
                    .font(.system(.caption2, design: .default, weight: .semibold))
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(statusColor.opacity(0.15))
                    .clipShape(Capsule())

                Spacer()

                // Stats
                HStack(spacing: MajorTomTheme.Spacing.md) {
                    Label("\(session.turnCount)", systemImage: "arrow.turn.down.right")
                        .font(MajorTomTheme.Typography.caption)
                        .foregroundStyle(MajorTomTheme.Colors.textSecondary)

                    Text(formattedCost)
                        .font(MajorTomTheme.Typography.caption)
                        .foregroundStyle(MajorTomTheme.Colors.accent)
                }

                Image(systemName: "arrow.right.circle")
                    .font(.caption)
                    .foregroundStyle(MajorTomTheme.Colors.accent)
            }
            .padding(.horizontal, MajorTomTheme.Spacing.md)
            .padding(.vertical, MajorTomTheme.Spacing.sm)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Computed

    private var statusColor: Color {
        switch session.status.lowercased() {
        case "active": MajorTomTheme.Colors.allow
        case "idle": MajorTomTheme.Colors.accent
        default: MajorTomTheme.Colors.textTertiary
        }
    }

    private var formattedCost: String {
        if session.totalCost < 0.01 && session.totalCost > 0 {
            return "<$0.01"
        }
        return String(format: "$%.2f", session.totalCost)
    }
}

#Preview {
    VStack(spacing: 0) {
        FleetSessionRow(
            session: FleetSession(
                sessionId: "abc-12345-def-678",
                status: "active",
                totalCost: 0.42,
                turnCount: 5,
                inputTokens: 15200,
                outputTokens: 8300
            ),
            onTap: {}
        )

        Divider()

        FleetSessionRow(
            session: FleetSession(
                sessionId: "ghi-90123-jkl-456",
                status: "idle",
                totalCost: 0.08,
                turnCount: 2,
                inputTokens: 4000,
                outputTokens: 2100
            ),
            onTap: {}
        )
    }
    .background(MajorTomTheme.Colors.surface)
    .padding()
    .background(MajorTomTheme.Colors.background)
}
