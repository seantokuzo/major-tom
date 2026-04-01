import SwiftUI

struct GitBranchesView: View {
    let relay: RelayService

    private var localBranches: [GitBranchEntry] {
        relay.gitBranches.filter { !$0.remote }
    }
    private var remoteBranches: [GitBranchEntry] {
        relay.gitBranches.filter { $0.remote }
    }

    var body: some View {
        if relay.gitBranches.isEmpty {
            ContentUnavailableView("No Branches", systemImage: "arrow.triangle.branch", description: Text("No branches found"))
        } else {
            List {
                if !localBranches.isEmpty {
                    Section("Local") {
                        ForEach(localBranches) { branch in
                            HStack {
                                HStack(spacing: MajorTomTheme.Spacing.xs) {
                                    if branch.current {
                                        Text("*")
                                            .foregroundStyle(MajorTomTheme.Colors.accent)
                                            .bold()
                                    }
                                    Text(branch.name)
                                        .font(.subheadline.monospaced())
                                        .foregroundStyle(branch.current ? MajorTomTheme.Colors.accent : MajorTomTheme.Colors.textPrimary)
                                }
                                Spacer()
                                HStack(spacing: MajorTomTheme.Spacing.sm) {
                                    if let upstream = branch.upstream {
                                        Text(upstream)
                                            .font(.caption2)
                                            .foregroundStyle(MajorTomTheme.Colors.textSecondary)
                                            .lineLimit(1)
                                    }
                                    if let ahead = branch.ahead, ahead > 0 {
                                        Text("+\(ahead)")
                                            .font(.caption2.monospaced())
                                            .foregroundStyle(MajorTomTheme.Colors.allow)
                                    }
                                    if let behind = branch.behind, behind > 0 {
                                        Text("-\(behind)")
                                            .font(.caption2.monospaced())
                                            .foregroundStyle(MajorTomTheme.Colors.deny)
                                    }
                                }
                            }
                        }
                    }
                }
                if !remoteBranches.isEmpty {
                    Section("Remote") {
                        ForEach(remoteBranches) { branch in
                            Text(branch.name)
                                .font(.subheadline.monospaced())
                                .foregroundStyle(MajorTomTheme.Colors.textSecondary)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(MajorTomTheme.Colors.background)
        }
    }
}
