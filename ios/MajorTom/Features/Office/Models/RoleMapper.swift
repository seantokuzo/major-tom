import Foundation
import UIKit

// MARK: - Role Mapper
//
// Post-QA-FIXES #9: character assignment is randomized per spawn by the
// relay, so the old role→CharacterType map + session-stable binding are
// gone. iOS trusts `sprite.link.characterType` from the relay directly
// and does not derive CharacterType from the canonical role. What remains
// here is the role → aura-color palette (Wave 5 spec), which is still
// keyed on canonicalRole.

enum RoleMapper {

    // MARK: - Role Color Palette (Wave 5)

    /// Role-colored aura palette. LOCKED per Wave 5 spec.
    ///
    /// Canonical → hex color:
    ///   researcher (.botanist)         → #4ADE80 (green)
    ///   architect  (.captain)          → #3B82F6 (blue)
    ///   qa         (.doctor)           → #EF4444 (red)
    ///   devops     (.mechanic)         → #F59E0B (orange)
    ///   frontend   (.frontendDev)      → #EC4899 (magenta)
    ///   backend    (.backendEngineer)  → #A855F7 (purple)
    ///   lead       (.pm)               → #EAB308 (yellow)
    ///   engineer   (.claudimusPrime)   → #06B6D4 (cyan)
    ///   (fallback)                     → #6B7280 (gray)
    ///
    /// Note: the parenthetical characters reference the legacy role→character
    /// map. They are not authoritative post-QA-FIXES #9 — characters are
    /// randomized per spawn, but the color-by-role palette is unchanged.
    static func color(forCanonicalRole role: String?) -> UIColor {
        guard let role = role?.lowercased() else {
            return UIColor(red: 0x6B / 255.0, green: 0x72 / 255.0, blue: 0x80 / 255.0, alpha: 1)
        }
        switch role {
        case "researcher":
            return UIColor(red: 0x4A / 255.0, green: 0xDE / 255.0, blue: 0x80 / 255.0, alpha: 1)
        case "architect":
            return UIColor(red: 0x3B / 255.0, green: 0x82 / 255.0, blue: 0xF6 / 255.0, alpha: 1)
        case "qa":
            return UIColor(red: 0xEF / 255.0, green: 0x44 / 255.0, blue: 0x44 / 255.0, alpha: 1)
        case "devops":
            return UIColor(red: 0xF5 / 255.0, green: 0x9E / 255.0, blue: 0x0B / 255.0, alpha: 1)
        case "frontend":
            return UIColor(red: 0xEC / 255.0, green: 0x48 / 255.0, blue: 0x99 / 255.0, alpha: 1)
        case "backend":
            return UIColor(red: 0xA8 / 255.0, green: 0x55 / 255.0, blue: 0xF7 / 255.0, alpha: 1)
        case "lead":
            return UIColor(red: 0xEA / 255.0, green: 0xB3 / 255.0, blue: 0x08 / 255.0, alpha: 1)
        case "engineer":
            return UIColor(red: 0x06 / 255.0, green: 0xB6 / 255.0, blue: 0xD4 / 255.0, alpha: 1)
        default:
            return UIColor(red: 0x6B / 255.0, green: 0x72 / 255.0, blue: 0x80 / 255.0, alpha: 1)
        }
    }
}
