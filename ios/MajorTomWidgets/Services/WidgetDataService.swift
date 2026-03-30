import Foundation

// MARK: - Widget Data Service

/// Reads session and fleet data from the App Groups shared container.
/// Used by the widget extension (separate process — no access to main app memory).
enum WidgetDataService {
    static let appGroupId = "group.com.majortom.shared"

    private static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupId)
    }

    // MARK: - Keys (must match WidgetDataProvider in main app)

    private enum Keys {
        static let sessionStatus = "widget_session_status"
        static let activeAgentCount = "widget_active_agent_count"
        static let totalAgentCount = "widget_total_agent_count"
        static let sessionCost = "widget_session_cost"
        static let isConnected = "widget_is_connected"

        static let widgetSessions = "widget_sessions"
        static let widgetTotalCost = "widget_total_cost"
        static let widgetFleetHealth = "widget_fleet_health"
        static let widgetLastUpdated = "widget_last_updated"
    }

    // MARK: - Read

    /// Read the full widget snapshot from shared UserDefaults.
    static func readSnapshot() -> WidgetSnapshot {
        guard let defaults = sharedDefaults else {
            return .empty
        }

        let sessions = readSessions(from: defaults)
        let totalCost = defaults.double(forKey: Keys.widgetTotalCost)
        let fleetHealth = defaults.string(forKey: Keys.widgetFleetHealth) ?? "offline"
        let isConnected = defaults.bool(forKey: Keys.isConnected)

        var lastUpdated: Date?
        if let str = defaults.string(forKey: Keys.widgetLastUpdated) {
            lastUpdated = ISO8601DateFormatter().date(from: str)
        }

        return WidgetSnapshot(
            sessions: sessions,
            totalCost: totalCost,
            fleetHealth: fleetHealth,
            isConnected: isConnected,
            lastUpdated: lastUpdated
        )
    }

    private static func readSessions(from defaults: UserDefaults) -> [WidgetSessionEntry] {
        guard let data = defaults.data(forKey: Keys.widgetSessions),
              let sessions = try? JSONDecoder().decode([WidgetSessionEntry].self, from: data)
        else {
            return []
        }
        return sessions
    }
}
