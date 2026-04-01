import SwiftUI

struct GitHubPanelView: View {
    let relay: RelayService

    enum Tab: String, CaseIterable {
        case pullRequests = "Pull Requests"
        case issues = "Issues"
    }

    @State private var selectedTab: Tab = .pullRequests

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $selectedTab) {
                    ForEach(Tab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, MajorTomTheme.Spacing.lg)
                .padding(.top, MajorTomTheme.Spacing.sm)

                if let error = relay.githubError {
                    HStack(spacing: MajorTomTheme.Spacing.sm) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(MajorTomTheme.Colors.deny)
                        Text(error)
                            .font(MajorTomTheme.Typography.caption)
                            .foregroundStyle(MajorTomTheme.Colors.deny)
                    }
                    .padding(MajorTomTheme.Spacing.md)
                }

                switch selectedTab {
                case .pullRequests:
                    GitHubPullRequestsView(relay: relay)
                case .issues:
                    GitHubIssuesView(relay: relay)
                }
            }
            .background(MajorTomTheme.Colors.background)
            .navigationTitle("GitHub")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task {
                            try? await relay.requestGitHubPullRequests()
                            try? await relay.requestGitHubIssues()
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
            try? await relay.requestGitHubPullRequests()
            try? await relay.requestGitHubIssues()
        }
    }
}
