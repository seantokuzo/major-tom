import Foundation

// MARK: - Watch Session Data

// NOTE: These models are intentionally duplicated in ios/MajorTomWatch/Models/WatchModels.swift.
// The iOS app and watchOS app are separate targets with no shared framework. WatchConnectivity
// serializes via JSON (Codable), so both sides need identical definitions. If you change a model
// here, you MUST update the watch copy to stay in sync.

/// Lightweight session model for watch display.
struct WatchSession: Identifiable, Codable {
    let id: String
    let name: String
    let workingDir: String
    let status: WatchSessionStatus
    let agentCount: Int
    let cost: Double
    let startedAt: Date?

    var formattedCost: String {
        if cost < 0.01 && cost > 0 {
            return "<$0.01"
        }
        return String(format: "$%.2f", cost)
    }

    var elapsedTime: String? {
        guard let start = startedAt else { return nil }
        let elapsed = Date().timeIntervalSince(start)
        let minutes = Int(elapsed) / 60
        let seconds = Int(elapsed) % 60
        if minutes >= 60 {
            let hours = minutes / 60
            let mins = minutes % 60
            return "\(hours)h \(mins)m"
        }
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }
}

enum WatchSessionStatus: String, Codable {
    case active
    case waiting
    case error
    case idle
}

// MARK: - Watch Approval Request

/// Lightweight approval request for watch display.
struct WatchApprovalRequest: Identifiable, Codable {
    let id: String
    let toolName: String
    let description: String
    let dangerLevel: WatchDangerLevel
    let fileOrCommand: String?
    let timestamp: Date

    init(
        id: String,
        toolName: String,
        description: String,
        dangerLevel: WatchDangerLevel,
        fileOrCommand: String? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.toolName = toolName
        self.description = description
        self.dangerLevel = dangerLevel
        self.fileOrCommand = fileOrCommand
        self.timestamp = timestamp
    }
}

enum WatchDangerLevel: String, Codable {
    case safe
    case moderate
    case dangerous
}

// MARK: - Watch Fleet Summary

struct WatchFleetSummary: Codable {
    let totalWorkers: Int
    let healthyWorkers: Int
    let totalCostToday: Double

    var isHealthy: Bool { healthyWorkers == totalWorkers }

    var formattedCost: String {
        if totalCostToday < 0.01 && totalCostToday > 0 {
            return "<$0.01"
        }
        return String(format: "$%.2f", totalCostToday)
    }
}

// MARK: - Watch Connectivity Keys

/// Keys used for WatchConnectivity data transfer.
enum WatchConnectivityKeys {
    static let sessions = "sessions"
    static let approvalRequests = "approvalRequests"
    static let fleetSummary = "fleetSummary"
    static let approvalDecision = "approvalDecision"
    static let requestId = "requestId"
    static let decision = "decision"
    static let connectionStatus = "connectionStatus"
    static let latestToolName = "latestToolName"
    static let latestToolStatus = "latestToolStatus"
    static let totalCostToday = "totalCostToday"
    static let pendingApprovalCount = "pendingApprovalCount"
    static let activeSessionCount = "activeSessionCount"
    static let terminalActive = "terminalActive"
    static let terminalTabCount = "terminalTabCount"
    static let terminalTitle = "terminalTitle"
}
