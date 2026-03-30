import SwiftUI
import Charts

struct CostChartView: View {
    let timeSeries: [AnalyticsTimeSeriesEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: MajorTomTheme.Spacing.sm) {
            Text("Cost Over Time")
                .font(MajorTomTheme.Typography.codeFontSmall)
                .foregroundStyle(MajorTomTheme.Colors.textSecondary)
                .textCase(.uppercase)

            if timeSeries.isEmpty {
                emptyState
            } else {
                Chart(timeSeries) { entry in
                    BarMark(
                        x: .value("Period", entry.period),
                        y: .value("Cost", entry.cost)
                    )
                    .foregroundStyle(MajorTomTheme.Colors.accent)
                    .cornerRadius(2)
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                        AxisValueLabel()
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundStyle(MajorTomTheme.Colors.textTertiary)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisValueLabel {
                            if let cost = value.as(Double.self) {
                                Text(formatCost(cost))
                                    .font(.system(size: 8, design: .monospaced))
                                    .foregroundStyle(MajorTomTheme.Colors.textTertiary)
                            }
                        }
                    }
                }
                .frame(height: 140)
            }
        }
        .padding(MajorTomTheme.Spacing.md)
        .background(MajorTomTheme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: MajorTomTheme.Radius.small))
    }

    private var emptyState: some View {
        Text("No cost data")
            .font(MajorTomTheme.Typography.codeFontSmall)
            .foregroundStyle(MajorTomTheme.Colors.textTertiary)
            .frame(height: 140)
            .frame(maxWidth: .infinity)
    }

    private func formatCost(_ cost: Double) -> String {
        if cost == 0 { return "$0" }
        if cost < 0.01 { return String(format: "$%.4f", cost) }
        return String(format: "$%.2f", cost)
    }
}
