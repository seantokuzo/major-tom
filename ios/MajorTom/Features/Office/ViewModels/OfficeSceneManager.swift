import Foundation
import SpriteKit

// MARK: - Office Scene Manager

/// Manages per-tab OfficeViewModel + OfficeScene pairs.
///
/// **Tab-Keyed Offices (Wave 4):** the `offices` dictionary is keyed by
/// **tabId** — the identifier of the iOS terminal tab hosting the Claude
/// session(s). Each tab has one Office; an Office can host multiple
/// concurrent sessions (Gate A).
///
/// **Legacy / fallback:** sessions that never bind to a tab (the legacy
/// `cli` and `vscode` adapter paths) fall back to using their `sessionId`
/// as a synthetic tabId — those Offices continue to work without any
/// TabRegistry binding.
///
/// Scenes are LRU-evicted beyond `maxWarmScenes` to control memory (~30-60MB each).
@Observable
@MainActor
final class OfficeSceneManager {

    // MARK: - Types

    struct OfficeEntry {
        let viewModel: OfficeViewModel
        var scene: OfficeScene?
        var lastAccessed: Date
        /// True when `createOffice` was called (full office with scene + idle sprites).
        /// False for lightweight entries created by `ensureViewModel`.
        var hasOffice: Bool = false
    }

    // MARK: - State

    /// Per-tab offices keyed by **tabId** (or by sessionId as a synthetic
    /// tabId for legacy `cli`/`vscode` sessions — see type docs above).
    private(set) var offices: [String: OfficeEntry] = [:]

    /// Reverse-lookup cache for `sessionId → office key`. Populated whenever
    /// an event lands with a known `tabId` so later events arriving without
    /// one still route to the same Office. For legacy sessions the entry is
    /// `sessionId → sessionId` (self-mapped).
    private var sessionToOfficeKey: [String: String] = [:]

    /// Maximum number of warm (in-memory) scenes before LRU eviction kicks in.
    static let maxWarmScenes = 2

    /// Relay service reference for sending sprite.state.request on cold rebuild.
    weak var relay: RelayService?

    // MARK: - Cross-session Banner (Wave 4 M2)

    /// Descriptor for a cross-session `/btw` response banner.
    ///
    /// Tab-Keyed Offices (Wave 4) — `tabId` is the primary routing key;
    /// `sessionId` is kept for legacy cli/vscode sessions whose events
    /// never carry a `tabId` on the wire.
    struct CrossSessionBanner: Identifiable, Equatable {
        let id: UUID
        let tabId: String?
        let sessionId: String
        let sessionName: String
        let spriteId: String
        let spriteName: String
        let preview: String

        init(
            id: UUID = UUID(),
            tabId: String? = nil,
            sessionId: String,
            sessionName: String,
            spriteId: String,
            spriteName: String,
            preview: String
        ) {
            self.id = id
            self.tabId = tabId
            self.sessionId = sessionId
            self.sessionName = sessionName
            self.spriteId = spriteId
            self.spriteName = spriteName
            self.preview = preview
        }

        /// Primary route key for navigation — tabId if the event carried
        /// one, else sessionId (legacy synthetic tabId).
        var routeKey: String { tabId ?? sessionId }
    }

    /// The banner currently surfaced to the user (nil = hidden). Consumed by
    /// OfficeManagerView's overlay. Auto-hides on a 3-second task.
    var pendingCrossSessionBanner: CrossSessionBanner?

    /// Surface a banner for a response that arrived in a non-active session.
    func showCrossSessionBanner(
        tabId: String? = nil,
        sessionId: String,
        sessionName: String,
        spriteId: String,
        spriteName: String,
        preview: String
    ) {
        pendingCrossSessionBanner = CrossSessionBanner(
            tabId: tabId,
            sessionId: sessionId,
            sessionName: sessionName,
            spriteId: spriteId,
            spriteName: spriteName,
            preview: preview
        )
    }

    /// Dismiss the banner (tap or auto-hide).
    func dismissCrossSessionBanner() {
        pendingCrossSessionBanner = nil
    }

    // MARK: - Public API

