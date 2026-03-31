import SwiftUI

struct TeamActivityView: View {
    private let relay: RelayService
    @State private var isLoading = false

    init(relay: RelayService) {
        self.relay = relay
    }

    var body: some View {
        List {
            if relay.activityEntries.isEmpty && !isLoading {
                ContentUnavailableView(
                    "No Activity",
                    systemImage: "person.3",
                    description: Text("Team activity will appear here")
                )
                .listRowBackground(Color.clear)
            } else if relay.activityEntries.isEmpty && isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                        .tint(MajorTomTheme.Colors.accent)
                    Spacer()
                }
                .listRowBackground(Color.clear)
            } else {
                ForEach(relay.activityEntries) { entry in
                    ActivityRow(entry: entry)
                        .listRowBackground(MajorTomTheme.Colors.surface)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(MajorTomTheme.Colors.background)
        .navigationTitle("Team Activity")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            isLoading = true
            defer { isLoading = false }
            do {
                let counterBefore = relay.responseCounter
                try await relay.requestActivityFeed()
                for _ in 0..<40 {
                    if Task.isCancelled { break }
                    if relay.responseCounter != counterBefore { break }
                    try await Task.sleep(for: .milliseconds(50))
                }
            } catch {
                // Silent fail
            }
        }
    }
}

// MARK: - Activity Row

struct ActivityRow: View {
    let entry: ActivityEntry

    var body: some View {
        HStack(alignment: .top, spacing: MajorTomTheme.Spacing.md) {
            Image(systemName: iconForAction(entry.action))
                .foregroundStyle(colorForAction(entry.action))
                .font(.body)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: MajorTomTheme.Spacing.sm) {
                    Text(entry.userName)
                        .font(MajorTomTheme.Typography.headline)
                        .foregroundStyle(MajorTomTheme.Colors.textPrimary)
                    Text(entry.action)
                        .font(MajorTomTheme.Typography.body)
                        .foregroundStyle(MajorTomTheme.Colors.textSecondary)
                }

                if let date = entry.timestampDate {
                    Text(date, style: .relative)
                        .font(MajorTomTheme.Typography.caption)
                        .foregroundStyle(MajorTomTheme.Colors.textTertiary)
                }
            }
        }
    }

    private func iconForAction(_ action: String) -> String {
        if action.contains("connect") { return "antenna.radiowaves.left.and.right" }
        if action.contains("disconnect") { return "antenna.radiowaves.left.and.right.slash" }
        if action.contains("session") { return "terminal" }
        if action.contains("approve") { return "checkmark.circle" }
        if action.contains("deny") { return "xmark.circle" }
        if action.contains("prompt") { return "text.bubble" }
        if action.contains("handoff") { return "arrow.triangle.swap" }
        if action.contains("invite") { return "person.badge.plus" }
        return "person.circle"
    }

    private func colorForAction(_ action: String) -> Color {
        if action.contains("approve") { return MajorTomTheme.Colors.allow }
        if action.contains("deny") { return MajorTomTheme.Colors.deny }
        if action.contains("disconnect") { return MajorTomTheme.Colors.textTertiary }
        return MajorTomTheme.Colors.accent
    }
}

#Preview {
    NavigationStack {
        TeamActivityView(relay: RelayService())
    }
    .preferredColorScheme(.dark)
}
