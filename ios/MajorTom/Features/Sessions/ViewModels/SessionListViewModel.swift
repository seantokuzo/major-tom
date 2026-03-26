import Foundation

@Observable
@MainActor
final class SessionListViewModel {
    var isLoading = false
    var newSessionWorkingDir = ""
    var showNewSessionInput = false

    private let relay: RelayService
    private let storage: SessionStorageService

    init(relay: RelayService, storage: SessionStorageService) {
        self.relay = relay
        self.storage = storage
    }

    // MARK: - Computed

    var sessions: [SessionMetaInfo] {
        relay.sessionList
    }

    var currentSessionId: String? {
        relay.currentSession?.id
    }

    var hasCurrentSession: Bool {
        relay.currentSession != nil
    }

    // MARK: - Actions

    /// Refresh the session list from the relay.
    func refreshSessions() async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await relay.requestSessionList()
            // Brief pause to let the response arrive
            try? await Task.sleep(for: .milliseconds(300))
        } catch {
            // Silently fail — list will just not update
        }
    }

    /// Switch to a different session.
    func switchToSession(_ session: SessionMetaInfo) async {
        guard session.id != currentSessionId else { return }

        HapticService.modeSwitch()

        // Save current messages before switching
        if let currentId = relay.currentSession?.id {
            storage.saveMessages(relay.chatMessages, for: currentId)
            storage.saveFromSessionInfo(relay.currentSession!, messageCount: relay.chatMessages.count)
        }

        // Clear current chat
        relay.chatMessages.removeAll()

        // Attach to the new session
        do {
            try await relay.attachSession(id: session.id)
            // Brief pause for session.info to arrive
            try? await Task.sleep(for: .milliseconds(300))

            // Restore locally saved messages for this session
            let restored = storage.loadMessages(for: session.id)
            if !restored.isEmpty {
                relay.chatMessages = restored
            }
        } catch {
            relay.chatMessages.append(
                ChatMessage(role: .system, content: "Failed to switch session: \(error.localizedDescription)")
            )
        }
    }

    /// Start a new session.
    func startNewSession() async {
        HapticService.notification(.success)

        // Save current messages before starting new
        if let currentId = relay.currentSession?.id {
            storage.saveMessages(relay.chatMessages, for: currentId)
            storage.saveFromSessionInfo(relay.currentSession!, messageCount: relay.chatMessages.count)
        }

        // Clear chat
        relay.chatMessages.removeAll()

        let dir = newSessionWorkingDir.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            try await relay.startSession(
                adapter: .cli,
                workingDir: dir.isEmpty ? nil : dir
            )
            newSessionWorkingDir = ""
            showNewSessionInput = false
        } catch {
            relay.chatMessages.append(
                ChatMessage(role: .system, content: "Failed to start session: \(error.localizedDescription)")
            )
        }
    }

    /// Save current session messages (called on backgrounding, etc.)
    func saveCurrentSession() {
        guard let session = relay.currentSession else { return }
        storage.saveMessages(relay.chatMessages, for: session.id)
        storage.saveFromSessionInfo(session, messageCount: relay.chatMessages.count)
    }

    /// Restore messages for current session on launch.
    func restoreCurrentSession() {
        guard let session = relay.currentSession else { return }
        if relay.chatMessages.isEmpty {
            let restored = storage.loadMessages(for: session.id)
            if !restored.isEmpty {
                relay.chatMessages = restored
            }
        }
    }
}
