import Foundation

// MARK: - Office View Model

/// Manages the state of all agents in the office scene.
/// Receives agent lifecycle events from RelayService and translates them
/// into agent state changes that drive the SpriteKit scene.
@Observable
@MainActor
final class OfficeViewModel {
    // MARK: - State

    var agents: [AgentState] = []
    var selectedAgentId: String?
    var desks: [Desk] = OfficeLayout.desks

    var showCharacterGallery: Bool = false

    /// Activity selection engine — JSON-configured, replaces hardcoded ActivityManager
    let activityEngine = ActivitySelectionEngine()

    /// Activity animator — periodic emotes and furniture texture swaps during activities.
    let activityAnimator = ActivityAnimator()

    /// Theme engine — day/night cycle + seasonal themes
    let themeEngine = ThemeEngine()

    /// Mood engine — per-agent mood tracking
    let moodEngine = MoodEngine()

    /// Live lookup — always returns current state, never a stale copy.
    var selectedAgent: AgentState? {
        guard let id = selectedAgentId else { return nil }
        return agents.first { $0.id == id }
    }

    // MARK: - Crew Roster

    /// Maximum number of human sprites visible when idle.
    /// Dogs are always shown. Extra humans only appear when subagent overflow demands them.
    static let maxIdleHumans = 6

    /// The crew roster — manages which humans are active and user preferences.
    let crewRoster = CrewRoster()

    // MARK: - Sprite-Agent Wiring (Wave 2)

    /// Session ID this Office is bound to (set by OfficeSceneManager on creation).
    var sessionId: String?

    /// Per-session role→CharacterType bindings (role-stable binding).
    /// First spawn for a canonical role locks the CharacterType for the session.
    var sessionRoleBindings: RoleMapper.SessionBindings = [:]

    // MARK: - Sprite Messaging (Wave 4)

    /// Per-sprite `/btw` modal state, keyed by the sprite's `AgentState.id`
    /// (which is the `subagentId` for linked sprites and the `idle-<type>` id
    /// for dogs).
    var spriteMessagingStates: [String: SpriteMessagingState] = [:]

    /// FIFO queue of sprite messages awaiting relay connectivity.
    /// Flushed when the socket reconnects.
    var queuedSpriteMessages: [QueuedSpriteMessage] = []

    /// Sprite IDs that have an unread `/btw` response and should render the
    /// green glow on their sprite node. Drained on "Cool Beans" or on open.
    var unreadResponseSpriteIds: Set<String> = []

    /// Sprite IDs that need a one-shot speech-bubble preview on the next
    /// scene render (cleared by the view after firing).
    var pendingBubblePreviews: [String: String] = [:]

    // MARK: - Visual Differentiation (Wave 5)

    /// Active tool-event labels by sprite id. Set on `tool.start`, cleared on
    /// `tool.complete` (matched by `toolUseId`) or on sprite despawn.
    var spriteToolLabels: [String: String] = [:]

    /// Open `toolUseId`s per sprite — lets `tool.complete` clear the exact
    /// bubble that `tool.start` raised, even when multiple tools interleave.
    var spriteOpenToolUseIds: [String: Set<String>] = [:]

    /// Per-sprite progress metrics (toolCount, tokenCount) from
    /// `agent.working`/`agent.idle`. Missing entry == hide indicator.
    struct ProgressMetrics: Equatable {
        var toolCount: Int?
        var tokenCount: Int?
    }
    var spriteProgressMetrics: [String: ProgressMetrics] = [:]

    /// Sprite ids currently "requesting" the role aura. The view diff-renders
    /// this set against the scene. Managed by working/idle/dismiss handlers.
    var spriteAuraActive: Set<String> = []

    // MARK: - Sprite Pool

    private static let idlePrefix = "idle-"

    /// Tracks which CharacterTypes have rendered idle sprites on screen.
    /// Used by populateIdleSprites() to manage the cosmetic idle crew.
    /// NOT used for agent allocation (clone-not-consume model).
    private var availableSprites: Set<CharacterType> = Set(CharacterType.allCases)

    private func isIdleSprite(_ id: String) -> Bool {
        id.hasPrefix(Self.idlePrefix)
    }

