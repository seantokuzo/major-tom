import SwiftUI

struct SessionCostRankingView: View {
    let sessions: [AnalyticsBySession]

    var body: some View {
        VStack(alignment: .leading, spacing: MajorTomTheme.Spacing.sm) {
            Text("Session Costs")
                .font(MajorTomTheme.Typography.codeFontSmall)
                .foregroundStyle(MajorTomTheme.Colors.textSecondary)
                .textCase(.uppercase)

            if sessions.isEmpty {
                Text("No session data")
                    .font(MajorTomTheme.Typography.codeFontSmall)
                    .foregroundStyle(MajorTomTheme.Colors.textTertiary)
                    .frame(maxWidth: .infinity)
            } else {
                ForEach(sessions.prefix(10)) { session in
                    HStack(spacing: MajorTomTheme.Spacing.sm) {
                        Text(dirName(session.workingDir))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(MajorTomTheme.Colors.textPrimary)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Spacer()

                        Text(formatCost(session.totalCost))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(MajorTomTheme.Colors.accent)
                            .fontWeight(.semibold)

                        Text(formatTokens(session.totalTokens))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(MajorTomTheme.Colors.textTertiary)
                            .frame(width: 40, alignment: .trailing)

                        Text("\(session.turnCount)t")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(MajorTomTheme.Colors.textTertiary)
                            .frame(width: 25, alignment: .trailing)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(MajorTomTheme.Spacing.md)
        .background(MajorTomTheme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: MajorTomTheme.Radius.small))
    }

    private func dirName(_ path: String) -> String {
        path.split(separator: "/").last.map(String.init) ?? path.prefix(8).description
    }

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
