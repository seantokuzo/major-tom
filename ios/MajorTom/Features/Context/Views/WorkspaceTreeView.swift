import SwiftUI

/// Shared workspace tree view that delegates to WorkspaceTreeRow.
/// This is a thin wrapper — the actual tree node rendering lives in
/// WorkspaceTreeRow (defined in FileContextView.swift).
struct WorkspaceTreeView: View {
    let files: [FileNode]
    @Binding var selectedPaths: Set<String>
    var searchText: String = ""

    var body: some View {
        List {
            ForEach(files) { node in
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