    func populateIdleSprites() {
        // Clear idle sprites only — real agents are preserved across shuffle/select.
        agents.removeAll { isIdleSprite($0.id) }

        // `availableSprites` is the claimable *rendered* idle pool — spawning
        // agents take over a visible idle sprite rather than adding a new one.
        // Rebuild it from the idle sprites we actually render below.
        availableSprites = []

        let claimed = Set(agents.map(\.characterType))
        let allTypes = CharacterType.allCases

        // Dogs are always on screen (unless a real agent is using that sprite).
        for charType in allTypes.filter({ $0.isDog }) where !claimed.contains(charType) {
            let config = CharacterCatalog.config(for: charType)
            agents.append(AgentState(
                id: "\(Self.idlePrefix)\(charType.rawValue)",
                name: config.displayName,
                role: charType.rawValue,
                characterType: charType,
                status: .idle,
                currentTask: nil,
                deskIndex: nil
            ))
            availableSprites.insert(charType)
        }

        // Only the active crew humans get rendered — skip any already claimed by real agents.
        let activeHumans = crewRoster.activeHumans(count: Self.maxIdleHumans)
        for charType in activeHumans where !claimed.contains(charType) {
            let config = CharacterCatalog.config(for: charType)
            agents.append(AgentState(
                id: "\(Self.idlePrefix)\(charType.rawValue)",
                name: config.displayName,
                role: charType.rawValue,
                characterType: charType,
                status: .idle,
                currentTask: nil,
                deskIndex: nil
            ))
            availableSprites.insert(charType)
        }
    }

    /// Re-randomize the active crew and repopulate idle sprites.
    /// populateIdleSprites() preserves real agents and rebuilds only the idle pool.
    func shuffleCrew() {
        crewRoster.shuffle()
        populateIdleSprites()
    }

    // MARK: - Agent Lifecycle Handlers

    /// Called when the relay broadcasts `agent.spawn`.
    /// Clone-not-consume: creates a NEW agent sprite instance without consuming idle sprites.
    /// Uses RoleMapper for deterministic role→CharacterType assignment with session-stable binding.
    /// Dogs are NEVER assigned as agent sprites.
    func handleAgentSpawn(id: String, role: String, task: String, parentId: String? = nil) {
        guard !agents.contains(where: { $0.id == id }) else { return }

        // Resolve CharacterType via role-stable binding (clone-not-consume)
        let (characterType, updatedBindings) = RoleMapper.resolveCharacterType(
            role: role,
            sessionBindings: sessionRoleBindings
        )
        sessionRoleBindings = updatedBindings

        let deskIndex = assignNextAvailableDesk(to: id)

        let agent = AgentState(
            id: id,
            name: role.capitalized,
            role: role,
            characterType: characterType,
            status: .spawning,
            currentTask: task,
            deskIndex: deskIndex,
            linkedSubagentId: id,
            canonicalRole: role,
            parentId: parentId
        )
        agents.append(agent)
        moodEngine.addAgent(id)
    }

    /// Called when the relay broadcasts `agent.working`.
    /// Agent sits at their desk and starts working.
    ///
    /// Wave 5: optional `toolCount` / `tokenCount` drive the mini progress
    /// indicator below the sprite. Missing values leave prior metrics intact.
    func handleAgentWorking(id: String, task: String, toolCount: Int? = nil, tokenCount: Int? = nil) {
        guard let index = agents.firstIndex(where: { $0.id == id }) else { return }
        guard !isIdleSprite(id) else { return }
        agents[index].status = .working
        agents[index].currentTask = task

        // Release any activity station
        activityEngine.releaseActivity(for: id)
        moodEngine.recordActivity(id)

        // Wave 5: role aura is active while working.
        spriteAuraActive.insert(id)

        // Wave 5: update progress metrics (preserve existing when a field is nil).
        var metrics = spriteProgressMetrics[id] ?? ProgressMetrics()
        if let toolCount { metrics.toolCount = toolCount }
        if let tokenCount { metrics.tokenCount = tokenCount }
        if metrics.toolCount != nil || metrics.tokenCount != nil {
            spriteProgressMetrics[id] = metrics
        }
    }

    /// Called when a tool error or permission denial occurs for an agent.
    func handleAgentError(id: String) {
        moodEngine.recordError(id)
    }

