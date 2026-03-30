import Foundation
import ActivityKit

// MARK: - Activity Attributes

/// Defines the static and dynamic data for the Major Tom Live Activity.
/// The Widget extension target renders this on Lock Screen and Dynamic Island.
struct MajorTomActivityAttributes: ActivityAttributes {
    /// Dynamic data — updates throughout the activity lifetime.
    struct ContentState: Codable, Hashable {
        /// Human-readable session name (e.g. working dir basename).
        var sessionName: String
        /// Session status: "active", "waiting", "error", "idle".
        var status: String
        /// Elapsed time in seconds since session start.
        var elapsedSeconds: Int
        /// Cumulative session cost in USD.
        var costDollars: Double
        /// Number of pending approval requests.
        var pendingApprovals: Int
        /// Number of currently active agents.
        var activeAgents: Int
        /// Name of the most recent tool (nil if idle).
        var latestTool: String?

        // MARK: - Formatted Strings

        var formattedCost: String {
            if costDollars >= 1.0 {
                return String(format: "$%.2f", costDollars)
            }
            return String(format: "$%.4f", costDollars)
        }

        var agentSummary: String {
            if activeAgents == 0 { return "No agents" }
            return "\(activeAgents) agent\(activeAgents == 1 ? "" : "s")"
        }

        var toolDisplay: String {
            latestTool ?? "Idle"
        }

        var statusColor: String {
            switch status {
            case "active": return "green"
            case "waiting": return "yellow"
            case "error": return "red"
            default: return "gray"
            }
        }

        var elapsedFormatted: String {
            let minutes = elapsedSeconds / 60
            let seconds = elapsedSeconds % 60
            if minutes > 0 {
                return "\(minutes)m \(seconds)s"
            }
            return "\(seconds)s"
        }
    }

    /// Fixed metadata — does not change during the activity lifetime.
    var sessionId: String
    var workingDir: String
}
