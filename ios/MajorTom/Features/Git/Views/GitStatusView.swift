import SwiftUI

struct GitStatusView: View {
    let relay: RelayService
    @State private var expandedFile: String?

    private var stagedEntries: [GitStatusEntry] {
        relay.gitStatus.filter { $0.staged }
    }
    private var unstagedEntries: [GitStatusEntry] {
        relay.gitStatus.filter { !$0.staged && $0.status != "untracked" }
    }
    private var untrackedEntries: [GitStatusEntry] {
        relay.gitStatus.filter { $0.status == "untracked" }
    }

    var body: some View {
        if relay.gitStatus.isEmpty {
            ContentUnavailableView("Clean", systemImage: "checkmark.circle", description: Text("Working tree clean"))
        } else {
            List {
                if !stagedEntries.isEmpty {
                    Section("Staged (\(stagedEntries.count))") {
                        ForEach(stagedEntries) { entry in
                            fileRow(entry, key: "\(entry.path):true")
                        }
                    }
                }
                if !unstagedEntries.isEmpty {
                    Section("Unstaged (\(unstagedEntries.count))") {
                        ForEach(unstagedEntries) { entry in
                            fileRow(entry, key: "\(entry.path):false")
                        }
                    }
                }
                if !untrackedEntries.isEmpty {
                    Section("Untracked (\(untrackedEntries.count))") {
                        ForEach(untrackedEntries) { entry in
                            HStack(spacing: MajorTomTheme.Spacing.sm) {
                                Text("?")
                                    .font(MajorTomTheme.Typography.codeFontSmall)
                                    .bold()
                                    .foregroundStyle(MajorTomTheme.Colors.allow)
                                    .frame(width: 16)
                                Text(entry.path)
                                    .font(MajorTomTheme.Typography.codeFontSmall)
                                    .foregroundStyle(MajorTomTheme.Colors.textPrimary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(MajorTomTheme.Colors.background)
        }
    }

    @ViewBuilder
    private func fileRow(_ entry: GitStatusEntry, key: String) -> some View {
        VStack(alignment: .leading, spacing: MajorTomTheme.Spacing.xs) {
            Button {
                if expandedFile == key {
                    expandedFile = nil
                } else {
                    expandedFile = key
                    Task {
                        try? await relay.requestGitDiff(path: entry.path, staged: entry.staged)
                    }
                }
            } label: {
                HStack(spacing: MajorTomTheme.Spacing.sm) {
                    Text(statusLabel(entry.status))
                        .font(MajorTomTheme.Typography.codeFontSmall)
                        .bold()
                        .foregroundStyle(statusColor(entry.status))
                        .frame(width: 16)
                    Text(entry.path)
                        .font(MajorTomTheme.Typography.codeFontSmall)
                        .foregroundStyle(MajorTomTheme.Colors.textPrimary)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: expandedFile == key ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(MajorTomTheme.Colors.textTertiary)
                }
            }
            .buttonStyle(.plain)

            if expandedFile == key && !relay.gitDiff.isEmpty {
                GitDiffView(diff: relay.gitDiff)
            }
        }
    }

    private func statusLabel(_ status: String) -> String {
        switch status {
        case "added": return "A"
        case "modified": return "M"
        case "deleted": return "D"
        case "renamed": return "R"
        case "copied": return "C"
        default: return "?"
        }
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "added": return MajorTomTheme.Colors.allow
        case "modified": return MajorTomTheme.Colors.warning
        case "deleted": return MajorTomTheme.Colors.deny
        case "renamed", "copied": return MajorTomTheme.Colors.accent
        default: return MajorTomTheme.Colors.textSecondary
        }
    }
}
