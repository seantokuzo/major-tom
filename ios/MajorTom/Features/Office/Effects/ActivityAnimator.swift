import SpriteKit

// MARK: - Activity Animator

/// Orchestrates activity-phase effects: periodic emotes and furniture texture swaps.
/// Started when an agent arrives at their activity, stopped on rotation or interruption.
@MainActor
final class ActivityAnimator {

    // MARK: - Types

    /// A running activity phase for one agent.
    private struct ActivePhase {
        let agentId: String
        let activityId: String
        let emoteTask: Task<Void, Never>?
        let appliedTransitions: [AppliedTransition]
    }

    /// A texture swap applied to a furniture node that may need reversal.
    private struct AppliedTransition {
        let furnitureInstanceId: String
        let originalTextureName: String
        let reverseOnComplete: Bool
    }

    // MARK: - State

    private var activePhases: [String: ActivePhase] = [:]

    /// Activity-appropriate emotes by animation type.
    private static let activityEmotes: [String: [EmoteType]] = [
        "sleeping": [.zzz],
        "cooking": [.star, .exclamation],
        "reading": [.thought],
        "exercising": [.exclamation, .star],
        "working": [.wrench, .thought],
        "arcade": [.exclamation, .star, .heart],
        "running": [.exclamation, .heart, .star],
        "sniffing": [.thought, .exclamation],
        "sitting": [.thought, .heart],
        "waiting": [.thought],
        "walking": [.heart, .star],
    ]

    // MARK: - Start / Stop

    /// Begin activity-phase effects for an agent.
    /// - Parameters:
    ///   - agentId: The agent performing the activity.
    ///   - assignment: The assigned activity (has emoteFrequency, animationID, duration).
    ///   - definition: The full activity definition (has assetTransitions).
    ///   - sprite: The agent's sprite node (for emotes).
    ///   - furnitureNodes: Scene's furniture node lookup (for texture swaps).
    ///   - furnitureRegistry: Registry to find furniture by type+room.
    func startPhase(
        agentId: String,
        assignment: ActivityAssignment,
        definition: ActivityDefinition,
        sprite: AgentSprite,
        furnitureNodes: [String: SKNode],
        furnitureRegistry: FurnitureRegistry
    ) {
        // Stop any existing phase for this agent
        stopPhase(for: agentId, furnitureNodes: furnitureNodes)

        // Apply asset transitions
        let applied = applyTransitions(
            definition.assetTransitions,
            furnitureInstanceId: assignment.furnitureInstanceId,
            furnitureNodes: furnitureNodes,
            furnitureRegistry: furnitureRegistry
        )

        // Start periodic emote task
        let emoteTask = startEmoteTimer(
            sprite: sprite,
            emoteFrequency: assignment.emoteFrequency,
            animationID: assignment.animationID,
            duration: assignment.duration
        )

        activePhases[agentId] = ActivePhase(
            agentId: agentId,
            activityId: assignment.activityId,
            emoteTask: emoteTask,
            appliedTransitions: applied
        )
    }

    /// Stop activity-phase effects for an agent and reverse any texture swaps.
    func stopPhase(for agentId: String, furnitureNodes: [String: SKNode]) {
        guard let phase = activePhases.removeValue(forKey: agentId) else { return }

        phase.emoteTask?.cancel()
        reverseTransitions(phase.appliedTransitions, furnitureNodes: furnitureNodes)
    }

    /// Stop all active phases (e.g., scene teardown).
    func stopAll(furnitureNodes: [String: SKNode]) {
        for (agentId, phase) in activePhases {
            phase.emoteTask?.cancel()
            reverseTransitions(phase.appliedTransitions, furnitureNodes: furnitureNodes)
            activePhases.removeValue(forKey: agentId)
        }
    }

    /// Whether an agent has an active animation phase.
    func hasActivePhase(for agentId: String) -> Bool {
        activePhases[agentId] != nil
    }

    // MARK: - Emote Timer

    /// Start a Task that periodically shows activity-appropriate emotes.
    /// Checks every 4 seconds, rolls against emoteFrequency.
    private func startEmoteTimer(
        sprite: AgentSprite,
        emoteFrequency: Double,
        animationID: String?,
        duration: TimeInterval
    ) -> Task<Void, Never>? {
        guard emoteFrequency > 0 else { return nil }

        let emotePool = Self.activityEmotes[animationID ?? ""] ?? [.thought, .star]

        return Task { [weak sprite] in
            // Initial delay before first possible emote
            try? await Task.sleep(for: .seconds(Double.random(in: 3...6)))

            let checkInterval: Duration = .seconds(4)
            var elapsed: TimeInterval = 0

            while !Task.isCancelled, elapsed < duration {
                guard let sprite else { return }

                if Double.random(in: 0...1) < emoteFrequency {
                    if let emote = emotePool.randomElement() {
                        sprite.showEmote(emote)
                    }
                }

                try? await Task.sleep(for: checkInterval)
                elapsed += 4
            }
        }
    }

    // MARK: - Asset Transitions

    /// Apply texture swaps to furniture nodes. Returns records for reversal.
    private func applyTransitions(
        _ transitions: [AssetTransition],
        furnitureInstanceId: String,
        furnitureNodes: [String: SKNode],
        furnitureRegistry: FurnitureRegistry
    ) -> [AppliedTransition] {
        guard !transitions.isEmpty else { return [] }

        // Determine which room the activity is in
        guard let assignedFurniture = furnitureRegistry.furniture(byId: furnitureInstanceId) else { return [] }
        let room = assignedFurniture.room

        var applied: [AppliedTransition] = []

        for transition in transitions {
            // Find furniture of the target type in the same room
            let candidates = furnitureRegistry.instances.values.filter {
                $0.furnitureType == transition.furnitureType && $0.room == room
            }

            for candidate in candidates {
                guard let node = furnitureNodes[candidate.id],
                      let spriteNode = node as? SKSpriteNode else { continue }

                // Swap texture
                let newTexture = SKTexture(imageNamed: transition.toTexture)
                newTexture.filteringMode = .nearest
                spriteNode.texture = newTexture

                applied.append(AppliedTransition(
                    furnitureInstanceId: candidate.id,
                    originalTextureName: transition.fromTexture,
                    reverseOnComplete: transition.reverseOnComplete
                ))
            }
        }

        return applied
    }

    /// Reverse previously applied texture swaps.
    private func reverseTransitions(_ transitions: [AppliedTransition], furnitureNodes: [String: SKNode]) {
        for transition in transitions where transition.reverseOnComplete {
            guard let node = furnitureNodes[transition.furnitureInstanceId],
                  let spriteNode = node as? SKSpriteNode else { continue }

            let originalTexture = SKTexture(imageNamed: transition.originalTextureName)
            originalTexture.filteringMode = .nearest
            spriteNode.texture = originalTexture
        }
    }
}
