import Foundation

struct ActivityEntry: Identifiable, Codable {
    let id: String
    let userId: String
    let userName: String
    let action: String
    var sessionId: String?
    let timestamp: String

    var timestampDate: Date? {
        ISO8601DateFormatter().date(from: timestamp)
    }
}
