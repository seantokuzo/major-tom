import Foundation

struct ApprovalRequest: Identifiable {
    let id: String
    let tool: String
    let description: String
    let details: [String: AnyCodableValue]?
    let receivedAt: Date

    init(from event: ApprovalRequestEvent) {
        self.id = event.requestId
        self.tool = event.tool
        self.description = event.description
        self.details = event.details
        self.receivedAt = Date()
    }
}
