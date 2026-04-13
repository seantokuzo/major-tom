import Foundation

// MARK: - Activity Type

enum ActivityType: String, Codable {
    case idle   // Fun/rest — cooking, gaming, sleeping, walking
    case work   // Task-oriented — research, planning, coding
}

// MARK: - Asset Transition

/// Texture swap on furniture during an activity (e.g., lamp on → off while reading).
struct AssetTransition: Codable {
    let furnitureType: String       // Which furniture type to modify
    let fromTexture: String         // Original texture name
    let toTexture: String           // Swap to this during activity
    let reverseOnComplete: Bool     // Swap back when activity ends
}

// MARK: - Activity Definition

/// A JSON-configured activity that characters can perform at furniture.
/// Adding a new activity = adding a JSON entry. No Swift changes needed.
struct ActivityDefinition: Identifiable, Codable {
    let id: String
    let displayName: String
    let type: ActivityType
    let description: String

    // Location
    let furnitureTypes: [String]     // e.g., ["food_dispenser"]
    let roomTypes: [String]          // e.g., ["galley"] — ModuleType raw values

    // Eligibility
    let characterGroup: String       // "humans", "dogs", "all", "specific"
    let specificCharacters: [String]  // Used when characterGroup == "specific"

    // Timing
    let durationRange: [Double]      // [min, max] in seconds
    let cooldown: Double             // Seconds before same character repeats
    let priority: Double             // 0-1, weight for random selection

    // Animation
    let animationID: String?         // Maps to AgentSprite animation method
    let emoteFrequency: Double       // 0-1, chance of emotes during activity

    // Position
    let positionOffset: [String: [Double]]  // furniture_type → [dx, dy] offset

    // Asset transitions (texture swaps on furniture during activity)
    let assetTransitions: [AssetTransition]
}

// MARK: - Activities File

/// Root container for the Activities.json file.
struct ActivitiesFile: Codable {
    let activities: [ActivityDefinition]
}