    /// Returns the OfficeViewModel for an Office key. The key may be either a
    /// tabId (tab-backed Office) or a sessionId (legacy synthetic Office).
    /// A sessionId that has been routed to a real tab resolves via the
    /// internal session→tab cache.
    func viewModel(for key: String) -> OfficeViewModel? {
        if let vm = offices[key]?.viewModel { return vm }
        if let tabKey = sessionToOfficeKey[key] {
            return offices[tabKey]?.viewModel
        }
        return nil
    }

    /// Creates a new Office keyed by the given tabId. For legacy `cli`/`vscode`
    /// sessions the caller passes the sessionId directly as a synthetic tabId.
    /// Returns the newly created entry. If an Office already exists, returns it.
    @discardableResult
    func createOffice(for tabId: String) -> OfficeEntry {
        if var existing = offices[tabId] {
            // If the entry already has a scene (full office), just touch LRU and return.
            if existing.scene != nil {
                offices[tabId]?.lastAccessed = Date()
                return existing
            }

            // Upgrade a lightweight ensureViewModel entry: create scene, populate idle sprites,
            // request sprite state — everything a fresh createOffice would do.
            let scene = makeScene()
            existing.scene = scene
            existing.lastAccessed = Date()
            existing.hasOffice = true
            offices[tabId] = existing

            seedRosterFromTabRegistry(vm: existing.viewModel, officeKey: tabId)
            existing.viewModel.populateIdleSprites()
            requestSpriteStateForAllSessions(in: existing.viewModel)

            evictIfNeeded(excluding: tabId)
            return existing
        }

        let vm = OfficeViewModel()
        vm.tabId = tabId

        let scene = makeScene()

        let entry = OfficeEntry(
            viewModel: vm,
            scene: scene,
            lastAccessed: Date(),
            hasOffice: true
        )
        offices[tabId] = entry

        // Seed the session roster from TabRegistryStore so sprite state requests
        // target real sessionIds (not the tabId by mistake) when an Office is
        // materialized straight from the tab list before any tagged event lands.
        seedRosterFromTabRegistry(vm: vm, officeKey: tabId)

        // Populate idle sprites for the fresh office
        vm.populateIdleSprites()

        // If events have already cached a session under this key, request state for it.
        requestSpriteStateForAllSessions(in: vm)

        evictIfNeeded(excluding: tabId)
        return entry
    }

    /// Side-effect-free scene peek — returns the current scene (or nil) without
    /// touching LRU timestamps or triggering cold rebuilds.
    /// Safe to call from SwiftUI computed properties / view body.
    func peekScene(for key: String) -> OfficeScene? {
        if let scene = offices[key]?.scene { return scene }
        if let tabKey = sessionToOfficeKey[key] {
            return offices[tabKey]?.scene
        }
        return nil
    }

    /// Activates an office for viewing: touches LRU, cold-rebuilds the scene if
    /// evicted, and syncs existing agent state into a fresh scene.
    /// Call from `.onAppear` or other imperative contexts — NOT from view body.
    @discardableResult
    func activateOffice(for tabId: String) -> OfficeScene? {
        let key = resolvedOfficeKey(tabId)
        guard var entry = offices[key] else { return nil }

        // Touch LRU timestamp
        entry.lastAccessed = Date()
        offices[key] = entry

        // If scene exists, return it
        if let scene = entry.scene {
            return scene
        }

        // Cold rebuild: create a new scene, restore from viewModel state
        let scene = makeScene()
        offices[key]?.scene = scene

        // Sync any existing agents into the fresh scene so they render immediately
        // (onChange won't fire for the initial value on a newly created scene).
        let vm = entry.viewModel
        for agent in vm.agents {
            scene.addAgent(id: agent.id, name: agent.name, characterType: agent.characterType)
            if let deskIndex = agent.deskIndex {
                scene.highlightDesk(deskIndex, occupied: true)
                scene.moveAgentToDesk(id: agent.id, deskIndex: deskIndex)
            } else if let overflowPosition = agent.overflowPosition {
                // Wave 6 — S5 overflow placement after cold rebuild.
                scene.moveAgentToOverflow(id: agent.id, position: overflowPosition)
            }
            switch agent.status {
            case .working:
                scene.updateAgentStatus(id: agent.id, status: .working)
            case .idle:
                scene.updateAgentStatus(id: agent.id, status: .idle)
            default:
                break
            }
        }

        // If viewModel has no real agents, request state from relay for each
        // known session in this Office.
        if vm.agents.filter({ !$0.id.hasPrefix("idle-") }).isEmpty {
            requestSpriteStateForAllSessions(in: vm)
        }

        evictIfNeeded(excluding: key)
        return scene
    }

