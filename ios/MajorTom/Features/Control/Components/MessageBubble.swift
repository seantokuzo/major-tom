import SwiftUI

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 60) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: MajorTomTheme.Spacing.xs) {
                Text(message.content)
                    .font(message.role == .tool ? MajorTomTheme.Typography.codeFontSmall : MajorTomTheme.Typography.body)
                    .foregroundStyle(textColor)
                    .textSelection(.enabled)

                Text(message.timestamp, style: .time)
                    .font(MajorTomTheme.Typography.caption)
                    .foregroundStyle(MajorTomTheme.Colors.textTertiary)
            }
            .padding(MajorTomTheme.Spacing.md)
            .background(bubbleColor)
            .clipShape(RoundedRectangle(cornerRadius: MajorTomTheme.Radius.medium))

            if message.role != .user { Spacer(minLength: 60) }
        }
    }

    private var bubbleColor: Color {
        switch message.role {
        case .user: MajorTomTheme.Colors.userBubble
        case .assistant: MajorTomTheme.Colors.assistantBubble
        case .tool: MajorTomTheme.Colors.surface
        case .system: MajorTomTheme.Colors.deny.opacity(0.2)
        }
    }

    private var textColor: Color {
        switch message.role {
        case .tool: MajorTomTheme.Colors.textSecondary
        case .system: MajorTomTheme.Colors.deny
        default: MajorTomTheme.Colors.textPrimary
        }
    }
}

#Preview {
    VStack(spacing: 12) {
        MessageBubble(message: ChatMessage(role: .user, content: "Fix the login bug"))
        MessageBubble(message: ChatMessage(role: .assistant, content: "I'll look at the auth module..."))
        MessageBubble(message: ChatMessage(role: .tool, content: "Read src/auth.ts"))
        MessageBubble(message: ChatMessage(role: .system, content: "Error: Connection lost"))
    }
    .padding()
    .background(MajorTomTheme.Colors.background)
}
