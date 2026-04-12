import SwiftUI

// MARK: - Break Destination

/// Places an agent character can visit during idle breaks.
enum BreakDestination: String, CaseIterable {
    case breakRoom
    case kitchen
    case dogCorner
    case dogPark
    case gym
    case rollercoaster
}

// MARK: - Character Config

/// Static configuration for each character type.
/// Defines display properties and behavior options.
struct CharacterConfig: Identifiable {
    let type: CharacterType
    let displayName: String
    let spriteColor: Color
    let breakBehaviors: [BreakDestination]

    /// Dachshund-specific: needs a blanket at their desk.
    /// Note: Blanket mechanic UI is planned for a future phase — this flag
    /// is pre-wired so the config is ready when the interaction is built.
    let needsBlanket: Bool

    var id: String { type.rawValue }
}

// MARK: - Character Catalog

/// The full catalog of all character configurations.
enum CharacterCatalog {

    static let all: [CharacterConfig] = [
        // MARK: Original Crew
        CharacterConfig(
            type: .dev,
            displayName: "Developer",
            spriteColor: Color(red: 0.30, green: 0.70, blue: 0.95),  // Blue
            breakBehaviors: [.breakRoom, .kitchen, .gym],
            needsBlanket: false
        ),
        CharacterConfig(
            type: .officeWorker,
            displayName: "Office Worker",
            spriteColor: Color(red: 0.55, green: 0.80, blue: 0.45),  // Green
            breakBehaviors: [.breakRoom, .kitchen],
            needsBlanket: false
        ),
        CharacterConfig(
            type: .pm,
            displayName: "Project Manager",
            spriteColor: Color(red: 0.95, green: 0.75, blue: 0.30),  // Yellow/Gold
            breakBehaviors: [.breakRoom, .kitchen, .gym],
            needsBlanket: false
        ),
        CharacterConfig(
            type: .clown,
            displayName: "Office Clown",
            spriteColor: Color(red: 0.95, green: 0.40, blue: 0.60),  // Pink
            breakBehaviors: [.breakRoom, .kitchen, .rollercoaster, .gym],
            needsBlanket: false
        ),
        CharacterConfig(
            type: .frankenstein,
            displayName: "Frankenstein",
            spriteColor: Color(red: 0.50, green: 0.85, blue: 0.50),  // Frankenstein green
            breakBehaviors: [.breakRoom, .gym, .rollercoaster],
            needsBlanket: false
        ),
        CharacterConfig(
            type: .dwight,
            displayName: "Dwight",
            spriteColor: Color(red: 0.75, green: 0.65, blue: 0.20),  // Mustard yellow tie
            breakBehaviors: [.breakRoom, .gym, .kitchen],
            needsBlanket: false
        ),
        CharacterConfig(
            type: .michael,
            displayName: "Michael",
            spriteColor: Color(red: 0.25, green: 0.30, blue: 0.55),  // Navy suit
            breakBehaviors: [.breakRoom, .kitchen, .rollercoaster],
            needsBlanket: false
        ),

        // MARK: New Crew
        CharacterConfig(
            type: .alienDiplomat,
            displayName: "Alien Diplomat",
            spriteColor: Color(red: 0.60, green: 0.90, blue: 0.70),  // Mint green
            breakBehaviors: [.breakRoom, .kitchen],
            needsBlanket: false
        ),
        CharacterConfig(
            type: .backendEngineer,
            displayName: "Backend Engineer",
            spriteColor: Color(red: 0.40, green: 0.55, blue: 0.80),  // Steel blue
            breakBehaviors: [.breakRoom, .kitchen, .gym],
            needsBlanket: false
        ),
        CharacterConfig(
            type: .botanist,
            displayName: "Botanist",
            spriteColor: Color(red: 0.45, green: 0.75, blue: 0.35),  // Plant green
            breakBehaviors: [.breakRoom, .kitchen],
            needsBlanket: false
        ),
        CharacterConfig(
            type: .captain,
            displayName: "Captain",
            spriteColor: Color(red: 0.20, green: 0.25, blue: 0.50),  // Navy blue coat
            breakBehaviors: [.breakRoom, .kitchen],
            needsBlanket: false
        ),
        CharacterConfig(
            type: .chef,
            displayName: "Space Chef",
            spriteColor: Color(red: 0.95, green: 0.95, blue: 0.95),  // Chef white
            breakBehaviors: [.breakRoom, .kitchen],
            needsBlanket: false
        ),
        CharacterConfig(
            type: .claudimusPrime,
            displayName: "Claudimus Prime",
            spriteColor: Color(red: 0.70, green: 0.75, blue: 0.85),  // Silver/blue
            breakBehaviors: [.breakRoom, .gym],
            needsBlanket: false
        ),
        CharacterConfig(
            type: .doctor,
            displayName: "Doctor",
            spriteColor: Color(red: 0.90, green: 0.95, blue: 0.95),  // White with teal
            breakBehaviors: [.breakRoom, .kitchen],
            needsBlanket: false
        ),
        CharacterConfig(
            type: .frontendDev,
            displayName: "Frontend Dev",
            spriteColor: Color(red: 0.85, green: 0.50, blue: 0.90),  // Purple/magenta
            breakBehaviors: [.breakRoom, .kitchen, .gym],
            needsBlanket: false
        ),
        CharacterConfig(
            type: .hacker,
            displayName: "Hacker",
            spriteColor: Color(red: 0.20, green: 0.85, blue: 0.30),  // Neon green
            breakBehaviors: [.breakRoom, .gym],
            needsBlanket: false
        ),
        CharacterConfig(
            type: .mechanic,
            displayName: "Mechanic",
            spriteColor: Color(red: 0.90, green: 0.55, blue: 0.20),  // Orange jumpsuit
            breakBehaviors: [.breakRoom, .kitchen, .gym],
            needsBlanket: false
        ),
        CharacterConfig(
            type: .pilot,
            displayName: "Pilot",
            spriteColor: Color(red: 0.25, green: 0.45, blue: 0.30),  // Dark green flight suit
            breakBehaviors: [.breakRoom, .kitchen, .gym],
            needsBlanket: false
        ),
        CharacterConfig(
            type: .security,
            displayName: "Security Officer",
            spriteColor: Color(red: 0.30, green: 0.30, blue: 0.35),  // Dark charcoal
            breakBehaviors: [.breakRoom, .gym],
            needsBlanket: false
        ),
        CharacterConfig(
            type: .tpm,
            displayName: "TPM",
            spriteColor: Color(red: 0.55, green: 0.45, blue: 0.70),  // Professional purple
            breakBehaviors: [.breakRoom, .kitchen],
            needsBlanket: false
        ),

        // MARK: Celebrities
        CharacterConfig(
            type: .kendrick,
            displayName: "Kendrick",
            spriteColor: Color(red: 0.85, green: 0.65, blue: 0.20),  // Gold
            breakBehaviors: [.breakRoom, .kitchen, .gym],
            needsBlanket: false
        ),
        CharacterConfig(
            type: .prince,
            displayName: "Prince",
            spriteColor: Color(red: 0.55, green: 0.20, blue: 0.80),  // Purple
            breakBehaviors: [.breakRoom, .kitchen, .rollercoaster],
            needsBlanket: false
        ),

        // MARK: Dogs
        CharacterConfig(
            type: .elvis,
            displayName: "Elvis",
            spriteColor: Color(red: 0.75, green: 0.45, blue: 0.20),  // Auburn brown
            breakBehaviors: [.dogCorner, .dogPark, .kitchen],
            needsBlanket: true  // Always needs a blanket at their desk
        ),
        CharacterConfig(
            type: .senor,
            displayName: "Señor",
            spriteColor: Color(red: 0.65, green: 0.40, blue: 0.18),  // Warm brown
            breakBehaviors: [.dogCorner, .dogPark, .kitchen],
            needsBlanket: true
        ),
        CharacterConfig(
            type: .steve,
            displayName: "Steve",
            spriteColor: Color(red: 0.85, green: 0.35, blue: 0.25),  // Red heeler
            breakBehaviors: [.dogCorner, .dogPark, .gym],
            needsBlanket: false
        ),
        CharacterConfig(
            type: .esteban,
            displayName: "Esteban",
            spriteColor: Color(red: 0.80, green: 0.30, blue: 0.22),  // Warm red
            breakBehaviors: [.dogCorner, .dogPark, .gym],
            needsBlanket: false
        ),
        CharacterConfig(
            type: .hoku,
            displayName: "Hoku",
            spriteColor: Color(red: 0.15, green: 0.15, blue: 0.20),  // All black
            breakBehaviors: [.dogCorner, .dogPark, .breakRoom],
            needsBlanket: false
        ),
        CharacterConfig(
            type: .kai,
            displayName: "Kai",
            spriteColor: Color(red: 0.35, green: 0.35, blue: 0.40),  // Salt & pepper
            breakBehaviors: [.dogCorner, .dogPark, .breakRoom],
            needsBlanket: false
        ),
    ]

    /// Dictionary for O(1) lookup by type.
    private static let configByType: [CharacterType: CharacterConfig] = {
        Dictionary(uniqueKeysWithValues: all.map { ($0.type, $0) })
    }()

    /// Look up config by character type.
    static func config(for type: CharacterType) -> CharacterConfig {
        guard let config = configByType[type] else {
            fatalError("Missing CharacterConfig for \(type). Ensure all CharacterType cases are in CharacterCatalog.all.")
        }
        return config
    }
}
