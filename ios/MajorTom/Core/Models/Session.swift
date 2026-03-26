import Foundation

struct RelaySession: Identifiable, Codable {
    let id: String
    let adapter: AdapterType
    let startedAt: String
    var tokenUsage: TokenUsage?
    var workingDir: String?

    var startDate: Date? {
        ISO8601DateFormatter().date(from: startedAt)
    }
}
