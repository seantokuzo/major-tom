import Foundation

@Observable
@MainActor
final class RelayService {
    // State exposed to views
    var connectionState: ConnectionState { webSocket.connectionState }
    var currentSession: RelaySession?
    var pendingApprovals: [ApprovalRequest] = []
    var chatMessages: [ChatMessage] = []
    var lastError: String? { webSocket.lastError }

    private let webSocket = WebSocketClient()

    init() {
        webSocket.onMessage = { [weak self] data in
            Task { @MainActor [weak self] in
                self?.handleMessage(data)
            }
        }
    }

    // MARK: - Connection

    func connect(to urlString: String) async throws {
        guard let url = URL(string: "ws://\(urlString)") else {
            throw WebSocketError.invalidURL
        }
        try await webSocket.connect(url: url)
    }

    func disconnect() {
        webSocket.disconnect()
        currentSession = nil
    }

    // MARK: - Session

    func startSession(adapter: AdapterType = .cli, workingDir: String? = nil) async throws {
        let message = SessionStartMessage(adapter: adapter, workingDir: workingDir)
        try await webSocket.send(message)
    }

    func attachSession(id: String) async throws {
        let message = SessionAttachMessage(sessionId: id)
        try await webSocket.send(message)
    }

    // MARK: - Chat

    func sendPrompt(_ text: String) async throws {
        guard let session = currentSession else { return }

        let userMessage = ChatMessage(role: .user, content: text)
        chatMessages.append(userMessage)

        let message = PromptMessage(sessionId: session.id, text: text)
        try await webSocket.send(message)
    }

    // MARK: - Approvals

    func sendApproval(requestId: String, decision: ApprovalDecision) async throws {
        let message = ApprovalDecisionMessage(requestId: requestId, decision: decision)
        try await webSocket.send(message)
        pendingApprovals.removeAll { $0.id == requestId }
    }

    // MARK: - Cancel

    func cancelOperation() async throws {
        guard let session = currentSession else { return }
        let message = CancelMessage(sessionId: session.id)
        try await webSocket.send(message)
    }

    // MARK: - Message Routing

    private func handleMessage(_ data: Data) {
        guard let type = MessageCodec.decodeType(from: data) else { return }

        switch type {
        case .output:
            if let event = try? MessageCodec.decode(OutputEvent.self, from: data) {
                appendOutput(event)
            }

        case .approvalRequest:
            if let event = try? MessageCodec.decode(ApprovalRequestEvent.self, from: data) {
                pendingApprovals.append(ApprovalRequest(from: event))
            }

        case .sessionInfo:
            if let event = try? MessageCodec.decode(SessionInfoEvent.self, from: data) {
                currentSession = RelaySession(
                    id: event.sessionId,
                    adapter: AdapterType(rawValue: event.adapter) ?? .cli,
                    startedAt: event.startedAt,
                    tokenUsage: event.tokenUsage
                )
            }

        case .toolStart:
            if let event = try? MessageCodec.decode(ToolStartEvent.self, from: data) {
                let msg = ChatMessage(role: .tool, content: "Using \(event.tool)...")
                chatMessages.append(msg)
            }

        case .toolComplete:
            if let event = try? MessageCodec.decode(ToolCompleteEvent.self, from: data) {
                let status = event.success ? "completed" : "failed"
                let msg = ChatMessage(role: .tool, content: "\(event.tool) \(status)")
                chatMessages.append(msg)
            }

        case .connectionStatus:
            break // Handled implicitly by WebSocket connection state

        case .error:
            if let event = try? MessageCodec.decode(ErrorEvent.self, from: data) {
                let msg = ChatMessage(role: .system, content: "Error: \(event.message)")
                chatMessages.append(msg)
            }

        default:
            break
        }
    }

    private func appendOutput(_ event: OutputEvent) {
        // Append to the last assistant message or create a new one
        if let last = chatMessages.last, last.role == .assistant {
            chatMessages[chatMessages.count - 1].content += event.chunk
        } else {
            let msg = ChatMessage(role: .assistant, content: event.chunk)
            chatMessages.append(msg)
        }
    }
}

// MARK: - Chat Message Model

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: ChatRole
    var content: String
    let timestamp = Date()
}

enum ChatRole {
    case user
    case assistant
    case tool
    case system
}
