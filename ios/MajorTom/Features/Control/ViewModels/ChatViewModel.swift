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

    var sessionCostUsd: Double {
        relay.sessionCostUsd
    }

    var sessionTurnCount: Int {
        relay.sessionTurnCount
    }

    var sessionInputTokens: Int {
        relay.sessionInputTokens
    }

    var sessionOutputTokens: Int {
        relay.sessionOutputTokens
    }

    // MARK: - Streaming Detection

    var isStreaming: Bool {
        // Streaming if the last message is from the assistant and tools are running
        guard let last = messages.last else { return false }
        return last.role == .assistant && !relay.activeTools.isEmpty
    }

    // MARK: - Smart Scroll

    func updateScrollPosition(contentMaxY: CGFloat) {
        // contentMaxY is the max Y of the content relative to the scroll view's coordinate space.
        // When near the bottom, this value is close to the scroll view's height.
        // We consider "near bottom" if the content bottom is within threshold of visible area.
        let wasNearBottom = isNearBottom
        isNearBottom = contentMaxY < nearBottomThreshold

        if !isNearBottom && wasNearBottom {
            withMainActorAnimation {
                showScrollFab = true
            }
        } else if isNearBottom && !wasNearBottom {
            unreadCount = 0
            withMainActorAnimation {
                showScrollFab = false
            }
        }
    }

    private func withMainActorAnimation(_ body: () -> Void) {
        body()
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
