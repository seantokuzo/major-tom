import SwiftUI

// MARK: - Achievements List View

struct AchievementsListView: View {
    @State private var viewModel: AchievementsViewModel

    init(auth: AuthService) {
        _viewModel = State(initialValue: AchievementsViewModel(auth: auth))
    }

    /// Initializer accepting an external view model (used for integration with RelayService events).
    init(viewModel: AchievementsViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ScrollView {
                    VStack(spacing: MajorTomTheme.Spacing.md) {
                        // Summary header
                        summaryHeader

                        // Category filter
                        categoryFilter

                        // Achievement list
                        if viewModel.isLoading && viewModel.achievements.isEmpty {
                            loadingState
                        } else if let error = viewModel.error, viewModel.achievements.isEmpty {
                            errorState(error)
                        } else if viewModel.filteredAchievements.isEmpty {
                            emptyState
                        } else {
                            achievementList
                        }
                    }
                    .padding(MajorTomTheme.Spacing.md)
                }
                .scrollContentBackground(.hidden)
                .background(MajorTomTheme.Colors.background)
                .navigationTitle("Achievements")
                .navigationBarTitleDisplayMode(.inline)
                .task {
                    await viewModel.fetchAchievements()
                }
                .refreshable {
                    await viewModel.fetchAchievements()
                }

                // Celebration overlay
                if let achievement = viewModel.recentlyUnlocked {
                    AchievementUnlockView(achievement: achievement) {
                        viewModel.dismissCelebration()
                    }
                }
            }
        }
    }

    // MARK: - Summary Header

    private var summaryHeader: some View {
        HStack(spacing: MajorTomTheme.Spacing.lg) {
            ProgressRing(
                progress: viewModel.completionPercentage,
                size: 54,
                lineWidth: 4
            )

            VStack(alignment: .leading, spacing: MajorTomTheme.Spacing.xs) {
                Text("\(viewModel.unlockedCount) of \(viewModel.totalCount)")
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundStyle(MajorTomTheme.Colors.textPrimary)
                Text("achievements unlocked")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(MajorTomTheme.Colors.textSecondary)
            }

            Spacer()
        }
        .padding(MajorTomTheme.Spacing.md)
        .background(MajorTomTheme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: MajorTomTheme.Radius.small))
    }

    // MARK: - Category Filter

    private var categoryFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: MajorTomTheme.Spacing.xs) {
                filterChip(label: "All", category: nil)
                ForEach(AchievementCategory.allCases) { category in
                    filterChip(label: category.label, category: category)
                }
            }
            .padding(.horizontal, MajorTomTheme.Spacing.xs)
        }
    }

    private func filterChip(label: String, category: AchievementCategory?) -> some View {
        Button {
            viewModel.selectCategory(category)
        } label: {
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .padding(.horizontal, MajorTomTheme.Spacing.md)
                .padding(.vertical, MajorTomTheme.Spacing.xs)
                .background(
                    viewModel.selectedCategory == category
                        ? MajorTomTheme.Colors.accent
                        : MajorTomTheme.Colors.surface
                )
                .foregroundStyle(
                    viewModel.selectedCategory == category
                        ? MajorTomTheme.Colors.background
                        : MajorTomTheme.Colors.textSecondary
                )
                .clipShape(Capsule())
        }
    }

    // MARK: - Achievement List

    private var achievementList: some View {
        LazyVStack(spacing: MajorTomTheme.Spacing.sm) {
            ForEach(viewModel.filteredAchievements) { achievement in
                NavigationLink(value: achievement.id) {
                    AchievementCard(achievement: achievement)
                }
                .buttonStyle(.plain)
            }
        }
        .navigationDestination(for: String.self) { achievementId in
            if let achievement = viewModel.achievements.first(where: { $0.id == achievementId }) {
                AchievementDetailView(achievement: achievement)
            }
        }
    }

    // MARK: - States

    private var loadingState: some View {
        VStack(spacing: MajorTomTheme.Spacing.md) {
            ProgressView()
                .tint(MajorTomTheme.Colors.accent)
            Text("Loading achievements...")
                .font(MajorTomTheme.Typography.codeFontSmall)
                .foregroundStyle(MajorTomTheme.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    private func errorState(_ error: String) -> some View {
        VStack(spacing: MajorTomTheme.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title2)
                .foregroundStyle(MajorTomTheme.Colors.deny)
            Text(error)
                .font(MajorTomTheme.Typography.codeFontSmall)
                .foregroundStyle(MajorTomTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    private var emptyState: some View {
        VStack(spacing: MajorTomTheme.Spacing.sm) {
            Image(systemName: "trophy")
                .font(.title2)
                .foregroundStyle(MajorTomTheme.Colors.textTertiary)
            Text("No achievements yet")
                .font(MajorTomTheme.Typography.codeFontSmall)
                .foregroundStyle(MajorTomTheme.Colors.textSecondary)
            Text("Start using Major Tom to unlock achievements")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(MajorTomTheme.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }
}

#Preview {
    AchievementsListView(auth: AuthService())
}
