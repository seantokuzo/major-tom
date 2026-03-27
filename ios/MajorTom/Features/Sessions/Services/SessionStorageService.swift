import Foundation

/// Persists session transcripts and metadata locally using UserDefaults.
@Observable
@MainActor
final class SessionStorageService {
    private let defaults = UserDefaults.standard
    private let metadataKey = "session_metadata_index"
    private let maxStoredSessions = 50

    // MARK: - Message Persistence

    /// Save chat messages for a session.
    func saveMessages(_ messages: [ChatMessage], for sessionId: String) {
        let entries = messages.map { StoredMessage(from: $0) }
        if let data = try? JSONEncoder().encode(entries) {
            defaults.set(data, forKey: messageKey(for: sessionId))
        }
        updateLastActive(for: sessionId)
    }

    /// Load chat messages for a session.
    func loadMessages(for sessionId: String) -> [ChatMessage] {
        guard let data = defaults.data(forKey: messageKey(for: sessionId)),
              let entries = try? JSONDecoder().decode([StoredMessage].self, from: data) else {
            return []
        }
        return entries.map { $0.toChatMessage() }
    }

    /// Remove stored messages for a session.
    func removeMessages(for sessionId: String) {
        defaults.removeObject(forKey: messageKey(for: sessionId))
    }

    // MARK: - Metadata Persistence

    /// Save or update metadata for a session.
    func saveMetadata(_ meta: StoredSessionMetadata) {
        var index = loadMetadataIndex()
        if let existing = index.firstIndex(where: { $0.id == meta.id }) {
            index[existing] = meta
        } else {
            index.append(meta)
        }
        // Purge oldest if over limit
        if index.count > maxStoredSessions {
            let sorted = index.sorted { $0.lastActive < $1.lastActive }
            let toPurge = sorted.prefix(index.count - maxStoredSessions)
            for old in toPurge {
                removeMessages(for: old.id)
            }
            index = Array(sorted.suffix(maxStoredSessions))
        }
        saveMetadataIndex(index)
    }

    /// Load all stored session metadata.
    func loadAllMetadata() -> [StoredSessionMetadata] {
        loadMetadataIndex()
    }

    /// Remove metadata for a session.
    func removeMetadata(for sessionId: String) {
        var index = loadMetadataIndex()
        index.removeAll { $0.id == sessionId }
        saveMetadataIndex(index)
        removeMessages(for: sessionId)
    }

    // MARK: - Helpers

    /// Save metadata for a session from relay info, preserving message count.
    func saveFromSessionInfo(_ session: RelaySession, messageCount: Int) {
        let meta = StoredSessionMetadata(
            id: session.id,
            adapter: session.adapter.rawValue,
            workingDir: session.workingDir,
            lastActive: Date(),
            messageCount: messageCount
        )
        saveMetadata(meta)
    }

    // MARK: - Private

    private func messageKey(for sessionId: String) -> String {
        "session_\(sessionId)_messages"
    }

    private func updateLastActive(for sessionId: String) {
        var index = loadMetadataIndex()
        if let i = index.firstIndex(where: { $0.id == sessionId }) {
            index[i].lastActive = Date()
            saveMetadataIndex(index)
        }
    }

    private func loadMetadataIndex() -> [StoredSessionMetadata] {
        guard let data = defaults.data(forKey: metadataKey),
              let index = try? JSONDecoder().decode([StoredSessionMetadata].self, from: data) else {
            return []
        }
        return index
    }

    private func saveMetadataIndex(_ index: [StoredSessionMetadata]) {
        if let data = try? JSONEncoder().encode(index) {
            defaults.set(data, forKey: metadataKey)
        }
    }
}

// MARK: - Stored Models

struct StoredSessionMetadata: Codable, Identifiable {
    let id: String
    let adapter: String
    var workingDir: String?
    var lastActive: Date
    var messageCount: Int
}

struct StoredMessage: Codable {
    let role: String
    let content: String
    let timestamp: Date
    var toolName: String?
    var toolStatusRaw: String?
    var toolOutput: String?

    init(from msg: ChatMessage) {
        self.role = switch msg.role {
        case .user: "user"
        case .assistant: "assistant"
        case .tool: "tool"
        case .system: "system"
        }
        self.content = msg.content
        self.timestamp = msg.timestamp
        self.toolName = msg.toolName
        self.toolStatusRaw = msg.toolStatus.map { status in
            switch status {
            case .running: "running"
            case .success: "success"
            case .failure: "failure"
            }
        }
        self.toolOutput = msg.toolOutput
    }

    func toChatMessage() -> ChatMessage {
        let chatRole: ChatRole = switch role {
        case "user": .user
        case "assistant": .assistant
        case "tool": .tool
        default: .system
        }
        let toolStatus: ToolStatus? = toolStatusRaw.flatMap { raw in
            switch raw {
            case "running": .running
            case "success": .success
            case "failure": .failure
            default: nil
            }
        }
        return ChatMessage(
            role: chatRole,
            content: content,
            toolName: toolName,
            toolStatus: toolStatus,
            toolOutput: toolOutput,
            timestamp: timestamp
        )
    }
}
