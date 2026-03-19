import SwiftUI

// MARK: - Agent Inspector View

/// Overlay panel showing details about a selected agent.
/// Presented as a sheet when an agent sprite is tapped.
struct AgentInspectorView: View {
    let agent: AgentState
    let onRename: (String) -> Void
    let onDismiss: () -> Void

    @State private var isRenaming = false
    @State private var renameText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: MajorTomTheme.Spacing.md) {
            // Header
            header

            Divider()
                .background(MajorTomTheme.Colors.textTertiary)

            // Details
            detailRows

            // Current task
            if let task = agent.currentTask {
                taskSection(task)
            }

            Spacer()

            // Actions
            actions
        }
        .padding(MajorTomTheme.Spacing.lg)
        .background(MajorTomTheme.Colors.surface)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Components

    private var header: some View {
        HStack {
            // Character color indicator
            Circle()
                .fill(CharacterCatalog.config(for: agent.characterType).spriteColor)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(agent.name)
                    .font(MajorTomTheme.Typography.headline)
                    .foregroundStyle(MajorTomTheme.Colors.textPrimary)

                Text(CharacterCatalog.config(for: agent.characterType).displayName)
                    .font(MajorTomTheme.Typography.caption)
                    .foregroundStyle(MajorTomTheme.Colors.textSecondary)
            }

            Spacer()

            statusBadge
        }
    }

    private var statusBadge: some View {
        Text(agent.status.rawValue.uppercased())
            .font(.system(.caption2, design: .monospaced, weight: .bold))
            .foregroundStyle(statusColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(statusColor.opacity(0.15))
            .clipShape(Capsule())
    }

    private var statusColor: Color {
        switch agent.status {
        case .spawning: return .gray
        case .walking: return .blue
        case .working: return MajorTomTheme.Colors.allow
        case .idle: return MajorTomTheme.Colors.accent
        case .celebrating: return .yellow
        case .leaving: return MajorTomTheme.Colors.deny
        }
    }

    private var detailRows: some View {
        VStack(alignment: .leading, spacing: MajorTomTheme.Spacing.sm) {
            detailRow(label: "Role", value: agent.role)
            detailRow(label: "Agent ID", value: String(agent.id.prefix(12)) + "...")
            detailRow(label: "Desk", value: agent.deskIndex.map { "Desk \($0 + 1)" } ?? "None")
            detailRow(label: "Uptime", value: agent.uptime)
        }
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(MajorTomTheme.Typography.caption)
                .foregroundStyle(MajorTomTheme.Colors.textTertiary)
                .frame(width: 80, alignment: .leading)

            Text(value)
                .font(MajorTomTheme.Typography.codeFontSmall)
                .foregroundStyle(MajorTomTheme.Colors.textSecondary)
        }
    }

    private func taskSection(_ task: String) -> some View {
        VStack(alignment: .leading, spacing: MajorTomTheme.Spacing.xs) {
            Text("Current Task")
                .font(MajorTomTheme.Typography.caption)
                .foregroundStyle(MajorTomTheme.Colors.textTertiary)

            Text(task)
                .font(MajorTomTheme.Typography.codeFontSmall)
                .foregroundStyle(MajorTomTheme.Colors.textPrimary)
                .padding(MajorTomTheme.Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(MajorTomTheme.Colors.background)
                .clipShape(RoundedRectangle(cornerRadius: MajorTomTheme.Radius.small))
        }
    }

    private var actions: some View {
        HStack(spacing: MajorTomTheme.Spacing.md) {
            // Rename button
            Button {
                renameText = agent.name
                isRenaming = true
            } label: {
                Label("Rename", systemImage: "pencil")
                    .font(MajorTomTheme.Typography.caption)
            }
            .buttonStyle(.bordered)
            .tint(MajorTomTheme.Colors.accent)
            .alert("Rename Agent", isPresented: $isRenaming) {
                TextField("Name", text: $renameText)
                Button("Cancel", role: .cancel) {}
                Button("Rename") {
                    if !renameText.isEmpty {
                        onRename(renameText)
                    }
                }
            } message: {
                Text("Enter a new display name for this agent.")
            }

            Spacer()

            // Dismiss button
            Button {
                onDismiss()
            } label: {
                Label("Close", systemImage: "xmark.circle")
                    .font(MajorTomTheme.Typography.caption)
            }
            .buttonStyle(.bordered)
            .tint(MajorTomTheme.Colors.textTertiary)
        }
    }
}
