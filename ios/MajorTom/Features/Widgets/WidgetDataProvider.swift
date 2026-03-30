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

        // Siri Shortcuts: fleet status snapshot
        static let fleetWorkerCount = "siri_fleet_worker_count"
        static let fleetTotalCost = "siri_fleet_total_cost"
        static let fleetActiveSessionCount = "siri_fleet_active_session_count"

        // Siri Shortcuts: pending approval
        static let pendingApprovalId = "siri_pending_approval_id"
        static let pendingApprovalTool = "siri_pending_approval_tool"
        static let pendingApprovalDescription = "siri_pending_approval_description"

        // Siri Shortcuts: active session summary
        static let sessionName = "siri_session_name"
        static let sessionTokensIn = "siri_session_tokens_in"
        static let sessionTokensOut = "siri_session_tokens_out"
        static let sessionDurationMs = "siri_session_duration_ms"
        static let sessionTurnCount = "siri_session_turn_count"

        // Siri Shortcuts: prompt and god-mode toggle
        static let pendingPromptText = "siri_pending_prompt_text"
        static let pendingGodModeToggle = "siri_pending_god_mode_toggle"
        static let currentPermissionMode = "siri_current_permission_mode"
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

    // MARK: - Siri Shortcuts: Fleet Status

    /// Write fleet status snapshot for Siri to read inline.
    static func updateFleetSnapshot(workerCount: Int, totalCost: Double, activeSessionCount: Int) {
        guard let defaults = sharedDefaults else { return }
        defaults.set(workerCount, forKey: Keys.fleetWorkerCount)
        defaults.set(totalCost, forKey: Keys.fleetTotalCost)
        defaults.set(activeSessionCount, forKey: Keys.fleetActiveSessionCount)
    }

    /// Read fleet snapshot for Siri inline result.
    static func readFleetSnapshot() -> (workerCount: Int, totalCost: Double, activeSessionCount: Int) {
        guard let defaults = sharedDefaults else { return (0, 0, 0) }
        return (
            workerCount: defaults.integer(forKey: Keys.fleetWorkerCount),
            totalCost: defaults.double(forKey: Keys.fleetTotalCost),
            activeSessionCount: defaults.integer(forKey: Keys.fleetActiveSessionCount)
        )
    }

    // MARK: - Siri Shortcuts: Pending Approval

    /// Write the most recent pending approval for Siri quick-approve.
    static func updatePendingApproval(id: String?, tool: String?, description: String?) {
        guard let defaults = sharedDefaults else { return }
        defaults.set(id, forKey: Keys.pendingApprovalId)
        defaults.set(tool, forKey: Keys.pendingApprovalTool)
        defaults.set(description, forKey: Keys.pendingApprovalDescription)
    }

    /// Read pending approval for Siri quick-approve.
    static func readPendingApproval() -> (id: String?, tool: String?, description: String?) {
        guard let defaults = sharedDefaults else { return (nil, nil, nil) }
        return (
            id: defaults.string(forKey: Keys.pendingApprovalId),
            tool: defaults.string(forKey: Keys.pendingApprovalTool),
            description: defaults.string(forKey: Keys.pendingApprovalDescription)
        )
    }

    // MARK: - Siri Shortcuts: Session Summary

    /// Write active session summary for Siri inline result.
    static func updateSessionSummary(
        name: String,
        costUsd: Double,
        tokensIn: Int,
        tokensOut: Int,
        durationMs: Int,
        turnCount: Int
    ) {
        guard let defaults = sharedDefaults else { return }
        defaults.set(name, forKey: Keys.sessionName)
        defaults.set(costUsd, forKey: Keys.sessionCost)
        defaults.set(tokensIn, forKey: Keys.sessionTokensIn)
        defaults.set(tokensOut, forKey: Keys.sessionTokensOut)
        defaults.set(durationMs, forKey: Keys.sessionDurationMs)
        defaults.set(turnCount, forKey: Keys.sessionTurnCount)
    }

    /// Read session summary for Siri inline result.
    static func readSessionSummary() -> (name: String, costUsd: Double, tokensIn: Int, tokensOut: Int, durationMs: Int, turnCount: Int) {
        guard let defaults = sharedDefaults else { return ("No Session", 0, 0, 0, 0, 0) }
        return (
            name: defaults.string(forKey: Keys.sessionName) ?? "No Session",
            costUsd: defaults.double(forKey: Keys.sessionCost),
            tokensIn: defaults.integer(forKey: Keys.sessionTokensIn),
            tokensOut: defaults.integer(forKey: Keys.sessionTokensOut),
            durationMs: defaults.integer(forKey: Keys.sessionDurationMs),
            turnCount: defaults.integer(forKey: Keys.sessionTurnCount)
        )
    }

    // MARK: - Siri Shortcuts: Prompt & God Mode

    /// Write a pending prompt from Siri for the app to consume on foreground.
    static func writePendingPrompt(_ text: String) {
        guard let defaults = sharedDefaults else { return }
        defaults.set(text, forKey: Keys.pendingPromptText)
    }

    /// Read and consume a pending Siri prompt. Returns nil if none.
    static func consumePendingPrompt() -> String? {
        guard let defaults = sharedDefaults else { return nil }
        guard let text = defaults.string(forKey: Keys.pendingPromptText), !text.isEmpty else { return nil }
        defaults.removeObject(forKey: Keys.pendingPromptText)
        return text
    }

    /// Write a god-mode toggle request for the app to consume.
    static func writeGodModeToggle() {
        guard let defaults = sharedDefaults else { return }
        defaults.set(true, forKey: Keys.pendingGodModeToggle)
    }

    /// Read and consume a pending god-mode toggle. Returns true if toggle was requested.
    static func consumeGodModeToggle() -> Bool {
        guard let defaults = sharedDefaults else { return false }
        let requested = defaults.bool(forKey: Keys.pendingGodModeToggle)
        if requested {
            defaults.removeObject(forKey: Keys.pendingGodModeToggle)
        }
        return requested
    }

    /// Write current permission mode for Siri to read.
    static func updatePermissionMode(_ mode: String) {
        guard let defaults = sharedDefaults else { return }
        defaults.set(mode, forKey: Keys.currentPermissionMode)
    }

    /// Read current permission mode.
    static func readPermissionMode() -> String {
        sharedDefaults?.string(forKey: Keys.currentPermissionMode) ?? "manual"
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
            // Siri Shortcuts keys
            Keys.fleetWorkerCount, Keys.fleetTotalCost, Keys.fleetActiveSessionCount,
            Keys.pendingApprovalId, Keys.pendingApprovalTool, Keys.pendingApprovalDescription,
            Keys.sessionName, Keys.sessionTokensIn, Keys.sessionTokensOut,
            Keys.sessionDurationMs, Keys.sessionTurnCount,
            Keys.pendingPromptText, Keys.pendingGodModeToggle, Keys.currentPermissionMode,
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
