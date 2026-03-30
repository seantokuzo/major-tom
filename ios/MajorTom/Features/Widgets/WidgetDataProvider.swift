import Foundation
import WidgetKit

// MARK: - Widget Data Provider

/// Provides shared session data between the main app and widget extension via App Groups.
///
/// The main app writes data here on every session/fleet update.
/// The widget extension reads from the same App Group shared UserDefaults.
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

        // Multi-session / fleet keys
        static let widgetSessions = "widget_sessions"
        static let widgetTotalCost = "widget_total_cost"
        static let widgetFleetHealth = "widget_fleet_health"
        static let widgetLastUpdated = "widget_last_updated"
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
    }

    /// Write a list of session summaries for the widget.
    static func updateSessions(_ sessions: [WidgetSessionSummary]) {
        guard let defaults = sharedDefaults else { return }
        if let data = try? JSONEncoder().encode(sessions) {
            defaults.set(data, forKey: Keys.widgetSessions)
        }
        defaults.set(ISO8601DateFormatter().string(from: Date()), forKey: Keys.widgetLastUpdated)
    }

    /// Write total cost for today.
    static func updateTotalCost(_ cost: Double) {
        guard let defaults = sharedDefaults else { return }
        defaults.set(cost, forKey: Keys.widgetTotalCost)
    }

    /// Write fleet health status.
    static func updateFleetHealth(_ health: String) {
        guard let defaults = sharedDefaults else { return }
        defaults.set(health, forKey: Keys.widgetFleetHealth)
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

    /// Read session list from shared defaults.
    static func readSessions() -> [WidgetSessionSummary] {
        guard let defaults = sharedDefaults,
              let data = defaults.data(forKey: Keys.widgetSessions),
              let sessions = try? JSONDecoder().decode([WidgetSessionSummary].self, from: data)
        else {
            return []
        }
        return sessions
    }

    /// Read total cost for today.
    static func readTotalCost() -> Double {
        sharedDefaults?.double(forKey: Keys.widgetTotalCost) ?? 0
    }

    /// Read fleet health string.
    static func readFleetHealth() -> String {
        sharedDefaults?.string(forKey: Keys.widgetFleetHealth) ?? "offline"
    }

    /// Read last updated ISO8601 string.
    static func readLastUpdated() -> Date? {
        guard let str = sharedDefaults?.string(forKey: Keys.widgetLastUpdated) else { return nil }
        return ISO8601DateFormatter().date(from: str)
    }

    /// Clear all widget data (e.g., on disconnect/unpair).
    static func clear() {
        guard let defaults = sharedDefaults else { return }
        let keys = [
            Keys.sessionStatus, Keys.activeAgentCount, Keys.totalAgentCount,
            Keys.sessionCost, Keys.currentTool, Keys.sessionStartDate,
            Keys.isConnected, Keys.lastUpdate, Keys.workingDirectory,
            Keys.widgetSessions, Keys.widgetTotalCost, Keys.widgetFleetHealth,
            Keys.widgetLastUpdated,
        ]
        keys.forEach { defaults.removeObject(forKey: $0) }

        WidgetCenter.shared.reloadAllTimelines()
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

// MARK: - Widget Session Summary (Codable for cross-process sharing)

/// Lightweight session summary stored in App Groups for widget display.
struct WidgetSessionSummary: Codable, Identifiable {
    let id: String
    let name: String
    let status: String  // "active", "idle", "error"
    let costUsd: Double
    let agentCount: Int
    let startedAt: String  // ISO8601

    var statusColor: WidgetStatusColor {
        switch status {
        case "active": return .green
        case "idle": return .yellow
        case "error": return .red
        default: return .yellow
        }
    }

    var formattedCost: String {
        if costUsd < 0.01 && costUsd > 0 {
            return "<$0.01"
        }
        return String(format: "$%.2f", costUsd)
    }
}

enum WidgetStatusColor: String, Codable {
    case green
    case yellow
    case red
}
