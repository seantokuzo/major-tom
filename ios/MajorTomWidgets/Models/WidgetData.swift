import Foundation

// MARK: - Widget Data Models

/// Lightweight session summary read from App Groups shared container.
/// This mirrors `WidgetSessionSummary` in the main app — must stay in sync.
struct WidgetSessionEntry: Codable, Identifiable {
    let id: String
    let name: String
    let status: String  // "active", "idle", "error"
    let costUsd: Double
    let agentCount: Int
    let startedAt: String  // ISO8601

    var formattedCost: String {
        if costUsd < 0.01 && costUsd > 0 {
            return "<$0.01"
        }
        return String(format: "$%.2f", costUsd)
    }
}

/// Snapshot of all widget data read from the shared container.
struct WidgetSnapshot {
    var sessions: [WidgetSessionEntry]
    var totalCost: Double
    var fleetHealth: String  // "healthy", "degraded", "offline"
    var isConnected: Bool
    var lastUpdated: Date?

    var activeSessionCount: Int {
        sessions.filter { $0.status == "active" }.count
    }

    var totalSessionCount: Int {
        sessions.count
    }

    var formattedTotalCost: String {
        if totalCost < 0.01 && totalCost > 0 {
            return "<$0.01"
        }
        return String(format: "$%.2f", totalCost)
    }

    var totalAgentCount: Int {
        sessions.reduce(0) { $0 + $1.agentCount }
    }

    static let empty = WidgetSnapshot(
        sessions: [],
        totalCost: 0,
        fleetHealth: "offline",
        isConnected: false,
        lastUpdated: nil
    )

    static let placeholder = WidgetSnapshot(
        sessions: [
            WidgetSessionEntry(id: "1", name: "major-tom", status: "active", costUsd: 0.42, agentCount: 3, startedAt: ""),
            WidgetSessionEntry(id: "2", name: "relay-server", status: "active", costUsd: 0.18, agentCount: 1, startedAt: ""),
            WidgetSessionEntry(id: "3", name: "ios-app", status: "idle", costUsd: 0.05, agentCount: 0, startedAt: ""),
            WidgetSessionEntry(id: "4", name: "web-client", status: "active", costUsd: 0.31, agentCount: 2, startedAt: ""),
            WidgetSessionEntry(id: "5", name: "vscode-ext", status: "idle", costUsd: 0.02, agentCount: 0, startedAt: ""),
            WidgetSessionEntry(id: "6", name: "docs-site", status: "active", costUsd: 0.11, agentCount: 1, startedAt: ""),
        ],
        totalCost: 1.09,
        fleetHealth: "healthy",
        isConnected: true,
        lastUpdated: Date()
    )
}
