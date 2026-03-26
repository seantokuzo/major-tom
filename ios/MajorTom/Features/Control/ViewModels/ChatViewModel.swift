import Foundation

@Observable
@MainActor
final class ChatViewModel {
    var inputText = ""
    var isLoading = false

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

    // MARK: - Input Text Handling

    func handleInputChange(_ newValue: String) {
        // Detect "/" at start for command palette
        if newValue.hasPrefix("/") && !newValue.contains(" ") {
            showCommandPalette = true
            commandQuery = String(newValue.dropFirst())
        } else {
            showCommandPalette = false
            commandQuery = ""
        }

        // Detect "@" for file context
        if newValue.hasSuffix("@") {
            showFileContext = true
            // Remove the "@" trigger character
            inputText = String(newValue.dropLast())
        }
    }

    // MARK: - Send

    func sendPrompt() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        // Record in history
        historyViewModel.addEntry(text)

        let context = contextPaths.isEmpty ? nil : contextPaths
        inputText = ""
        showCommandPalette = false
        isLoading = true
        defer { isLoading = false }

        // Clear context after sending
        let sentContext = context
        contextPaths.removeAll()

        do {
            try await relay.sendPrompt(text, context: sentContext)
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
            relay.chatMessages.append(
                ChatMessage(role: .system, content: "Model switching coming soon")
            )

        case .compactMode:
            relay.chatMessages.append(
                ChatMessage(role: .system, content: "Compact mode coming soon")
            )

        case .help:
            let helpText = SlashCommand.allCommands
                .map { "/\($0.name) — \($0.description)" }
                .joined(separator: "\n")
            relay.chatMessages.append(
                ChatMessage(role: .system, content: "Available commands:\n\(helpText)")
            )

        case .showCost:
            let cost = String(format: "$%.4f", relay.sessionCostUsd)
            let turns = relay.sessionTurnCount
            relay.chatMessages.append(
                ChatMessage(role: .system, content: "Session cost: \(cost) | Turns: \(turns)")
            )

        case .cancel:
            Task { await cancelOperation() }

        case .templates:
            showTemplates = true

        case .history:
            showHistoryOverlay = true

        case .devices:
            Task { try? await relay.requestDeviceList() }
            let devices = relay.deviceList
            let deviceText = devices.isEmpty
                ? "No devices connected"
                : devices.map { $0.name }.joined(separator: ", ")
            relay.chatMessages.append(
                ChatMessage(role: .system, content: "Devices: \(deviceText)")
            )
        }
    }

    // MARK: - Context

    func addContextFiles(_ paths: [String]) {
        for path in paths {
            if !contextPaths.contains(path) {
                contextPaths.append(path)
                // Also add server-side context
                Task {
                    try? await relay.addContext(path: path, type: .file)
                }
            }
        }
    }

    func removeContextFile(_ path: String) {
        contextPaths.removeAll { $0 == path }
        Task {
            try? await relay.removeContext(path: path)
        }
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
