import Foundation

// MARK: - Activity Assignment (New)

/// An assigned activity — what the agent is doing, where, and for how long.
struct ActivityAssignment {
    let activityId: String
    let displayName: String
    let furnitureInstanceId: String
    let targetPosition: CGPoint       // Where the agent should stand
    let animationID: String?
    let emoteFrequency: Double
    let duration: TimeInterval
    let startedAt: Date

    var isExpired: Bool {
        Date().timeIntervalSince(startedAt) >= duration
    }

    var timeRemaining: TimeInterval {
        max(0, duration - Date().timeIntervalSince(startedAt))
    }
}

// MARK: - Activity Selection Engine

/// Selects activities for idle agents using weighted random selection,
/// character group filtering, cooldowns, and furniture occupancy.
@Observable
@MainActor
final class ActivitySelectionEngine {

    /// Current activity assignments by agent ID.
    private(set) var assignments: [String: ActivityAssignment] = [:]

    /// Cooldown tracking: agentId → (activityId → lastCompletedAt)
    private var cooldowns: [String: [String: Date]] = [:]

    /// Timer for cycling activities.
    private var cycleTask: Task<Void, Never>?

    /// External dependencies.
    private let registry: ActivityRegistry
    private(set) var furnitureRegistry: FurnitureRegistry

    init() {
        self.registry = ActivityRegistry.shared
        self.furnitureRegistry = FurnitureRegistry()
    }

    /// Replace the furniture registry with the scene's instance.
    /// Called from OfficeView.onAppear to wire the scene-owned registry.
    func setFurnitureRegistry(_ registry: FurnitureRegistry) {
        self.furnitureRegistry = registry
    }

    // MARK: - Selection

    /// Select and assign an activity for an idle agent.
    /// Returns the assignment if a suitable activity was found, nil otherwise.
    func assignActivity(
        agentId: String,
        characterType: CharacterType,
        currentRoom: String
    ) -> ActivityAssignment? {
        // Release any existing assignment first
        releaseActivity(for: agentId)

        let isDog = characterType.isDog

        // Get all activities available in this room for this character
        let candidates = registry.availableActivities(in: currentRoom, characterType: characterType, isDog: isDog)

        // Filter by furniture availability and cooldowns
        var weightedCandidates: [(activity: ActivityDefinition, furniture: FurnitureInstance, weight: Double)] = []

        for activity in candidates {
            // Check cooldown
            if let lastDone = cooldowns[agentId]?[activity.id] {
                let elapsed = Date().timeIntervalSince(lastDone)
                if elapsed < activity.cooldown { continue }
            }

            // Find available furniture for this activity in this room
            let available = furnitureRegistry.availableFurniture(types: activity.furnitureTypes, in: currentRoom)
            guard let furniture = available.randomElement() else { continue }

            // Calculate weight
            var weight = activity.priority

            // Variety penalty — reduce weight if agent recently did similar activities
            if let agentCooldowns = cooldowns[agentId] {
                let recentCount = agentCooldowns.values.filter { Date().timeIntervalSince($0) < 120 }.count
                weight *= max(0.3, 1.0 - Double(recentCount) * 0.1)
            }

            weightedCandidates.append((activity, furniture, weight))
        }

        guard !weightedCandidates.isEmpty else { return nil }

        // Weighted random selection
        let totalWeight = weightedCandidates.reduce(0) { $0 + $1.weight }
        guard totalWeight > 0 else { return nil }
        var roll = Double.random(in: 0..<totalWeight)

        var selected = weightedCandidates[0]
        for candidate in weightedCandidates {
            roll -= candidate.weight
            if roll <= 0 {
                selected = candidate
                break
            }
        }

        // Calculate target position with offset
        var targetPos = selected.furniture.position
        if let offsets = selected.activity.positionOffset[selected.furniture.furnitureType],
           offsets.count >= 2 {
            targetPos.x += CGFloat(offsets[0])
            targetPos.y += CGFloat(offsets[1])
        }
        // Add slight randomization so agents don't stack perfectly
        targetPos.x += CGFloat.random(in: -5...5)
        targetPos.y += CGFloat.random(in: -5...5)

        // Determine duration
        let minDuration = selected.activity.durationRange.first ?? 15
        let maxDuration = selected.activity.durationRange.last ?? 60
        let duration = TimeInterval.random(in: minDuration...maxDuration)

        // Create assignment
        let assignment = ActivityAssignment(
            activityId: selected.activity.id,
            displayName: selected.activity.displayName,
            furnitureInstanceId: selected.furniture.id,
            targetPosition: targetPos,
            animationID: selected.activity.animationID,
            emoteFrequency: selected.activity.emoteFrequency,
            duration: duration,
            startedAt: Date()
        )

        // Commit
        assignments[agentId] = assignment
        furnitureRegistry.occupy(furnitureId: selected.furniture.id, agentId: agentId)

        return assignment
    }

    // MARK: - Release

    /// Release an agent's current activity and free furniture.
    func releaseActivity(for agentId: String) {
        guard let assignment = assignments[agentId] else { return }

        // Record cooldown
        cooldowns[agentId, default: [:]][assignment.activityId] = Date()

        // Release furniture
        furnitureRegistry.release(furnitureId: assignment.furnitureInstanceId)

        assignments.removeValue(forKey: agentId)
    }

    // MARK: - Queries

    /// Get the current assignment for an agent.
    func currentActivity(for agentId: String) -> ActivityAssignment? {
        assignments[agentId]
    }

    /// Human-readable description of an agent's current activity.
    func activityDescription(for agentId: String) -> String? {
        assignments[agentId]?.displayName
    }

    /// Get all agents whose activities have expired.
    func agentsNeedingRotation() -> [String] {
        assignments.compactMap { id, assignment in
            assignment.isExpired ? id : nil
        }
    }

    // MARK: - Cycle Management

    /// Start the activity cycling timer.
    /// Checks every 2 seconds for expired activities and rotates agents.
    func startCycling(onRotate: @escaping (String, ActivityAssignment?) -> Void) {
        stopCycling()

        cycleTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))

                guard let self else { return }

                let agentsToRotate = self.agentsNeedingRotation()
                for agentId in agentsToRotate {
                    onRotate(agentId, nil)
                }
            }
        }
    }

    /// Stop the activity cycling timer.
    func stopCycling() {
        cycleTask?.cancel()
        cycleTask = nil
    }

    /// Clear all assignments and stop cycling.
    func reset() {
        stopCycling()
        assignments.removeAll()
        cooldowns.removeAll()
        furnitureRegistry.reset()
    }
}
