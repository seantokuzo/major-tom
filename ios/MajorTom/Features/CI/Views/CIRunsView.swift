import SwiftUI

struct CIRunsView: View {
    let relay: RelayService
    @State private var expandedRun: Int?

    var body: some View {
        if relay.ciRuns.isEmpty {
            ContentUnavailableView("No CI Runs", systemImage: "gearshape.2", description: Text("No workflow runs found"))
        } else {
            List {
                ForEach(relay.ciRuns) { run in
                    VStack(alignment: .leading, spacing: MajorTomTheme.Spacing.xs) {
                        Button {
                            if expandedRun == run.id {
                                expandedRun = nil
                                relay.ciRunDetail = nil
                            } else {
                                expandedRun = run.id
                                Task { try? await relay.requestCIRunDetail(runId: run.id) }
                            }
                        } label: {
                            runRow(run)
                        }
                        .buttonStyle(.plain)

                        if expandedRun == run.id,
                           let detail = relay.ciRunDetail,
                           detail.id == run.id {
                            runDetailSection(detail)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(MajorTomTheme.Colors.background)
        }
    }

    // MARK: - Run Row

    @ViewBuilder
    private func runRow(_ run: CIRunEntry) -> some View {
        VStack(alignment: .leading, spacing: MajorTomTheme.Spacing.xs) {
            HStack {
                statusIcon(status: run.status, conclusion: run.conclusion)
                Text(run.name)
                    .font(.subheadline.bold())
                    .foregroundStyle(MajorTomTheme.Colors.textPrimary)
                    .lineLimit(1)
                Spacer()
                Image(systemName: expandedRun == run.id ? "chevron.down" : "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(MajorTomTheme.Colors.textTertiary)
            }

            Text(run.displayTitle)
                .font(.caption)
                .foregroundStyle(MajorTomTheme.Colors.textSecondary)
                .lineLimit(2)

            HStack(spacing: MajorTomTheme.Spacing.sm) {
                Text(run.headBranch)
                    .font(MajorTomTheme.Typography.codeFontSmall)
                    .foregroundStyle(MajorTomTheme.Colors.accent)
                    .lineLimit(1)

                eventBadge(run.event)

                Spacer()

                if !run.conclusion.isEmpty && run.conclusion != "null" {
                    conclusionBadge(run.conclusion)
                }
            }

            HStack(spacing: MajorTomTheme.Spacing.sm) {
                Text(run.actor)
                    .font(.caption2)
                    .foregroundStyle(MajorTomTheme.Colors.textSecondary)

                Text(timeAgo(run.createdAt))
                    .font(.caption2)
                    .foregroundStyle(MajorTomTheme.Colors.textTertiary)

                Spacer()
            }
        }
    }

    // MARK: - Run Detail

    @ViewBuilder
    private func runDetailSection(_ detail: CIRunDetailEntry) -> some View {
        VStack(alignment: .leading, spacing: MajorTomTheme.Spacing.md) {
            if !detail.headSha.isEmpty {
                HStack(spacing: MajorTomTheme.Spacing.xs) {
                    Text("SHA:")
                        .font(.caption.bold())
                        .foregroundStyle(MajorTomTheme.Colors.textSecondary)
                    Text(String(detail.headSha.prefix(8)))
                        .font(MajorTomTheme.Typography.codeFontSmall)
                        .foregroundStyle(MajorTomTheme.Colors.textPrimary)
                }
            }

            if !detail.jobs.isEmpty {
                VStack(alignment: .leading, spacing: MajorTomTheme.Spacing.xs) {
                    Text("Jobs")
                        .font(.caption.bold())
                        .foregroundStyle(MajorTomTheme.Colors.textSecondary)

                    ForEach(detail.jobs) { job in
                        HStack(spacing: MajorTomTheme.Spacing.sm) {
                            statusIcon(status: job.status, conclusion: job.conclusion)
                            Text(job.name)
                                .font(MajorTomTheme.Typography.codeFontSmall)
                                .foregroundStyle(MajorTomTheme.Colors.textPrimary)
                                .lineLimit(1)
                            Spacer()
                            if let duration = jobDuration(startedAt: job.startedAt, completedAt: job.completedAt) {
                                Text(duration)
                                    .font(.caption2)
                                    .foregroundStyle(MajorTomTheme.Colors.textTertiary)
                            }
                        }
                    }
                }
            }
        }
        .padding(.top, MajorTomTheme.Spacing.xs)
    }

    // MARK: - Status Icon

    @ViewBuilder
    private func statusIcon(status: String, conclusion: String) -> some View {
        switch conclusion.lowercased() {
        case "success":
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(MajorTomTheme.Colors.allow)
                .font(.caption)
        case "failure":
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(MajorTomTheme.Colors.deny)
                .font(.caption)
        case "cancelled":
            Image(systemName: "circle.dashed")
                .foregroundStyle(MajorTomTheme.Colors.textTertiary)
                .font(.caption)
        default:
            switch status.lowercased() {
            case "in_progress":
                Image(systemName: "arrow.circlepath")
                    .foregroundStyle(MajorTomTheme.Colors.warning)
                    .font(.caption)
            case "queued", "waiting", "pending":
                Image(systemName: "circle.dashed")
                    .foregroundStyle(MajorTomTheme.Colors.textTertiary)
                    .font(.caption)
            default:
                Image(systemName: "circle")
                    .foregroundStyle(MajorTomTheme.Colors.textTertiary)
                    .font(.caption)
            }
        }
    }

    // MARK: - Badges

    private func eventBadge(_ event: String) -> some View {
        Text(event)
            .font(.caption2.bold())
            .foregroundStyle(MajorTomTheme.Colors.textSecondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .overlay(Capsule().stroke(MajorTomTheme.Colors.textTertiary, lineWidth: 1))
    }

    private func conclusionBadge(_ conclusion: String) -> some View {
        let color = conclusionColor(conclusion)
        return Text(conclusion.capitalized)
            .font(.caption2.bold())
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .overlay(Capsule().stroke(color, lineWidth: 1))
    }

    private func conclusionColor(_ conclusion: String) -> Color {
        switch conclusion.lowercased() {
        case "success": MajorTomTheme.Colors.allow
        case "failure": MajorTomTheme.Colors.deny
        case "cancelled": MajorTomTheme.Colors.textTertiary
        default: MajorTomTheme.Colors.warning
        }
    }

    // MARK: - Duration

    private func jobDuration(startedAt: String?, completedAt: String?) -> String? {
        guard let start = startedAt,
              let end = completedAt,
              let startDate = Self.isoFormatter.date(from: start) ?? Self.isoFormatterBasic.date(from: start),
              let endDate = Self.isoFormatter.date(from: end) ?? Self.isoFormatterBasic.date(from: end) else {
            return nil
        }
        let seconds = Int(endDate.timeIntervalSince(startDate))
        if seconds < 60 { return "\(seconds)s" }
        let mins = seconds / 60
        let secs = seconds % 60
        if mins < 60 { return "\(mins)m \(secs)s" }
        let hrs = mins / 60
        let remainingMins = mins % 60
        return "\(hrs)h \(remainingMins)m"
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
