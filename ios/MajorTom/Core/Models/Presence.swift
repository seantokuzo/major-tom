import Foundation

struct UserPresence: Identifiable, Codable {
    let userId: String
    let email: String
    var name: String?
    var picture: String?
    let role: String
    let connectedAt: String
    var watchingSessionId: String?

    var id: String { userId }

    var displayName: String {
        name ?? email.components(separatedBy: "@").first ?? email
    }

    var userRole: UserRole? {
        UserRole(rawValue: role)
    }
}
