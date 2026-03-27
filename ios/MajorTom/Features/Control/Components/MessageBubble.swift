import SwiftUI

struct MessageBubble: View {
    let message: ChatMessage
    @State private var relativeTime = ""

    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 60) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: MajorTomTheme.Spacing.xs) {
                // Content — markdown + code blocks for assistant, plain for user
                contentView

                // Relative timestamp
                Text(relativeTime)
                    .font(.caption2)
                    .foregroundStyle(MajorTomTheme.Colors.textTertiary)
            }
            .padding(MajorTomTheme.Spacing.md)
            .background(bubbleColor)
            .clipShape(RoundedRectangle(cornerRadius: MajorTomTheme.Radius.medium))

            if message.role != .user { Spacer(minLength: 60) }
        }
        .onAppear { updateRelativeTime() }
        .onReceive(timer) { _ in updateRelativeTime() }
    }

    // MARK: - Content Router

    @ViewBuilder
    private var contentView: some View {
        switch message.role {
        case .assistant:
            assistantContent
        case .user:
            Text(message.content)
                .font(MajorTomTheme.Typography.body)
                .foregroundStyle(MajorTomTheme.Colors.textPrimary)
                .textSelection(.enabled)
        case .system:
            Text(message.content)
                .font(MajorTomTheme.Typography.body)
                .foregroundStyle(MajorTomTheme.Colors.deny)
                .textSelection(.enabled)
        case .tool:
            // Tool messages use ToolMessageView — this shouldn't render
            Text(message.content)
                .font(MajorTomTheme.Typography.codeFontSmall)
                .foregroundStyle(MajorTomTheme.Colors.textSecondary)
                .textSelection(.enabled)
        }
    }

    // MARK: - Assistant Content (Mixed Markdown + Code Blocks)

    private var assistantContent: some View {
        let segments = ContentParser.parse(message.content)
        return VStack(alignment: .leading, spacing: MajorTomTheme.Spacing.sm) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .text(let text):
                    MarkdownText(text: text)
                case .codeBlock(let code, let language):
                    CodeBlockView(code: code, language: language)
                }
            }
        }
    }

    // MARK: - Styling

    private var bubbleColor: Color {
        switch message.role {
        case .user: MajorTomTheme.Colors.userBubble
        case .assistant: MajorTomTheme.Colors.assistantBubble
        case .tool: MajorTomTheme.Colors.surface
        case .system: MajorTomTheme.Colors.deny.opacity(0.2)
        }
    }

    // MARK: - Relative Time

    private func updateRelativeTime() {
        relativeTime = RelativeTimeFormatter.format(message.timestamp)
    }
}

// MARK: - Content Parser

enum ContentSegment {
    case text(String)
    case codeBlock(code: String, language: String)
}

enum ContentParser {
    // Cache regex to avoid recompilation on every parse call
    private static let codeBlockRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: "```(\\w*)\\n([\\s\\S]*?)```", options: [])
    }()

    static func parse(_ content: String) -> [ContentSegment] {
        var segments: [ContentSegment] = []

        guard let regex = codeBlockRegex else {
            return [.text(content)]
        }

        let nsContent = content as NSString
        var lastEnd = 0
        let matches = regex.matches(in: content, range: NSRange(location: 0, length: nsContent.length))

        for match in matches {
            let matchStart = match.range.location

            // Text before this code block
            if matchStart > lastEnd {
                let textRange = NSRange(location: lastEnd, length: matchStart - lastEnd)
                let text = nsContent.substring(with: textRange).trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    segments.append(.text(text))
                }
            }

            // Language
            let langRange = match.range(at: 1)
            let language = langRange.location != NSNotFound ? nsContent.substring(with: langRange) : ""

            // Code content
            let codeRange = match.range(at: 2)
            let code = codeRange.location != NSNotFound ? nsContent.substring(with: codeRange).trimmingCharacters(in: .newlines) : ""

            if !code.isEmpty {
                segments.append(.codeBlock(code: code, language: language))
            }

            lastEnd = match.range.location + match.range.length
        }

        // Remaining text after last code block
        if lastEnd < nsContent.length {
            let text = nsContent.substring(from: lastEnd).trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                segments.append(.text(text))
            }
        }

        // No code blocks found — entire content is text
        if segments.isEmpty {
            return [.text(content)]
        }

        return segments
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 12) {
            MessageBubble(message: ChatMessage(role: .user, content: "Fix the login bug"))

            MessageBubble(message: ChatMessage(
                role: .assistant,
                content: """
                I found the issue. The **auth token** is expiring too early.

                ```swift
                func refreshToken() async throws {
                    let newToken = try await api.refresh()
                    KeychainService.save(newToken)
                }
                ```

                This should fix the `401` errors you're seeing.
                """
            ))

            MessageBubble(message: ChatMessage(role: .system, content: "Error: Connection lost"))
        }
        .padding()
    }
    .background(MajorTomTheme.Colors.background)
}
