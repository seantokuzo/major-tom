import SwiftUI
import WidgetKit
import ActivityKit

// MARK: - Dynamic Island Configuration

/// Provides the Dynamic Island presentations for the Major Tom Live Activity.
///
/// - **Compact leading**: Claude icon or colored status dot
/// - **Compact trailing**: Session name (truncated) + cost "$X.XX"
/// - **Expanded**: Full session status with cost, elapsed time, agents, approvals
/// - **Minimal**: Colored dot indicating session status (green/yellow/red)
struct MajorTomDynamicIslandView {

    // MARK: - Dynamic Island Builder

    static func dynamicIsland(
        for context: ActivityViewContext<MajorTomActivityAttributes>
    ) -> DynamicIsland {
        DynamicIsland {
            // MARK: Expanded Presentation
            expandedContent(for: context)
        } compactLeading: {
            // Status dot with session icon
            compactLeadingView(for: context)
        } compactTrailing: {
            // Session name + cost
            compactTrailingView(for: context)
        } minimal: {
            // Just a colored status dot
            minimalView(for: context)
        }
        .widgetURL(URL(string: "majortom://session/\(context.attributes.sessionId)"))
    }

    // MARK: - Compact Leading

    @ViewBuilder
    private static func compactLeadingView(
        for context: ActivityViewContext<MajorTomActivityAttributes>
    ) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor(context.state.status))
                .frame(width: 10, height: 10)
            Image(systemName: "terminal")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(accentColor)
        }
    }

    // MARK: - Compact Trailing

    @ViewBuilder
    private static func compactTrailingView(
        for context: ActivityViewContext<MajorTomActivityAttributes>
    ) -> some View {
        HStack(spacing: 4) {
            Text(context.state.sessionName)
                .font(.system(.caption2, design: .default, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: 60, alignment: .trailing)

            Text(context.state.formattedCost)
                .font(.system(.caption2, design: .monospaced, weight: .bold))
                .foregroundStyle(accentColor)
        }
    }

    // MARK: - Minimal

    @ViewBuilder
    private static func minimalView(
        for context: ActivityViewContext<MajorTomActivityAttributes>
    ) -> some View {
        ZStack {
            Circle()
                .fill(statusColor(context.state.status))
                .frame(width: 12, height: 12)

            // Show badge overlay if there are pending approvals
            if context.state.pendingApprovals > 0 {
                Circle()
                    .fill(Color(red: 0.95, green: 0.30, blue: 0.30))
                    .frame(width: 6, height: 6)
                    .offset(x: 5, y: -5)
            }
        }
    }

    // MARK: - Expanded Content

    @DynamicIslandExpandedContentBuilder
    private static func expandedContent(
        for context: ActivityViewContext<MajorTomActivityAttributes>
    ) -> DynamicIslandExpandedContent<some View> {
        // Top: Session name + status dot
        DynamicIslandExpandedRegion(.leading) {
            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor(context.state.status))
                    .frame(width: 8, height: 8)
                Text(context.state.sessionName)
                    .font(.system(.subheadline, design: .default, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
        }

        DynamicIslandExpandedRegion(.trailing) {
            Text(context.state.elapsedFormatted)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
        }

        // Bottom: Cost, agents, approvals, tool
        DynamicIslandExpandedRegion(.bottom) {
            VStack(spacing: 8) {
                // Cost + agents row
                HStack {
                    // Cost
                    HStack(spacing: 4) {
                        Image(systemName: "dollarsign.circle")
                            .font(.caption2)
                            .foregroundStyle(accentColor)
                        Text(context.state.formattedCost)
                            .font(.system(.callout, design: .monospaced, weight: .bold))
                            .foregroundStyle(accentColor)
                    }

                    Spacer()

                    // Active agents or current tool
                    if context.state.activeAgents > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "person.2")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(context.state.agentSummary)
                                .font(.system(.caption, design: .default))
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let tool = context.state.latestTool {
                        HStack(spacing: 3) {
                            Image(systemName: "wrench")
                                .font(.system(size: 9))
                                .foregroundStyle(accentColor)
                            Text(tool)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                        }
                    }
                }

                // Pending approvals badge
                if context.state.pendingApprovals > 0 {
                    HStack {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.shield.fill")
                                .font(.caption2)
                                .foregroundStyle(denyColor)
                            Text("\(context.state.pendingApprovals) pending")
                                .font(.system(.caption, design: .default, weight: .medium))
                                .foregroundStyle(denyColor)
                        }

                        Spacer()

                        // Deep-link buttons
                        HStack(spacing: 6) {
                            Link(destination: URL(string: "majortom://approve/latest")!) {
                                Text("Approve")
                                    .font(.system(.caption2, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(allowColor, in: Capsule())
                            }

                            Link(destination: URL(string: "majortom://deny/latest")!) {
                                Text("Deny")
                                    .font(.system(.caption2, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(denyColor, in: Capsule())
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Colors

    private static let accentColor = Color(red: 0.95, green: 0.65, blue: 0.25)
    private static let allowColor = Color(red: 0.30, green: 0.85, blue: 0.45)
    private static let denyColor = Color(red: 0.95, green: 0.30, blue: 0.30)
    private static let warningColor = Color(red: 0.95, green: 0.80, blue: 0.20)

    private static func statusColor(_ status: String) -> Color {
        switch status {
        case "active": return allowColor
        case "waiting": return warningColor
        case "error": return denyColor
        default: return Color(white: 0.40)
        }
    }
}
