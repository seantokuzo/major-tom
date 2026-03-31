import SwiftUI

// MARK: - Achievement Detail View

struct AchievementDetailView: View {
    let achievement: Achievement

    var body: some View {
        ScrollView {
            VStack(spacing: MajorTomTheme.Spacing.xl) {
                // Icon + Status
                headerSection

                // Progress
                if achievement.hasProgress {
                    progressSection
                }

                // Details
                detailsSection
            }
            .padding(MajorTomTheme.Spacing.lg)
        }
        .scrollContentBackground(.hidden)
        .background(MajorTomTheme.Colors.background)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: MajorTomTheme.Spacing.md) {
            // Large icon
            ZStack {
                Circle()
                    .fill(achievement.isUnlocked ? MajorTomTheme.Colors.accent.opacity(0.2) : MajorTomTheme.Colors.surface)
                    .frame(width: 80, height: 80)

                Text(displayIcon)
                    .font(.system(size: 40))
            }

            // Name
            Text(displayName)
                .font(.system(size: 20, weight: .bold, design: .monospaced))
                .foregroundStyle(MajorTomTheme.Colors.textPrimary)
                .multilineTextAlignment(.center)

            // Description
            Text(displayDescription)
                .font(.system(size: 14, design: .monospaced))
                .foregroundStyle(MajorTomTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)

            // Status badge
            statusBadge
        }
    }

    private var statusBadge: some View {
        HStack(spacing: MajorTomTheme.Spacing.xs) {
            Image(systemName: achievement.isUnlocked ? "checkmark.circle.fill" : "lock.fill")
                .font(.system(size: 10))
            Text(achievement.isUnlocked ? "Unlocked" : "Locked")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
        }
        .foregroundStyle(achievement.isUnlocked ? MajorTomTheme.Colors.allow : MajorTomTheme.Colors.textTertiary)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            (achievement.isUnlocked ? MajorTomTheme.Colors.allow : MajorTomTheme.Colors.textTertiary)
                .opacity(0.15)
        )
        .clipShape(Capsule())
    }

    // MARK: - Progress Section

    private var progressSection: some View {
        VStack(spacing: MajorTomTheme.Spacing.md) {
            ProgressRing(
                progress: achievement.progressPercentage,
                size: 100,
                lineWidth: 8
            )

            if let progressText = achievement.progressText {
                Text(progressText)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(MajorTomTheme.Colors.textSecondary)
            }
        }
        .padding(MajorTomTheme.Spacing.lg)
        .frame(maxWidth: .infinity)
        .background(MajorTomTheme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: MajorTomTheme.Radius.medium))
    }

    // MARK: - Details Section

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: MajorTomTheme.Spacing.md) {
            detailRow(label: "Category", value: achievement.category.label, icon: achievement.category.icon)

            if let date = achievement.formattedUnlockDate {
                detailRow(label: "Unlocked", value: date, icon: "calendar")
            }

            if achievement.secret {
                detailRow(label: "Type", value: "Secret", icon: "eye.slash")
            }
        }
        .padding(MajorTomTheme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MajorTomTheme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: MajorTomTheme.Radius.small))
    }

    private func detailRow(label: String, value: String, icon: String) -> some View {
        HStack(spacing: MajorTomTheme.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(MajorTomTheme.Colors.accent)
                .frame(width: 20)

            Text(label)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(MajorTomTheme.Colors.textTertiary)

            Spacer()

            Text(value)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(MajorTomTheme.Colors.textPrimary)
        }
    }

    // MARK: - Display Helpers

    private var displayIcon: String {
        if achievement.secret && !achievement.isUnlocked { return "?" }
        return achievement.icon
    }

    private var displayName: String {
        if achievement.secret && !achievement.isUnlocked { return "???" }
        return achievement.name
    }

    private var displayDescription: String {
        if achievement.secret && !achievement.isUnlocked { return "Secret achievement" }
        return achievement.description
    }
}

#Preview {
    NavigationStack {
        AchievementDetailView(achievement: Achievement(
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
    }
}
