import Foundation
import ActivityKit

// MARK: - Activity Attributes

/// Defines the static and dynamic data for the Major Tom Live Activity.
/// The actual Widget extension target must be set up separately to render this.
struct MajorTomActivityAttributes: ActivityAttributes {
    /// Static data — set once when the activity starts.
    struct ContentState: Codable, Hashable {
        /// Number of currently active agents.
        var activeAgentCount: Int
        /// Total number of agents spawned this session.
        var totalAgentCount: Int
        /// Cumulative session cost in USD.
        var costUsd: Double
        /// Name of the latest tool being executed (nil if idle).
        var currentTool: String?
        /// Session start time — used to calculate elapsed duration.
        var sessionStartDate: Date
        /// Most recent agent role/name for display.
        var latestAgentRole: String?
        /// Whether the session is still active.
        var isActive: Bool

        // MARK: - Formatted Strings

        var formattedCost: String {
            String(format: "$%.4f", costUsd)
        }

        var agentSummary: String {
            "\(activeAgentCount)/\(totalAgentCount)"
        }

        var toolDisplay: String {
            currentTool ?? "Idle"
        }
    }

    /// Fixed metadata — does not change during the activity lifetime.
    var sessionId: String
    var workingDirectory: String
}

// MARK: - Activity State Snapshot

/// A snapshot of session state used to build ContentState updates.
struct SessionActivitySnapshot {
    var activeAgentCount: Int = 0
    var totalAgentCount: Int = 0
    var costUsd: Double = 0
    var currentTool: String?
    var sessionStartDate: Date = Date()
    var latestAgentRole: String?
    var isActive: Bool = true

    var contentState: MajorTomActivityAttributes.ContentState {
        .init(
            activeAgentCount: activeAgentCount,
            totalAgentCount: totalAgentCount,
            costUsd: costUsd,
            currentTool: currentTool,
            sessionStartDate: sessionStartDate,
            latestAgentRole: latestAgentRole,
            isActive: isActive
        )
    }
}
