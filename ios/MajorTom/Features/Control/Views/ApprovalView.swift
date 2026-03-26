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
                    description: "rm -rf /tmp/build && npm install",
                    details: [
                        "command": .string("rm -rf /tmp/build && npm install"),
                        "working_directory": .string("/Users/dev/project"),
                    ]
                )
            ),
            ApprovalRequest(
                from: ApprovalRequestEvent(
                    type: "approval.request",
                    requestId: "2",
                    tool: "Edit",
                    description: "Editing src/server.ts",
                    details: [
                        "file_path": .string("src/server.ts"),
                        "old_string": .string("const port = 3000;"),
                        "new_string": .string("const port = process.env.PORT || 3000;"),
                    ]
                )
            ),
            ApprovalRequest(
                from: ApprovalRequestEvent(
                    type: "approval.request",
                    requestId: "3",
                    tool: "Read",
                    description: "Reading package.json",
                    details: [
                        "path": .string("package.json")
                    ]
                )
            ),
        ],
        onDecision: { _, _ in }
    )
}
