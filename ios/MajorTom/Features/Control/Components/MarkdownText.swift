import SwiftUI

struct MarkdownText: View {
    let text: String

    var body: some View {
        if let attributed = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            Text(attributed)
                .font(MajorTomTheme.Typography.body)
                .foregroundStyle(MajorTomTheme.Colors.textPrimary)
                .tint(MajorTomTheme.Colors.accent)
                .textSelection(.enabled)
        } else {
            Text(text)
                .font(MajorTomTheme.Typography.body)
                .foregroundStyle(MajorTomTheme.Colors.textPrimary)
                .textSelection(.enabled)
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 12) {
        MarkdownText(text: "Hello **bold** and *italic* text")
        MarkdownText(text: "Use `inline code` for variables")
        MarkdownText(text: "Visit [Apple](https://apple.com)")
        MarkdownText(text: "- Item one\n- Item two\n- Item three")
        MarkdownText(text: "Plain text fallback")
    }
    .padding()
    .background(MajorTomTheme.Colors.background)
}
