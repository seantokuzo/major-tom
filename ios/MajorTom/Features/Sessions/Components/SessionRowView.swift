import SwiftUI

struct SessionRowView: View {
    let session: SessionMetaInfo
    let isCurrentSession: Bool

    var body: some View {
        HStack(spacing: MajorTomTheme.Spacing.md) {
            // Status indicator
            Circle()
                .fill(isActive ? MajorTomTheme.Colors.allow : MajorTomTheme.Colors.textTertiary)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: MajorTomTheme.Spacing.xs) {
                // Working dir name + current indicator
                HStack(spacing: MajorTomTheme.Spacing.sm) {
                    Text(session.workingDirName)
                        .font(MajorTomTheme.Typography.headline)
                        .foregroundStyle(MajorTomTheme.Colors.textPrimary)
                        .lineLimit(1)

                    if isCurrentSession {
                        Text("ACTIVE")
                            .font(.system(.caption2, design: .default, weight: .bold))
                            .foregroundStyle(MajorTomTheme.Colors.background)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(MajorTomTheme.Colors.accent)
                            .clipShape(Capsule())
                    }
                }

                // Stats row
                HStack(spacing: MajorTomTheme.Spacing.md) {
                    Label(formattedCost, systemImage: "dollarsign.circle")
                    Label(tokenSummary, systemImage: "textformat.size")
                    Label(formattedDuration, systemImage: "clock")
                }
                .font(MajorTomTheme.Typography.caption)
                .foregroundStyle(MajorTomTheme.Colors.textSecondary)
                .lineLimit(1)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(MajorTomTheme.Colors.textTertiary)
        }
        .padding(MajorTomTheme.Spacing.md)
        .background(
            isCurrentSession
                ? MajorTomTheme.Colors.accentSubtle
                : MajorTomTheme.Colors.surface
        )
        .clipShape(RoundedRectangle(cornerRadius: MajorTomTheme.Radius.small))
        .overlay(
            RoundedRectangle(cornerRadius: MajorTomTheme.Radius.small)
                .stroke(
                    isCurrentSession
                        ? MajorTomTheme.Colors.accent.opacity(0.4)
                        : Color.clear,
                    lineWidth: 1
                )
        )
    }

    // MARK: - Computed

    private var isActive: Bool {
        session.status == "active"
    }

    private var formattedCost: String {
        if session.totalCost < 0.01 {
            return "<$0.01"
        }
        return String(format: "$%.2f", session.totalCost)
    }

    private var tokenSummary: String {
        let total = session.inputTokens + session.outputTokens
        if total >= 1_000_000 {
            return String(format: "%.1fM tok", Double(total) / 1_000_000)
        } else if total >= 1_000 {
            return String(format: "%.1fK tok", Double(total) / 1_000)
        }
        return "\(total) tok"
    }

    private var formattedDuration: String {
        let seconds = session.totalDuration / 1000
        if seconds < 60 {
            return "\(seconds)s"
        }
        let minutes = seconds / 60
        if minutes < 60 {
            return "\(minutes)m"
        }
        let hours = minutes / 60
        let remainMinutes = minutes % 60
        return "\(hours)h \(remainMinutes)m"
    }
}

#Preview {
    VStack(spacing: MajorTomTheme.Spacing.sm) {
        SessionRowView(
            session: SessionMetaInfo(
                id: "abc-123",
                adapter: "cli",
                workingDirName: "major-tom",
                status: "active",
                startedAt: "2024-01-01T12:00:00Z",
                totalCost: 0.42,
                inputTokens: 15200,
                outputTokens: 8300,
                turnCount: 5,
                totalDuration: 180000
            ),
            isCurrentSession: true
        )

        SessionRowView(
            session: SessionMetaInfo(
                id: "def-456",
                adapter: "cli",
                workingDirName: "other-project",
                status: "ended",
                startedAt: "2024-01-01T10:00:00Z",
                totalCost: 1.23,
                inputTokens: 52000,
                outputTokens: 31000,
                turnCount: 12,
                totalDuration: 720000
            ),
            isCurrentSession: false
        )
    }
    .padding()
    .background(MajorTomTheme.Colors.background)
}
