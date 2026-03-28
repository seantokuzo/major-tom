import Foundation

@Observable
@MainActor
final class ToolActivityViewModel {
    enum Tab: String, CaseIterable {
        case active = "Active"
        case all = "All"
    }

    var selectedTab: Tab = .active

    private let relay: RelayService
    private static let autoApprovalMatchWindowSeconds: TimeInterval = 2.0

    init(relay: RelayService) {
        self.relay = relay
    }

    // MARK: - Data Access

    var activeTools: [ToolActivity] {
        relay.activeTools
    }

    var completedTools: [ToolActivity] {
        relay.completedTools
    }

    var autoApprovedTools: [AutoApprovedTool] {
        relay.autoApprovedTools
    }

    // MARK: - Computed Properties

    var totalToolCount: Int {
        activeTools.count + completedTools.count
    }

    var runningCount: Int {
        activeTools.count
    }

    var failedCount: Int {
        completedTools.filter { $0.success == false }.count
    }

    /// All tools sorted: active first, then completed (most recent first).
    var allToolsSorted: [ToolActivity] {
        let sortedActive = activeTools.sorted { $0.startedAt > $1.startedAt }
        let sortedCompleted = completedTools.sorted {
            ($0.completedAt ?? $0.startedAt) > ($1.completedAt ?? $1.startedAt)
        }
        return sortedActive + sortedCompleted
    }

    /// Tools for the currently selected tab.
    var displayedTools: [ToolActivity] {
        switch selectedTab {
        case .active:
            return activeTools.sorted { $0.startedAt > $1.startedAt }
        case .all:
            return allToolsSorted
        }
    }

    /// Find the auto-approval record for a given tool activity, if one exists.
    func autoApproval(for activity: ToolActivity) -> AutoApprovedTool? {
        autoApprovedTools.first { autoTool in
            autoTool.tool == activity.tool &&
            abs(autoTool.timestamp.timeIntervalSince(activity.startedAt)) < Self.autoApprovalMatchWindowSeconds
        }
    }

}
