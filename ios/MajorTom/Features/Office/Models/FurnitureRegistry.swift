import Foundation

// MARK: - Furniture Instance

/// A placed furniture item in a specific room, tracked for activity targeting.
struct FurnitureInstance: Identifiable {
    let id: String              // Unique instance ID (e.g., "crew_couch")
    let furnitureType: String   // Generic type (e.g., "couch")
    let room: String            // ModuleType raw value (e.g., "crewQuarters")
    let position: CGPoint       // Scene-space position

    /// Currently occupied by this agent ID (nil = available).
    var occupantId: String?

    var isAvailable: Bool { occupantId == nil }
}

// MARK: - Furniture Registry

/// Tracks all placed furniture instances per room.
/// Registered at scene init, queried by the ActivitySelectionEngine.
@MainActor
final class FurnitureRegistry {

    /// All furniture instances keyed by instance ID.
    private(set) var instances: [String: FurnitureInstance] = [:]

    // MARK: - Registration

    /// Register a furniture instance when placed in the scene.
    func register(id: String, furnitureType: String, room: String, position: CGPoint) {
        instances[id] = FurnitureInstance(
            id: id,
            furnitureType: furnitureType,
            room: room,
            position: position
        )
    }

    // MARK: - Queries

    /// Find available furniture of a given type in a given room.
    func availableFurniture(type: String, in room: String) -> [FurnitureInstance] {
        instances.values.filter { $0.furnitureType == type && $0.room == room && $0.isAvailable }
    }

    /// Find any available furniture matching any of the given types in a room.
    func availableFurniture(types: [String], in room: String) -> [FurnitureInstance] {
        instances.values.filter { types.contains($0.furnitureType) && $0.room == room && $0.isAvailable }
    }

    /// Get a specific furniture instance.
    func furniture(byId id: String) -> FurnitureInstance? {
        instances[id]
    }

    // MARK: - Occupancy

    /// Mark a furniture instance as occupied by an agent.
    func occupy(furnitureId: String, agentId: String) {
        instances[furnitureId]?.occupantId = agentId
    }

    /// Release a furniture instance.
    func release(furnitureId: String) {
        instances[furnitureId]?.occupantId = nil
    }

    /// Release all furniture occupied by a given agent.
    func releaseAll(for agentId: String) {
        let ids = instances.compactMap { id, instance in
            instance.occupantId == agentId ? id : nil
        }
        for id in ids {
            instances[id]?.occupantId = nil
        }
    }

    /// Clear all registrations.
    func reset() {
        instances.removeAll()
    }
}
