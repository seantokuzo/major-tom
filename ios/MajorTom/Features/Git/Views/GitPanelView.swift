import SwiftUI

struct GitPanelView: View {
    let relay: RelayService

    enum Tab: String, CaseIterable {
        case status = "Status"
        case log = "Log"
        case branches = "Branches"
    }

    @State private var selectedTab: Tab = .status

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Tab picker
                Picker("", selection: $selectedTab) {
                    ForEach(Tab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, MajorTomTheme.Spacing.lg)
                .padding(.top, MajorTomTheme.Spacing.sm)

                // Tab content
                switch selectedTab {
                case .status:
                    GitStatusView(relay: relay)
                case .log:
                    GitLogView(relay: relay)
                case .branches:
                    GitBranchesView(relay: relay)
                }
            }
            .background(MajorTomTheme.Colors.background)
            .navigationTitle("Git")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !relay.gitBranch.isEmpty {
                        Text(relay.gitBranch)
                            .font(MajorTomTheme.Typography.codeFontSmall)
                            .foregroundStyle(MajorTomTheme.Colors.accent)
                            .padding(.horizontal, MajorTomTheme.Spacing.sm)
                            .padding(.vertical, 2)
                            .background(MajorTomTheme.Colors.accentSubtle, in: Capsule())
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task {
                            try? await relay.requestGitStatus()
                            try? await relay.requestGitLog()
                            try? await relay.requestGitBranches()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .foregroundStyle(MajorTomTheme.Colors.accent)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
        .presentationBackground(MajorTomTheme.Colors.background)
        .task {
            try? await relay.requestGitStatus()
            try? await relay.requestGitLog()
            try? await relay.requestGitBranches()
        }
    }
}