    /// Creates a lightweight OfficeViewModel entry (no scene) for the Office
    /// hosting this session so agent events can accumulate before the user
    /// opens an Office.
    ///
    /// Routes by **tabId** when provided (Wave 4 `cli-external` sessions) and
    /// falls back to the TabRegistryStore or the sessionId itself for legacy
    /// `cli`/`vscode` sessions. The session→office key mapping is cached so
    /// subsequent events without a `tabId` still land in the same Office.
    @discardableResult
    func ensureViewModel(for sessionId: String, tabId: String? = nil) -> OfficeViewModel {
        let officeKey = resolveOfficeKey(sessionId: sessionId, tabIdHint: tabId)
        sessionToOfficeKey[sessionId] = officeKey

        if let existing = offices[officeKey] {
            if tabId != nil, existing.viewModel.tabId == nil {
                existing.viewModel.tabId = officeKey
            }
            existing.viewModel.activeSessionIds.insert(sessionId)
            if existing.viewModel.sessionId == nil {
                existing.viewModel.sessionId = sessionId
            }
            return existing.viewModel
        }

        let vm = OfficeViewModel()
        vm.tabId = officeKey
        vm.sessionId = sessionId
        vm.activeSessionIds.insert(sessionId)

        let entry = OfficeEntry(
            viewModel: vm,
            scene: nil,
            lastAccessed: Date()
        )
        offices[officeKey] = entry
        return vm
    }

    // MARK: - Tab Session Lifecycle (Wave 4)

    /// Called when the relay broadcasts `tab.session.started`. Records the
    /// session in the owning Office's roster (if the Office already exists)
    /// and seeds the session→tab reverse cache so subsequent events for this
    /// session route correctly even if they arrive without a `tabId` hint.
    ///
    /// Wave 5 note — **no explicit walk-in animation is fired here.** The
    /// user-visible "new crew joining" moment is already produced by the
    /// existing `agent.spawn` path: when the first subagent of the new
    /// session lands, `OfficeViewModel.handleAgentSpawn` appends an
    /// AgentState with `.spawning` status, the view inserts the sprite at
    /// `OfficeLayout.doorPosition` via `OfficeScene.addAgent`, then
    /// `moveAgentToDesk` pathfinds from the airlock to the assigned desk —
    /// that airlock-to-desk walk IS the walk-in. A session without any
    /// subagents produces no visible humans at all (by design), so a
    /// session-start level animation would be a decoration without a
    /// subject. If we ever want a pre-spawn "session lit up" feel, the
    /// right hook is here; today it is deliberately empty.
    func handleTabSessionStarted(tabId: String, sessionId: String) {
        sessionToOfficeKey[sessionId] = tabId

        if let vm = offices[tabId]?.viewModel {
            vm.activeSessionIds.insert(sessionId)
            if vm.sessionId == nil {
                vm.sessionId = sessionId
            }
            if vm.tabId == nil {
                vm.tabId = tabId
            }
        }
        // If the Office hasn't been materialized yet (user hasn't tapped
        // "Available Tabs" or no agent events have landed), it will be
        // created lazily by `ensureViewModel` and `createOffice`. The cache
        // above guarantees those paths land in the right Office key.
    }

    /// Called when the relay broadcasts `tab.session.ended`. Drops the
    /// session from the Office's roster and walks off any active humans
    /// **scoped to the ending session**. Dogs (idle sprites) stay, and
    /// humans belonging to any other session still alive in this tab stay
    /// too (Gate A — multi-claude in one tab). The Office itself survives;
    /// tab teardown happens on `tab.closed` after PTY grace expires.
    func handleTabSessionEnded(tabId: String, sessionId: String) {
        sessionToOfficeKey.removeValue(forKey: sessionId)

        guard let vm = offices[tabId]?.viewModel else { return }
        vm.activeSessionIds.remove(sessionId)

        // If the session that just ended was the VM's primary sessionId,
        // rotate to any remaining active session so sprite messaging +
        // state-request paths still have a valid binding.
        if vm.sessionId == sessionId {
            vm.sessionId = vm.activeSessionIds.first
        }

        // Wave 5: walk off only the agents whose originating session is the
        // one that just ended. Agents bound to sibling sessions in the same
        // tab (Gate A) survive, as do dogs (sessionId == nil). Any agent that
        // slipped in pre-Wave-3 without a sessionId would also survive here —
        // acceptable since such legacy agents are rare and get cleaned up by
        // the full-tab walk-off on `tab.closed` (Commit 4).
        let endingIds = vm.agents
            .filter { !$0.id.hasPrefix("idle-") && $0.sessionId == sessionId }
            .map(\.id)
        for id in endingIds {
            vm.handleAgentDismissed(id: id)
        }
    }

