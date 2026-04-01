import SwiftUI

struct GitHubIssuesView: View {
    let relay: RelayService
    @State private var stateFilter: String = "open"
    @State private var expandedIssue: Int?

    var body: some View {
        VStack(spacing: 0) {
            Picker("State", selection: $stateFilter) {
                Text("Open").tag("open")
                Text("Closed").tag("closed")
                Text("All").tag("all")
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, MajorTomTheme.Spacing.lg)
            .padding(.vertical, MajorTomTheme.Spacing.sm)

            if relay.githubIssues.isEmpty {
                ContentUnavailableView("No Issues", systemImage: "exclamationmark.circle", description: Text("No issues found"))
            } else {
                List {
                    ForEach(relay.githubIssues) { issue in
                        VStack(alignment: .leading, spacing: MajorTomTheme.Spacing.xs) {
                            Button {
                                if expandedIssue == issue.number {
                                    expandedIssue = nil
                                    relay.githubIssueDetail = nil
                                } else {
                                    expandedIssue = issue.number
                                    Task { try? await relay.requestGitHubIssueDetail(number: issue.number) }
                                }
                            } label: {
                                issueRow(issue)
                            }
                            .buttonStyle(.plain)

                            if expandedIssue == issue.number,
                               let detail = relay.githubIssueDetail,
                               detail.number == issue.number {
                                issueDetailSection(detail)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(MajorTomTheme.Colors.background)
            }
        }
        .onChange(of: stateFilter) {
            Task { try? await relay.requestGitHubIssues(state: stateFilter) }
        }
    }

    @ViewBuilder
    private func issueRow(_ issue: GitHubIssueEntry) -> some View {
        VStack(alignment: .leading, spacing: MajorTomTheme.Spacing.xs) {
            HStack {
                Text("#\(issue.number)")
                    .font(MajorTomTheme.Typography.codeFontSmall)
                    .foregroundStyle(MajorTomTheme.Colors.accent)
                Text(issue.title)
                    .font(.subheadline)
                    .foregroundStyle(MajorTomTheme.Colors.textPrimary)
                    .lineLimit(2)
                Spacer()
                Image(systemName: expandedIssue == issue.number ? "chevron.down" : "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(MajorTomTheme.Colors.textTertiary)
            }

            HStack(spacing: MajorTomTheme.Spacing.sm) {
                issueStateBadge(issue.state)

                Text(issue.author)
                    .font(.caption2)
                    .foregroundStyle(MajorTomTheme.Colors.textSecondary)

                Text(timeAgo(issue.createdAt))
                    .font(.caption2)
                    .foregroundStyle(MajorTomTheme.Colors.textTertiary)

                Spacer()

                if issue.commentCount > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "bubble.left")
                            .font(.caption2)
                        Text("\(issue.commentCount)")
                            .font(.caption2)
                    }
                    .foregroundStyle(MajorTomTheme.Colors.textTertiary)
                }
            }

            if !issue.labels.isEmpty {
                FlowLayout(spacing: 4) {
                    ForEach(issue.labels, id: \.self) { label in
                        Text(label)
                            .font(.caption2)
                            .foregroundStyle(MajorTomTheme.Colors.accent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(MajorTomTheme.Colors.accentSubtle, in: Capsule())
                    }
                }
            }

            if !issue.assignees.isEmpty {
                HStack(spacing: MajorTomTheme.Spacing.xs) {
                    Image(systemName: "person")
                        .font(.caption2)
                        .foregroundStyle(MajorTomTheme.Colors.textTertiary)
                    Text(issue.assignees.joined(separator: ", "))
                        .font(.caption2)
                        .foregroundStyle(MajorTomTheme.Colors.textSecondary)
                        .lineLimit(1)
                }
            }
        }
    }

    @ViewBuilder
    private func issueDetailSection(_ detail: GitHubIssueDetail) -> some View {
        VStack(alignment: .leading, spacing: MajorTomTheme.Spacing.md) {
            if !detail.body.isEmpty {
                Text(detail.body)
                    .font(MajorTomTheme.Typography.caption)
                    .foregroundStyle(MajorTomTheme.Colors.textSecondary)
                    .padding(MajorTomTheme.Spacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(MajorTomTheme.Colors.surface, in: RoundedRectangle(cornerRadius: MajorTomTheme.Radius.medium))
            }

            if !detail.comments.isEmpty {
                VStack(alignment: .leading, spacing: MajorTomTheme.Spacing.xs) {
                    Text("Comments")
                        .font(.caption.bold())
                        .foregroundStyle(MajorTomTheme.Colors.textSecondary)
                    ForEach(detail.comments) { comment in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(comment.author)
                                    .font(.caption.bold())
                                    .foregroundStyle(MajorTomTheme.Colors.textPrimary)
                                Spacer()
                                Text(timeAgo(comment.createdAt))
                                    .font(.caption2)
                                    .foregroundStyle(MajorTomTheme.Colors.textTertiary)
                            }
                            Text(comment.body)
                                .font(.caption2)
                                .foregroundStyle(MajorTomTheme.Colors.textSecondary)
                        }
                        .padding(MajorTomTheme.Spacing.sm)
                        .background(MajorTomTheme.Colors.surface, in: RoundedRectangle(cornerRadius: MajorTomTheme.Radius.small))
                    }
                }
            }
        }
        .padding(.top, MajorTomTheme.Spacing.xs)
    }

    @ViewBuilder
    private func issueStateBadge(_ state: String) -> some View {
        Text(state.capitalized)
            .font(.caption2.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(issueStateColor(state), in: Capsule())
    }

    private func issueStateColor(_ state: String) -> Color {
        switch state.lowercased() {
        case "open": MajorTomTheme.Colors.allow
        case "closed": MajorTomTheme.Colors.accent
        default: MajorTomTheme.Colors.textTertiary
        }
    }

    // MARK: - Time Formatting

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoFormatterBasic = ISO8601DateFormatter()

    private func timeAgo(_ dateStr: String) -> String {
        guard let date = Self.isoFormatter.date(from: dateStr) ?? Self.isoFormatterBasic.date(from: dateStr) else {
            return dateStr
        }
        let diff = Date().timeIntervalSince(date)
        let mins = Int(diff / 60)
        if mins < 1 { return "just now" }
        if mins < 60 { return "\(mins)m ago" }
        let hrs = mins / 60
        if hrs < 24 { return "\(hrs)h ago" }
        let days = hrs / 24
        if days < 30 { return "\(days)d ago" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}

// MARK: - Flow Layout

private struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }

        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
