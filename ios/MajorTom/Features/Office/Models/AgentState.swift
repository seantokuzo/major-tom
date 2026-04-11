import Foundation

// MARK: - Agent Status

enum AgentStatus: String, CaseIterable {
    case spawning
    case walking
    case working
    case idle
    case celebrating
    case leaving
}

// MARK: - Character Type

/// The 13 character types available in the station: 7 humans + 6 dogs.
enum CharacterType: String, CaseIterable {
    // Humans
    case dev
    case officeWorker
    case pm
    case clown
    case frankenstein
    case dwight         // Dwight Schrute — The Office
    case michael        // Michael Scott — The Office

    // Dogs (named after the real dogs)
    case elvis          // Dachshund in space suit
    case senor          // Dachshund alt (green hoodie)
    case steve          // Cattle dog in space suit
    case esteban        // Cattle dog alt (bow tie)
    case hoku           // Black schnauzer
    case kai            // Pepper schnauzer
}

// MARK: - Agent State

/// Represents the current state of a single agent in the office.
/// Tracks lifecycle from spawn through dismissal.
struct AgentState: Identifiable {
    let id: String
    var name: String
    let role: String
    var characterType: CharacterType
    var status: AgentStatus
    var currentTask: String?
    var deskIndex: Int?
    let spawnedAt: Date

    init(
        id: String,
        name: String,
        role: String,
        characterType: CharacterType,
        status: AgentStatus = .spawning,
        currentTask: String? = nil,
        deskIndex: Int? = nil,
        spawnedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.role = role
        self.characterType = characterType
        self.status = status
        self.currentTask = currentTask
        self.deskIndex = deskIndex
        self.spawnedAt = spawnedAt
    }

    /// Time since the agent was spawned, formatted for display.
    var uptime: String {
        let interval = Date().timeIntervalSince(spawnedAt)
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }
}

// MARK: - Equatable (for onChange diffing in OfficeView)

extension AgentState: Equatable {
    static func == (lhs: AgentState, rhs: AgentState) -> Bool {
        lhs.id == rhs.id &&
        lhs.name == rhs.name &&
        lhs.status == rhs.status &&
        lhs.currentTask == rhs.currentTask &&
        lhs.deskIndex == rhs.deskIndex
    }
}