    /// Called when the relay broadcasts `agent.idle`.
    /// Agent gets up and wanders to a break area.
    ///
    /// Wave 5: stop the role aura and clear the progress indicator unless an
    /// unread `/btw` response is still pending (in which case the sprite keeps
    /// the green glow until the user hits Cool Beans).
    func handleAgentIdle(id: String, toolCount: Int? = nil, tokenCount: Int? = nil) {
        guard let index = agents.firstIndex(where: { $0.id == id }) else { return }
        guard !isIdleSprite(id) else { return }
        agents[index].status = .idle
        agents[index].currentTask = nil
        moodEngine.recordIdle(id)

        // Wave 5: role aura is not shown in idle state.
        spriteAuraActive.remove(id)

        // Wave 5: hide progress indicator unless there's an unread /btw
        // response — in which case we still want to keep the indicator clean
        // (green glow is the primary attention cue).
        if unreadResponseSpriteIds.contains(id) {
            // Keep any last-reported metrics visible until the user Cool Beans.
            // Just don't overwrite with the final counts.
            _ = toolCount
            _ = tokenCount
        } else {
            spriteProgressMetrics.removeValue(forKey: id)
        }
    }

    /// Called when the relay broadcasts `agent.complete`.
    /// Clone-not-consume: agent sprite celebrates then despawns entirely.
    /// Idle sprites are unaffected — no return-to-pool needed.
    func handleAgentComplete(id: String, result: String) {
        guard let index = agents.firstIndex(where: { $0.id == id }) else { return }
        guard !isIdleSprite(id) else { return }

        // Scenario #4 — if there's a pending /btw for this agent, mark it
        // dropped so the user isn't left on "Thinking…" forever.
        markPendingDropped(for: id)

        agents[index].status = .celebrating
        agents[index].currentTask = result
        moodEngine.recordCompletion(id)

        // After a brief celebration, transition to leaving, then despawn
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            if let idx = agents.firstIndex(where: { $0.id == id }) {
                agents[idx].status = .leaving
            }
            try? await Task.sleep(for: .seconds(1.5))
            removeAgent(id: id)
            // Clone-not-consume: agent sprite simply despawns.
            // Idle sprites were never consumed, so no return-to-pool.
        }
    }

    /// Called when the relay broadcasts `agent.dismissed`.
    /// Clone-not-consume: agent sprite leaves then despawns entirely.
    func handleAgentDismissed(id: String) {
        guard agents.contains(where: { $0.id == id }) else { return }
        guard !isIdleSprite(id) else { return }

        markPendingDropped(for: id)

        guard let index = agents.firstIndex(where: { $0.id == id }) else { return }
        agents[index].status = .leaving
        agents[index].currentTask = nil

        // Agent sprite despawns after walking out.
        // Clone-not-consume: idle sprites were never consumed, so no return-to-pool.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            removeAgent(id: id)
        }
    }

    // MARK: - Achievement Celebration

    /// Trigger a celebration on an agent when an achievement is unlocked.
    func handleAgentCelebration(id: String) {
        guard let index = agents.firstIndex(where: { $0.id == id }) else { return }
        let previousStatus = agents[index].status
        let previousTask = agents[index].currentTask
        agents[index].status = .celebrating
        agents[index].currentTask = "Achievement unlocked!"

        // Restore previous state after celebration
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            if let idx = agents.firstIndex(where: { $0.id == id }),
               agents[idx].status == .celebrating {
                agents[idx].status = previousStatus
                agents[idx].currentTask = previousTask
            }
        }
    }

    // MARK: - Agent Selection

    /// Select an agent for the inspector view.
    func selectAgent(_ agent: AgentState) {
        selectedAgentId = agent.id
    }

    /// Dismiss the inspector.
    func dismissInspector() {
        selectedAgentId = nil
    }

    /// Rename the selected agent's display name.
    func renameAgent(id: String, newName: String) {
        guard let index = agents.firstIndex(where: { $0.id == id }) else { return }
        agents[index].name = newName
    }

    // MARK: - Private Helpers

    /// Find the next available desk and assign it.
    /// Returns nil if all desks are occupied.
    private func assignNextAvailableDesk(to agentId: String) -> Int? {
        guard let deskIndex = desks.firstIndex(where: { $0.isAvailable }) else {
            return nil
        }
        desks[deskIndex].occupantId = agentId
        return deskIndex
    }

    /// Release a desk when an agent leaves.
    private func releaseDesk(for agentId: String) {
        if let deskIndex = desks.firstIndex(where: { $0.occupantId == agentId }) {
            desks[deskIndex].occupantId = nil
        }
    }

    /// Remove an agent entirely (after they've left the office).
    private func removeAgent(id: String) {
        releaseDesk(for: id)
        activityEngine.releaseActivity(for: id)
        moodEngine.removeAgent(id)
        agents.removeAll { $0.id == id }
        // Wave 5 cleanup — stop any bubbles/indicators pointing at this sprite.
        spriteAuraActive.remove(id)
        spriteToolLabels.removeValue(forKey: id)
        spriteOpenToolUseIds.removeValue(forKey: id)
        spriteProgressMetrics.removeValue(forKey: id)
        if selectedAgentId == id {
            selectedAgentId = nil
        }
    }

    // MARK: - Sprite Protocol Handlers (Wave 2)

    /// Handle `sprite.link` — create or upgrade an agent sprite linked to a subagent.
    /// Clone-not-consume: idle sprites are NOT consumed. A new agent sprite instance
    /// is created with the role-mapped CharacterType.
    ///
    /// De-duplication: if `agent.spawn` already created an AgentState for this subagentId,
    /// we UPGRADE the existing agent with sprite link metadata instead of creating a duplicate.
    /// Primary key is always `subagentId` so that `agent.*` lifecycle handlers find the agent.
    func handleSpriteLink(_ event: SpriteLinkEvent) {
        // Latch sessionId if not already set (e.g. pre-Wave-3 compat)
        if sessionId == nil {
            sessionId = event.sessionId
        }

        // De-dupe: if agent.spawn already created this agent, upgrade it with sprite link info
        if let existingIndex = agents.firstIndex(where: { $0.id == event.subagentId }) {
            agents[existingIndex].spriteHandle = event.spriteHandle
            agents[existingIndex].linkedSubagentId = event.subagentId
            agents[existingIndex].canonicalRole = event.canonicalRole
            agents[existingIndex].parentId = event.parentId
            if !event.task.isEmpty {
                agents[existingIndex].currentTask = event.task
            }
            return
        }

        // Don't double-create if we already have this sprite handle linked
        guard !agents.contains(where: { $0.spriteHandle == event.spriteHandle && !isIdleSprite($0.id) }) else {
            return
        }

        // Resolve CharacterType via role-stable binding
        let (characterType, updatedBindings) = RoleMapper.resolveCharacterType(
            role: event.canonicalRole,
            sessionBindings: sessionRoleBindings
        )
        sessionRoleBindings = updatedBindings

        // Use subagentId as primary ID so agent.* lifecycle handlers find this agent
        let deskIndex = assignNextAvailableDesk(to: event.subagentId)

        let agent = AgentState(
            id: event.subagentId,
            name: event.canonicalRole.capitalized,
            role: event.canonicalRole,
            characterType: characterType,
            status: .spawning,
            currentTask: event.task,
            deskIndex: deskIndex,
            linkedSubagentId: event.subagentId,
            spriteHandle: event.spriteHandle,
            canonicalRole: event.canonicalRole,
            parentId: event.parentId
        )
        agents.append(agent)
        moodEngine.addAgent(event.subagentId)
    }

    /// Handle `sprite.unlink` — despawn the linked sprite.
    /// Looks up by subagentId first (primary key), falls back to spriteHandle metadata.
    func handleSpriteUnlink(_ event: SpriteUnlinkEvent) {
        guard let index = agents.firstIndex(where: {
            $0.id == event.subagentId || $0.spriteHandle == event.spriteHandle
        }) else {
            return
        }

        let agentId = agents[index].id

        // Scenario #4 — drop any pending /btw since the subagent is leaving.
        markPendingDropped(for: agentId)

        switch event.reason {
        case "completed":
            agents[index].status = .celebrating
            agents[index].currentTask = event.result
            moodEngine.recordCompletion(agentId)

            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                if let idx = agents.firstIndex(where: { $0.id == agentId }) {
                    agents[idx].status = .leaving
                }
                try? await Task.sleep(for: .seconds(1.5))
                removeAgent(id: agentId)
            }

        case "failed":
            agents[index].status = .leaving
            agents[index].currentTask = event.result ?? "Error"
            moodEngine.recordError(agentId)

            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.5))
                removeAgent(id: agentId)
            }

        default:  // "dismissed" or unknown
            agents[index].status = .leaving
            agents[index].currentTask = nil

            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.5))
                removeAgent(id: agentId)
            }
        }
    }

    // MARK: - Tool Bubble Handlers (Wave 5)

    /// Handle a `tool.start` event routed to a specific subagent's sprite.
    /// Call only when `subagentId` resolves to a known agent. The humanized
    /// label is shown above the sprite until `tool.complete` for the same
    /// `toolUseId` arrives (or 30s safety-net expires on the sprite itself).
    func handleSpriteToolStart(subagentId: String, toolUseId: String?, tool: String, input: [String: AnyCodableValue]?) {
        // Resolve by subagentId — agent.spawn/sprite.link uses subagentId as the primary key.
        guard agents.contains(where: { $0.id == subagentId }) else { return }
        guard !isIdleSprite(subagentId) else { return }

        let label = ToolHumanizer.label(for: tool, input: input)
        spriteToolLabels[subagentId] = label

        if let id = toolUseId {
            var open = spriteOpenToolUseIds[subagentId] ?? Set<String>()
            open.insert(id)
            spriteOpenToolUseIds[subagentId] = open
        }
    }

    /// Handle a `tool.complete` event for a specific subagent's sprite.
    /// Removes the matching open `toolUseId`. If no other tools are still
    /// pending, the tool bubble is cleared.
    func handleSpriteToolComplete(subagentId: String, toolUseId: String?) {
        guard agents.contains(where: { $0.id == subagentId }) else { return }

        if let id = toolUseId, var open = spriteOpenToolUseIds[subagentId] {
            open.remove(id)
            if open.isEmpty {
                spriteOpenToolUseIds.removeValue(forKey: subagentId)
                spriteToolLabels.removeValue(forKey: subagentId)
            } else {
                spriteOpenToolUseIds[subagentId] = open
            }
        } else {
            // No toolUseId to match — best-effort clear all open ids so the
            // bubble doesn't stick around forever on pre-Wave-5 relay frames.
            spriteOpenToolUseIds.removeValue(forKey: subagentId)
            spriteToolLabels.removeValue(forKey: subagentId)
        }
    }

    // MARK: - Sprite Messaging Handlers (Wave 4)

    /// Return the current messaging state for a sprite (`.idle` if none).
    func messagingState(for spriteId: String) -> SpriteMessagingState {
        spriteMessagingStates[spriteId] ?? .idle
    }

    /// Transition a sprite's state.
    private func setMessagingState(_ state: SpriteMessagingState, for spriteId: String) {
        if case .idle = state {
            spriteMessagingStates.removeValue(forKey: spriteId)
        } else {
            spriteMessagingStates[spriteId] = state
        }
    }

    /// Begin a pending `/btw` for a linked sprite. Caller (RelayService/view) is
    /// responsible for actually dispatching the WebSocket send when connected.
    /// Returns the queued message descriptor so the caller can submit it.
    @discardableResult
    func beginPendingMessage(
        spriteId: String,
        spriteHandle: String,
        subagentId: String,
        text: String,
        isConnected: Bool
    ) -> QueuedSpriteMessage? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard case .idle = messagingState(for: spriteId) else { return nil }

        let sid = sessionId ?? ""
        let messageId = UUID().uuidString

        setMessagingState(.pending(messageId: messageId, question: trimmed), for: spriteId)

        let queued = QueuedSpriteMessage(
            id: messageId,
            sessionId: sid,
            spriteHandle: spriteHandle,
            subagentId: subagentId,
            text: trimmed,
            createdAt: Date()
        )
        if !isConnected {
            queuedSpriteMessages.append(queued)
            return queued
        }
        return queued
    }

    /// Dog canned-response path — no relay roundtrip. Still transitions
    /// through pending → ready with a ~200ms delay for consistent UX.
    func sendDogCannedMessage(spriteId: String, text: String, character: CharacterType) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard case .idle = messagingState(for: spriteId) else { return }

        let messageId = UUID().uuidString
        setMessagingState(.pending(messageId: messageId, question: trimmed), for: spriteId)

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard let self else { return }
            guard case .pending(let pendingId, let pendingQ) = self.messagingState(for: spriteId),
                  pendingId == messageId else { return }
            let reply = DogCannedResponses.randomResponse(for: character)
            self.setMessagingState(
                .ready(messageId: pendingId, question: pendingQ, response: reply, wasDropped: false),
                for: spriteId
            )
        }
    }

    /// Route an incoming `sprite.response` to the matching sprite.
    func handleSpriteResponse(_ event: SpriteResponseEvent) {
        guard event.status == "delivered" || event.status == "dropped" else {
            return  // "queued" is informational — no state change
        }

        // Find sprite by messageId first (most reliable), fall back to subagentId.
        let spriteId: String? = {
            if let direct = spriteMessagingStates.first(where: { $0.value.messageId == event.messageId })?.key {
                return direct
            }
            return agents.first(where: { $0.linkedSubagentId == event.subagentId })?.id
        }()

        guard let spriteId else { return }

        queuedSpriteMessages.removeAll { $0.id == event.messageId }

        let current = messagingState(for: spriteId)
        guard case .pending(let pendingId, let question) = current,
              pendingId == event.messageId else {
            return
        }

        let responseText: String
        let wasDropped: Bool
        switch event.status {
        case "delivered":
            responseText = event.text
            wasDropped = false
        case "dropped":
            responseText = "(Agent completed before delivery)"
            wasDropped = true
        default:
            return
        }

        setMessagingState(
            .ready(messageId: pendingId, question: question, response: responseText, wasDropped: wasDropped),
            for: spriteId
        )

        // If the inspector isn't open on this sprite, flag unread for green
        // glow + speech bubble preview. The view handles the preview.
        if selectedAgentId != spriteId {
            unreadResponseSpriteIds.insert(spriteId)
            pendingBubblePreviews[spriteId] = responseText
        }
    }

    /// "Cool Beans" dismisses the response back to idle.
    func dismissResponse(for spriteId: String) {
        setMessagingState(.idle, for: spriteId)
        unreadResponseSpriteIds.remove(spriteId)
    }

    /// Inspector opened on this sprite — if there was an unread response,
    /// clear the green-glow flag so the sprite stops pulsing.
    func markResponseRead(for spriteId: String) {
        unreadResponseSpriteIds.remove(spriteId)
        pendingBubblePreviews.removeValue(forKey: spriteId)
    }

    /// Called by the view after it has rendered the bubble preview once.
    func consumeBubblePreview(for spriteId: String) {
        pendingBubblePreviews.removeValue(forKey: spriteId)
    }

    /// Pop all queued messages (FIFO). Caller sends them.
    func drainQueuedSpriteMessages() -> [QueuedSpriteMessage] {
        let drained = queuedSpriteMessages
        queuedSpriteMessages.removeAll()
        return drained
    }

    /// Mark any pending /btw for `spriteId` as dropped (scenario #4).
    /// Surfaces the `(Agent completed before delivery)` text + green glow.
    func markPendingDropped(for spriteId: String) {
        guard case .pending(let messageId, let question) = messagingState(for: spriteId) else { return }

        queuedSpriteMessages.removeAll { $0.id == messageId }
        setMessagingState(
            .ready(
                messageId: messageId,
                question: question,
                response: "(Agent completed before delivery)",
                wasDropped: true
            ),
            for: spriteId
        )
        if selectedAgentId != spriteId {
            unreadResponseSpriteIds.insert(spriteId)
            pendingBubblePreviews[spriteId] = "(Agent completed before delivery)"
        }
    }

    /// Handle `sprite.state` — bulk restore all sprite mappings (reconnect).
    /// Clears any existing agent sprites (non-idle) and rebuilds from relay state.
    /// Uses `subagentId` as the primary AgentState.id so agent.* handlers find them.
    func handleSpriteState(_ event: SpriteStateEvent) {
        // Latch sessionId if not already set (e.g. pre-Wave-3 compat)
        if sessionId == nil {
            sessionId = event.sessionId
        }

        // Remove all existing non-idle agent sprites
        let nonIdleIds = agents.filter { !isIdleSprite($0.id) }.map(\.id)
        for id in nonIdleIds {
            removeAgent(id: id)
        }

        // Reset role bindings for this session
        sessionRoleBindings = [:]

        // Rebuild from relay mappings — primary key is subagentId
        for mapping in event.mappings {
            let (characterType, updatedBindings) = RoleMapper.resolveCharacterType(
                role: mapping.canonicalRole,
                sessionBindings: sessionRoleBindings
            )
            sessionRoleBindings = updatedBindings

            let status: AgentStatus
            switch mapping.status {
            case "working": status = .working
            case "idle": status = .idle
            case "spawning": status = .spawning
            default: status = .working
            }

            let deskIndex = assignNextAvailableDesk(to: mapping.subagentId)

            let agent = AgentState(
                id: mapping.subagentId,
                name: mapping.canonicalRole.capitalized,
                role: mapping.canonicalRole,
                characterType: characterType,
                status: status,
                currentTask: mapping.task,
                deskIndex: deskIndex,
                linkedSubagentId: mapping.subagentId,
                spriteHandle: mapping.spriteHandle,
                canonicalRole: mapping.canonicalRole,
                parentId: mapping.parentId
            )
            agents.append(agent)
            moodEngine.addAgent(mapping.subagentId)
        }
    }
}
