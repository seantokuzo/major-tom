import SwiftUI

/// Edits the relay-side `defaultSpawnCwd` setting via `/api/relay-config`.
/// New PTY tabs spawn into this directory when the tab has no fresh
/// per-tab `workingDir`. QA-FIXES #17 + #19.
struct DefaultWorkingDirView: View {
    private let relay: RelayService

    @State private var draft: String = ""
    @State private var serverValue: String? = nil
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var loadError: String?
    @State private var saveError: String?
    @State private var saveConfirmation: String?

    init(relay: RelayService) {
        self.relay = relay
    }

    var body: some View {
        List {
            currentValueSection
            editSection
        }
        .scrollContentBackground(.hidden)
        .background(MajorTomTheme.Colors.background)
        .navigationTitle("Default Directory")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(isLoading || isSaving)
            }
        }
        .task { await refresh() }
    }

    private var currentValueSection: some View {
        Section {
            HStack {
                Label("Current", systemImage: "folder")
                Spacer()
                if isLoading {
                    ProgressView().tint(MajorTomTheme.Colors.accent)
                } else {
                    Text(displayCurrent)
                        .font(MajorTomTheme.Typography.codeFontSmall)
                        .foregroundStyle(MajorTomTheme.Colors.textSecondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
            }
            .listRowBackground(MajorTomTheme.Colors.surface)

            if let loadError {
                Text(loadError)
                    .font(.footnote)
                    .foregroundStyle(MajorTomTheme.Colors.deny)
                    .listRowBackground(MajorTomTheme.Colors.surface)
            }
        } header: {
            Text("Configured")
        } footer: {
            Text("New terminal tabs spawn here when there is no recently-used directory for the tab. Leave empty to fall back to the relay default ($HOME/Documents/code/dev if it exists, otherwise $HOME).")
        }
    }

    private var editSection: some View {
        Section {
            TextField(
                "/Users/you/Documents/code/dev",
                text: $draft,
                axis: .vertical,
            )
            .font(MajorTomTheme.Typography.codeFont)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled(true)
            .listRowBackground(MajorTomTheme.Colors.surface)

            HStack {
                Button {
                    Task { await save() }
                } label: {
                    if isSaving {
                        ProgressView().tint(MajorTomTheme.Colors.accent)
                    } else {
                        Text("Save")
                    }
                }
                .disabled(isSaving || draft == (serverValue ?? ""))

                Spacer()

                Button(role: .destructive) {
                    Task { await clear() }
                } label: {
                    Text("Clear")
                }
                .disabled(isSaving || (serverValue ?? "").isEmpty)
            }
            .listRowBackground(MajorTomTheme.Colors.surface)

            if let saveError {
                Text(saveError)
                    .font(.footnote)
                    .foregroundStyle(MajorTomTheme.Colors.deny)
                    .listRowBackground(MajorTomTheme.Colors.surface)
            }
            if let saveConfirmation {
                Text(saveConfirmation)
                    .font(.footnote)
                    .foregroundStyle(MajorTomTheme.Colors.allow)
                    .listRowBackground(MajorTomTheme.Colors.surface)
            }
        } header: {
            Text("Edit")
        } footer: {
            Text("The relay validates that the path exists and is a directory. The next new tab picks up the change — existing tabs keep their current cwd.")
        }
    }

    private var displayCurrent: String {
        guard let v = serverValue, !v.isEmpty else {
            return "Not set"
        }
        return v
    }

    private func refresh() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            let data = try await relay.fetchRelayConfig()
            let value = data.defaultSpawnCwd ?? ""
            serverValue = data.defaultSpawnCwd
            draft = value
            saveError = nil
            saveConfirmation = nil
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func save() async {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let next = trimmed.isEmpty ? nil : trimmed
        await applyUpdate(next)
    }

    private func clear() async {
        await applyUpdate(nil)
    }

    private func applyUpdate(_ value: String?) async {
        isSaving = true
        saveError = nil
        saveConfirmation = nil
        defer { isSaving = false }
        do {
            let data = try await relay.updateRelayConfig(defaultSpawnCwd: value)
            serverValue = data.defaultSpawnCwd
            draft = data.defaultSpawnCwd ?? ""
            saveConfirmation = value == nil
                ? "Cleared. New tabs will use the relay default."
                : "Saved. New tabs will spawn here."
            HapticService.selection()
        } catch {
            saveError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            HapticService.impact(.medium)
        }
    }
}

#Preview {
    NavigationStack {
        DefaultWorkingDirView(relay: RelayService())
    }
}
