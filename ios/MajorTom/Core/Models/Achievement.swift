import Foundation

// MARK: - Achievement Category

enum AchievementCategory: String, Codable, CaseIterable, Identifiable {
    case sessions
    case approvals
    case cost
    case agents
    case tools
    case fleet
    case meta

    var id: String { rawValue }

    var label: String {
        switch self {
        case .sessions: "Sessions"
        case .approvals: "Approvals"
        case .cost: "Cost"
        case .agents: "Agents"
        case .tools: "Tools"
        case .fleet: "Fleet"
        case .meta: "Meta"
        }
    }

    var icon: String {
        switch self {
        case .sessions: "play.circle"
        case .approvals: "checkmark.shield"
        case .cost: "dollarsign.circle"
        case .agents: "person.3"
        case .tools: "wrench.and.screwdriver"
        case .fleet: "server.rack"
        case .meta: "trophy"
        }
    }
}

// MARK: - Achievement

struct Achievement: Codable, Identifiable {
    let id: String
    let name: String
    let description: String
    let category: AchievementCategory
    let icon: String
    let unlocked: Bool
    let unlockedAt: String?
    let progress: Int?
    let target: Int?
    let percentage: Double?
    let secret: Bool

    var isUnlocked: Bool { unlocked }

    var progressPercentage: Double {
        if unlocked { return 1.0 }
        if let percentage { return min(max(percentage / 100.0, 0), 1.0) }
        guard let progress, let target, target > 0 else { return 0 }
        return min(Double(progress) / Double(target), 1.0)
    }

    var hasProgress: Bool {
        target != nil && (target ?? 0) > 1
    }

    var unlockedDate: Date? {
        guard let unlockedAt else { return nil }
        return ISO8601DateFormatter().date(from: unlockedAt)
    }

    var formattedUnlockDate: String? {
        guard let date = unlockedDate else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    var progressText: String? {
        guard let progress, let target, target > 1 else { return nil }
        return "\(progress) / \(target)"
    }
}

// MARK: - Achievement List Response

struct AchievementListResponse: Codable {
    let achievements: [Achievement]
    let totalCount: Int
    let unlockedCount: Int
}

// MARK: - Achievement WebSocket Events

struct AchievementUnlockedEvent: Codable {
    let type: String
    let achievementId: String
    let name: String
    let description: String
    let category: String
    let icon: String
    let unlockedAt: String
}

struct AchievementProgressEvent: Codable {
    let type: String
    let achievementId: String
    let name: String
    let current: Int
    let target: Int
    let percentage: Double
}
