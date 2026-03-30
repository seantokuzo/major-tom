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

    // Productivity features
    var showCommandPalette = false
    var commandQuery = ""
    var showFileContext = false
    var showHistoryOverlay = false
    var showTemplates = false
    var contextPaths: [String] = []

    let speechService = SpeechService()
    let templateViewModel = TemplateViewModel()
    let historyViewModel = PromptHistoryViewModel()

    private(set) var relay: RelayService
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

    func countdownFor(request: ApprovalRequest, at now: Date = Date()) -> Int {
        guard isDelayMode else { return 0 }
        let elapsed = Int(now.timeIntervalSince(request.receivedAt))
        return max(0, relay.delaySeconds - elapsed)
    }

    // MARK: - Smart Scroll

    /// Track the visible height of the scroll view for accurate near-bottom detection.
    var scrollViewHeight: CGFloat = 0

    func updateScrollPosition(contentMaxY: CGFloat) {
        // contentMaxY is the position of the bottom-of-content marker in the scroll
        // view's coordinate space. When scrolled to bottom, contentMaxY ~ scrollViewHeight.
        // When scrolled up, contentMaxY > scrollViewHeight (the marker is below the visible area).
        // Guard against uninitialized scrollViewHeight.
        guard scrollViewHeight > 0 else { return }

        let wasNearBottom = isNearBottom
        let distanceFromBottom = contentMaxY - scrollViewHeight
        isNearBottom = distanceFromBottom < nearBottomThreshold

        if !isNearBottom && wasNearBottom {
            showScrollFab = true
        } else if isNearBottom && !wasNearBottom {
            unreadCount = 0
            showScrollFab = false
        }
    }

    // MARK: - Input Text Handling

    func handleInputChange(_ newValue: String) {
        if newValue.hasPrefix("/") && !newValue.contains(" ") {
            showCommandPalette = true
            commandQuery = String(newValue.dropFirst())
        } else {
            showCommandPalette = false
            commandQuery = ""
        }

        if newValue.hasSuffix("@") {
            showFileContext = true
            inputText = String(newValue.dropLast())
        }
    }

    // MARK: - Send

    func sendPrompt() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        historyViewModel.addEntry(text)

        let context = contextPaths.isEmpty ? nil : contextPaths
        inputText = ""
        showCommandPalette = false
        isLoading = true
        defer { isLoading = false }

        contextPaths.removeAll()

        do {
            try await relay.sendPrompt(text, context: context)
        } catch {
            relay.chatMessages.append(
                ChatMessage(role: .system, content: "Failed to send: \(error.localizedDescription)")
            )
        }
    }

    // MARK: - Session

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

    // MARK: - Commands

    func executeCommand(_ command: SlashCommand) {
        inputText = ""
        showCommandPalette = false

        switch command.action {
        case .newSession:
            Task { await startSession() }
        case .clearChat:
            relay.chatMessages.removeAll()
        case .switchModel:
            relay.chatMessages.append(ChatMessage(role: .system, content: "Model switching coming soon"))
        case .compactMode:
            relay.chatMessages.append(ChatMessage(role: .system, content: "Compact mode coming soon"))
        case .help:
            let helpText = SlashCommand.allCommands.map { "/\($0.name) — \($0.description)" }.joined(separator: "\n")
            relay.chatMessages.append(ChatMessage(role: .system, content: "Available commands:\n\(helpText)"))
        case .showCost:
            let cost = String(format: "$%.4f", relay.sessionCostUsd)
            relay.chatMessages.append(ChatMessage(role: .system, content: "Session cost: \(cost) | Turns: \(relay.sessionTurnCount)"))
        case .cancel:
            Task { await cancelOperation() }
        case .templates:
            showTemplates = true
        case .history:
            showHistoryOverlay = true
        case .devices:
            Task { try? await relay.requestDeviceList() }
            let devices = relay.deviceList
            let text = devices.isEmpty ? "No devices connected" : devices.map { $0.name }.joined(separator: ", ")
            relay.chatMessages.append(ChatMessage(role: .system, content: "Devices: \(text)"))
        }
    }

    // MARK: - Context

    func addContextFiles(_ paths: [String]) {
        for path in paths where !contextPaths.contains(path) {
            contextPaths.append(path)
            Task { try? await relay.addContext(path: path, type: .file) }
        }
    }

    func removeContextFile(_ path: String) {
        contextPaths.removeAll { $0 == path }
        Task { try? await relay.removeContext(path: path) }
    }

    // MARK: - Voice

    func handleTranscription(_ text: String) {
        if inputText.isEmpty {
            inputText = text
        } else {
            inputText += " " + text
        }
    }

    // MARK: - Templates

    func insertTemplate(_ content: String) {
        inputText = content
    }

    // MARK: - History

    func insertHistoryEntry(_ text: String) {
        inputText = text
    }
}
