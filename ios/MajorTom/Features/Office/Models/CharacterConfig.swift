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

/// Static configuration for each of the 9 character types.
/// Defines display properties and behavior options.
struct CharacterConfig: Identifiable {
    let type: CharacterType
    let displayName: String
    let spriteColor: Color
    let breakBehaviors: [BreakDestination]

    /// Dachshund-specific: needs a blanket at their desk.
    let needsBlanket: Bool

    var id: String { type.rawValue }
}

// MARK: - Character Catalog

/// The full catalog of all 9 character configurations.
enum CharacterCatalog {

    static let all: [CharacterConfig] = [
        // MARK: Humans
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

        // MARK: Dogs
        CharacterConfig(
            type: .dachshund,
            displayName: "Dachshund",
            spriteColor: Color(red: 0.75, green: 0.45, blue: 0.20),  // Auburn brown
            breakBehaviors: [.dogCorner, .dogPark, .kitchen],
            needsBlanket: true  // Always needs a blanket at their desk
        ),
        CharacterConfig(
            type: .cattleDog,
            displayName: "Cattle Dog",
            spriteColor: Color(red: 0.85, green: 0.35, blue: 0.25),  // Red heeler
            breakBehaviors: [.dogCorner, .dogPark, .gym],
            needsBlanket: false
        ),
        CharacterConfig(
            type: .schnauzerBlack,
            displayName: "Black Schnauzer",
            spriteColor: Color(red: 0.15, green: 0.15, blue: 0.20),  // All black
            breakBehaviors: [.dogCorner, .dogPark, .breakRoom],
            needsBlanket: false
        ),
        CharacterConfig(
            type: .schnauzerPepper,
            displayName: "Pepper Schnauzer",
            spriteColor: Color(red: 0.35, green: 0.35, blue: 0.40),  // Salt & pepper (mostly dark)
            breakBehaviors: [.dogCorner, .dogPark, .breakRoom],
            needsBlanket: false
        ),
    ]

    /// Look up config by character type.
    static func config(for type: CharacterType) -> CharacterConfig {
        all.first { $0.type == type }!
    }
}
