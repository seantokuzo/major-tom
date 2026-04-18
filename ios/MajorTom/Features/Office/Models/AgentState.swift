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

/// All character types available in the station: crew, celebrities, and dogs.
enum CharacterType: String, CaseIterable {
    // MARK: Crew
    case alienDiplomat
    case backendEngineer
    case botanist
    case bowenYang      // Bowen Yang — celebrity
    case captain
    case chef
    case claudimusPrime // Ship's android
    case doctor
    case dwight         // Dwight Schrute — The Office
    case frontendDev
    case kendrick       // Kendrick Lamar
    case mechanic
    case pm
    case prince         // Prince

    // MARK: Dogs (named after the real dogs)
    case elvis          // Dachshund in space suit
    case esteban        // Cattle dog alt (bow tie)
    case hoku           // Black schnauzer
    case kai            // Pepper schnauzer
    case senor          // Dachshund alt (green hoodie)
    case steve          // Cattle dog in space suit
    case zuckerbot      // Robot dog

    /// Whether this character is a dog (used for activity group filtering).
    var isDog: Bool {
        switch self {
        case .elvis, .esteban, .hoku, .kai, .senor, .steve, .zuckerbot:
            return true
        default:
            return false
        }
    }
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

    // MARK: - Sprite-Agent Wiring (Wave 2)

    /// The subagent ID this sprite is linked to (nil for idle/cosmetic sprites).
    var linkedSubagentId: String?

    /// Unique instance ID from relay — supports clone-not-consume model
    /// where multiple agent sprites can share the same CharacterType.
    var spriteHandle: String?

    /// The classified canonical role (researcher, architect, qa, devops,
    /// frontend, backend, lead, engineer) used by RoleMapper.
    var canonicalRole: String?

    /// The parent agent ID from the spawn event (orchestrator that spawned this subagent).
    /// Needed for future multi-session routing (Wave 3).
    var parentId: String?

    // MARK: - Tab-Keyed Offices (Wave 5)

    /// The Claude `sessionId` that originated this agent.
    ///
    /// Populated on `agent.spawn` / `sprite.link` / `sprite.state` rehydration
    /// and **preserved** across every state transition. Used by
    /// `OfficeSceneManager.handleTabSessionEnded` to walk off only the agents
    /// whose originating session ended — dogs (idle sprites) and agents
    /// scoped to any other still-active session in the tab stay put.
    ///
    /// `nil` for idle cosmetic sprites (dogs + crew pool) and for agents that
    /// slipped in before Wave 3 plumbing propagated the sessionId onto their
    /// spawn path.
    ///
    /// NOTE: deliberately **not** included in the custom `Equatable` below —
    /// sessionId may be populated at spawn or latched later when an existing
    /// agent is upgraded on `sprite.link`, but once set it is expected to
    /// remain stable. Omitting it keeps `.onChange(of: viewModel.agents)`
    /// diffing cheap and avoids spurious walk-in triggers.
    var sessionId: String?

    // MARK: - Overflow Placement (Wave 6 — S5)

    /// Pre-claimed overflow position when all 8 desks are occupied.
    /// Set when the agent spawns into an empty-desk situation; the scene
    /// walks the sprite to this point instead of a desk seat.
    var overflowPosition: CGPoint?

    init(
        id: String,
        name: String,
        role: String,
        characterType: CharacterType,
        status: AgentStatus = .spawning,
        currentTask: String? = nil,
        deskIndex: Int? = nil,
        spawnedAt: Date = Date(),
        linkedSubagentId: String? = nil,
        spriteHandle: String? = nil,
        canonicalRole: String? = nil,
        parentId: String? = nil,
        sessionId: String? = nil,
        overflowPosition: CGPoint? = nil
    ) {
        self.id = id
        self.name = name
        self.role = role
        self.characterType = characterType
        self.status = status
        self.currentTask = currentTask
        self.deskIndex = deskIndex
        self.spawnedAt = spawnedAt
        self.linkedSubagentId = linkedSubagentId
        self.spriteHandle = spriteHandle
        self.canonicalRole = canonicalRole
        self.parentId = parentId
        self.sessionId = sessionId
        self.overflowPosition = overflowPosition
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
        lhs.deskIndex == rhs.deskIndex &&
        lhs.linkedSubagentId == rhs.linkedSubagentId &&
        lhs.spriteHandle == rhs.spriteHandle &&
        lhs.canonicalRole == rhs.canonicalRole &&
        lhs.parentId == rhs.parentId &&
        lhs.characterType == rhs.characterType &&
        lhs.overflowPosition == rhs.overflowPosition
    }
}
