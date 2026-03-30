import SwiftUI

// MARK: - Watch Session Detail View

struct WatchSessionDetailView: View {
    let session: WatchSession
    let viewModel: WatchViewModel

    private let accentColor = Color(red: 0.95, green: 0.65, blue: 0.25)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // Session name
                Text(session.name)
                    .font(.headline)
                    .foregroundStyle(.white)

                // Working directory
                Text(session.workingDir)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Divider()

                // Status
                HStack {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                    Text(session.status.rawValue.capitalized)
                        .font(.caption)
                    Spacer()
                }

                // Agents
                HStack {
                    Image(systemName: "person.2.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("\(session.agentCount) agents")
                        .font(.caption)
                    Spacer()
                }

                // Cost
                HStack {
                    Image(systemName: "dollarsign.circle")
                        .font(.caption2)
                        .foregroundStyle(accentColor)
                    Text(session.formattedCost)
                        .font(.caption)
                        .foregroundStyle(accentColor)
                    Spacer()
                }

                // Elapsed time
                if let elapsed = session.elapsedTime {
                    HStack {
                        Image(systemName: "clock")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(elapsed)
                            .font(.caption)
                        Spacer()
                    }
                }

                // Latest tool
                if let tool = viewModel.latestToolName {
                    Divider()
                    HStack {
                        Image(systemName: "wrench.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading) {
                            Text(tool)
                                .font(.caption)
                            if let status = viewModel.latestToolStatus {
                                Text(status)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                }
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("Detail")
        .containerBackground(Color(red: 0.05, green: 0.05, blue: 0.07).gradient, for: .navigation)
    }

    private var statusColor: Color {
        switch session.status {
        case .active: .green
        case .waiting: .yellow
        case .error: .red
        case .idle: .gray
        }
    }
}
