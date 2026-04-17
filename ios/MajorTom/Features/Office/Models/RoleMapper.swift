import Foundation

// MARK: - Role Mapper

/// Maps canonical agent roles to CharacterTypes for sprite assignment.
///
/// Locked mapping (from Sprite-Agent Wiring spec):
///   researcher  -> .botanist
///   architect   -> .captain
///   qa          -> .doctor
///   devops      -> .mechanic
///   frontend    -> .frontendDev
///   backend     -> .backendEngineer
///   lead        -> .pm
///   engineer    -> .claudimusPrime
///
/// Role-stable binding: the first spawn for a given canonical role in a session
/// locks the CharacterType for that role. All subsequent spawns with the same role
/// reuse the same CharacterType. Different sessions bind independently.
enum RoleMapper {

    // MARK: - Canonical Role Mapping

    /// The 8 canonical roles recognized by the classifier.
    static let canonicalRoles: Set<String> = [
        "researcher", "architect", "qa", "devops",
        "frontend", "backend", "lead", "engineer"
    ]

    /// The overflow pool — used when a role doesn't map to any of the 8 primaries.
    /// These human CharacterTypes are never assigned as primary role mappings.
    static let overflowPool: [CharacterType] = [
        .alienDiplomat, .bowenYang, .chef, .dwight, .kendrick, .prince
    ]

    /// Direct mapping from canonical role string to CharacterType.
    static func characterType(forCanonicalRole role: String) -> CharacterType? {
        switch role.lowercased() {
        case "researcher": return .botanist
        case "architect":  return .captain
        case "qa":         return .doctor
        case "devops":     return .mechanic
        case "frontend":   return .frontendDev
        case "backend":    return .backendEngineer
        case "lead":       return .pm
        case "engineer":   return .claudimusPrime
        default:           return nil
        }
    }

    // MARK: - Role-Stable Binding

    /// Session-scoped bindings: maps canonical role -> locked CharacterType.
    /// Passed in and returned so callers own the storage (per-session).
    typealias SessionBindings = [String: CharacterType]

    /// Resolve the CharacterType for a role, respecting session-stable bindings.
    ///
    /// 1. If `role` was already bound this session, return the bound CharacterType.
    /// 2. If `role` maps to a canonical primary, bind and return it.
    /// 3. Otherwise, pick a random CharacterType from the overflow pool (excluding
    ///    already-bound types) and bind it.
    ///
    /// - Parameters:
    ///   - role: The canonical role string from the relay classifier.
    ///   - sessionBindings: Current session's role->CharacterType bindings.
    /// - Returns: The resolved CharacterType and the (potentially updated) bindings.
    static func resolveCharacterType(
        role: String,
        sessionBindings: SessionBindings
    ) -> (CharacterType, SessionBindings) {
        let normalizedRole = role.lowercased()

        // Already bound this session — reuse
        if let bound = sessionBindings[normalizedRole] {
            return (bound, sessionBindings)
        }

        var updatedBindings = sessionBindings

        // Try canonical mapping first
        if let mapped = characterType(forCanonicalRole: normalizedRole) {
            updatedBindings[normalizedRole] = mapped
            return (mapped, updatedBindings)
        }

        // Overflow: pick from pool, excluding already-bound types
        let boundTypes = Set(updatedBindings.values)
        let available = overflowPool.filter { !boundTypes.contains($0) }

        let picked: CharacterType
        if let choice = available.randomElement() {
            picked = choice
        } else {
            // All overflow exhausted — duplicate a random overflow character
            picked = overflowPool.randomElement() ?? .alienDiplomat
        }

        updatedBindings[normalizedRole] = picked
        return (picked, updatedBindings)
    }
}
