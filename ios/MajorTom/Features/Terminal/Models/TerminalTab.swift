import Foundation

/// Represents a single terminal tab backed by a PTY session on the relay.
///
/// Each tab maps to a unique `/shell/:tabId` WebSocket endpoint. The relay
/// spawns (or re-attaches to) a PTY keyed by `tabId`, holding it through a
/// 30-min disconnect grace so app backgrounding does not lose state.
struct TerminalTab: Identifiable, Equatable {
    /// Unique identifier for SwiftUI list diffing.
    let id: UUID

    /// The tab ID used in the WebSocket path (`/shell/:tabId`).
    /// Matches the regex `[a-zA-Z0-9._-]{1,64}` enforced by the relay.
    let tabId: String

    /// Shell-supplied title from xterm's title escape sequence.
    var title: String

    /// User-supplied rename, takes precedence over `title` when set.
    /// iOS-only UI metadata — never sent over the wire protocol.
    var userTitle: String?

    /// Whether this tab is currently the active/visible one.
    var isActive: Bool

    /// Timestamp when this tab was created (for ordering).
    let createdAt: Date

    /// The title to render — user override when set, otherwise shell title.
    var displayTitle: String {
        if let userTitle, !userTitle.isEmpty {
            return userTitle
        }
        return title
    }

    init(
        id: UUID = UUID(),
        tabId: String? = nil,
        title: String = "Terminal",
        userTitle: String? = nil,
        isActive: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        // Generate a relay-safe tabId from the UUID if none provided.
        // Uses the first 8 chars of the UUID for brevity + readability.
        self.tabId = tabId ?? "tab-\(id.uuidString.prefix(8).lowercased())"
        self.title = title
        self.userTitle = userTitle
        self.isActive = isActive
        self.createdAt = createdAt
    }
}
