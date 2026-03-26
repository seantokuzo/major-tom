import SwiftUI

struct CommandPaletteView: View {
    let query: String
    var onSelectCommand: (SlashCommand) -> Void

    private var commands: [SlashCommand] {
        SlashCommand.search(query)
    }

    var body: some View {
        if !commands.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(commands) { command in
                    commandRow(command)

                    if command.id != commands.last?.id {
                        Divider()
                            .background(MajorTomTheme.Colors.textTertiary.opacity(0.2))
                    }
                }
            }
            .background(MajorTomTheme.Colors.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: MajorTomTheme.Radius.medium))
            .shadow(color: .black.opacity(0.3), radius: 10, y: -3)
            .padding(.horizontal, MajorTomTheme.Spacing.md)
            .padding(.bottom, MajorTomTheme.Spacing.sm)
        }
    }

    private func commandRow(_ command: SlashCommand) -> some View {
        Button {
            HapticService.buttonTap()
            onSelectCommand(command)
        } label: {
            HStack(spacing: MajorTomTheme.Spacing.md) {
                Image(systemName: command.icon)
                    .font(.body)
                    .foregroundStyle(MajorTomTheme.Colors.accent)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text("/\(command.name)")
                        .font(MajorTomTheme.Typography.headline)
                        .foregroundStyle(MajorTomTheme.Colors.textPrimary)

                    Text(command.description)
                        .font(MajorTomTheme.Typography.caption)
                        .foregroundStyle(MajorTomTheme.Colors.textSecondary)
                }

                Spacer()
            }
            .padding(.horizontal, MajorTomTheme.Spacing.lg)
            .padding(.vertical, MajorTomTheme.Spacing.md)
            .contentShape(Rectangle())
        }
    }
}

#Preview {
    VStack {
        Spacer()
        CommandPaletteView(
            query: "",
            onSelectCommand: { cmd in print(cmd.name) }
        )
    }
    .background(MajorTomTheme.Colors.background)
    .preferredColorScheme(.dark)
}

#Preview("Filtered") {
    VStack {
        Spacer()
        CommandPaletteView(
            query: "cl",
            onSelectCommand: { cmd in print(cmd.name) }
        )
    }
    .background(MajorTomTheme.Colors.background)
    .preferredColorScheme(.dark)
}
