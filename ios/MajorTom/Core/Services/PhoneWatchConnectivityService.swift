import Foundation
import WatchConnectivity

// MARK: - iPhone-side WatchConnectivity Service

/// Bridges data from RelayService to the Apple Watch companion app.
@Observable
@MainActor
final class PhoneWatchConnectivityService: NSObject {
    var isWatchReachable: Bool = false
    var isPaired: Bool = false

    /// Callback for when the watch sends an approval decision.
    var onApprovalDecision: ((String, Bool) -> Void)?

    private var wcSession: WCSession?

    override init() {
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        wcSession = session
    }

    // MARK: - Send Data to Watch

    /// Update the watch with current session context (persistent, last-wins).
    func updateContext(
        sessions: [WatchSession],
        fleetSummary: WatchFleetSummary?,
        isRelayConnected: Bool,
        latestToolName: String?,
        latestToolStatus: String?
    ) {
        guard let session = wcSession, session.activationState == .activated else { return }

        var context: [String: Any] = [
            WatchConnectivityKeys.connectionStatus: isRelayConnected,
        ]

        if let tool = latestToolName {
            context[WatchConnectivityKeys.latestToolName] = tool
        }
        if let status = latestToolStatus {
            context[WatchConnectivityKeys.latestToolStatus] = status
        }

        // Encode sessions
        if let data = try? JSONEncoder().encode(sessions) {
            context[WatchConnectivityKeys.sessions] = data
        }

        // Encode fleet summary
        if let fleet = fleetSummary, let data = try? JSONEncoder().encode(fleet) {
            context[WatchConnectivityKeys.fleetSummary] = data
        }

        // Complication / widget data via App Group
        let defaults = UserDefaults(suiteName: "group.com.majortom.shared")
        defaults?.set(sessions.count, forKey: WatchConnectivityKeys.activeSessionCount)
        defaults?.set(
            sessions.reduce(0) { $0 + $1.cost },
            forKey: WatchConnectivityKeys.totalCostToday
        )
        // Note: pendingApprovalCount is written by sendApprovalRequests — don't overwrite it here
        defaults?.set(isRelayConnected, forKey: WatchConnectivityKeys.connectionStatus)

        try? session.updateApplicationContext(context)
    }

    /// Send terminal-specific context to the watch without overwriting relay data.
    ///
    /// Unlike `updateContext` (which replaces the entire `applicationContext`), this
    /// uses `transferUserInfo` so it layers on top of whatever RelayService has set.
    func updateTerminalContext(isActive: Bool, tabCount: Int, title: String) {
        guard let session = wcSession, session.activationState == .activated else { return }

        let payload: [String: Any] = [
            WatchConnectivityKeys.terminalActive: isActive,
            WatchConnectivityKeys.terminalTabCount: tabCount,
            WatchConnectivityKeys.terminalTitle: title,
        ]

        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { _ in
                session.transferUserInfo(payload)
            }
        } else {
            session.transferUserInfo(payload)
        }
    }

    /// Forward approval requests to the watch (real-time when reachable).
    func sendApprovalRequests(_ requests: [WatchApprovalRequest]) {
        guard let session = wcSession, session.activationState == .activated else { return }

        guard let data = try? JSONEncoder().encode(requests) else { return }

        let payload: [String: Any] = [
            WatchConnectivityKeys.approvalRequests: data,
            WatchConnectivityKeys.pendingApprovalCount: requests.count,
        ]

        // Update App Group for complications
        let defaults = UserDefaults(suiteName: "group.com.majortom.shared")
        defaults?.set(requests.count, forKey: WatchConnectivityKeys.pendingApprovalCount)

        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { error in
                print("Phone: failed to send approvals to watch: \(error.localizedDescription)")
                // Fall back to transferUserInfo
                session.transferUserInfo(payload)
            }
        } else {
            session.transferUserInfo(payload)
        }
    }

    // MARK: - Process Watch Messages

    private func processWatchMessage(_ message: [String: Any]) {
        Task { @MainActor in
            // Check for approval decision from watch
            if message[WatchConnectivityKeys.approvalDecision] as? Bool == true,
               let requestId = message[WatchConnectivityKeys.requestId] as? String,
               let decision = message[WatchConnectivityKeys.decision] as? String
            {
                let approved = decision == "allow"
                onApprovalDecision?(requestId, approved)
            }
        }
    }
}

// MARK: - WCSessionDelegate

extension PhoneWatchConnectivityService: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            self.isPaired = session.isPaired
            self.isWatchReachable = session.isReachable
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            processWatchMessage(message)
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        Task { @MainActor in
            processWatchMessage(message)
        }
        replyHandler(["status": "received"])
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        Task { @MainActor in
            processWatchMessage(userInfo)
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.isWatchReachable = session.isReachable
        }
    }
}
