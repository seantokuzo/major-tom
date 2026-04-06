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

    /// Activity manager for station-based idle activities
    let activityManager = ActivityManager()

    /// Theme engine — day/night cycle + seasonal themes
    let themeEngine = ThemeEngine()

    /// Mood engine — per-agent mood tracking
    let moodEngine = MoodEngine()

    /// Live lookup — always returns current state, never a stale copy.
    var selectedAgent: AgentState? {
        guard let id = selectedAgentId else { return nil }
        return agents.first { $0.id == id }
    }

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
        guard agents.isEmpty || agents.allSatisfy({ isIdleSprite($0.id) }) else { return }

        // Clear any existing idle sprites
        agents.removeAll { isIdleSprite($0.id) }
        availableSprites = Set(CharacterType.allCases)

        for charType in CharacterType.allCases {
            let config = CharacterCatalog.config(for: charType)
            let agent = AgentState(
                id: "\(Self.idlePrefix)\(charType.rawValue)",
                name: config.displayName,
                role: charType.rawValue,
                characterType: charType,
                status: .idle,
                currentTask: nil,
                deskIndex: nil
            )
            agents.append(agent)
        }
    }

    // MARK: - Agent Lifecycle Handlers

    /// Called when the relay broadcasts `agent.spawn`.
    /// Creates a new agent, claims a sprite from the idle pool, assigns a desk, sets status to spawning.
    func handleAgentSpawn(id: String, role: String, task: String) {
        guard !agents.contains(where: { $0.id == id }) else { return }

        let characterType: CharacterType
        if let claimed = claimRandomSprite() {
            // Remove the idle sprite for this character
            let idleSpriteId = "\(Self.idlePrefix)\(claimed.rawValue)"
            agents.removeAll { $0.id == idleSpriteId }
            characterType = claimed
        } else {
            // Overflow: all sprites occupied, use round-robin fallback
            let allTypes = CharacterType.allCases
            characterType = allTypes[agents.count % allTypes.count]
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
        activityManager.releaseStation(for: id)
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

        // Release any activity station immediately on completion
        activityManager.releaseStation(for: id)
        moodEngine.recordCompletion(id)

        // After a brief celebration, transition to leaving
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            if let idx = agents.firstIndex(where: { $0.id == id }) {
                agents[idx].status = .leaving
                releaseDesk(for: id)
            }
            // Remove after walking out, then return sprite to idle pool
            try? await Task.sleep(for: .seconds(1.5))
            moodEngine.removeAgent(id)
            agents.removeAll { $0.id == id }
            if selectedAgentId == id {
                selectedAgentId = nil
            }
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
        releaseDesk(for: id)
        activityManager.releaseStation(for: id)

        // Remove after walking out, then return sprite to idle pool
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            moodEngine.removeAgent(id)
            agents.removeAll { $0.id == id }
            if selectedAgentId == id {
                selectedAgentId = nil
            }
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
    private func returnToIdlePool(_ charType: CharacterType) {
        releaseSprite(charType)

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
        activityManager.releaseStation(for: id)
        moodEngine.removeAgent(id)
        agents.removeAll { $0.id == id }
        if selectedAgentId == id {
            selectedAgentId = nil
        }
    }
}
