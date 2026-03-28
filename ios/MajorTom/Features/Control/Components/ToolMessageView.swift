import SwiftUI

struct ToolMessageView: View {
    let message: ChatMessage
    @State private var isExpanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Collapsed header — always visible
            toolHeader
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                    HapticService.buttonTap()
                }

            // Expanded output
            if isExpanded, let output = message.toolOutput, !output.isEmpty {
                toolOutput(output)
            }
        }
        .background(MajorTomTheme.Colors.surface.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: MajorTomTheme.Radius.small))
    }

    // MARK: - Header

    private var toolHeader: some View {
        HStack(spacing: MajorTomTheme.Spacing.sm) {
            // Tool icon
            Image(systemName: toolIcon)
                .font(.caption)
                .foregroundStyle(MajorTomTheme.Colors.textTertiary)
                .frame(width: 20, height: 20)

            // Tool name
            Text(message.toolName ?? "tool")
                .font(MajorTomTheme.Typography.codeFontSmall)
                .foregroundStyle(MajorTomTheme.Colors.textSecondary)

            Spacer()

            // Status badge
            statusBadge

            // Expand chevron (if has output)
            if message.toolOutput != nil, !(message.toolOutput?.isEmpty ?? true) {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(MajorTomTheme.Colors.textTertiary)
            }
        }
        .padding(.horizontal, MajorTomTheme.Spacing.md)
        .padding(.vertical, MajorTomTheme.Spacing.sm)
    }

    // MARK: - Status Badge

    @ViewBuilder
    private var statusBadge: some View {
        switch message.toolStatus {
        case .running:
            HStack(spacing: MajorTomTheme.Spacing.xs) {
                ProgressView()
                    .scaleEffect(0.6)
                    .tint(MajorTomTheme.Colors.accent)
                Text("running")
                    .font(.caption2)
                    .foregroundStyle(MajorTomTheme.Colors.accent)
            }
        case .success:
            HStack(spacing: MajorTomTheme.Spacing.xs) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(MajorTomTheme.Colors.allow)
                Text("done")
                    .font(.caption2)
                    .foregroundStyle(MajorTomTheme.Colors.allow)
            }
        case .failure:
            HStack(spacing: MajorTomTheme.Spacing.xs) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(MajorTomTheme.Colors.deny)
                Text("failed")
                    .font(.caption2)
                    .foregroundStyle(MajorTomTheme.Colors.deny)
            }
        case .none:
            EmptyView()
        }
    }

    // MARK: - Output

    private func toolOutput(_ output: String) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(output)
                .font(MajorTomTheme.Typography.codeFontSmall)
                .foregroundStyle(MajorTomTheme.Colors.textTertiary)
                .textSelection(.enabled)
                .padding(MajorTomTheme.Spacing.md)
        }
        .frame(maxHeight: 200)
        .background(Color(white: 0.05))
    }

    // MARK: - Tool Icon Mapping

    private var toolIcon: String {
        guard let name = message.toolName?.lowercased() else { return "wrench" }

        if name.contains("bash") || name.contains("terminal") || name.contains("exec") {
            return "terminal"
        } else if name.contains("read") || name.contains("cat") {
            return "doc.text"
        } else if name.contains("edit") || name.contains("write") || name.contains("patch") {
            return "pencil"
        } else if name.contains("search") || name.contains("grep") || name.contains("glob") || name.contains("find") {
            return "magnifyingglass"
        } else if name.contains("list") || name.contains("ls") {
            return "list.bullet"
        } else if name.contains("git") {
            return "arrow.triangle.branch"
        } else if name.contains("web") || name.contains("fetch") || name.contains("http") {
            return "globe"
        } else if name.contains("file") {
            return "doc"
        } else {
            return "wrench"
        }
    }
}

#Preview {
    VStack(spacing: 8) {
        ToolMessageView(message: ChatMessage(
            role: .tool,
            content: "Using Bash...",
            toolName: "Bash",
            toolStatus: .running
        ))

        ToolMessageView(message: ChatMessage(
            role: .tool,
            content: "Read completed",
            toolName: "Read",
            toolStatus: .success,
            toolOutput: "Line 1: import SwiftUI\nLine 2: \nLine 3: struct MyView: View {"
        ))

        ToolMessageView(message: ChatMessage(
            role: .tool,
            content: "Edit failed",
            toolName: "Edit",
            toolStatus: .failure,
            toolOutput: "Error: File not found"
        ))

        ToolMessageView(message: ChatMessage(
            role: .tool,
            content: "Searching...",
            toolName: "Grep",
            toolStatus: .success,
            toolOutput: "Found 3 matches in 2 files"
        ))
    }
    .padding()
    .background(MajorTomTheme.Colors.background)
}
