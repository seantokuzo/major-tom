import SwiftUI

struct GitLogView: View {
    let relay: RelayService
    @State private var expandedHash: String?

    var body: some View {
        if relay.gitLog.isEmpty {
            ContentUnavailableView("No Commits", systemImage: "clock", description: Text("No commit history"))
        } else {
            List {
                ForEach(relay.gitLog) { entry in
                    VStack(alignment: .leading, spacing: MajorTomTheme.Spacing.xs) {
                        Button {
                            if expandedHash == entry.hash {
                                expandedHash = nil
                                relay.gitShowCommit = nil
                            } else {
                                expandedHash = entry.hash
                                Task { try? await relay.requestGitShow(commitHash: entry.hash) }
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: MajorTomTheme.Spacing.xs) {
                                HStack {
                                    Text(entry.shortHash)
                                        .font(MajorTomTheme.Typography.codeFontSmall)
                                        .foregroundStyle(MajorTomTheme.Colors.accent)
                                    Spacer()
                                    Text(timeAgo(entry.date))
                                        .font(.caption2)
                                        .foregroundStyle(MajorTomTheme.Colors.textTertiary)
                                }
                                Text(entry.message)
                                    .font(.subheadline)
                                    .foregroundStyle(MajorTomTheme.Colors.textPrimary)
                                    .lineLimit(2)
                                Text(entry.author)
                                    .font(.caption2)
                                    .foregroundStyle(MajorTomTheme.Colors.textSecondary)
                            }
                        }
                        .buttonStyle(.plain)

                        if expandedHash == entry.hash, let show = relay.gitShowCommit, show.hash == entry.hash {
                            VStack(alignment: .leading, spacing: MajorTomTheme.Spacing.xs) {
                                Text(show.message)
                                    .font(MajorTomTheme.Typography.caption)
                                    .bold()
                                    .foregroundStyle(MajorTomTheme.Colors.textPrimary)
                                Text("\(show.author) \u{00B7} \(timeAgo(show.date))")
                                    .font(.caption2)
                                    .foregroundStyle(MajorTomTheme.Colors.textSecondary)
                                GitDiffView(diff: show.diff)
                            }
                            .padding(.top, MajorTomTheme.Spacing.xs)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(MajorTomTheme.Colors.background)
        }
    }

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
