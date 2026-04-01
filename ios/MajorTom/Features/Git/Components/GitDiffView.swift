import SwiftUI

struct GitDiffView: View {
    let diff: String

    @State private var isExpanded = true

    private var lines: [(type: LineType, text: String)] {
        diff.components(separatedBy: "\n").map { line in
            if line.hasPrefix("+++") || line.hasPrefix("---") || line.hasPrefix("diff ") || line.hasPrefix("index ") || line.hasPrefix("@@") {
                return (.header, line)
            } else if line.hasPrefix("+") {
                return (.add, line)
            } else if line.hasPrefix("-") {
                return (.remove, line)
            }
            return (.context, line)
        }
    }

    enum LineType {
        case add, remove, context, header
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack {
                    Text("Diff (\(lines.count) lines)")
                        .font(MajorTomTheme.Typography.caption)
                        .foregroundStyle(MajorTomTheme.Colors.textSecondary)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(MajorTomTheme.Colors.textSecondary)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(lines.prefix(200).enumerated()), id: \.offset) { _, line in
                            Text(line.text)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(lineColor(line.type))
                                .padding(.horizontal, MajorTomTheme.Spacing.xs)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(lineBackground(line.type))
                        }
                        if lines.count > 200 {
                            Text("... \(lines.count - 200) more lines")
                                .font(MajorTomTheme.Typography.caption)
                                .foregroundStyle(MajorTomTheme.Colors.textSecondary)
                                .padding(MajorTomTheme.Spacing.xs)
                        }
                    }
                }
                .frame(maxHeight: 300)
                .background(MajorTomTheme.Colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: MajorTomTheme.Radius.small))
            }
        }
    }

    private func lineColor(_ type: LineType) -> Color {
        switch type {
        case .add: return MajorTomTheme.Colors.allow
        case .remove: return MajorTomTheme.Colors.deny
        case .header: return MajorTomTheme.Colors.accent
        case .context: return MajorTomTheme.Colors.textSecondary
        }
    }

    private func lineBackground(_ type: LineType) -> Color {
        switch type {
        case .add: return MajorTomTheme.Colors.allow.opacity(0.08)
        case .remove: return MajorTomTheme.Colors.deny.opacity(0.08)
        default: return .clear
        }
    }
}
