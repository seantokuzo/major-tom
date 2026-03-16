import SwiftUI

struct ApprovalView: View {
    let approvals: [ApprovalRequest]
    let onDecision: (String, ApprovalDecision) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: MajorTomTheme.Spacing.md) {
                    ForEach(approvals) { request in
                        ApprovalCard(request: request) { decision in
                            onDecision(request.id, decision)
                        }
                    }
                }
                .padding(MajorTomTheme.Spacing.lg)
            }
            .background(MajorTomTheme.Colors.background)
            .navigationTitle("Pending Approvals")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    ApprovalView(
        approvals: [
            ApprovalRequest(
                from: ApprovalRequestEvent(
                    type: "approval.request",
                    requestId: "1",
                    tool: "Bash",
                    description: "npm install",
                    details: nil
                )
            ),
            ApprovalRequest(
                from: ApprovalRequestEvent(
                    type: "approval.request",
                    requestId: "2",
                    tool: "Edit",
                    description: "Editing src/server.ts",
                    details: nil
                )
            ),
        ],
        onDecision: { _, _ in }
    )
}
