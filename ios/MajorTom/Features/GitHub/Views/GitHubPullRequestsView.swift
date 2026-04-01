import SwiftUI

struct GitHubPullRequestsView: View {
    let relay: RelayService
    @State private var stateFilter: String = "open"
    @State private var expandedPR: Int?

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

            if relay.githubPullRequests.isEmpty {
                ContentUnavailableView("No Pull Requests", systemImage: "arrow.triangle.pull", description: Text("No pull requests found"))
            } else {
                List {
                    ForEach(relay.githubPullRequests) { pr in
                        VStack(alignment: .leading, spacing: MajorTomTheme.Spacing.xs) {
                            Button {
                                if expandedPR == pr.number {
                                    expandedPR = nil
                                    relay.githubPullRequestDetail = nil
                                } else {
                                    expandedPR = pr.number
                                    Task { try? await relay.requestGitHubPullRequestDetail(number: pr.number) }
                                }
                            } label: {
                                prRow(pr)
                            }
                            .buttonStyle(.plain)

                            if expandedPR == pr.number,
                               let detail = relay.githubPullRequestDetail,
                               detail.number == pr.number {
                                prDetailSection(detail)
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
            Task { try? await relay.requestGitHubPullRequests(state: stateFilter) }
        }
    }

    @ViewBuilder
    private func prRow(_ pr: GitHubPullRequestEntry) -> some View {
        VStack(alignment: .leading, spacing: MajorTomTheme.Spacing.xs) {
            HStack {
                Text("#\(pr.number)")
                    .font(MajorTomTheme.Typography.codeFontSmall)
                    .foregroundStyle(MajorTomTheme.Colors.accent)
                Text(pr.title)
                    .font(.subheadline)
                    .foregroundStyle(MajorTomTheme.Colors.textPrimary)
                    .lineLimit(2)
                Spacer()
                Image(systemName: expandedPR == pr.number ? "chevron.down" : "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(MajorTomTheme.Colors.textTertiary)
            }

            HStack(spacing: MajorTomTheme.Spacing.sm) {
                prStateBadge(state: pr.state, draft: pr.draft)

                Text(pr.author)
                    .font(.caption2)
                    .foregroundStyle(MajorTomTheme.Colors.textSecondary)

                Text(timeAgo(pr.createdAt))
                    .font(.caption2)
                    .foregroundStyle(MajorTomTheme.Colors.textTertiary)

                Spacer()
            }

            HStack(spacing: MajorTomTheme.Spacing.sm) {
                Text("\(pr.headBranch) \u{2192} \(pr.baseBranch)")
                    .font(MajorTomTheme.Typography.codeFontSmall)
                    .foregroundStyle(MajorTomTheme.Colors.textSecondary)
                    .lineLimit(1)

                Spacer()

                Text("+\(pr.additions)")
                    .font(MajorTomTheme.Typography.codeFontSmall)
                    .foregroundStyle(MajorTomTheme.Colors.allow)
                Text("-\(pr.deletions)")
                    .font(MajorTomTheme.Typography.codeFontSmall)
                    .foregroundStyle(MajorTomTheme.Colors.deny)

                if !pr.reviewDecision.isEmpty {
                    reviewDecisionBadge(pr.reviewDecision)
                }
            }
        }
    }

    @ViewBuilder
    private func prDetailSection(_ detail: GitHubPullRequestDetail) -> some View {
        VStack(alignment: .leading, spacing: MajorTomTheme.Spacing.md) {
            if !detail.body.isEmpty {
                Text(detail.body)
                    .font(MajorTomTheme.Typography.caption)
                    .foregroundStyle(MajorTomTheme.Colors.textSecondary)
                    .padding(MajorTomTheme.Spacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(MajorTomTheme.Colors.surface, in: RoundedRectangle(cornerRadius: MajorTomTheme.Radius.medium))
            }

            if !detail.checks.isEmpty {
                VStack(alignment: .leading, spacing: MajorTomTheme.Spacing.xs) {
                    Text("CI Checks")
                        .font(.caption.bold())
                        .foregroundStyle(MajorTomTheme.Colors.textSecondary)
                    ForEach(detail.checks) { check in
                        HStack(spacing: MajorTomTheme.Spacing.sm) {
                            checkIcon(check.conclusion)
                            Text(check.name)
                                .font(MajorTomTheme.Typography.codeFontSmall)
                                .foregroundStyle(MajorTomTheme.Colors.textPrimary)
                                .lineLimit(1)
                            Spacer()
                            Text(check.status)
                                .font(.caption2)
                                .foregroundStyle(MajorTomTheme.Colors.textTertiary)
                        }
                    }
                }
            }

            if !detail.reviews.isEmpty {
                VStack(alignment: .leading, spacing: MajorTomTheme.Spacing.xs) {
                    Text("Reviews")
                        .font(.caption.bold())
                        .foregroundStyle(MajorTomTheme.Colors.textSecondary)
                    ForEach(detail.reviews) { review in
                        HStack(spacing: MajorTomTheme.Spacing.sm) {
                            reviewStateBadge(review.state)
                            Text(review.author)
                                .font(.caption)
                                .foregroundStyle(MajorTomTheme.Colors.textPrimary)
                            Spacer()
                            Text(timeAgo(review.submittedAt))
                                .font(.caption2)
                                .foregroundStyle(MajorTomTheme.Colors.textTertiary)
                        }
                        if !review.body.isEmpty {
                            Text(review.body)
                                .font(.caption2)
                                .foregroundStyle(MajorTomTheme.Colors.textSecondary)
                                .padding(.leading, MajorTomTheme.Spacing.lg)
                        }
                    }
                }
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
    private func prStateBadge(state: String, draft: Bool) -> some View {
        if draft {
            Text("Draft")
                .font(.caption2.bold())
                .foregroundStyle(MajorTomTheme.Colors.textSecondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .overlay(Capsule().stroke(MajorTomTheme.Colors.textTertiary, lineWidth: 1))
        } else {
            Text(state.capitalized)
                .font(.caption2.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(prStateColor(state), in: Capsule())
        }
    }

    private func reviewDecisionBadge(_ decision: String) -> some View {
        let (label, color) = reviewDecisionInfo(decision)
        return Text(label)
            .font(.caption2.bold())
            .foregroundStyle(color)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .overlay(Capsule().stroke(color, lineWidth: 1))
    }

    private func reviewDecisionInfo(_ decision: String) -> (String, Color) {
        switch decision.lowercased() {
        case "approved": ("Approved", MajorTomTheme.Colors.allow)
        case "changes_requested": ("Changes", MajorTomTheme.Colors.deny)
        case "review_required": ("Review", MajorTomTheme.Colors.warning)
        default: (decision, MajorTomTheme.Colors.textTertiary)
        }
    }

    @ViewBuilder
    private func checkIcon(_ conclusion: String) -> some View {
        switch conclusion.lowercased() {
        case "success":
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(MajorTomTheme.Colors.allow)
                .font(.caption)
        case "failure":
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(MajorTomTheme.Colors.deny)
                .font(.caption)
        default:
            Image(systemName: "circle")
                .foregroundStyle(MajorTomTheme.Colors.textTertiary)
                .font(.caption)
        }
    }

    private func reviewStateBadge(_ state: String) -> some View {
        let (label, color) = reviewStateInfo(state)
        return Text(label)
            .font(.caption2.bold())
            .foregroundStyle(color)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .overlay(Capsule().stroke(color, lineWidth: 1))
    }

    private func reviewStateInfo(_ state: String) -> (String, Color) {
        switch state.lowercased() {
        case "approved": ("Approved", MajorTomTheme.Colors.allow)
        case "changes_requested": ("Changes Requested", MajorTomTheme.Colors.deny)
        case "commented": ("Commented", MajorTomTheme.Colors.accent)
        case "dismissed": ("Dismissed", MajorTomTheme.Colors.textTertiary)
        default: (state, MajorTomTheme.Colors.textTertiary)
        }
    }

    private func prStateColor(_ state: String) -> Color {
        switch state.lowercased() {
        case "open": MajorTomTheme.Colors.allow
        case "merged": MajorTomTheme.Colors.accent
        case "closed": MajorTomTheme.Colors.deny
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
