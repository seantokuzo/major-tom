import SwiftUI

// MARK: - Achievement Card

/// Compact card displaying an achievement with icon, name, locked/unlocked state, and progress.
struct AchievementCard: View {
    let achievement: Achievement

    var body: some View {
        HStack(spacing: MajorTomTheme.Spacing.md) {
            // Icon
            achievementIcon

            // Info
            VStack(alignment: .leading, spacing: MajorTomTheme.Spacing.xs) {
                Text(displayName)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(achievement.isUnlocked ? MajorTomTheme.Colors.textPrimary : MajorTomTheme.Colors.textTertiary)
                    .lineLimit(1)

                Text(displayDescription)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(MajorTomTheme.Colors.textSecondary)
                    .lineLimit(2)

                if let progressText = achievement.progressText, !achievement.isUnlocked {
                    Text(progressText)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(MajorTomTheme.Colors.accent)
                }
            }

            Spacer()

            // Progress ring or checkmark
            if achievement.isUnlocked {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(MajorTomTheme.Colors.allow)
            } else if achievement.hasProgress {
                ProgressRing(
                    progress: achievement.progressPercentage,
                    size: 36,
                    lineWidth: 3,
                    showLabel: false
                )
            } else {
                Image(systemName: "lock.fill")
                    .font(.title3)
                    .foregroundStyle(MajorTomTheme.Colors.textTertiary)
            }
        }
        .padding(MajorTomTheme.Spacing.md)
        .background(achievement.isUnlocked ? MajorTomTheme.Colors.surfaceElevated : MajorTomTheme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: MajorTomTheme.Radius.small))
        .opacity(achievement.isUnlocked ? 1.0 : 0.75)
    }

    // MARK: - Sub-views

    private var achievementIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(achievement.isUnlocked ? MajorTomTheme.Colors.accent.opacity(0.2) : MajorTomTheme.Colors.surface)
                .frame(width: 40, height: 40)

            Text(achievement.isUnlocked || !achievement.secret ? achievement.icon : "?")
                .font(.title2)
        }
    }

    private var displayName: String {
        if achievement.secret && !achievement.isUnlocked {
            return "???"
        }
        return achievement.name
    }

    private var displayDescription: String {
        if achievement.secret && !achievement.isUnlocked {
            return "Secret achievement"
        }
        return achievement.description
    }
}

#Preview {
    VStack(spacing: 12) {
        AchievementCard(achievement: Achievement(
            id: "first_contact",
            name: "First Contact",
            description: "Start your first session",
            category: .sessions,
            icon: "\u{1F680}",
            unlocked: true,
            unlockedAt: "2025-03-15T10:30:00Z",
            progress: 1,
            target: 1,
            percentage: 100,
            secret: false
        ))

        AchievementCard(achievement: Achievement(
            id: "big_approver",
            name: "Big Approver",
            description: "Approve 100 tool requests",
            category: .approvals,
            icon: "\u{1F4CB}",
            unlocked: false,
            unlockedAt: nil,
            progress: 42,
            target: 100,
            percentage: 42,
            secret: false
        ))

        AchievementCard(achievement: Achievement(
            id: "completionist",
            name: "Completionist",
            description: "Unlock every achievement",
            category: .meta,
            icon: "\u{1F451}",
            unlocked: false,
            unlockedAt: nil,
            progress: nil,
            target: nil,
            percentage: nil,
            secret: true
        ))
    }
    .padding()
    .background(MajorTomTheme.Colors.background)
}
