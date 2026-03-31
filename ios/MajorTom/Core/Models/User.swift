import Foundation

enum UserRole: String, Codable, CaseIterable {
    case admin
    case `operator`
    case viewer

    var displayName: String {
        switch self {
        case .admin: return "Admin"
        case .operator: return "Operator"
        case .viewer: return "Viewer"
        }
    }
}

struct TeamUser: Identifiable, Codable {
    let id: String
    let email: String
    var name: String?
    var picture: String?
    let role: UserRole
    var isOnline: Bool
    var lastLoginAt: String?
}
