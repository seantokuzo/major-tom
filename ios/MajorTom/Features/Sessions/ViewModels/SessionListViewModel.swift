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

        let previousCount = relay.sessionList.count
        do {
            try await relay.requestSessionList()
            // Poll for response arrival instead of arbitrary sleep.
            // Check every 50ms for up to 2 seconds.
            for _ in 0..<40 {
                if relay.sessionList.count != previousCount || !relay.sessionList.isEmpty { break }
                try? await Task.sleep(for: .milliseconds(50))
            }
        } catch {
            // Silently fail — list will just not update
        }
    }

    /// Switch to a different session.
    func switchToSession(_ session: SessionMetaInfo) async {
        guard session.id != currentSessionId else { return }

        HapticService.modeSwitch()

        // Save current messages before switching
        if let currentSession = relay.currentSession {
            storage.saveMessages(relay.chatMessages, for: currentSession.id)
            storage.saveFromSessionInfo(currentSession, messageCount: relay.chatMessages.count)
        }

        // Attach to the new session
        do {
            try await relay.attachSession(id: session.id)

            // Clear current chat only after successful attach
            relay.chatMessages.removeAll()

            // Poll for session.info to arrive instead of arbitrary sleep.
            for _ in 0..<40 {
                if relay.currentSession?.id == session.id { break }
                try? await Task.sleep(for: .milliseconds(50))
            }

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
        // Save current messages before starting new
        if let currentSession = relay.currentSession {
            storage.saveMessages(relay.chatMessages, for: currentSession.id)
            storage.saveFromSessionInfo(currentSession, messageCount: relay.chatMessages.count)
        }

        let dir = newSessionWorkingDir.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            try await relay.startSession(
                adapter: .cli,
                workingDir: dir.isEmpty ? nil : dir
            )

            // Clear chat and fire haptic only after successful start
            relay.chatMessages.removeAll()
            HapticService.notification(.success)

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

}
