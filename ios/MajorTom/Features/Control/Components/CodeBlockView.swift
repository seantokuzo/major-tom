import SwiftUI
import UIKit

struct CodeBlockView: View {
    let code: String
    let language: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: language label + copy button
            header

            // Code content
            codeContent
        }
        .clipShape(RoundedRectangle(cornerRadius: MajorTomTheme.Radius.small))
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text(language.isEmpty ? "code" : language.lowercased())
                .font(MajorTomTheme.Typography.codeFontSmall)
                .foregroundStyle(MajorTomTheme.Colors.textTertiary)

            Spacer()

            Button {
                UIPasteboard.general.string = code
                HapticService.buttonTap()
                copied = true
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    copied = false
                }
            } label: {
                HStack(spacing: MajorTomTheme.Spacing.xs) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption2)
                    Text(copied ? "Copied" : "Copy")
                        .font(MajorTomTheme.Typography.codeFontSmall)
                }
                .foregroundStyle(copied ? MajorTomTheme.Colors.allow : MajorTomTheme.Colors.textTertiary)
            }
        }
        .padding(.horizontal, MajorTomTheme.Spacing.md)
        .padding(.vertical, MajorTomTheme.Spacing.sm)
        .background(Color(white: 0.08))
    }

    // MARK: - Code Content

    private var codeContent: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(highlightedCode)
                .font(MajorTomTheme.Typography.codeFont)
                .textSelection(.enabled)
                .padding(MajorTomTheme.Spacing.md)
        }
        .background(Color(white: 0.05))
    }

    // MARK: - Simple Keyword Highlighting

    private var highlightedCode: AttributedString {
        var result = AttributedString(code)
        result.foregroundColor = UIColor(MajorTomTheme.Colors.textPrimary)

        let keywords = languageKeywords
        let stringPatterns = [
            ("\"", "\""),
            ("'", "'"),
            ("`", "`"),
        ]

        // Highlight keywords
        for keyword in keywords {
            highlightPattern(
                in: &result,
                pattern: "\\b\(keyword)\\b",
                color: UIColor(MajorTomTheme.Colors.accent)
            )
        }

        // Highlight strings
        for (open, close) in stringPatterns {
            let escaped = NSRegularExpression.escapedPattern(for: open)
            let escapedClose = NSRegularExpression.escapedPattern(for: close)
            highlightPattern(
                in: &result,
                pattern: "\(escaped)[^\(escapedClose)]*\(escapedClose)",
                color: UIColor(red: 0.55, green: 0.85, blue: 0.55, alpha: 1)
            )
        }

        // Highlight comments (// and #)
        highlightPattern(
            in: &result,
            pattern: "(?://|#).*$",
            color: UIColor(MajorTomTheme.Colors.textTertiary),
            multiline: true
        )

        // Highlight numbers
        highlightPattern(
            in: &result,
            pattern: "\\b\\d+(?:\\.\\d+)?\\b",
            color: UIColor(red: 0.70, green: 0.55, blue: 0.95, alpha: 1)
        )

        return result
    }

    private func highlightPattern(
        in attributed: inout AttributedString,
        pattern: String,
        color: UIColor,
        multiline: Bool = false
    ) {
        var options: NSRegularExpression.Options = []
        if multiline { options.insert(.anchorsMatchLines) }

        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return }
        let nsString = String(attributed.characters) as NSString
        let matches = regex.matches(in: String(attributed.characters), range: NSRange(location: 0, length: nsString.length))

        for match in matches {
            guard let range = Range(match.range, in: attributed) else { continue }
            attributed[range].foregroundColor = color
        }
    }

    private var languageKeywords: [String] {
        switch language.lowercased() {
        case "swift":
            return ["func", "var", "let", "if", "else", "guard", "return", "import", "struct", "class", "enum", "protocol", "extension", "self", "Self", "nil", "true", "false", "async", "await", "throws", "throw", "try", "catch", "for", "while", "switch", "case", "default", "break", "continue", "where", "in", "private", "public", "internal", "static", "override", "final", "init", "deinit", "some", "any"]
        case "typescript", "ts", "javascript", "js":
            return ["function", "const", "let", "var", "if", "else", "return", "import", "export", "from", "class", "interface", "type", "enum", "async", "await", "throw", "try", "catch", "for", "while", "switch", "case", "default", "break", "continue", "new", "this", "super", "extends", "implements", "true", "false", "null", "undefined", "typeof", "instanceof"]
        case "python", "py":
            return ["def", "class", "if", "elif", "else", "return", "import", "from", "as", "for", "while", "with", "try", "except", "raise", "pass", "break", "continue", "and", "or", "not", "in", "is", "None", "True", "False", "self", "lambda", "yield", "async", "await"]
        case "bash", "sh", "zsh":
            return ["if", "then", "else", "elif", "fi", "for", "while", "do", "done", "case", "esac", "function", "return", "export", "local", "readonly", "echo", "exit", "cd", "ls", "grep", "sed", "awk"]
        case "go":
            return ["func", "var", "const", "if", "else", "return", "import", "package", "struct", "interface", "type", "for", "range", "switch", "case", "default", "break", "continue", "go", "defer", "chan", "select", "map", "nil", "true", "false", "make", "new"]
        case "rust":
            return ["fn", "let", "mut", "if", "else", "return", "use", "mod", "pub", "struct", "enum", "impl", "trait", "for", "while", "loop", "match", "break", "continue", "self", "Self", "true", "false", "async", "await", "move", "ref", "where", "type", "const", "static"]
        default:
            return ["function", "func", "def", "class", "var", "let", "const", "if", "else", "return", "import", "for", "while", "true", "false", "null", "nil"]
        }
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 16) {
            CodeBlockView(
                code: """
                func greet(_ name: String) -> String {
                    let message = "Hello, \\(name)!"
                    return message // greeting
                }
                """,
                language: "swift"
            )

            CodeBlockView(
                code: """
                const handler = async (req, res) => {
                    const data = await fetch("/api");
                    return data.json();
                };
                """,
                language: "typescript"
            )

            CodeBlockView(
                code: "echo 'hello world'",
                language: "bash"
            )
        }
        .padding()
    }
    .background(MajorTomTheme.Colors.background)
}
