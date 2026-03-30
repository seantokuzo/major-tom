import SwiftUI
import WidgetKit
import ActivityKit

// MARK: - Lock Screen Live Activity View

/// Full-width Lock Screen Live Activity for active Claude sessions.
///
/// Layout:
/// - Header: Session name + status dot + elapsed time
/// - Middle: Cost + active agents count
/// - Bottom: Pending approvals with Approve/Deny deep-link buttons (if any)
struct MajorTomLiveActivityView: View {
    let context: ActivityViewContext<MajorTomActivityAttributes>

    var body: some View {
        VStack(spacing: 10) {
            // MARK: Header Row
            HStack {
                // Status dot
                Circle()
                    .fill(statusColor(context.state.status))
                    .frame(width: 8, height: 8)

                Text(context.state.sessionName)
                    .font(.system(.headline, design: .default, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Spacer()

                // Elapsed time
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
                // Cost
                HStack(spacing: 4) {
                    Image(systemName: "dollarsign.circle")
                        .font(.caption)
                        .foregroundStyle(Color(red: 0.95, green: 0.65, blue: 0.25))
                    Text(context.state.formattedCost)
                        .font(.system(.title3, design: .monospaced, weight: .bold))
                        .foregroundStyle(Color(red: 0.95, green: 0.65, blue: 0.25))
                }

                Spacer()

                // Active agents
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

                // Current tool
                if let tool = context.state.latestTool {
                    HStack(spacing: 4) {
                        Image(systemName: "wrench")
                            .font(.caption2)
                            .foregroundStyle(Color(red: 0.95, green: 0.65, blue: 0.25))
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
                            .foregroundStyle(Color(red: 0.95, green: 0.30, blue: 0.30))
                        Text("\(context.state.pendingApprovals) pending approval\(context.state.pendingApprovals == 1 ? "" : "s")")
                            .font(.system(.caption, design: .default, weight: .medium))
                            .foregroundStyle(Color(red: 0.95, green: 0.30, blue: 0.30))
                    }

                    Spacer()

                    // Deep-link buttons for approve/deny
                    HStack(spacing: 8) {
                        Link(destination: LiveActivityDeepLinks.approveLatest) {
                            Text("Approve")
                                .font(.system(.caption, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .background(Color(red: 0.30, green: 0.85, blue: 0.45), in: Capsule())
                        }

                        Link(destination: LiveActivityDeepLinks.denyLatest) {
                            Text("Deny")
                                .font(.system(.caption, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .background(Color(red: 0.95, green: 0.30, blue: 0.30), in: Capsule())
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

    // MARK: - Helpers

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "active": return Color(red: 0.30, green: 0.85, blue: 0.45)
        case "waiting": return Color(red: 0.95, green: 0.80, blue: 0.20)
        case "error": return Color(red: 0.95, green: 0.30, blue: 0.30)
        default: return Color(white: 0.40)
        }
    }
}
