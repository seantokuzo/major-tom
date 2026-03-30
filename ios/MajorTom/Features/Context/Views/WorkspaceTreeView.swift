import SwiftUI

struct WorkspaceTreeView: View {
    let files: [FileNode]
    @Binding var selectedPaths: Set<String>

    var body: some View {
        List {
            ForEach(files) { node in
                WorkspaceTreeNodeView(
                    node: node,
                    selectedPaths: $selectedPaths,
                    depth: 0
                )
                .listRowBackground(MajorTomTheme.Colors.surface)
                .listRowSeparatorTint(MajorTomTheme.Colors.textTertiary.opacity(0.2))
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }
}

// MARK: - Tree Node

struct WorkspaceTreeNodeView: View {
    let node: FileNode
    @Binding var selectedPaths: Set<String>
    let depth: Int

    @State private var isExpanded = false

    private var isSelected: Bool {
        selectedPaths.contains(node.path)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Node row
            Button {
                HapticService.buttonTap()
                if node.isDirectory {
                    withAnimation(.spring(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } else {
                    if isSelected {
                        selectedPaths.remove(node.path)
                    } else {
                        selectedPaths.insert(node.path)
                    }
                }
            } label: {
                HStack(spacing: MajorTomTheme.Spacing.sm) {
                    if depth > 0 {
                        Spacer()
                            .frame(width: CGFloat(depth) * 20)
                    }

                    // Disclosure indicator for directories
                    if node.isDirectory {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(MajorTomTheme.Colors.textTertiary)
                            .frame(width: 12)
                    } else {
                        Spacer().frame(width: 12)
                    }

                    // Icon
                    Image(systemName: iconForNode)
                        .font(.caption)
                        .foregroundStyle(
                            node.isDirectory
                                ? MajorTomTheme.Colors.accent
                                : MajorTomTheme.Colors.textSecondary
                        )

                    // Name
                    Text(node.name)
                        .font(MajorTomTheme.Typography.body)
                        .foregroundStyle(MajorTomTheme.Colors.textPrimary)
                        .lineLimit(1)

                    Spacer()

                    // Selection
                    if !node.isDirectory {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(
                                isSelected
                                    ? MajorTomTheme.Colors.accent
                                    : MajorTomTheme.Colors.textTertiary
                            )
                    }
                }
                .padding(.vertical, MajorTomTheme.Spacing.xs)
                .contentShape(Rectangle())
            }

            // Children
            if isExpanded, let children = node.children {
                ForEach(children) { child in
                    WorkspaceTreeNodeView(
                        node: child,
                        selectedPaths: $selectedPaths,
                        depth: depth + 1
                    )
                }
            }
        }
    }

    private var iconForNode: String {
        if node.isDirectory {
            return isExpanded ? "folder.fill" : "folder"
        }
        let ext = (node.name as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "ts", "tsx", "js", "jsx": return "doc.text"
        case "json": return "curlybraces"
        case "md": return "doc.richtext"
        case "yml", "yaml": return "list.bullet"
        case "css", "scss": return "paintbrush"
        case "html": return "globe"
        case "png", "jpg", "jpeg", "svg": return "photo"
        default: return "doc"
        }
    }
}

#Preview {
    WorkspaceTreeView(
        files: [
            FileNode(name: "src", path: "/src", isDirectory: true, children: [
                FileNode(name: "App.swift", path: "/src/App.swift", isDirectory: false, children: nil),
                FileNode(name: "Models", path: "/src/Models", isDirectory: true, children: [
                    FileNode(name: "User.swift", path: "/src/Models/User.swift", isDirectory: false, children: nil),
                ]),
            ]),
            FileNode(name: "Package.swift", path: "/Package.swift", isDirectory: false, children: nil),
        ],
        selectedPaths: .constant(["/src/App.swift"])
    )
    .background(MajorTomTheme.Colors.background)
    .preferredColorScheme(.dark)
}
