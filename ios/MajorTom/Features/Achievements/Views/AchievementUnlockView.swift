import SwiftUI

// MARK: - Achievement Unlock View

/// Celebration overlay shown briefly when an achievement is unlocked.
struct AchievementUnlockView: View {
    let achievement: Achievement
    let onDismiss: () -> Void

    @State private var showContent = false
    @State private var iconScale: CGFloat = 0.3

    var body: some View {
        ZStack {
            // Dimmed backdrop
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            // Celebration card
            VStack(spacing: MajorTomTheme.Spacing.lg) {
                // Trophy burst
                Text("Achievement Unlocked!")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(MajorTomTheme.Colors.accent)
                    .textCase(.uppercase)

                // Icon with scale animation
                Text(achievement.icon)
                    .font(.system(size: 56))
                    .scaleEffect(iconScale)

                // Name
                Text(achievement.name)
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundStyle(MajorTomTheme.Colors.textPrimary)
                    .multilineTextAlignment(.center)

                // Description
                Text(achievement.description)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(MajorTomTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)

                // Category badge
                HStack(spacing: MajorTomTheme.Spacing.xs) {
                    Image(systemName: achievement.category.icon)
                        .font(.system(size: 10))
                    Text(achievement.category.label)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                }
                .foregroundStyle(MajorTomTheme.Colors.accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(MajorTomTheme.Colors.accent.opacity(0.15))
                .clipShape(Capsule())
            }
            .padding(MajorTomTheme.Spacing.xl)
            .background(MajorTomTheme.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: MajorTomTheme.Radius.large))
            .shadow(color: MajorTomTheme.Colors.accent.opacity(0.3), radius: 20)
            .padding(.horizontal, MajorTomTheme.Spacing.xxl)
            .opacity(showContent ? 1 : 0)
            .scaleEffect(showContent ? 1 : 0.8)
        }
        .task {
            // Entrance animation
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                showContent = true
                iconScale = 1.0
            }

            // Auto-dismiss after 3 seconds
            try? await Task.sleep(for: .seconds(3))
            dismiss()
        }
    }

    private func dismiss() {
        withAnimation(.easeOut(duration: 0.2)) {
            showContent = false
        }
        // Brief delay for animation to complete before calling dismiss
        Task {
            try? await Task.sleep(for: .milliseconds(200))
            onDismiss()
        }
    }
}

#Preview {
    AchievementUnlockView(
        achievement: Achievement(
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
        ),
        onDismiss: {}
    )
}
