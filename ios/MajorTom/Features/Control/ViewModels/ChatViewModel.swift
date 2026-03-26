import Foundation

@Observable
@MainActor
final class ChatViewModel {
    var inputText = ""
    var isLoading = false

    private let relay: RelayService

    init(relay: RelayService) {
        self.relay = relay
    }

    var messages: [ChatMessage] {
        relay.chatMessages
    }

    var pendingApprovals: [ApprovalRequest] {
        relay.pendingApprovals
    }

    var hasSession: Bool {
        relay.currentSession != nil
    }

    var connectionState: ConnectionState {
        relay.connectionState
    }

    /// Whether the relay is in delay mode (auto-approve after countdown).
    var isDelayMode: Bool {
        relay.permissionMode == .delay
    }

    /// Recent auto-approved tools (last 5, for dimmed display).
    var recentAutoApproved: [AutoApprovedTool] {
        Array(relay.autoApprovedTools.suffix(5))
    }

    /// Calculate countdown remaining for a request in delay mode.
    func countdownFor(request: ApprovalRequest) -> Int {
        guard isDelayMode else { return 0 }
        let elapsed = Int(Date().timeIntervalSince(request.receivedAt))
        let remaining = max(0, relay.delaySeconds - elapsed)
        return remaining
    }

    func sendPrompt() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        inputText = ""
        isLoading = true
        defer { isLoading = false }

        do {
            try await relay.sendPrompt(text)
        } catch {
            relay.chatMessages.append(
                ChatMessage(role: .system, content: "Failed to send: \(error.localizedDescription)")
            )
        }
    }

    func startSession() async {
        do {
            try await relay.startSession()
        } catch {
            relay.chatMessages.append(
                ChatMessage(role: .system, content: "Failed to start session: \(error.localizedDescription)")
            )
        }
    }

    func handleApproval(requestId: String, decision: ApprovalDecision) async {
        do {
            try await relay.sendApproval(requestId: requestId, decision: decision)
        } catch {
            relay.chatMessages.append(
                ChatMessage(role: .system, content: "Failed to send approval: \(error.localizedDescription)")
            )
        }
    }

    func cancelOperation() async {
        do {
            try await relay.cancelOperation()
        } catch {
            relay.chatMessages.append(
                ChatMessage(role: .system, content: "Failed to cancel: \(error.localizedDescription)")
            )
        }
    }
}
