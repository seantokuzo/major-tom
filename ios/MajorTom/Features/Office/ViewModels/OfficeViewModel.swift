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
    var selectedAgent: AgentState?
    var desks: [Desk] = OfficeLayout.desks

    // MARK: - Character Assignment

    /// Tracks which character type index we're on for round-robin assignment.
    private var nextCharacterIndex = 0
    private let characterTypes = CharacterType.allCases

    // MARK: - Agent Lifecycle Handlers

    /// Called when the relay broadcasts `agent.spawn`.
    /// Creates a new agent, assigns a character type and desk, sets status to spawning.
    func handleAgentSpawn(id: String, role: String, task: String) {
        // Don't double-spawn
        guard !agents.contains(where: { $0.id == id }) else { return }

        let characterType = assignNextCharacterType()
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
    }

    /// Called when the relay broadcasts `agent.working`.
    /// Agent sits at their desk and starts working.
    func handleAgentWorking(id: String, task: String) {
        guard let index = agents.firstIndex(where: { $0.id == id }) else { return }
        agents[index].status = .working
        agents[index].currentTask = task
    }

    /// Called when the relay broadcasts `agent.idle`.
    /// Agent gets up and wanders to a break area.
    func handleAgentIdle(id: String) {
        guard let index = agents.firstIndex(where: { $0.id == id }) else { return }
        agents[index].status = .idle
        agents[index].currentTask = nil
    }

    /// Called when the relay broadcasts `agent.complete`.
    /// Agent celebrates, then leaves.
    func handleAgentComplete(id: String, result: String) {
        guard let index = agents.firstIndex(where: { $0.id == id }) else { return }
        agents[index].status = .celebrating
        agents[index].currentTask = result

        // After a brief celebration, transition to leaving
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            if let idx = agents.firstIndex(where: { $0.id == id }) {
                agents[idx].status = .leaving
            }
            // Remove after walking out
            try? await Task.sleep(for: .seconds(1.5))
            removeAgent(id: id)
        }
    }

    /// Called when the relay broadcasts `agent.dismissed`.
    /// Agent immediately starts leaving.
    func handleAgentDismissed(id: String) {
        guard let index = agents.firstIndex(where: { $0.id == id }) else { return }
        agents[index].status = .leaving
        agents[index].currentTask = nil

        // Remove after walking out
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            removeAgent(id: id)
        }
    }

    // MARK: - Agent Selection

    /// Select an agent for the inspector view.
    func selectAgent(_ agent: AgentState) {
        selectedAgent = agent
    }

    /// Dismiss the inspector.
    func dismissInspector() {
        selectedAgent = nil
    }

    /// Rename the selected agent's display name.
    func renameAgent(id: String, newName: String) {
        guard let index = agents.firstIndex(where: { $0.id == id }) else { return }
        agents[index].name = newName
        // Keep selectedAgent in sync if it's the same one
        if selectedAgent?.id == id {
            selectedAgent?.name = newName
        }
    }

    // MARK: - Private Helpers

    /// Round-robin through all 9 character types.
    private func assignNextCharacterType() -> CharacterType {
        let type = characterTypes[nextCharacterIndex % characterTypes.count]
        nextCharacterIndex += 1
        return type
    }

    /// Find the next available desk and assign it.
    /// Returns nil if all desks are occupied.
    private func assignNextAvailableDesk(to agentId: String) -> Int? {
        guard let deskIndex = desks.firstIndex(where: { $0.isAvailable }) else {
            return nil
        }
        desks[deskIndex].occupantId = agentId
        return desks[deskIndex].id
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
        agents.removeAll { $0.id == id }
        if selectedAgent?.id == id {
            selectedAgent = nil
        }
    }
}
