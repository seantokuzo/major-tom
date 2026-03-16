import SwiftUI

struct ApprovalCard: View {
    let request: ApprovalRequest
    let onDecision: (ApprovalDecision) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: MajorTomTheme.Spacing.md) {
            // Tool name header
            HStack {
                Image(systemName: "exclamationmark.shield")
                    .foregroundStyle(MajorTomTheme.Colors.accent)
                Text(request.tool)
                    .font(MajorTomTheme.Typography.headline)
                    .foregroundStyle(MajorTomTheme.Colors.textPrimary)
                Spacer()
            }

            // Description
            Text(request.description)
                .font(MajorTomTheme.Typography.codeFontSmall)
                .foregroundStyle(MajorTomTheme.Colors.textSecondary)
                .lineLimit(5)

            // Action buttons
            HStack(spacing: MajorTomTheme.Spacing.md) {
                ApprovalButton(title: "Allow", color: MajorTomTheme.Colors.allow) {
                    onDecision(.allow)
                }

                ApprovalButton(title: "Skip", color: MajorTomTheme.Colors.skip) {
                    onDecision(.skip)
                }

                ApprovalButton(title: "Deny", color: MajorTomTheme.Colors.deny) {
                    onDecision(.deny)
                }
            }
        }
        .padding(MajorTomTheme.Spacing.lg)
        .background(MajorTomTheme.Colors.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: MajorTomTheme.Radius.medium))
        .overlay(
            RoundedRectangle(cornerRadius: MajorTomTheme.Radius.medium)
                .stroke(MajorTomTheme.Colors.accent.opacity(0.3), lineWidth: 1)
        )
    }
}

struct ApprovalButton: View {
    let title: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(MajorTomTheme.Typography.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, MajorTomTheme.Spacing.sm)
                .background(color)
                .clipShape(RoundedRectangle(cornerRadius: MajorTomTheme.Radius.small))
        }
    }
}

#Preview {
    ApprovalCard(
        request: ApprovalRequest(
            from: ApprovalRequestEvent(
                type: "approval.request",
                requestId: "123",
                tool: "Bash",
                description: "rm -rf node_modules && npm install",
                details: nil
            )
        ),
        onDecision: { _ in }
    )
    .padding()
    .background(MajorTomTheme.Colors.background)
}
