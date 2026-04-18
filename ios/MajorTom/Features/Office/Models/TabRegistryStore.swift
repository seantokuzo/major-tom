import Foundation
import Observation

/// Client-side cache of tabs registered with the relay.
///
/// Tab-Keyed Offices (Wave 3) — the Office Manager UI will eventually read
/// from this store instead of `sessionList`. Wave 3 only populates the cache;
/// Wave 4 wires it into the UI.
///
/// The store is keyed by `tabId` (not `sessionId`) — a tab can host multiple
/// concurrent claude sessions (Gate A in the phase spec), so sessions live
/// inside each `TabMeta`.
@Observable
@MainActor
final class TabRegistryStore {
    /// All tabs known to the relay, keyed by `tabId`.
    private(set) var tabs: [String: TabMeta] = [:]

    // MARK: - Mutation

    /// Replace the full cache with a fresh `tab.list.response` payload.
    func replaceAll(with response: TabListResponseEvent) {
        tabs = Dictionary(uniqueKeysWithValues: response.tabs.map { ($0.tabId, $0) })
    }

    /// Insert or update a full `TabMeta` (e.g., pushed ad-hoc by the relay).
    func upsert(_ tab: TabMeta) {
        tabs[tab.tabId] = tab
    }

    /// Drop a tab from the cache outright. Called on `tab.closed`.
    func remove(tabId: String) {
        tabs.removeValue(forKey: tabId)
    }

    /// Apply a `tab.session.started` event. If the tab is already in the
    /// cache, bump `lastSeenAt` and add the session to its roster. If not,
    /// seed a minimal `TabMeta` so the event isn't lost — a subsequent
    /// `tab.list.response` will fill in the real metadata.
    func apply(started event: TabSessionStartedEvent) {
        let summary = TabSessionSummary(
            sessionId: event.sessionId,
            startedAt: event.startedAt
        )

        if let existing = tabs[event.tabId] {
            // Dedupe — keep the first startedAt we saw for this session.
            var sessions = existing.sessions
            if !sessions.contains(where: { $0.sessionId == event.sessionId }) {
                sessions.append(summary)
            }
            tabs[event.tabId] = TabMeta(
                tabId: existing.tabId,
                workingDirName: existing.workingDirName.isEmpty
                    ? event.workingDirName
                    : existing.workingDirName,
                status: "active",
                createdAt: existing.createdAt,
                lastSeenAt: event.startedAt,
                sessions: sessions
            )
        } else {
            // First time seeing this tab — seed a minimal entry. Details
            // will arrive via the next `tab.list.response`.
            tabs[event.tabId] = TabMeta(
                tabId: event.tabId,
                workingDirName: event.workingDirName,
                status: "active",
                createdAt: event.startedAt,
                lastSeenAt: event.startedAt,
                sessions: [summary]
            )
        }
    }

    /// Apply a `tab.session.ended` event. Removes the session from the tab's
    /// roster and touches `lastSeenAt`. The tab itself survives — PTY close
    /// is what removes it (via `remove(tabId:)`).
    func apply(ended event: TabSessionEndedEvent) {
        guard let existing = tabs[event.tabId] else { return }
        let sessions = existing.sessions.filter { $0.sessionId != event.sessionId }
        tabs[event.tabId] = TabMeta(
            tabId: existing.tabId,
            workingDirName: existing.workingDirName,
            status: sessions.isEmpty ? "idle" : existing.status,
            createdAt: existing.createdAt,
            lastSeenAt: event.endedAt,
            sessions: sessions
        )
    }
}
