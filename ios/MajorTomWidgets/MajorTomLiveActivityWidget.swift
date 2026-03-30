import SwiftUI
import WidgetKit
import ActivityKit

// MARK: - Live Activity Widget

/// ActivityConfiguration that provides the Lock Screen and Dynamic Island
/// presentations for Major Tom Live Activities.
struct MajorTomLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MajorTomActivityAttributes.self) { context in
            // Lock Screen / banner presentation
            MajorTomLockScreenView(context: context)
        } dynamicIsland: { context in
            // Dynamic Island presentations
            MajorTomDynamicIslandContent.dynamicIsland(for: context)
        }
    }
}

// MARK: - Lock Screen View (Widget Extension)

/// Full-width Lock Screen Live Activity view.
///
/// Layout:
/// - Header row: Session name + status dot + elapsed time
/// - Middle row: Cost + active agents count
/// - Bottom row: Pending approvals with Approve/Deny deep-link buttons
private struct MajorTomLockScreenView: View {
    let context: ActivityViewContext<MajorTomActivityAttributes>

    var body: some View {
        VStack(spacing: 10) {
            // MARK: Header Row
            HStack {
                Circle()
                    .fill(statusColor(context.state.status))
                    .frame(width: 8, height: 8)

                Text(context.state.sessionName)
                    .font(.system(.headline, design: .default, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(context.state.elapsedFormatted)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            // MARK: Middle Row
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "dollarsign.circle")
                        .font(.caption)
                        .foregroundStyle(accentColor)
                    Text(context.state.formattedCost)
                        .font(.system(.title3, design: .monospaced, weight: .bold))
                        .foregroundStyle(accentColor)
                }

                Spacer()

                if context.state.activeAgents > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "person.2")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(context.state.agentSummary)
                            .font(.system(.caption, design: .default))
                            .foregroundStyle(.secondary)
                    }
                }

                if let tool = context.state.latestTool {
                    HStack(spacing: 4) {
                        Image(systemName: "wrench")
                            .font(.caption2)
                            .foregroundStyle(accentColor)
                        Text(tool)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                }
            }

            // MARK: Bottom Row — Pending Approvals
            if context.state.pendingApprovals > 0 {
                Divider()
                    .background(Color.white.opacity(0.2))

                HStack {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.shield")
                            .font(.caption)
                            .foregroundStyle(denyColor)
                        Text("\(context.state.pendingApprovals) pending approval\(context.state.pendingApprovals == 1 ? "" : "s")")
                            .font(.system(.caption, design: .default, weight: .medium))
                            .foregroundStyle(denyColor)
                    }

                    Spacer()

                    HStack(spacing: 8) {
                        Link(destination: URL(string: "majortom://approve/latest")!) {
                            Text("Approve")
                                .font(.system(.caption, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .background(allowColor, in: Capsule())
                        }

                        Link(destination: URL(string: "majortom://deny/latest")!) {
                            Text("Deny")
                                .font(.system(.caption, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .background(denyColor, in: Capsule())
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.08, blue: 0.10),
                    Color(red: 0.05, green: 0.05, blue: 0.07)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    // MARK: - Colors

    private let accentColor = Color(red: 0.95, green: 0.65, blue: 0.25)
    private let allowColor = Color(red: 0.30, green: 0.85, blue: 0.45)
    private let denyColor = Color(red: 0.95, green: 0.30, blue: 0.30)

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "active": return Color(red: 0.30, green: 0.85, blue: 0.45)
        case "waiting": return Color(red: 0.95, green: 0.80, blue: 0.20)
        case "error": return Color(red: 0.95, green: 0.30, blue: 0.30)
        default: return Color(white: 0.40)
        }
    }
}

// MARK: - Dynamic Island Content (Widget Extension)

/// Dynamic Island presentations for the Major Tom Live Activity.
///
/// - **Compact leading**: Status dot + terminal icon
/// - **Compact trailing**: Session name + cost
/// - **Expanded**: Full session info with cost, agents, tool, approvals
/// - **Minimal**: Colored status dot
private enum MajorTomDynamicIslandContent {

    static func dynamicIsland(
        for context: ActivityViewContext<MajorTomActivityAttributes>
    ) -> DynamicIsland {
        DynamicIsland {
            expandedContent(for: context)
        } compactLeading: {
            HStack(spacing: 4) {
                Circle()
                    .fill(statusColor(context.state.status))
                    .frame(width: 10, height: 10)
                Image(systemName: "terminal")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(accentColor)
            }
        } compactTrailing: {
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
        } minimal: {
            ZStack {
                Circle()
                    .fill(statusColor(context.state.status))
                    .frame(width: 12, height: 12)

                if context.state.pendingApprovals > 0 {
                    Circle()
                        .fill(denyColor)
                        .frame(width: 6, height: 6)
                        .offset(x: 5, y: -5)
                }
            }
        }
        .widgetURL(URL(string: "majortom://session/\(context.attributes.sessionId)"))
    }

    // MARK: - Expanded Content

    @DynamicIslandExpandedContentBuilder
    private static func expandedContent(
        for context: ActivityViewContext<MajorTomActivityAttributes>
    ) -> DynamicIslandExpandedContent<some View> {
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

        DynamicIslandExpandedRegion(.bottom) {
            VStack(spacing: 8) {
                HStack {
                    HStack(spacing: 4) {
                        Image(systemName: "dollarsign.circle")
                            .font(.caption2)
                            .foregroundStyle(accentColor)
                        Text(context.state.formattedCost)
                            .font(.system(.callout, design: .monospaced, weight: .bold))
                            .foregroundStyle(accentColor)
                    }

                    Spacer()

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

    private static func statusColor(_ status: String) -> Color {
        switch status {
        case "active": return Color(red: 0.30, green: 0.85, blue: 0.45)
        case "waiting": return Color(red: 0.95, green: 0.80, blue: 0.20)
        case "error": return Color(red: 0.95, green: 0.30, blue: 0.30)
        default: return Color(white: 0.40)
        }
    }
}
