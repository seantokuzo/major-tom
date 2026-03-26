import Foundation

@Observable
@MainActor
final class ChatViewModel {
    var inputText = ""
    var isLoading = false

    // Smart scroll state
    var isNearBottom = true
    var showScrollFab = false
    var unreadCount = 0
    var scrollToBottomTrigger = 0

    private let relay: RelayService
    private let nearBottomThreshold: CGFloat = 150

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

    // MARK: - Cost Passthrough

    var sessionCostUsd: Double { relay.sessionCostUsd }
    var sessionTurnCount: Int { relay.sessionTurnCount }
    var sessionInputTokens: Int { relay.sessionInputTokens }
    var sessionOutputTokens: Int { relay.sessionOutputTokens }

    // MARK: - Streaming Detection

    var isStreaming: Bool {
        guard let last = messages.last else { return false }
        return last.role == .assistant && !relay.activeTools.isEmpty
    }

    // MARK: - Permission / Delay Mode

    var isDelayMode: Bool { relay.permissionMode == .delay }

    var recentAutoApproved: [AutoApprovedTool] {
        Array(relay.autoApprovedTools.suffix(5))
    }

    func countdownFor(request: ApprovalRequest) -> Int {
        guard isDelayMode else { return 0 }
        let elapsed = Int(Date().timeIntervalSince(request.receivedAt))
        return max(0, relay.delaySeconds - elapsed)
    }

    // MARK: - Smart Scroll

    func updateScrollPosition(contentMaxY: CGFloat) {
        let wasNearBottom = isNearBottom
        isNearBottom = contentMaxY < nearBottomThreshold

        if !isNearBottom && wasNearBottom {
            showScrollFab = true
        } else if isNearBottom && !wasNearBottom {
            unreadCount = 0
            showScrollFab = false
        }
    }

    // MARK: - Actions

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
