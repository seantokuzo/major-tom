import SwiftUI

// MARK: - Watch Content View (Root Navigation)

struct ContentView: View {
    let viewModel: WatchViewModel

    var body: some View {
        NavigationStack {
            TabView {
                // Tab 1: Status Glance
                StatusGlanceView(viewModel: viewModel)

                // Tab 2: Session List
                WatchSessionListView(viewModel: viewModel)

                // Tab 3: Approvals (if any)
                if viewModel.hasPendingApprovals {
                    WatchApprovalView(
                        viewModel: ApprovalViewModel(connectivity: viewModel.connectivity)
                    )
                }
            }
            .tabViewStyle(.verticalPage)
        }
    }
}