    /// Closes an Office. Destroys both scene and viewModel.
    /// Does NOT affect the terminal session on the relay.
    ///
    /// Legacy sessions: pass the sessionId directly (acts as the synthetic
    /// office key). Tab-backed sessions: pass the tabId.
    func closeOffice(for key: String) {
        let officeKey = resolvedOfficeKey(key)
        guard let entry = offices[officeKey] else { return }
        entry.scene?.isPaused = true
        offices.removeValue(forKey: officeKey)

        // Drop any reverse-lookup entries pointing at this Office so future
        // events for those sessions don't leak into a stale key.
        sessionToOfficeKey = sessionToOfficeKey.filter { $0.value != officeKey }
    }

    /// Wave 5: graceful teardown on `tab.closed`. Walks off every agent
    /// scoped to any session in the tab, then tears down the Office after
    /// `tabClosedTeardownGraceSeconds` so the dismiss animation has time to
    /// finish (matches the ~1.5s walk-to-door + despawn timeline inside
    /// `handleAgentDismissed`).
    ///
    /// Covers the hard-kill PTY path: when the relay broadcasts
    /// `tab.closed` without a preceding `tab.session.ended` (e.g. PTY grace
    /// expired mid-session), this is the only place humans get walked off
    /// before the Office evaporates. If `tab.session.ended` already fired
    /// for a session, its dismiss Tasks are still in flight — we don't
    /// cancel those, and the idempotent `handleAgentDismissed` guard
    /// (`guard agents.contains(where:)`) keeps re-firing harmless.
    func handleTabClosed(tabId: String) {
        let officeKey = resolvedOfficeKey(tabId)

        guard let vm = offices[officeKey]?.viewModel else {
            // No Office materialized — nothing to walk off. Clean up the
            // reverse cache below for consistency.
            sessionToOfficeKey = sessionToOfficeKey.filter { $0.value != officeKey }
            return
        }

        // Walk off every non-idle sprite in the Office regardless of
        // sessionId. Dogs (idle sprites) stay put for the grace window and
        // get torn down with the scene.
        let humanIds = vm.agents
            .filter { !$0.id.hasPrefix("idle-") }
            .map(\.id)
        for id in humanIds {
            vm.handleAgentDismissed(id: id)
        }

        // Delay the actual Office teardown so the dismiss animations have
        // time to play out. If there are no humans to walk off we still
        // apply the grace (cheap), which keeps the code path trivially
        // predictable.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(Self.tabClosedTeardownGraceMilliseconds))
            self?.closeOffice(for: officeKey)
        }
    }

    /// Grace window between the `tab.closed` walk-off and the Office
    /// teardown. Matches the sprite dismiss animation timeline in
    /// `handleAgentDismissed` (warmup + 1.5s leaving pose).
    private static let tabClosedTeardownGraceMilliseconds: Int = 1_500

    /// Keys (tabId or synthetic sessionId) of offices that have a full scene.
    /// Excludes lightweight entries created by `ensureViewModel` that were
    /// never upgraded via `createOffice`.
    ///
    /// Renamed from `linkedSessionIds` — the returned strings are office
    /// keys, not sessionIds, after the Wave 4 rekey.
    var linkedOfficeKeys: Set<String> {
        Set(offices.filter { $0.value.hasOffice }.keys)
    }

    // MARK: - Private

    /// Create a fresh OfficeScene with the standard dimensions.
    private func makeScene() -> OfficeScene {
        let scene = OfficeScene()
        scene.size = CGSize(width: StationLayout.sceneWidth, height: StationLayout.sceneHeight)
        scene.scaleMode = .aspectFill
        return scene
    }

    /// Translate an incoming identifier (tabId or sessionId) into the actual
    /// `offices` dictionary key. Used by UI-facing entry points where the
    /// caller may have either flavor.
    private func resolvedOfficeKey(_ key: String) -> String {
        if offices[key] != nil { return key }
        if let mapped = sessionToOfficeKey[key], offices[mapped] != nil {
            return mapped
        }
        return key
    }

    /// Resolve the Office key for an event tagged with `sessionId` and an
    /// optional `tabId` hint. Preference order:
    /// 1. Explicit `tabId` from the wire (Wave 4 `cli-external` sessions).
    /// 2. Locally cached `sessionToOfficeKey` (from an earlier tagged event).
    /// 3. `TabRegistryStore.getTabForSession` (the authoritative mapping if
    ///    the client has already seen a `tab.session.started` broadcast).
    /// 4. `sessionId` itself — synthetic tabId for legacy sessions that
    ///    never bind to a terminal tab.
    private func resolveOfficeKey(sessionId: String, tabIdHint: String?) -> String {
        if let tabIdHint { return tabIdHint }
        if let cached = sessionToOfficeKey[sessionId] { return cached }
        if let tab = relay?.tabRegistryStore.getTabForSession(sessionId) {
            return tab.tabId
        }
        return sessionId
    }

    /// Ask the relay to re-send sprite state for every session currently
    /// hosted by this Office. Covers both the single-session common case and
    /// Wave 5 multi-session tabs. Falls back through:
    /// 1. VM's `activeSessionIds` roster — seeded by events and
    ///    `seedRosterFromTabRegistry`.
    /// 2. The cached `sessionToOfficeKey` reverse map.
    /// 3. The Office key itself — **only** when the key is not a known
    ///    tabId in `TabRegistryStore` (i.e. legacy synthetic-sessionId
    ///    Office). This prevents requesting sprite state for a bogus
    ///    sessionId equal to the tabId when a real tab's roster hasn't
    ///    been populated yet.
    private func requestSpriteStateForAllSessions(in vm: OfficeViewModel) {
        guard let relay else { return }
        let tabKey = vm.tabId
        var sessionIds = vm.activeSessionIds
        if sessionIds.isEmpty, let tabKey {
            sessionIds = Set(
                sessionToOfficeKey
                    .filter { $0.value == tabKey }
                    .map(\.key)
            )
        }
        if sessionIds.isEmpty, let tabKey {
            // Legacy fallback: the key IS the sessionId — but only when
            // the key isn't registered as a real tab, otherwise we'd be
            // asking the relay for sprite state on a tabId (wrong).
            if relay.tabRegistryStore.tabs[tabKey] == nil {
                sessionIds = [tabKey]
            }
        }
        for sid in sessionIds {
            relay.requestSpriteState(for: sid)
        }
    }

    /// Seed the VM's session roster from `TabRegistryStore` metadata so
    /// sprite state requests target real sessionIds immediately — avoiding
    /// the race where `createOffice(for: tabId)` fires before any
    /// `tab.session.started` / sprite / agent events have populated the
    /// in-memory roster.
    private func seedRosterFromTabRegistry(vm: OfficeViewModel, officeKey: String) {
        guard let relay, let tab = relay.tabRegistryStore.tabs[officeKey] else {
            return
        }
        for summary in tab.sessions {
            vm.activeSessionIds.insert(summary.sessionId)
            sessionToOfficeKey[summary.sessionId] = officeKey
        }
        if vm.sessionId == nil {
            vm.sessionId = tab.sessions.first?.sessionId
        }
    }

    /// LRU eviction: destroy scenes beyond maxWarmScenes (keep viewModel alive).
    private func evictIfNeeded(excluding activeOfficeKey: String) {
        let warmEntries = offices.filter { $0.value.scene != nil && $0.key != activeOfficeKey }

        guard warmEntries.count >= Self.maxWarmScenes else { return }

        // Sort by lastAccessed ascending (oldest first)
        let sorted = warmEntries.sorted { $0.value.lastAccessed < $1.value.lastAccessed }

        // Evict oldest entries until we're under the threshold
        let evictCount = warmEntries.count - Self.maxWarmScenes + 1  // +1 for the active one
        for entry in sorted.prefix(evictCount) {
            offices[entry.key]?.scene?.isPaused = true
            offices[entry.key]?.scene = nil
        }
    }
}
