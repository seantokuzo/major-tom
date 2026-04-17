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

    /// Session ID this Office is bound to.
    /// TODO: [Wave 3] Each OfficeViewModel will be keyed by sessionId for per-session routing.
    var sessionId: String?

    /// Per-session role→CharacterType bindings (role-stable binding).
    /// First spawn for a canonical role locks the CharacterType for the session.
    var sessionRoleBindings: RoleMapper.SessionBindings = [:]

    // MARK: - Sprite Pool

    private static let idlePrefix = "idle-"
    private var availableSprites: Set<CharacterType> = Set(CharacterType.allCases)

    private func isIdleSprite(_ id: String) -> Bool {
        id.hasPrefix(Self.idlePrefix)
    }

    private func claimRandomSprite() -> CharacterType? {
        guard let picked = availableSprites.randomElement() else { return nil }
        availableSprites.remove(picked)
        return picked
    }

    private func releaseSprite(_ type: CharacterType) {
        availableSprites.insert(type)
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
    /// Creates a new agent, claims a sprite from the idle pool, assigns a desk, sets status to spawning.
    func handleAgentSpawn(id: String, role: String, task: String) {
        guard !agents.contains(where: { $0.id == id }) else { return }

        let characterType: CharacterType
        if let claimed = claimRandomSprite() {
            // Remove the idle sprite for this character. Release its activity
            // first so any occupied furniture (couch, treadmill, etc.) is freed
            // — otherwise the engine leaks assignments for the removed sprite.
            let idleSpriteId = "\(Self.idlePrefix)\(claimed.rawValue)"
            activityEngine.releaseActivity(for: idleSpriteId)
            agents.removeAll { $0.id == idleSpriteId }
            characterType = claimed
        } else {
            // Overflow: pull an unrendered human from the crew roster
            let claimedTypes = Set(agents.map(\.characterType))
            if let overflow = crewRoster.overflowHuman(excluding: claimedTypes, maxIdleCount: Self.maxIdleHumans) {
                characterType = overflow
            } else {
                // Absolute fallback — all humans exhausted, reuse a dog type
                characterType = CharacterType.allCases.filter(\.isDog).randomElement() ?? .elvis
            }
        }

        let deskIndex = assignNextAvailableDesk(to: id)

        let agent = AgentState(
            id: id,
            name: role.capitalized,
            role: role,
            characterType: characterType,
            status: .spawning,
            currentTask: task,
            deskIndex: deskIndex
        )
        agents.append(agent)
        moodEngine.addAgent(id)
    }

    /// Called when the relay broadcasts `agent.working`.
    /// Agent sits at their desk and starts working.
    func handleAgentWorking(id: String, task: String) {
        guard let index = agents.firstIndex(where: { $0.id == id }) else { return }
        agents[index].status = .working
        agents[index].currentTask = task

        // Release any activity station
        activityEngine.releaseActivity(for: id)
        moodEngine.recordActivity(id)
    }

    /// Called when a tool error or permission denial occurs for an agent.
    func handleAgentError(id: String) {
        moodEngine.recordError(id)
    }

    /// Called when the relay broadcasts `agent.idle`.
    /// Agent gets up and wanders to a break area.
    func handleAgentIdle(id: String) {
        guard let index = agents.firstIndex(where: { $0.id == id }) else { return }
        agents[index].status = .idle
        agents[index].currentTask = nil
        moodEngine.recordIdle(id)
    }

    /// Called when the relay broadcasts `agent.complete`.
    /// Agent celebrates, then leaves and returns sprite to idle pool.
    func handleAgentComplete(id: String, result: String) {
        guard let index = agents.firstIndex(where: { $0.id == id }) else { return }
        guard !isIdleSprite(id) else { return }

        let charType = agents[index].characterType
        agents[index].status = .celebrating
        agents[index].currentTask = result
        moodEngine.recordCompletion(id)

        // After a brief celebration, transition to leaving
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            if let idx = agents.firstIndex(where: { $0.id == id }) {
                agents[idx].status = .leaving
            }
            // Remove after walking out via the centralized cleanup path
            // (releases desk + activity station + mood + selection in one
            // place), then return the sprite to the idle pool. The inline
            // cleanup that lived here previously regressed away from
            // calling `removeAgent(id:)` in the sprite-pool refactor —
            // Copilot review on PR #89.
            try? await Task.sleep(for: .seconds(1.5))
            removeAgent(id: id)
            returnToIdlePool(charType)
        }
    }

    /// Called when the relay broadcasts `agent.dismissed`.
    /// Agent immediately starts leaving, then returns sprite to idle pool.
    func handleAgentDismissed(id: String) {
        guard let agent = agents.first(where: { $0.id == id }) else { return }
        guard !isIdleSprite(id) else { return }

        let charType = agent.characterType

        guard let index = agents.firstIndex(where: { $0.id == id }) else { return }
        agents[index].status = .leaving
        agents[index].currentTask = nil

        // Remove after walking out via the centralized cleanup path,
        // then return the sprite to the idle pool. Same dedupe as
        // handleAgentComplete (Copilot review on PR #89).
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            removeAgent(id: id)
            returnToIdlePool(charType)
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

    /// Return a character type to the idle pool after an agent leaves.
    /// Overflow humans (not part of the active crew) simply vanish — no re-rendering,
    /// and crucially not added to `availableSprites` since there's nothing to claim.
    private func returnToIdlePool(_ charType: CharacterType) {
        // Overflow human — don't re-render, don't add to claimable pool.
        if !charType.isDog && !crewRoster.isActiveCrew(charType, maxCount: Self.maxIdleHumans) {
            return
        }

        let config = CharacterCatalog.config(for: charType)
        let idleId = "\(Self.idlePrefix)\(charType.rawValue)"

        // Don't re-create if already exists
        guard !agents.contains(where: { $0.id == idleId }) else { return }

        let idleAgent = AgentState(
            id: idleId,
            name: config.displayName,
            role: charType.rawValue,
            characterType: charType,
            status: .idle,
            currentTask: nil,
            deskIndex: nil
        )
        agents.append(idleAgent)
        releaseSprite(charType)  // now there's a rendered idle to claim
    }

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
        if selectedAgentId == id {
            selectedAgentId = nil
        }
    }

    // MARK: - Sprite Protocol Handlers (Wave 2)

    /// Handle `sprite.link` — create a new agent sprite linked to a subagent.
    /// Clone-not-consume: idle sprites are NOT consumed. A new agent sprite instance
    /// is created with the role-mapped CharacterType.
    func handleSpriteLink(_ event: SpriteLinkEvent) {
        // Don't double-create if we already have this sprite handle
        guard !agents.contains(where: { $0.spriteHandle == event.spriteHandle }) else {
            // Update existing link if needed
            if let index = agents.firstIndex(where: { $0.spriteHandle == event.spriteHandle }) {
                agents[index].linkedSubagentId = event.subagentId
                agents[index].currentTask = event.task
                agents[index].canonicalRole = event.canonicalRole
                agents[index].parentId = event.parentId
            }
            return
        }

        // Resolve CharacterType via role-stable binding
        let (characterType, updatedBindings) = RoleMapper.resolveCharacterType(
            role: event.canonicalRole,
            sessionBindings: sessionRoleBindings
        )
        sessionRoleBindings = updatedBindings

        let deskIndex = assignNextAvailableDesk(to: event.spriteHandle)

        let agent = AgentState(
            id: event.spriteHandle,
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
        moodEngine.addAgent(event.spriteHandle)
    }

    /// Handle `sprite.unlink` — despawn the linked sprite.
    func handleSpriteUnlink(_ event: SpriteUnlinkEvent) {
        guard let index = agents.firstIndex(where: { $0.spriteHandle == event.spriteHandle }) else {
            return
        }

        let agentId = agents[index].id

        switch event.reason {
        case "complete":
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

        case "error", "crashed":
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

    /// Handle `sprite.state` — bulk restore all sprite mappings (reconnect).
    /// Clears any existing agent sprites (non-idle) and rebuilds from relay state.
    func handleSpriteState(_ event: SpriteStateEvent) {
        // Remove all existing non-idle agent sprites
        let nonIdleIds = agents.filter { !isIdleSprite($0.id) }.map(\.id)
        for id in nonIdleIds {
            removeAgent(id: id)
        }

        // Reset role bindings for this session
        sessionRoleBindings = [:]

        // Rebuild from relay mappings
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

            let deskIndex = assignNextAvailableDesk(to: mapping.spriteHandle)

            let agent = AgentState(
                id: mapping.spriteHandle,
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
            moodEngine.addAgent(mapping.spriteHandle)
        }
    }
}
