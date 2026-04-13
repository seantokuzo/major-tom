import Foundation

// MARK: - Activity Registry

/// Loads activity definitions from Activities.json and provides query APIs.
/// Singleton — loaded once at app startup, immutable after that.
@MainActor
final class ActivityRegistry {

    static let shared = ActivityRegistry()

    private(set) var activities: [ActivityDefinition] = []

    private init() {
        loadActivities()
    }

    // MARK: - Loading

    private func loadActivities() {
        guard let url = Bundle.main.url(forResource: "Activities", withExtension: "json") else {
            print("[ActivityRegistry] Activities.json not found in bundle")
            return
        }
        do {
            let data = try Data(contentsOf: url)
            let file = try JSONDecoder().decode(ActivitiesFile.self, from: data)
            activities = file.activities
            print("[ActivityRegistry] Loaded \(activities.count) activities")
        } catch {
            print("[ActivityRegistry] Failed to decode Activities.json: \(error)")
        }
    }

    // MARK: - Queries

    /// Find activities available in a given room for a given character.
    func availableActivities(
        in room: String,
        characterType: CharacterType,
        isDog: Bool
    ) -> [ActivityDefinition] {
        activities.filter { activity in
            // Room match
            guard activity.roomTypes.contains(room) else { return false }

            // Character group match
            switch activity.characterGroup {
            case "all":
                return true
            case "humans":
                return !isDog
            case "dogs":
                return isDog
            case "specific":
                return activity.specificCharacters.contains(characterType.rawValue)
            default:
                return false
            }
        }
    }

    /// Find activities that can use a specific furniture type.
    func activities(for furnitureType: String) -> [ActivityDefinition] {
        activities.filter { $0.furnitureTypes.contains(furnitureType) }
    }

    /// Look up a single activity by ID.
    func activity(byId id: String) -> ActivityDefinition? {
        activities.first { $0.id == id }
    }
}
