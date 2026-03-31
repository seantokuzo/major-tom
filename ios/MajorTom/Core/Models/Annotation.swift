import Foundation

struct SessionAnnotation: Identifiable, Codable {
    let id: String
    let userId: String
    let userName: String
    var turnIndex: Int?
    let text: String
    let mentions: [String]
    let createdAt: String

    var createdDate: Date? {
        ISO8601DateFormatter().date(from: createdAt)
    }
}
