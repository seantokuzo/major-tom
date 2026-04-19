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

    /// Shell-supplied title from xterm's title escape sequence. The
    /// user-supplied override (and its persistence) now lives on the
    /// shared `TabTitleStore` so it can be edited from either the
    /// terminal tab bar or the Office Manager.
    var title: String

    /// Whether this tab is currently the active/visible one.
    var isActive: Bool

    /// Timestamp when this tab was created (for ordering).
    let createdAt: Date

    init(
        id: UUID = UUID(),
        tabId: String? = nil,
        title: String = "Terminal",
        isActive: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        // Generate a relay-safe tabId from the UUID if none provided.
        // Uses the first 8 chars of the UUID for brevity + readability.
        self.tabId = tabId ?? "tab-\(id.uuidString.prefix(8).lowercased())"
        self.title = title
        self.isActive = isActive
        self.createdAt = createdAt
    }
}
