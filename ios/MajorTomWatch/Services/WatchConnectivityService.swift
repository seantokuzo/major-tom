import Foundation
import WatchConnectivity

// MARK: - Watch-side WatchConnectivity Service

/// Receives data from the iPhone companion app via WatchConnectivity.
@Observable
@MainActor
final class WatchConnectivityService: NSObject {
    var sessions: [WatchSession] = []
    var pendingApprovals: [WatchApprovalRequest] = []
    var fleetSummary: WatchFleetSummary?
    var isConnectedToPhone: Bool = false
    var isRelayConnected: Bool = false
    var latestToolName: String?
    var latestToolStatus: String?

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

    // MARK: - Send Approval Decision

    func sendApprovalDecision(requestId: String, approved: Bool) {
        // Optimistic removal — remove immediately so callers (e.g. advanceToNext)
        // work with the already-updated list. The request is considered "handled"
        // regardless of transport (sendMessage vs transferUserInfo fallback).
        pendingApprovals.removeAll { $0.id == requestId }

        let payload: [String: Any] = [
            WatchConnectivityKeys.approvalDecision: true,
            WatchConnectivityKeys.requestId: requestId,
            WatchConnectivityKeys.decision: approved ? "allow" : "deny",
        ]

        guard let session = wcSession, session.isReachable else {
            // Fall back to transferUserInfo for background delivery
            wcSession?.transferUserInfo(payload)
            return
        }

        session.sendMessage(payload, replyHandler: { _ in
            // Already removed optimistically
        }) { error in
            print("Watch: sendMessage failed, falling back to transferUserInfo: \(error.localizedDescription)")
            // Fall back to transferUserInfo on failure — delivery still ensured
            session.transferUserInfo(payload)
        }
    }

    // MARK: - Process Incoming Data

    private func processApplicationContext(_ context: [String: Any]) {
        Task { @MainActor in
            if let connected = context[WatchConnectivityKeys.connectionStatus] as? Bool {
                self.isRelayConnected = connected
            }
            if let tool = context[WatchConnectivityKeys.latestToolName] as? String {
                self.latestToolName = tool
            }
            if let status = context[WatchConnectivityKeys.latestToolStatus] as? String {
                self.latestToolStatus = status
            }

            // Decode sessions
            if let sessionsData = context[WatchConnectivityKeys.sessions] as? Data {
                if let decoded = try? JSONDecoder().decode([WatchSession].self, from: sessionsData) {
                    self.sessions = decoded
                }
            }

            // Decode fleet summary
            if let fleetData = context[WatchConnectivityKeys.fleetSummary] as? Data {
                if let decoded = try? JSONDecoder().decode(WatchFleetSummary.self, from: fleetData) {
                    self.fleetSummary = decoded
                }
            }
        }
    }

    private func processMessage(_ message: [String: Any]) {
        Task { @MainActor in
            // Check for approval request
            if let approvalData = message[WatchConnectivityKeys.approvalRequests] as? Data {
                if let decoded = try? JSONDecoder().decode([WatchApprovalRequest].self, from: approvalData) {
                    self.pendingApprovals = decoded
                }
            }

            // Also process any context-like data in messages
            processApplicationContext(message)
        }
    }
}

// MARK: - WCSessionDelegate

extension WatchConnectivityService: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            self.isConnectedToPhone = activationState == .activated
            if activationState == .activated {
                // Process any existing application context
                processApplicationContext(session.receivedApplicationContext)
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            processApplicationContext(applicationContext)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            processMessage(message)
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        Task { @MainActor in
            processMessage(message)
        }
        replyHandler(["status": "received"])
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        Task { @MainActor in
            processMessage(userInfo)
        }
    }

    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
    #endif
}
