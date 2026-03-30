import SwiftUI

struct FileContextView: View {
    let relay: RelayService
    var onFilesSelected: ([String]) -> Void
    @Binding var isPresented: Bool

    @State private var selectedPaths: Set<String> = []
    @State private var searchText = ""
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if isLoading {
                    loadingView
                } else if relay.workspaceFiles.isEmpty {
                    emptyState
                } else {
                    fileTree
                }

                // Selection summary
                if !selectedPaths.isEmpty {
                    selectionBar
                }
            }
            .background(MajorTomTheme.Colors.background)
            .navigationTitle("Add Context")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search files")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                    }
                    .foregroundStyle(MajorTomTheme.Colors.textSecondary)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add") {
                        HapticService.buttonTap()
                        onFilesSelected(selectedPaths.sorted())
                        isPresented = false
                    }
                    .foregroundStyle(
                        selectedPaths.isEmpty
                            ? MajorTomTheme.Colors.textTertiary
                            : MajorTomTheme.Colors.accent
                    )
                    .disabled(selectedPaths.isEmpty)
                }
            }
            .task {
                await loadWorkspaceTree()
            }
        }
    }

    // MARK: - File Tree

    private var fileTree: some View {
        List {
            ForEach(filteredFiles) { node in
                WorkspaceTreeRow(
                    node: node,
                    selectedPaths: $selectedPaths,
                    searchText: searchText
                )
                .listRowBackground(MajorTomTheme.Colors.surface)
                .listRowSeparatorTint(MajorTomTheme.Colors.textTertiary.opacity(0.2))
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private var filteredFiles: [FileNode] {
        guard !searchText.isEmpty else { return relay.workspaceFiles }
        return filterNodes(relay.workspaceFiles, query: searchText.lowercased())
    }

    private func filterNodes(_ nodes: [FileNode], query: String) -> [FileNode] {
        nodes.compactMap { node in
            if node.name.lowercased().contains(query) {
                return node
            }
            if node.isDirectory, let children = node.children {
                let filtered = filterNodes(children, query: query)
                if !filtered.isEmpty {
                    var copy = node
                    copy.children = filtered
                    return copy
                }
            }
            return nil
        }
    }

    // MARK: - Selection Bar

    private var selectionBar: some View {
        HStack(spacing: MajorTomTheme.Spacing.md) {
            Image(systemName: "doc.on.doc")
                .foregroundStyle(MajorTomTheme.Colors.accent)

            Text("\(selectedPaths.count) file\(selectedPaths.count == 1 ? "" : "s") selected")
                .font(MajorTomTheme.Typography.body)
                .foregroundStyle(MajorTomTheme.Colors.textPrimary)

            Spacer()

            Button {
                HapticService.buttonTap()
                selectedPaths.removeAll()
            } label: {
                Text("Clear")
                    .font(MajorTomTheme.Typography.caption)
                    .foregroundStyle(MajorTomTheme.Colors.deny)
            }
        }
        .padding(MajorTomTheme.Spacing.md)
        .background(MajorTomTheme.Colors.surface)
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: MajorTomTheme.Spacing.lg) {
            Spacer()
            ProgressView()
                .tint(MajorTomTheme.Colors.accent)
            Text("Loading workspace...")
                .font(MajorTomTheme.Typography.body)
                .foregroundStyle(MajorTomTheme.Colors.textSecondary)
            Spacer()
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: MajorTomTheme.Spacing.lg) {
            Spacer()
            Image(systemName: "folder")
                .font(.system(size: 48))
                .foregroundStyle(MajorTomTheme.Colors.textTertiary)

            Text("No workspace files")
                .font(MajorTomTheme.Typography.headline)
                .foregroundStyle(MajorTomTheme.Colors.textSecondary)

            Text("Start a session to browse workspace files")
                .font(MajorTomTheme.Typography.body)
                .foregroundStyle(MajorTomTheme.Colors.textTertiary)
            Spacer()
        }
        .padding(MajorTomTheme.Spacing.xl)
    }

    // MARK: - Actions

    private func loadWorkspaceTree() async {
        isLoading = true
        defer { isLoading = false }

        do {
            try await relay.requestWorkspaceTree()
            // Small delay to let the response come back
            try? await Task.sleep(for: .milliseconds(500))
        } catch {
            // workspace files will remain empty
        }
    }
}

// MARK: - Workspace Tree Row

struct WorkspaceTreeRow: View {
    let node: FileNode
    @Binding var selectedPaths: Set<String>
    var searchText: String
    var depth: Int = 0

    @State private var isExpanded = false

    private var isSelected: Bool {
        selectedPaths.contains(node.path)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                HapticService.buttonTap()
                if node.isDirectory {
                    isExpanded.toggle()
                } else {
                    toggleSelection()
                }
            } label: {
                HStack(spacing: MajorTomTheme.Spacing.sm) {
                    // Indent
                    if depth > 0 {
                        Spacer()
                            .frame(width: CGFloat(depth) * 16)
                    }

                    // Icon
                    Image(systemName: nodeIcon)
                        .font(.caption)
                        .foregroundStyle(node.isDirectory ? MajorTomTheme.Colors.accent : MajorTomTheme.Colors.textSecondary)
                        .frame(width: 20)

                    // Name
                    Text(node.name)
                        .font(MajorTomTheme.Typography.body)
                        .foregroundStyle(MajorTomTheme.Colors.textPrimary)
                        .lineLimit(1)

                    Spacer()

                    // Selection indicator
                    if !node.isDirectory {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(isSelected ? MajorTomTheme.Colors.accent : MajorTomTheme.Colors.textTertiary)
                    }
                }
                .padding(.vertical, MajorTomTheme.Spacing.xs)
            }

            // Children
            if node.isDirectory && isExpanded, let children = node.children {
                ForEach(children) { child in
                    WorkspaceTreeRow(
                        node: child,
                        selectedPaths: $selectedPaths,
                        searchText: searchText,
                        depth: depth + 1
                    )
                }
            }
        }
        .onAppear {
            // Auto-expand when searching
            if !searchText.isEmpty && node.isDirectory {
                isExpanded = true
            }
        }
    }

    private var nodeIcon: String {
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
        default: return "doc"
        }
    }

    private func toggleSelection() {
        if isSelected {
            selectedPaths.remove(node.path)
        } else {
            selectedPaths.insert(node.path)
        }
    }
}

#Preview {
    FileContextView(
        relay: RelayService(),
        onFilesSelected: { paths in print(paths) },
        isPresented: .constant(true)
    )
    .preferredColorScheme(.dark)
}
