import SwiftUI

struct DirectoryPermissionsView: View {
    let userId: String
    let relay: RelayService
    @State private var newPath = ""

    private var paths: [String] {
        relay.userSandboxPaths[userId] ?? []
    }

    var body: some View {
        List {
            if paths.isEmpty {
                Section {
                    Label("Unrestricted Access", systemImage: "lock.open")
                        .foregroundStyle(.green)
                        .font(MajorTomTheme.Typography.body)
                }
                .listRowBackground(MajorTomTheme.Colors.surface)
            }

            Section("Allowed Directories") {
                ForEach(paths, id: \.self) { path in
                    HStack {
                        Image(systemName: "folder")
                            .foregroundStyle(MajorTomTheme.Colors.accent)
                        Text(path)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(MajorTomTheme.Colors.textPrimary)
                        Spacer()
                        Button(role: .destructive) {
                            removePath(path)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                    }
                    .listRowBackground(MajorTomTheme.Colors.surface)
                }

                HStack {
                    TextField("Path", text: $newPath)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(MajorTomTheme.Colors.textPrimary)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Button("Add") { addPath() }
                        .disabled(newPath.trimmingCharacters(in: .whitespaces).isEmpty)
                        .foregroundStyle(MajorTomTheme.Colors.accent)
                }
                .listRowBackground(MajorTomTheme.Colors.surface)
            }

            if !paths.isEmpty {
                Section {
                    Button("Clear All Restrictions", role: .destructive) {
                        clearAll()
                    }
                }
                .listRowBackground(MajorTomTheme.Colors.surface)
            }
        }
        .scrollContentBackground(.hidden)
        .background(MajorTomTheme.Colors.background)
        .navigationTitle("Directory Access")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do {
                try await relay.getUserSandboxPaths(userId: userId)
            } catch {
                // Silent fail — paths just won't load
            }
        }
    }

    // MARK: - Actions

    private func addPath() {
        let trimmed = newPath.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let updated = paths + [trimmed]
        Task {
            try? await relay.setUserSandboxPaths(userId: userId, paths: updated)
        }
        newPath = ""
    }

    private func removePath(_ path: String) {
        let updated = paths.filter { $0 != path }
        Task {
            try? await relay.setUserSandboxPaths(userId: userId, paths: updated)
        }
    }

    private func clearAll() {
        Task {
            try? await relay.clearUserSandboxPaths(userId: userId)
        }
    }
}

#Preview {
    NavigationStack {
        DirectoryPermissionsView(userId: "test-user", relay: RelayService())
    }
    .preferredColorScheme(.dark)
}
