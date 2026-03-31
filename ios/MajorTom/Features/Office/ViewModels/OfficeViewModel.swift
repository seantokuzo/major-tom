import Foundation

// MARK: - Demo Agent Names & Tasks

/// Pre-defined demo agents for demo mode.
private enum DemoData {
    struct DemoAgent {
        let name: String
        let role: String
        let task: String
        let characterType: CharacterType
    }

    static let agents: [DemoAgent] = [
        DemoAgent(name: "Alice", role: "frontend", task: "Building the login page", characterType: .dev),
        DemoAgent(name: "Bob", role: "backend", task: "Setting up API endpoints", characterType: .officeWorker),
        DemoAgent(name: "Carol", role: "pm", task: "Sprint planning for Q2", characterType: .pm),
        DemoAgent(name: "Dave", role: "fullstack", task: "Implementing dark mode", characterType: .dev),
        DemoAgent(name: "Eve", role: "devops", task: "Configuring CI/CD pipeline", characterType: .officeWorker),
        DemoAgent(name: "Bonkers", role: "morale", task: "Organizing team event", characterType: .clown),
        DemoAgent(name: "Frank", role: "security", task: "Auditing auth system", characterType: .frankenstein),
        DemoAgent(name: "Pretzel", role: "qa", task: "Running regression tests", characterType: .dachshund),
        DemoAgent(name: "Heeler", role: "infra", task: "Scaling worker nodes", characterType: .cattleDog),
        DemoAgent(name: "Shadow", role: "data", task: "Training ML model", characterType: .schnauzerBlack),
        DemoAgent(name: "Pepper", role: "design", task: "Updating component library", characterType: .schnauzerPepper),
        DemoAgent(name: "Grace", role: "architect", task: "Designing microservices", characterType: .pm),
        DemoAgent(name: "Hank", role: "sre", task: "Monitoring production alerts", characterType: .dev),
        DemoAgent(name: "Ziggy", role: "intern", task: "Learning the codebase", characterType: .clown),
    ]
}

// MARK: - Demo State

/// The lifecycle states for demo mode cycling.
private enum DemoPhase: CaseIterable {
    case idle
    case work
    case celebrate
}

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

    /// Demo mode state
    var isDemoMode: Bool = false
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

    // MARK: - Character Assignment

    /// Tracks which character type index we're on for round-robin assignment.
    private var nextCharacterIndex = 0
    private let characterTypes = CharacterType.allCases

    /// Demo mode cycling task
    private var demoCycleTask: Task<Void, Never>?

    // MARK: - Demo Mode

    /// Start demo mode with 14 fake agents.
    func startDemoMode() {
        guard !isDemoMode else { return }

        // Don't wipe real (non-demo) agents if any exist
        let realAgents = agents.filter { !$0.id.hasPrefix("demo-") }
        if !realAgents.isEmpty { return }

        isDemoMode = true

        // Clear existing state (safe — only demo agents or empty)
        agents.removeAll()
        desks = OfficeLayout.desks
        nextCharacterIndex = 0

        // Spawn 14 demo agents
        for (index, demo) in DemoData.agents.enumerated() {
            let deskIndex = index < desks.count ? index : nil
            if let deskIndex {
                desks[deskIndex].occupantId = "demo-\(index)"
            }

            let agent = AgentState(
                id: "demo-\(index)",
                name: demo.name,
                role: demo.role,
                characterType: demo.characterType,
                status: .working,
                currentTask: demo.task,
                deskIndex: deskIndex
            )
            agents.append(agent)
        }

        // Start cycling demo agents through states
        startDemoCycling()
    }

    /// Stop demo mode and clear all demo agents.
    func stopDemoMode() {
        isDemoMode = false
        demoCycleTask?.cancel()
        demoCycleTask = nil
        activityManager.reset()

        // Clear demo agents
        agents.removeAll { $0.id.hasPrefix("demo-") }
        desks = OfficeLayout.desks
    }

    /// Toggle demo mode on/off.
    func toggleDemoMode() {
        if isDemoMode {
            stopDemoMode()
        } else {
            startDemoMode()
        }
    }

    /// Cycle demo agents through states: idle -> work -> break -> celebrate
    private func startDemoCycling() {
        demoCycleTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }

                // Pick 2-4 random agents to cycle
                let count = Int.random(in: 2...4)
                let shuffled = self.agents.filter { $0.id.hasPrefix("demo-") }.shuffled()
                let selected = Array(shuffled.prefix(count))

                for agent in selected {
                    guard let index = self.agents.firstIndex(where: { $0.id == agent.id }) else { continue }

                    // Pick next phase based on current status
                    let nextPhase = self.nextDemoPhase(for: agent.status)

                    switch nextPhase {
                    case .idle:
                        self.agents[index].status = .idle
                        self.agents[index].currentTask = nil

                    case .work:
                        self.agents[index].status = .working
                        self.agents[index].currentTask = DemoData.agents
                            .randomElement()?.task ?? "Working hard"

                    case .celebrate:
                        self.agents[index].status = .celebrating
                        self.agents[index].currentTask = "Task completed!"
                        // Reset after 2 seconds
                        let agentId = agent.id
                        Task { @MainActor [weak self] in
                            try? await Task.sleep(for: .seconds(2))
                            guard let self else { return }
                            if let idx = self.agents.firstIndex(where: { $0.id == agentId }) {
                                self.agents[idx].status = .working
                                self.agents[idx].currentTask = DemoData.agents
                                    .randomElement()?.task ?? "Back to work"
                            }
                        }
                    }
                }

                // Wait 4-8 seconds before next cycle
                let delay = TimeInterval.random(in: 4...8)
                try? await Task.sleep(for: .seconds(delay))
            }
        }
    }

    /// Determine the next demo phase based on current status.
    private func nextDemoPhase(for status: AgentStatus) -> DemoPhase {
        switch status {
        case .working:
            // From working: go idle or celebrate
            return Bool.random() ? .idle : .celebrate
        case .idle:
            // From idle: go back to work
            return .work
        case .celebrating:
            // From celebrating: go back to work
            return .work
        default:
            return .work
        }
    }

    // MARK: - Agent Lifecycle Handlers

    /// Called when the relay broadcasts `agent.spawn`.
    /// Creates a new agent, assigns a character type and desk, sets status to spawning.
    func handleAgentSpawn(id: String, role: String, task: String) {
        // Don't double-spawn
        guard !agents.contains(where: { $0.id == id }) else { return }

        // If in demo mode, stop it when real agents arrive
        if isDemoMode {
            stopDemoMode()
        }

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
    /// Agent celebrates, then leaves.
    func handleAgentComplete(id: String, result: String) {
        guard let index = agents.firstIndex(where: { $0.id == id }) else { return }
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
        releaseDesk(for: id)
        activityManager.releaseStation(for: id)

        // Remove after walking out
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
