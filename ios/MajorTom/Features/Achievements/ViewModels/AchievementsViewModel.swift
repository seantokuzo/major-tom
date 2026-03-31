import Foundation

// MARK: - Achievements ViewModel

@Observable
@MainActor
final class AchievementsViewModel {
    var achievements: [Achievement] = []
    var totalCount: Int = 0
    var unlockedCount: Int = 0
    var isLoading = false
    var error: String?

    var selectedCategory: AchievementCategory?

    /// Set when an achievement is freshly unlocked — drives celebration overlay.
    var recentlyUnlocked: Achievement?

    private let auth: AuthService

    init(auth: AuthService) {
        self.auth = auth
    }

    // MARK: - Computed

    var filteredAchievements: [Achievement] {
        let source: [Achievement]
        if let category = selectedCategory {
            source = achievements.filter { $0.category == category }
        } else {
            source = achievements
        }
        // Unlocked first, then by progress descending, then alphabetical
        return source.sorted { a, b in
            if a.isUnlocked != b.isUnlocked { return a.isUnlocked }
            if !a.isUnlocked && !b.isUnlocked {
                return a.progressPercentage > b.progressPercentage
            }
            return a.name < b.name
        }
    }

    var completionPercentage: Double {
        guard totalCount > 0 else { return 0 }
        return Double(unlockedCount) / Double(totalCount)
    }

    // MARK: - Fetch

    func fetchAchievements() async {
        isLoading = true
        error = nil

        let scheme = auth.serverURL.contains("://") ? "" : "http://"
        let baseURL = "\(scheme)\(auth.serverURL)"
        let urlString = "\(baseURL)/api/achievements"

        guard let url = URL(string: urlString) else {
            error = "Invalid URL"
            isLoading = false
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if let cookie = auth.sessionCookie {
            request.setValue("mt-session=\(cookie)", forHTTPHeaderField: "Cookie")
        }

        do {
            let (responseData, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                error = "Invalid response"
                isLoading = false
                return
            }

            if httpResponse.statusCode == 200 {
                let decoded = try JSONDecoder().decode(AchievementListResponse.self, from: responseData)
                achievements = decoded.achievements
                totalCount = decoded.totalCount
                unlockedCount = decoded.unlockedCount
            } else if httpResponse.statusCode == 401 {
                error = "Authentication required"
            } else {
                error = "HTTP \(httpResponse.statusCode)"
            }
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Category Filter

    func selectCategory(_ category: AchievementCategory?) {
        selectedCategory = category
        HapticService.selection()
    }

    // MARK: - WebSocket Event Handlers

    /// Called when an `achievement.unlocked` event arrives via RelayService.
    func handleAchievementUnlocked(_ event: AchievementUnlockedEvent) {
        // Update in-memory list
        if let index = achievements.firstIndex(where: { $0.id == event.achievementId }) {
            let existing = achievements[index]
            // Only celebrate if transitioning from locked to unlocked
            guard !existing.isUnlocked else { return }
            achievements[index] = Achievement(
                id: existing.id,
                name: event.name,
                description: event.description,
                category: AchievementCategory(rawValue: event.category) ?? existing.category,
                icon: event.icon,
                unlocked: true,
                unlockedAt: event.unlockedAt,
                progress: existing.target,
                target: existing.target,
                percentage: 100,
                secret: existing.secret
            )
            recentlyUnlocked = achievements[index]
        } else {
            // New achievement not yet in our list — add it
            let category = AchievementCategory(rawValue: event.category) ?? .meta
            let newAchievement = Achievement(
                id: event.achievementId,
                name: event.name,
                description: event.description,
                category: category,
                icon: event.icon,
                unlocked: true,
                unlockedAt: event.unlockedAt,
                progress: nil,
                target: nil,
                percentage: 100,
                secret: false
            )
            achievements.append(newAchievement)
            totalCount = achievements.count
            recentlyUnlocked = newAchievement
        }

        // Recompute counts from actual data to avoid drift
        unlockedCount = achievements.filter(\.isUnlocked).count

        // Haptic celebration
        HapticService.celebrate()
    }

    /// Called when an `achievement.progress` event arrives via RelayService.
    func handleAchievementProgress(_ event: AchievementProgressEvent) {
        if let index = achievements.firstIndex(where: { $0.id == event.achievementId }) {
            let existing = achievements[index]
            achievements[index] = Achievement(
                id: existing.id,
                name: event.name,
                description: existing.description,
                category: existing.category,
                icon: existing.icon,
                unlocked: existing.unlocked,
                unlockedAt: existing.unlockedAt,
                progress: event.current,
                target: event.target,
                percentage: event.percentage,
                secret: existing.secret
            )
        }
    }

    /// Dismiss the celebration overlay.
    func dismissCelebration() {
        recentlyUnlocked = nil
    }
}
