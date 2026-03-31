import SwiftUI

// MARK: - Achievement Badge

/// Small badge for displaying achievement info in other views (e.g., profile, settings).
struct AchievementBadge: View {
    let unlockedCount: Int
    let totalCount: Int

    var body: some View {
        HStack(spacing: MajorTomTheme.Spacing.xs) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 10))
            Text("\(unlockedCount)/\(totalCount)")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
        }
        .foregroundStyle(badgeColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(badgeColor.opacity(0.15))
        .clipShape(Capsule())
    }

    private var badgeColor: Color {
        let percentage = totalCount > 0 ? Double(unlockedCount) / Double(totalCount) : 0
        if percentage >= 1.0 {
            return MajorTomTheme.Colors.accent
        } else if percentage >= 0.5 {
            return MajorTomTheme.Colors.allow
        } else {
            return MajorTomTheme.Colors.textSecondary
        }
    }
}

#Preview {
    VStack(spacing: 12) {
        AchievementBadge(unlockedCount: 0, totalCount: 30)
        AchievementBadge(unlockedCount: 15, totalCount: 30)
        AchievementBadge(unlockedCount: 30, totalCount: 30)
    }
    .padding()
    .background(MajorTomTheme.Colors.background)
}
