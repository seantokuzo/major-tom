import SwiftUI

// MARK: - Watch Approval View

struct WatchApprovalView: View {
    @Bindable var viewModel: ApprovalViewModel

    var body: some View {
        if let request = viewModel.currentRequest {
            ScrollView {
                VStack(spacing: 12) {
                    // Header
                    if viewModel.hasMultiple {
                        Text(viewModel.currentPosition)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    // Tool name
                    Text(request.toolName)
                        .font(.headline)
                        .foregroundStyle(.white)

                    // File or command info
                    if let detail = request.fileOrCommand {
                        Text(detail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // Danger indicator
                    dangerIndicator(request.dangerLevel)

                    Divider()

                    // Action buttons
                    HStack(spacing: 12) {
                        Button {
                            viewModel.deny()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.title3)
                                .fontWeight(.bold)
                                .frame(maxWidth: .infinity)
                        }
                        .tint(.red)

                        Button {
                            viewModel.approve()
                        } label: {
                            Image(systemName: "checkmark")
                                .font(.title3)
                                .fontWeight(.bold)
                                .frame(maxWidth: .infinity)
                        }
                        .tint(.green)
                    }
                    .buttonStyle(.borderedProminent)

                    // Next indicator
                    if viewModel.remainingCount > 0 {
                        Text("\(viewModel.remainingCount) more pending")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 4)
            }
            .navigationTitle("Approval")
            .containerBackground(borderColor(for: request.dangerLevel).opacity(0.1).gradient, for: .navigation)
        } else {
            ContentUnavailableView {
                Label("No Approvals", systemImage: "checkmark.circle")
            } description: {
                Text("All clear")
            }
        }
    }

    @ViewBuilder
    private func dangerIndicator(_ level: WatchDangerLevel) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(borderColor(for: level))
                .frame(width: 6, height: 6)
            Text(dangerLabel(level))
                .font(.caption2)
                .foregroundStyle(borderColor(for: level))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(borderColor(for: level).opacity(0.15))
        .clipShape(Capsule())
    }

    private func borderColor(for level: WatchDangerLevel) -> Color {
        switch level {
        case .safe: .green
        case .moderate: .yellow
        case .dangerous: .red
        }
    }

    private func dangerLabel(_ level: WatchDangerLevel) -> String {
        switch level {
        case .safe: "Safe"
        case .moderate: "Moderate"
        case .dangerous: "Dangerous"
        }
    }
}
