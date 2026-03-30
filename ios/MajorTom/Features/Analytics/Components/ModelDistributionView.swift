import SwiftUI
import Charts

struct ModelDistributionView: View {
    let models: [AnalyticsByModel]

    private var chartModels: [AnalyticsByModel] {
        models.filter { $0.cost > 0 }
    }

    private static let colors: [Color] = [
        MajorTomTheme.Colors.accent,
        .purple,
        .orange,
        .cyan,
        .green,
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: MajorTomTheme.Spacing.sm) {
            Text("Model Distribution")
                .font(MajorTomTheme.Typography.codeFontSmall)
                .foregroundStyle(MajorTomTheme.Colors.textSecondary)
                .textCase(.uppercase)

            if chartModels.isEmpty {
                emptyState
            } else {
                HStack(spacing: MajorTomTheme.Spacing.lg) {
                    // Pie chart
                    Chart(chartModels) { model in
                        SectorMark(
                            angle: .value("Cost", model.cost),
                            innerRadius: .ratio(0.5),
                            angularInset: 1
                        )
                        .foregroundStyle(by: .value("Model", shortModelName(model.model)))
                        .cornerRadius(3)
                    }
                    .chartForegroundStyleScale(domain: chartModels.map { shortModelName($0.model) },
                                                range: Self.colors.prefix(chartModels.count).map { $0 })
                    .chartLegend(.hidden)
                    .frame(width: 90, height: 90)

                    // Legend
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(chartModels.enumerated()), id: \.element.id) { index, model in
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Self.colors[index % Self.colors.count])
                                    .frame(width: 6, height: 6)
                                Text(shortModelName(model.model))
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(MajorTomTheme.Colors.textSecondary)
                                    .lineLimit(1)
                                Spacer()
                                Text(formatCost(model.cost))
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(MajorTomTheme.Colors.textPrimary)
                                    .fontWeight(.semibold)
                            }
                        }
                    }
                }
            }
        }
        .padding(MajorTomTheme.Spacing.md)
        .background(MajorTomTheme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: MajorTomTheme.Radius.small))
    }

    private var emptyState: some View {
        Text("No model data")
            .font(MajorTomTheme.Typography.codeFontSmall)
            .foregroundStyle(MajorTomTheme.Colors.textTertiary)
            .frame(height: 90)
            .frame(maxWidth: .infinity)
    }

    private func shortModelName(_ name: String) -> String {
        let parts = name.split(separator: "-")
        if parts.count >= 2 {
            return parts.suffix(2).joined(separator: "-")
        }
        return name
    }

    private func formatCost(_ cost: Double) -> String {
        if cost == 0 { return "$0.00" }
        if cost < 0.01 { return String(format: "$%.4f", cost) }
        return String(format: "$%.2f", cost)
    }
}
