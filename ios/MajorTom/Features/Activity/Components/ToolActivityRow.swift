import SwiftUI

struct ToolActivityRow: View {
    let activity: ToolActivity
    var autoApproval: AutoApprovedTool?

    var body: some View {
        HStack(spacing: MajorTomTheme.Spacing.md) {
            // Tool icon
            Image(systemName: toolIcon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(MajorTomTheme.Colors.accent)
                .frame(width: 28, height: 28)
                .background(MajorTomTheme.Colors.accent.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            // Tool info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: MajorTomTheme.Spacing.sm) {
                    Text(activity.tool)
                        .font(MajorTomTheme.Typography.headline)
                        .foregroundStyle(MajorTomTheme.Colors.textPrimary)

                    if let autoApproval {
                        AutoApprovalBadge(reason: autoApproval.reason)
                    }
                }

                if let inputDescription = formatInput(activity.input) {
                    Text(inputDescription)
                        .font(MajorTomTheme.Typography.codeFontSmall)
                        .foregroundStyle(MajorTomTheme.Colors.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer()

            // Status indicator
            statusView
        }
        .padding(.vertical, MajorTomTheme.Spacing.sm)
        .padding(.horizontal, MajorTomTheme.Spacing.md)
    }

    // MARK: - Tool Icon Mapping

    private var toolIcon: String {
        switch activity.tool.lowercased() {
        case "bash":
            return "terminal"
        case "read":
            return "doc.text"
        case "write":
            return "doc.text.fill"
        case "edit":
            return "pencil"
        case "glob":
            return "magnifyingglass"
        case "grep":
            return "text.magnifyingglass"
        case "agent":
            return "person.2"
        default:
            return "wrench"
        }
    }

    // MARK: - Status View

    @ViewBuilder
    private var statusView: some View {
        if activity.isRunning {
            HStack(spacing: MajorTomTheme.Spacing.xs) {
                ProgressView()
                    .controlSize(.small)
                    .tint(MajorTomTheme.Colors.accent)
                Text("Running...")
                    .font(MajorTomTheme.Typography.caption)
                    .foregroundStyle(MajorTomTheme.Colors.accent)
            }
        } else if activity.success == true {
            HStack(spacing: MajorTomTheme.Spacing.xs) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(MajorTomTheme.Colors.allow)
                Text(formattedDuration)
                    .font(MajorTomTheme.Typography.caption)
                    .foregroundStyle(MajorTomTheme.Colors.textSecondary)
            }
        } else {
            HStack(spacing: MajorTomTheme.Spacing.xs) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(MajorTomTheme.Colors.deny)
                Text("Failed")
                    .font(MajorTomTheme.Typography.caption)
                    .foregroundStyle(MajorTomTheme.Colors.deny)
            }
        }
    }

    // MARK: - Duration Formatting

    private var formattedDuration: String {
        guard let duration = activity.duration else { return "" }
        if duration < 1 {
            return String(format: "%.0fms", duration * 1000)
        } else if duration < 60 {
            return String(format: "%.1fs", duration)
        } else {
            let minutes = Int(duration) / 60
            let seconds = Int(duration) % 60
            return "\(minutes)m\(seconds)s"
        }
    }

    // MARK: - Input Formatting

    private func formatInput(_ input: [String: AnyCodableValue]?) -> String? {
        guard let input else { return nil }

        // Try common input fields in order of usefulness
        if let command = input["command"]?.stringValue {
            return command
        }
        if let filePath = input["file_path"]?.stringValue {
            return filePath
        }
        if let path = input["path"]?.stringValue {
            return path
        }
        if let pattern = input["pattern"]?.stringValue {
            return pattern
        }
        if let content = input["content"]?.stringValue {
            let truncated = content.prefix(80)
            return String(truncated)
        }

        // Fallback: show first string value
        for (_, value) in input {
            if let str = value.stringValue {
                return String(str.prefix(80))
            }
        }

        return nil
    }
}

#Preview("Running") {
    ToolActivityRow(
        activity: ToolActivity(
            id: "1",
            tool: "Bash",
            input: ["command": .string("npm install")],
            startedAt: Date()
        )
    )
    .background(MajorTomTheme.Colors.surface)
}

#Preview("Success") {
    ToolActivityRow(
        activity: ToolActivity(
            id: "2",
            tool: "Read",
            input: ["file_path": .string("/src/index.ts")],
            startedAt: Date().addingTimeInterval(-1.2),
            completedAt: Date(),
            success: true,
            output: "file contents..."
        )
    )
    .background(MajorTomTheme.Colors.surface)
}

#Preview("Failed") {
    ToolActivityRow(
        activity: ToolActivity(
            id: "3",
            tool: "Write",
            input: ["file_path": .string("/etc/hosts")],
            startedAt: Date().addingTimeInterval(-0.5),
            completedAt: Date(),
            success: false,
            output: "Permission denied"
        )
    )
    .background(MajorTomTheme.Colors.surface)
}

#Preview("Auto-approved") {
    ToolActivityRow(
        activity: ToolActivity(
            id: "4",
            tool: "Grep",
            input: ["pattern": .string("TODO")],
            startedAt: Date().addingTimeInterval(-0.3),
            completedAt: Date(),
            success: true
        ),
        autoApproval: AutoApprovedTool(
            tool: "Grep",
            description: "Search for TODO",
            reason: .smartSettings,
            timestamp: Date()
        )
    )
    .background(MajorTomTheme.Colors.surface)
}
