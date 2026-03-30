import SwiftUI
import Charts

struct TokenBreakdownView: View {
    let timeSeries: [AnalyticsTimeSeriesEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: MajorTomTheme.Spacing.sm) {
            Text("Token Usage")
                .font(MajorTomTheme.Typography.codeFontSmall)
                .foregroundStyle(MajorTomTheme.Colors.textSecondary)
                .textCase(.uppercase)

            // Legend
            HStack(spacing: MajorTomTheme.Spacing.md) {
                legendItem(color: MajorTomTheme.Colors.accent, label: "Input")
                legendItem(color: .purple, label: "Output")
                legendItem(color: MajorTomTheme.Colors.textTertiary, label: "Cache")
            }

            if timeSeries.isEmpty {
                emptyState
            } else {
                Chart {
                    ForEach(timeSeries) { entry in
                        BarMark(
                            x: .value("Period", entry.period),
                            y: .value("Tokens", entry.inputTokens)
                        )
                        .foregroundStyle(MajorTomTheme.Colors.accent)

                        BarMark(
                            x: .value("Period", entry.period),
                            y: .value("Tokens", entry.outputTokens)
                        )
                        .foregroundStyle(.purple)

                        BarMark(
                            x: .value("Period", entry.period),
                            y: .value("Tokens", entry.cacheTokens)
                        )
                        .foregroundStyle(MajorTomTheme.Colors.textTertiary)
                    }
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
                            if let tokens = value.as(Int.self) {
                                Text(formatTokens(tokens))
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
        Text("No token data")
            .font(MajorTomTheme.Typography.codeFontSmall)
            .foregroundStyle(MajorTomTheme.Colors.textTertiary)
            .frame(height: 140)
            .frame(maxWidth: .infinity)
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(MajorTomTheme.Colors.textTertiary)
        }
    }

    private func formatTokens(_ n: Int) -> String {
        if n >= 1_000_000 { return "\(n / 1_000_000)M" }
        if n >= 1_000 { return "\(n / 1_000)K" }
        return "\(n)"
    }
}
