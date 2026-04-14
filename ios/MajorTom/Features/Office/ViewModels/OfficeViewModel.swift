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

    // MARK: - Sleep Roster

    /// Number of human characters that stay awake (all dogs are always awake).
    /// Tune this to balance visual density vs. performance.
    static let awakeHumanCount = 6

    /// IDs of idle sprites that are sleeping in crew quarters bunks.
    /// Sleeping sprites get a static sleeping animation — no activity cycling, no pathfinding.
    private(set) var sleepingAgentIds: Set<String> = []

    /// Check whether a given agent is on the sleep roster.
    func isSleeping(_ agentId: String) -> Bool {
        sleepingAgentIds.contains(agentId)
    }

    /// Wake a sleeping agent (e.g., when a real agent spawns and claims that sprite).
    /// Removes the agent from the sleep roster so the scene can transition it.
    func wakeSleepingAgent(_ agentId: String) {
        sleepingAgentIds.remove(agentId)
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

        // Clear any existing idle sprites and sleep roster
        agents.removeAll { isIdleSprite($0.id) }
        sleepingAgentIds.removeAll()
        availableSprites = Set(CharacterType.allCases)

        let allTypes = CharacterType.allCases

        // Dogs are always awake
        let dogs = allTypes.filter { $0.isDog }
        // Humans get split into awake day-shift and sleeping night-shift
        var humans = allTypes.filter { !$0.isDog }
        humans.shuffle()
        let awakeHumans = Array(humans.prefix(Self.awakeHumanCount))
        let sleepingHumans = Array(humans.dropFirst(Self.awakeHumanCount))

        // Add all dogs as normal idle sprites
        for charType in dogs {
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
        }

        // Add awake humans as normal idle sprites
        for charType in awakeHumans {
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
        }

        // Add sleeping humans — same idle status but tracked in sleepingAgentIds
        for charType in sleepingHumans {
            let config = CharacterCatalog.config(for: charType)
            let agentId = "\(Self.idlePrefix)\(charType.rawValue)"
            agents.append(AgentState(
                id: agentId,
                name: config.displayName,
                role: charType.rawValue,
                characterType: charType,
                status: .idle,
                currentTask: nil,
                deskIndex: nil
            ))
            sleepingAgentIds.insert(agentId)
        }
    }

    // MARK: - Agent Lifecycle Handlers

    /// Called when the relay broadcasts `agent.spawn`.
    /// Creates a new agent, claims a sprite from the idle pool, assigns a desk, sets status to spawning.
    func handleAgentSpawn(id: String, role: String, task: String) {
        guard !agents.contains(where: { $0.id == id }) else { return }

        let characterType: CharacterType
        if let claimed = claimRandomSprite() {
            // Remove the idle sprite for this character and clean up sleep roster
            let idleSpriteId = "\(Self.idlePrefix)\(claimed.rawValue)"
            sleepingAgentIds.remove(idleSpriteId)
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
    /// Non-dog humans go back to sleep if the awake roster is already full.
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

        // If this is a human and we already have enough awake humans, send them to sleep
        if !charType.isDog {
            let awakeHumanIdleCount = agents.filter {
                isIdleSprite($0.id) && !$0.characterType.isDog && !sleepingAgentIds.contains($0.id)
            }.count
            if awakeHumanIdleCount > Self.awakeHumanCount {
                sleepingAgentIds.insert(idleId)
            }
        }
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
}
