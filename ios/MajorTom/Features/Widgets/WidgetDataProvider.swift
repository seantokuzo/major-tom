import Foundation

// MARK: - Widget Data Provider

/// Provides shared session data between the main app and widget extension via App Groups.
///
/// To use this with an actual WidgetKit extension:
/// 1. Enable App Groups capability on both app and widget targets
/// 2. Create a shared App Group: "group.com.majortom.shared"
/// 3. Both targets read/write via this provider
///
/// The widget extension target needs separate setup in Xcode with WidgetKit framework.
enum WidgetDataProvider {
    /// App Group identifier for sharing data between app and widget.
    static let appGroupId = "group.com.majortom.shared"

    /// Shared UserDefaults using App Group container.
    static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupId)
    }

    // MARK: - Keys

    private enum Keys {
        static let sessionStatus = "widget_session_status"
        static let activeAgentCount = "widget_active_agent_count"
        static let totalAgentCount = "widget_total_agent_count"
        static let sessionCost = "widget_session_cost"
        static let currentTool = "widget_current_tool"
        static let sessionStartDate = "widget_session_start_date"
        static let isConnected = "widget_is_connected"
        static let lastUpdate = "widget_last_update"
        static let workingDirectory = "widget_working_directory"
    }

    // MARK: - Write (from main app)

    /// Update widget data with current session status.
    static func updateSessionStatus(_ status: WidgetSessionStatus) {
        guard let defaults = sharedDefaults else { return }

        defaults.set(status.isActive, forKey: Keys.sessionStatus)
        defaults.set(status.activeAgentCount, forKey: Keys.activeAgentCount)
        defaults.set(status.totalAgentCount, forKey: Keys.totalAgentCount)
        defaults.set(status.costUsd, forKey: Keys.sessionCost)
        defaults.set(status.currentTool, forKey: Keys.currentTool)
        defaults.set(status.sessionStartDate?.timeIntervalSince1970, forKey: Keys.sessionStartDate)
        defaults.set(status.isConnected, forKey: Keys.isConnected)
        defaults.set(Date().timeIntervalSince1970, forKey: Keys.lastUpdate)
        defaults.set(status.workingDirectory, forKey: Keys.workingDirectory)

        // Trigger widget refresh
        // WidgetCenter.shared.reloadAllTimelines() — requires WidgetKit import in widget target
    }

    // MARK: - Read (from widget extension)

    /// Read current session status from shared defaults.
    static func readSessionStatus() -> WidgetSessionStatus {
        guard let defaults = sharedDefaults else {
            return .empty
        }

        let startInterval = defaults.double(forKey: Keys.sessionStartDate)

        return WidgetSessionStatus(
            isActive: defaults.bool(forKey: Keys.sessionStatus),
            activeAgentCount: defaults.integer(forKey: Keys.activeAgentCount),
            totalAgentCount: defaults.integer(forKey: Keys.totalAgentCount),
            costUsd: defaults.double(forKey: Keys.sessionCost),
            currentTool: defaults.string(forKey: Keys.currentTool),
            sessionStartDate: startInterval > 0 ? Date(timeIntervalSince1970: startInterval) : nil,
            isConnected: defaults.bool(forKey: Keys.isConnected),
            workingDirectory: defaults.string(forKey: Keys.workingDirectory)
        )
    }

    /// Clear all widget data (e.g., on disconnect/unpair).
    static func clear() {
        guard let defaults = sharedDefaults else { return }
        let keys = [
            Keys.sessionStatus, Keys.activeAgentCount, Keys.totalAgentCount,
            Keys.sessionCost, Keys.currentTool, Keys.sessionStartDate,
            Keys.isConnected, Keys.lastUpdate, Keys.workingDirectory,
        ]
        keys.forEach { defaults.removeObject(forKey: $0) }
    }
}

// MARK: - Widget Session Status Model

struct WidgetSessionStatus {
    var isActive: Bool
    var activeAgentCount: Int
    var totalAgentCount: Int
    var costUsd: Double
    var currentTool: String?
    var sessionStartDate: Date?
    var isConnected: Bool
    var workingDirectory: String?

    static let empty = WidgetSessionStatus(
        isActive: false,
        activeAgentCount: 0,
        totalAgentCount: 0,
        costUsd: 0,
        currentTool: nil,
        sessionStartDate: nil,
        isConnected: false,
        workingDirectory: nil
    )

    var formattedCost: String {
        String(format: "$%.4f", costUsd)
    }

    var agentSummary: String {
        if totalAgentCount == 0 { return "No agents" }
        return "\(activeAgentCount) active / \(totalAgentCount) total"
    }

    var statusText: String {
        if !isConnected { return "Disconnected" }
        if !isActive { return "No Active Session" }
        return currentTool ?? "Idle"
    }

    var elapsedTime: String? {
        guard let start = sessionStartDate else { return nil }
        let elapsed = Date().timeIntervalSince(start)
        let minutes = Int(elapsed) / 60
        let seconds = Int(elapsed) % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }
}
