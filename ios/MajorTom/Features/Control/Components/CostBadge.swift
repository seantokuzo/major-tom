import SwiftUI

struct CostBadge: View {
    let costUsd: Double
    let turnCount: Int
    let inputTokens: Int
    let outputTokens: Int
    @State private var isExpanded = false

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
            HapticService.buttonTap()
        } label: {
            if isExpanded {
                expandedView
            } else {
                collapsedView
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Collapsed

    private var collapsedView: some View {
        HStack(spacing: MajorTomTheme.Spacing.xs) {
            Image(systemName: "dollarsign.circle")
                .font(.caption2)
                .foregroundStyle(MajorTomTheme.Colors.textTertiary)
            Text(formattedCost)
                .font(MajorTomTheme.Typography.codeFontSmall)
                .foregroundStyle(MajorTomTheme.Colors.textSecondary)
        }
        .padding(.horizontal, MajorTomTheme.Spacing.sm)
        .padding(.vertical, MajorTomTheme.Spacing.xs)
        .background(MajorTomTheme.Colors.surface.opacity(0.8))
        .clipShape(Capsule())
    }

    // MARK: - Expanded

    private var expandedView: some View {
        VStack(alignment: .leading, spacing: MajorTomTheme.Spacing.xs) {
            statRow(label: "Cost", value: formattedCost)
            statRow(label: "Turns", value: "\(turnCount)")
            statRow(label: "Input", value: formatTokens(inputTokens))
            statRow(label: "Output", value: formatTokens(outputTokens))
        }
        .padding(MajorTomTheme.Spacing.sm)
        .background(MajorTomTheme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: MajorTomTheme.Radius.small))
    }

    private func statRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(MajorTomTheme.Typography.codeFontSmall)
                .foregroundStyle(MajorTomTheme.Colors.textTertiary)
            Spacer()
            Text(value)
                .font(MajorTomTheme.Typography.codeFontSmall)
                .foregroundStyle(MajorTomTheme.Colors.textSecondary)
        }
    }

    // MARK: - Formatting

    private var formattedCost: String {
        if costUsd < 0.01 && costUsd > 0 {
            return String(format: "$%.4f", costUsd)
        } else {
            return String(format: "$%.2f", costUsd)
        }
    }

    private func formatTokens(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        } else {
            return "\(count)"
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        CostBadge(costUsd: 0.0042, turnCount: 3, inputTokens: 1234, outputTokens: 567)
        CostBadge(costUsd: 1.23, turnCount: 15, inputTokens: 45_200, outputTokens: 12_800)
        CostBadge(costUsd: 0, turnCount: 0, inputTokens: 0, outputTokens: 0)
    }
    .padding()
    .background(MajorTomTheme.Colors.background)
}
