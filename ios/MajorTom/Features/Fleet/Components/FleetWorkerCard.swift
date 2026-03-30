import SwiftUI

struct FleetWorkerCard: View {
    let worker: FleetWorker
    let isExpanded: Bool
    let onToggle: () -> Void
    let onSessionTap: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header — always visible
            Button(action: onToggle) {
                workerHeader
            }
            .buttonStyle(.plain)

            // Expanded session list
            if isExpanded && !worker.sessions.isEmpty {
                Divider()
                    .background(MajorTomTheme.Colors.textTertiary.opacity(0.3))

                VStack(spacing: 0) {
                    ForEach(worker.sessions) { session in
                        FleetSessionRow(session: session) {
                            onSessionTap(session.sessionId)
                        }

                        if session.id != worker.sessions.last?.id {
                            Divider()
                                .background(MajorTomTheme.Colors.textTertiary.opacity(0.2))
                                .padding(.leading, MajorTomTheme.Spacing.xl)
                        }
                    }
                }
            }
        }
        .background(MajorTomTheme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: MajorTomTheme.Radius.small))
        .overlay(
            RoundedRectangle(cornerRadius: MajorTomTheme.Radius.small)
                .stroke(
                    worker.healthy ? Color.clear : MajorTomTheme.Colors.deny.opacity(0.4),
                    lineWidth: 1
                )
        )
    }

    // MARK: - Worker Header

    private var workerHeader: some View {
        HStack(spacing: MajorTomTheme.Spacing.md) {
            // Health dot
            Circle()
                .fill(healthColor)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: MajorTomTheme.Spacing.xs) {
                HStack(spacing: MajorTomTheme.Spacing.sm) {
                    Text(worker.dirName)
                        .font(MajorTomTheme.Typography.headline)
                        .foregroundStyle(MajorTomTheme.Colors.textPrimary)
                        .lineLimit(1)

                    if worker.restartCount > 0 {
                        restartBadge
                    }
                }

                Text(worker.workingDir)
                    .font(MajorTomTheme.Typography.caption)
                    .foregroundStyle(MajorTomTheme.Colors.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            // Stats
            VStack(alignment: .trailing, spacing: MajorTomTheme.Spacing.xs) {
                HStack(spacing: MajorTomTheme.Spacing.sm) {
                    Label("\(worker.sessionCount)", systemImage: "terminal")
                        .font(MajorTomTheme.Typography.caption)
                        .foregroundStyle(MajorTomTheme.Colors.textSecondary)

                    Text(formattedUptime)
                        .font(MajorTomTheme.Typography.caption)
                        .foregroundStyle(MajorTomTheme.Colors.textSecondary)
                }

                Text(workerCostSubtotal)
                    .font(MajorTomTheme.Typography.caption)
                    .foregroundStyle(MajorTomTheme.Colors.accent)
            }

            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.caption)
                .foregroundStyle(MajorTomTheme.Colors.textTertiary)
        }
        .padding(MajorTomTheme.Spacing.md)
    }

    // MARK: - Restart Badge

    private var restartBadge: some View {
        HStack(spacing: 2) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 9, weight: .bold))
            Text("\(worker.restartCount)")
                .font(.system(.caption2, design: .default, weight: .bold))
        }
        .foregroundStyle(MajorTomTheme.Colors.warning)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(MajorTomTheme.Colors.warning.opacity(0.2))
        .clipShape(Capsule())
    }

    // MARK: - Computed

    private var healthColor: Color {
        worker.healthy ? MajorTomTheme.Colors.allow : MajorTomTheme.Colors.deny
    }

    private var formattedUptime: String {
        let totalSeconds = worker.uptimeMs / 1000
        if totalSeconds < 60 {
            return "\(totalSeconds)s"
        }
        let minutes = totalSeconds / 60
        if minutes < 60 {
            return "\(minutes)m"
        }
        let hours = minutes / 60
        let remainMinutes = minutes % 60
        return "\(hours)h \(remainMinutes)m"
    }

    private var workerCostSubtotal: String {
        let cost = worker.sessions.reduce(0.0) { $0 + $1.totalCost }
        if cost < 0.01 && cost > 0 {
            return "<$0.01"
        }
        return String(format: "$%.2f", cost)
    }
}

#Preview {
    VStack(spacing: MajorTomTheme.Spacing.sm) {
        FleetWorkerCard(
            worker: FleetWorker(
                workerId: "w1",
                workingDir: "/Users/dev/major-tom",
                dirName: "major-tom",
                sessionCount: 2,
                uptimeMs: 7_200_000,
                restartCount: 0,
                healthy: true,
                sessions: [
                    FleetSession(sessionId: "s1", status: "active", totalCost: 0.42, turnCount: 5, inputTokens: 15200, outputTokens: 8300),
                    FleetSession(sessionId: "s2", status: "idle", totalCost: 0.18, turnCount: 3, inputTokens: 8000, outputTokens: 4200)
                ]
            ),
            isExpanded: true,
            onToggle: {},
            onSessionTap: { _ in }
        )

        FleetWorkerCard(
            worker: FleetWorker(
                workerId: "w2",
                workingDir: "/Users/dev/other-project",
                dirName: "other-project",
                sessionCount: 1,
                uptimeMs: 300_000,
                restartCount: 2,
                healthy: false,
                sessions: []
            ),
            isExpanded: false,
            onToggle: {},
            onSessionTap: { _ in }
        )
    }
    .padding()
    .background(MajorTomTheme.Colors.background)
}
