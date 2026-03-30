import Foundation

// MARK: - Watch View Model

@Observable
@MainActor
final class WatchViewModel {
    let connectivity: WatchConnectivityService

    init(connectivity: WatchConnectivityService) {
        self.connectivity = connectivity
    }

    // MARK: - Computed

    var sessions: [WatchSession] {
        connectivity.sessions
    }

    var activeSessions: [WatchSession] {
        connectivity.sessions.filter { $0.status == .active || $0.status == .waiting }
    }

    var pendingApprovals: [WatchApprovalRequest] {
        connectivity.pendingApprovals
    }

    var pendingApprovalCount: Int {
        connectivity.pendingApprovals.count
    }

    var hasPendingApprovals: Bool {
        !connectivity.pendingApprovals.isEmpty
    }

    var totalCostToday: Double {
        connectivity.sessions.reduce(0) { $0 + $1.cost }
    }

    var formattedTotalCost: String {
        if totalCostToday < 0.01 && totalCostToday > 0 {
            return "<$0.01"
        }
        return String(format: "$%.2f", totalCostToday)
    }

    var activeSessionCount: Int {
        activeSessions.count
    }

    var isRelayConnected: Bool {
        connectivity.isRelayConnected
    }

    var isPhoneConnected: Bool {
        connectivity.isConnectedToPhone
    }

    var fleetSummary: WatchFleetSummary? {
        connectivity.fleetSummary
    }

    var latestToolName: String? {
        connectivity.latestToolName
    }

    var latestToolStatus: String? {
        connectivity.latestToolStatus
    }
}
