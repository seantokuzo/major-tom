import SwiftUI

// MARK: - Session Status Widget Views

/// Widget views for the session status widget.
/// These are defined here so the main app can preview them,
/// but the actual WidgetKit extension target must be created separately.
///
/// TODO: Create a Widget Extension target "MajorTomWidget" that:
/// 1. Imports WidgetKit
/// 2. Defines a TimelineProvider using WidgetDataProvider.readSessionStatus()
/// 3. Uses these views for the widget body
/// 4. Supports .systemSmall, .systemMedium, and .systemLarge families

/// Small widget view — shows connection status and cost.
struct SessionStatusSmallView: View {
    let status: WidgetSessionStatus

    var body: some View {
        VStack(alignment: .leading, spacing: MajorTomTheme.Spacing.sm) {
            HStack {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .foregroundStyle(status.isConnected ? MajorTomTheme.Colors.allow : MajorTomTheme.Colors.deny)
                Spacer()
                Text("Major Tom")
                    .font(MajorTomTheme.Typography.caption)
                    .foregroundStyle(MajorTomTheme.Colors.textSecondary)
            }

            Spacer()

            if status.isActive {
                Text(status.formattedCost)
                    .font(.system(.title2, design: .monospaced, weight: .bold))
                    .foregroundStyle(MajorTomTheme.Colors.accent)

                Text(status.agentSummary)
                    .font(MajorTomTheme.Typography.caption)
                    .foregroundStyle(MajorTomTheme.Colors.textSecondary)
            } else {
                Text(status.statusText)
                    .font(MajorTomTheme.Typography.body)
                    .foregroundStyle(MajorTomTheme.Colors.textSecondary)
            }
        }
        .padding(MajorTomTheme.Spacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MajorTomTheme.Colors.background)
    }
}

/// Medium widget view — shows agents, cost, and current tool.
struct SessionStatusMediumView: View {
    let status: WidgetSessionStatus

    var body: some View {
        HStack(spacing: MajorTomTheme.Spacing.lg) {
            // Left: status + cost
            VStack(alignment: .leading, spacing: MajorTomTheme.Spacing.sm) {
                HStack {
                    Circle()
                        .fill(status.isConnected ? MajorTomTheme.Colors.allow : MajorTomTheme.Colors.deny)
                        .frame(width: 8, height: 8)
                    Text(status.isConnected ? "Connected" : "Disconnected")
                        .font(MajorTomTheme.Typography.caption)
                        .foregroundStyle(MajorTomTheme.Colors.textSecondary)
                }

                Spacer()

                if status.isActive {
                    Text(status.formattedCost)
                        .font(.system(.title, design: .monospaced, weight: .bold))
                        .foregroundStyle(MajorTomTheme.Colors.accent)

                    if let elapsed = status.elapsedTime {
                        Text(elapsed)
                            .font(MajorTomTheme.Typography.caption)
                            .foregroundStyle(MajorTomTheme.Colors.textTertiary)
                    }
                } else {
                    Text("No Active Session")
                        .font(MajorTomTheme.Typography.body)
                        .foregroundStyle(MajorTomTheme.Colors.textSecondary)
                }
            }

            Divider()
                .background(MajorTomTheme.Colors.surfaceElevated)

            // Right: agents + tool
            VStack(alignment: .leading, spacing: MajorTomTheme.Spacing.sm) {
                Label {
                    Text(status.agentSummary)
                        .font(MajorTomTheme.Typography.caption)
                } icon: {
                    Image(systemName: "person.2")
                        .font(.caption2)
                }
                .foregroundStyle(MajorTomTheme.Colors.textSecondary)

                Spacer()

                if let tool = status.currentTool {
                    Label {
                        Text(tool)
                            .font(MajorTomTheme.Typography.codeFontSmall)
                            .lineLimit(2)
                    } icon: {
                        Image(systemName: "wrench")
                            .font(.caption2)
                    }
                    .foregroundStyle(MajorTomTheme.Colors.accent)
                }

                if let dir = status.workingDirectory {
                    Text(dir)
                        .font(MajorTomTheme.Typography.codeFontSmall)
                        .foregroundStyle(MajorTomTheme.Colors.textTertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(MajorTomTheme.Spacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MajorTomTheme.Colors.background)
    }
}

// MARK: - Previews

#Preview("Small Widget") {
    SessionStatusSmallView(status: .init(
        isActive: true,
        activeAgentCount: 3,
        totalAgentCount: 5,
        costUsd: 0.1234,
        currentTool: "Edit",
        sessionStartDate: Date().addingTimeInterval(-300),
        isConnected: true,
        workingDirectory: "major-tom"
    ))
    .frame(width: 160, height: 160)
}

#Preview("Medium Widget") {
    SessionStatusMediumView(status: .init(
        isActive: true,
        activeAgentCount: 2,
        totalAgentCount: 7,
        costUsd: 0.5678,
        currentTool: "WriteFile",
        sessionStartDate: Date().addingTimeInterval(-600),
        isConnected: true,
        workingDirectory: "~/code/major-tom"
    ))
    .frame(width: 340, height: 160)
}

#Preview("Disconnected Widget") {
    SessionStatusSmallView(status: .empty)
        .frame(width: 160, height: 160)
}
