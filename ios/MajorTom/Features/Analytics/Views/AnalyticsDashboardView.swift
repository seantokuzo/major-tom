import SwiftUI

struct AnalyticsDashboardView: View {
    @State private var viewModel: AnalyticsViewModel

    init(auth: AuthService) {
        _viewModel = State(initialValue: AnalyticsViewModel(auth: auth))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: MajorTomTheme.Spacing.md) {
                    // Time range picker
                    timeRangePicker

                    if viewModel.isLoading && viewModel.data == nil {
                        loadingState
                    } else if let error = viewModel.error, viewModel.data == nil {
                        errorState(error)
                    } else if let data = viewModel.data {
                        // Totals
                        totalsRow(data.totals)

                        // Charts
                        CostChartView(timeSeries: data.timeSeries)
                        TokenBreakdownView(timeSeries: data.timeSeries)
                        ModelDistributionView(models: data.byModel)
                        SessionCostRankingView(sessions: data.bySession)

                        // Top tools
                        if !data.byTool.isEmpty {
                            toolsSection(data.byTool)
                        }
                    } else {
                        emptyState
                    }
                }
                .padding(MajorTomTheme.Spacing.md)
            }
            .scrollContentBackground(.hidden)
            .background(MajorTomTheme.Colors.background)
            .navigationTitle("Analytics")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await viewModel.fetchAnalytics()
            }
            .refreshable {
                await viewModel.fetchAnalytics()
            }
        }
    }

    // MARK: - Time Range Picker

    private var timeRangePicker: some View {
        HStack(spacing: 2) {
            ForEach(AnalyticsTimeRange.allCases) { range in
                Button {
                    viewModel.setTimeRange(range)
                } label: {
                    Text(range.label)
                        .font(.system(size: 12, design: .monospaced))
                        .fontWeight(.semibold)
                        .padding(.horizontal, MajorTomTheme.Spacing.md)
                        .padding(.vertical, MajorTomTheme.Spacing.xs)
                        .background(
                            viewModel.timeRange == range
                                ? MajorTomTheme.Colors.accent
                                : MajorTomTheme.Colors.surface
                        )
                        .foregroundStyle(
                            viewModel.timeRange == range
                                ? MajorTomTheme.Colors.background
                                : MajorTomTheme.Colors.textSecondary
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
        }
        .padding(.horizontal, MajorTomTheme.Spacing.xs)
    }

    // MARK: - Totals

    private func totalsRow(_ totals: AnalyticsTotals) -> some View {
        HStack(spacing: MajorTomTheme.Spacing.lg) {
            statItem(value: formatCost(totals.cost), label: "Cost")
            statItem(value: formatTokens(totals.inputTokens + totals.outputTokens), label: "Tokens")
            statItem(value: "\(totals.turnCount)", label: "Turns")
            statItem(value: "\(totals.sessionCount)", label: "Sessions")
        }
        .padding(MajorTomTheme.Spacing.md)
        .background(MajorTomTheme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: MajorTomTheme.Radius.small))
    }

    private func statItem(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 14, design: .monospaced))
                .fontWeight(.bold)
                .foregroundStyle(MajorTomTheme.Colors.textPrimary)
            Text(label)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(MajorTomTheme.Colors.textTertiary)
                .textCase(.uppercase)
        }
    }

    // MARK: - Tools Section

    private func toolsSection(_ tools: [AnalyticsByTool]) -> some View {
        VStack(alignment: .leading, spacing: MajorTomTheme.Spacing.sm) {
            Text("Top Tools")
                .font(MajorTomTheme.Typography.codeFontSmall)
                .foregroundStyle(MajorTomTheme.Colors.textSecondary)
                .textCase(.uppercase)

            ForEach(tools.prefix(10)) { tool in
                HStack(spacing: MajorTomTheme.Spacing.sm) {
                    Text(tool.tool)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(MajorTomTheme.Colors.textPrimary)
                        .lineLimit(1)
                    Spacer()
                    Text("\(tool.count)x")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(MajorTomTheme.Colors.accent)
                        .fontWeight(.semibold)
                }
                .padding(.vertical, 2)
            }
        }
        .padding(MajorTomTheme.Spacing.md)
        .background(MajorTomTheme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: MajorTomTheme.Radius.small))
    }

    // MARK: - States

    private var loadingState: some View {
        VStack(spacing: MajorTomTheme.Spacing.md) {
            ProgressView()
                .tint(MajorTomTheme.Colors.accent)
            Text("Loading analytics...")
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
            Image(systemName: "chart.bar")
                .font(.title2)
                .foregroundStyle(MajorTomTheme.Colors.textTertiary)
            Text("No analytics data yet")
                .font(MajorTomTheme.Typography.codeFontSmall)
                .foregroundStyle(MajorTomTheme.Colors.textSecondary)
            Text("Data will appear after your first session")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(MajorTomTheme.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    // MARK: - Formatting

    private func formatCost(_ cost: Double) -> String {
        if cost == 0 { return "$0.00" }
        if cost < 0.01 { return String(format: "$%.4f", cost) }
        return String(format: "$%.2f", cost)
    }

    private func formatTokens(_ n: Int) -> String {
        if n >= 1_000_000 { return "\(n / 1_000_000)M" }
        if n >= 1_000 { return "\(n / 1_000)K" }
        return "\(n)"
    }
}

#Preview {
    AnalyticsDashboardView(auth: AuthService())
}
