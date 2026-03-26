import Foundation

struct PromptTemplate: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var content: String
    var category: TemplateCategory
    var usageCount: Int
    var createdAt: Date
    var lastUsedAt: Date?

    init(
        id: UUID = UUID(),
        name: String,
        content: String,
        category: TemplateCategory = .general,
        usageCount: Int = 0,
        createdAt: Date = Date(),
        lastUsedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.content = content
        self.category = category
        self.usageCount = usageCount
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
    }
}

enum TemplateCategory: String, Codable, CaseIterable, Identifiable {
    case general = "General"
    case debug = "Debug"
    case refactor = "Refactor"
    case review = "Review"
    case test = "Test"
    case custom = "Custom"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general: "text.bubble"
        case .debug: "ladybug"
        case .refactor: "arrow.triangle.2.circlepath"
        case .review: "eye"
        case .test: "checkmark.shield"
        case .custom: "star"
        }
    }
}
