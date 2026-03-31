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

    private enum ActionCategory {
        case connect, disconnect, session, approve, deny, prompt, handoff, invite, unknown
    }

    private func categorize(_ action: String) -> ActionCategory {
        let lower = action.lowercased()

        // Order matters: check "disconnect" before "connect" since "disconnect" contains "connect"
        if lower.contains("disconnect") { return .disconnect }
        if lower.contains("connect") { return .connect }
        if lower.contains("session") { return .session }
        // Approval: approved, approve, approval, allow
        if lower.contains("approv") || lower.contains("allow") { return .approve }
        // Denial: denied, deny
        if lower.contains("den") { return .deny }
        if lower.contains("prompt") { return .prompt }
        // Handoff: handoff, handed off, hand off
        if lower.contains("handoff") || lower.contains("handed") || lower.contains("hand off") { return .handoff }
        // Invite: invite, invited
        if lower.contains("invit") { return .invite }
        return .unknown
    }

    private func iconForAction(_ action: String) -> String {
        switch categorize(action) {
        case .connect:    return "antenna.radiowaves.left.and.right"
        case .disconnect: return "antenna.radiowaves.left.and.right.slash"
        case .session:    return "terminal"
        case .approve:    return "checkmark.circle"
        case .deny:       return "xmark.circle"
        case .prompt:     return "text.bubble"
        case .handoff:    return "arrow.triangle.swap"
        case .invite:     return "person.badge.plus"
        case .unknown:    return "person.circle"
        }
    }

    private func colorForAction(_ action: String) -> Color {
        switch categorize(action) {
        case .approve:    return MajorTomTheme.Colors.allow
        case .deny:       return MajorTomTheme.Colors.deny
        case .disconnect: return MajorTomTheme.Colors.textTertiary
        default:          return MajorTomTheme.Colors.accent
        }
    }
}

#Preview {
    NavigationStack {
        TeamActivityView(relay: RelayService())
    }
    .preferredColorScheme(.dark)
}
