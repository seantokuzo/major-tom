import SwiftUI

struct ContextChipView: View {
    let path: String
    var onRemove: () -> Void

    private var fileName: String {
        (path as NSString).lastPathComponent
    }

    private var fileIcon: String {
        let ext = (fileName as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "ts", "tsx": return "doc.text"
        case "js", "jsx": return "doc.text"
        case "json": return "curlybraces"
        case "md": return "doc.richtext"
        case "yml", "yaml": return "list.bullet"
        default: return "doc"
        }
    }

    var body: some View {
        HStack(spacing: MajorTomTheme.Spacing.xs) {
            Image(systemName: fileIcon)
                .font(.system(size: 10))
                .foregroundStyle(MajorTomTheme.Colors.accent)

            Text(fileName)
                .font(MajorTomTheme.Typography.caption)
                .foregroundStyle(MajorTomTheme.Colors.textPrimary)
                .lineLimit(1)

            Button {
                HapticService.buttonTap()
                onRemove()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(MajorTomTheme.Colors.textTertiary)
            }
        }
        .padding(.horizontal, MajorTomTheme.Spacing.sm)
        .padding(.vertical, MajorTomTheme.Spacing.xs)
        .background(MajorTomTheme.Colors.surface)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .strokeBorder(MajorTomTheme.Colors.accent.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Context Chips Bar

struct ContextChipsBar: View {
    let paths: [String]
    var onRemove: (String) -> Void

    var body: some View {
        if !paths.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: MajorTomTheme.Spacing.sm) {
                    Image(systemName: "at")
                        .font(.caption2)
                        .foregroundStyle(MajorTomTheme.Colors.textTertiary)

                    ForEach(paths, id: \.self) { path in
                        ContextChipView(path: path) {
                            onRemove(path)
                        }
                    }
                }
                .padding(.horizontal, MajorTomTheme.Spacing.md)
                .padding(.vertical, MajorTomTheme.Spacing.sm)
            }
            .background(MajorTomTheme.Colors.surface.opacity(0.5))
        }
    }
}

#Preview {
    VStack(spacing: MajorTomTheme.Spacing.md) {
        ContextChipView(path: "/src/App.swift") {}
        ContextChipView(path: "/relay/server.ts") {}

        ContextChipsBar(
            paths: ["/src/App.swift", "/relay/server.ts", "/package.json"],
            onRemove: { _ in }
        )
    }
    .padding()
    .background(MajorTomTheme.Colors.background)
    .preferredColorScheme(.dark)
}
