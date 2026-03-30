import SwiftUI

struct FleetDashboardView: View {
    var viewModel: FleetViewModel
    @State private var expandedWorkers: Set<String> = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                MajorTomTheme.Colors.background
                    .ignoresSafeArea()

                if let status = viewModel.fleetStatus, !status.workers.isEmpty {
                    fleetContent(status: status)
                } else if viewModel.isLoading {
                    loadingState
                } else {
                    emptyState
                }
            }
            .navigationTitle("Fleet Command")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(MajorTomTheme.Colors.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(MajorTomTheme.Colors.accent)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    workerCountPill
                }
            }
            .task {
                viewModel.startAutoRefresh()
            }
            .onDisappear {
                viewModel.stopAutoRefresh()
            }
        }
    }

    // MARK: - Worker Count Pill

    private var workerCountPill: some View {
        HStack(spacing: 4) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 11, weight: .medium))

            Text("\(viewModel.workerCount)")
                .font(.system(.caption2, design: .default, weight: .bold))

            Circle()
                .fill(healthPillColor)
                .frame(width: 6, height: 6)
        }
        .foregroundStyle(MajorTomTheme.Colors.textPrimary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(MajorTomTheme.Colors.surfaceElevated)
        .clipShape(Capsule())
    }

    private var healthPillColor: Color {
        switch viewModel.fleetHealthColor {
        case .green: MajorTomTheme.Colors.allow
        case .yellow: MajorTomTheme.Colors.warning
        case .red: MajorTomTheme.Colors.deny
        }
    }

    // MARK: - Fleet Content

    private func fleetContent(status: FleetStatus) -> some View {
        ScrollView {
            VStack(spacing: MajorTomTheme.Spacing.lg) {
                // Aggregate stats
                aggregateStats(status: status)

                // Worker list
                workerList(workers: status.workers)
            }
            .padding(MajorTomTheme.Spacing.md)
        }
        .refreshable {
            await viewModel.requestFleetStatus()
        }
    }

    // MARK: - Aggregate Stats Cards

    private func aggregateStats(status: FleetStatus) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: MajorTomTheme.Spacing.sm) {
                StatCard(
                    title: "Workers",
                    value: "\(status.totalWorkers)",
                    icon: "server.rack",
                    accentColor: viewModel.isFleetHealthy ? MajorTomTheme.Colors.allow : MajorTomTheme.Colors.warning
                )

                StatCard(
                    title: "Sessions",
                    value: "\(status.totalSessions)",
                    icon: "terminal",
                    accentColor: MajorTomTheme.Colors.accent
                )

                StatCard(
                    title: "Cost",
                    value: viewModel.formattedTotalCost,
                    icon: "dollarsign.circle",
                    accentColor: MajorTomTheme.Colors.accent
                )

                StatCard(
                    title: "Tokens",
                    value: "\(viewModel.formattedInputTokens) / \(viewModel.formattedOutputTokens)",
                    icon: "textformat.size",
                    accentColor: MajorTomTheme.Colors.textSecondary
                )
            }
            .padding(.horizontal, MajorTomTheme.Spacing.xs)
        }
    }

    // MARK: - Worker List

    private func workerList(workers: [FleetWorker]) -> some View {
        VStack(alignment: .leading, spacing: MajorTomTheme.Spacing.sm) {
            Text("Workers")
                .font(MajorTomTheme.Typography.headline)
                .foregroundStyle(MajorTomTheme.Colors.textSecondary)
                .padding(.horizontal, MajorTomTheme.Spacing.xs)

            ForEach(workers) { worker in
                FleetWorkerCard(
                    worker: worker,
                    isExpanded: expandedWorkers.contains(worker.workerId),
                    onToggle: {
                        withAnimation(.spring(duration: 0.3)) {
                            if expandedWorkers.contains(worker.workerId) {
                                expandedWorkers.remove(worker.workerId)
                            } else {
                                expandedWorkers.insert(worker.workerId)
                            }
                        }
                        HapticService.buttonTap()
                    },
                    onSessionTap: { sessionId in
                        Task {
                            await viewModel.switchToSession(sessionId: sessionId)
                            dismiss()
                        }
                    }
                )
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: MajorTomTheme.Spacing.lg) {
            Spacer()

            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 48))
                .foregroundStyle(MajorTomTheme.Colors.textTertiary)

            Text("No Active Workers")
                .font(MajorTomTheme.Typography.title)
                .foregroundStyle(MajorTomTheme.Colors.textPrimary)

            Text("Start a session to deploy a worker")
                .font(MajorTomTheme.Typography.body)
                .foregroundStyle(MajorTomTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Loading State

    private var loadingState: some View {
        VStack(spacing: MajorTomTheme.Spacing.lg) {
            Spacer()

            ProgressView()
                .tint(MajorTomTheme.Colors.accent)

            Text("Loading fleet status...")
                .font(MajorTomTheme.Typography.body)
                .foregroundStyle(MajorTomTheme.Colors.textSecondary)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Stat Card

private struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let accentColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: MajorTomTheme.Spacing.sm) {
            HStack(spacing: MajorTomTheme.Spacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(accentColor)

                Text(title)
                    .font(MajorTomTheme.Typography.caption)
                    .foregroundStyle(MajorTomTheme.Colors.textSecondary)
            }

            Text(value)
                .font(.system(.title3, design: .default, weight: .bold))
                .foregroundStyle(MajorTomTheme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(minWidth: 100, alignment: .leading)
        .padding(MajorTomTheme.Spacing.md)
        .background(MajorTomTheme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: MajorTomTheme.Radius.small))
    }
}

#Preview {
    FleetDashboardView(viewModel: FleetViewModel(relay: RelayService(), storage: SessionStorageService()))
        .preferredColorScheme(.dark)
}
