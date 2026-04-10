import SwiftUI

/// Full-screen sheet for drag-to-reorder keybar customization.
///
/// Two segments: "Accessory Row" (above keyboard) and "Specialty Grid" (keyboard replacement).
/// Active keys can be reordered via native drag, removed with the minus button.
/// New keys can be added from the full library, filtered by search text.
/// Mirrors the web PWA's `KeybarCustomizeSheet.svelte` with native SwiftUI controls.
struct KeybarCustomizer: View {
    let keybarViewModel: KeybarViewModel

    @State private var activeTab: KeybarTab = .accessory
    @State private var searchText = ""
    @State private var showAddKeys = false
    @State private var showResetAlert = false
    @Environment(\.dismiss) private var dismiss

    private enum KeybarTab: String, CaseIterable {
        case accessory = "Accessory Row"
        case specialty = "Specialty Grid"
    }

    /// Current active key IDs for the selected tab.
    private var currentIds: [String] {
        activeTab == .accessory ? keybarViewModel.accessoryIds : keybarViewModel.specialtyIds
    }

    /// Current active keys resolved for the selected tab.
    private var currentKeys: [KeySpec] {
        activeTab == .accessory ? keybarViewModel.accessoryKeys : keybarViewModel.specialtyKeys
    }

    /// Available keys not already in the active layout, filtered by search.
    private var availableKeys: [KeySpec] {
        let activeSet = Set(currentIds)
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return KeyLibrary.all.filter { key in
            guard !activeSet.contains(key.id) else { return false }
            guard !query.isEmpty else { return true }
            return key.id.lowercased().contains(query) ||
                   key.label.lowercased().contains(query) ||
                   (key.description ?? "").lowercased().contains(query)
        }
    }

    /// Available keys grouped by KeyGroup for organized display.
    private var groupedAvailableKeys: [(KeyGroup, [KeySpec])] {
        let grouped = Dictionary(grouping: availableKeys) { $0.group }
        return KeyGroup.allCases.compactMap { group in
            guard let keys = grouped[group], !keys.isEmpty else { return nil }
            return (group, keys)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Segment picker
                Picker("Layout", selection: $activeTab) {
                    ForEach(KeybarTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, MajorTomTheme.Spacing.md)
                .padding(.vertical, MajorTomTheme.Spacing.sm)

                // Active keys list
                List {
                    activeKeysSection
                    addKeysSection
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .background(MajorTomTheme.Colors.background)
            .navigationTitle("Customize Keys")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Reset") {
                        showResetAlert = true
                    }
                    .foregroundStyle(MajorTomTheme.Colors.deny)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(MajorTomTheme.Colors.accent)
                }
            }
            .alert("Reset to Defaults", isPresented: $showResetAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Reset", role: .destructive) {
                    HapticService.buttonTap()
                    keybarViewModel.resetToDefaults()
                }
            } message: {
                Text("This will reset both the accessory row and specialty grid to their default layouts.")
            }
        }
    }

    // MARK: - Active Keys Section

    private var activeKeysSection: some View {
        Section {
            if currentKeys.isEmpty {
                Text("No keys configured. Add some below.")
                    .font(MajorTomTheme.Typography.caption)
                    .foregroundStyle(MajorTomTheme.Colors.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, MajorTomTheme.Spacing.md)
            } else {
                ForEach(currentKeys) { key in
                    HStack(spacing: MajorTomTheme.Spacing.md) {
                        // Key label
                        Text(key.label)
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundStyle(MajorTomTheme.Colors.textPrimary)
                            .frame(minWidth: 36, alignment: .center)

                        // Description
                        Text(key.description ?? key.id)
                            .font(MajorTomTheme.Typography.caption)
                            .foregroundStyle(MajorTomTheme.Colors.textSecondary)
                            .lineLimit(1)

                        Spacer()

                        // Remove button
                        Button {
                            HapticService.buttonTap()
                            removeKey(key.id)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(MajorTomTheme.Colors.deny)
                        }
                        .buttonStyle(.plain)
                    }
                    .listRowBackground(MajorTomTheme.Colors.surface)
                }
                .onMove(perform: moveKeys)
            }
        } header: {
            HStack {
                Text("Active (\(currentKeys.count))")
                Spacer()
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 10))
                    .foregroundStyle(MajorTomTheme.Colors.textTertiary)
                Text("Drag to reorder")
                    .font(.system(size: 10))
                    .foregroundStyle(MajorTomTheme.Colors.textTertiary)
            }
        }
        .listRowBackground(MajorTomTheme.Colors.surface)
    }

    // MARK: - Add Keys Section

    private var addKeysSection: some View {
        Section {
            DisclosureGroup(
                isExpanded: $showAddKeys,
                content: {
                    // Search field
                    TextField("Filter keys...", text: $searchText)
                        .font(MajorTomTheme.Typography.caption)
                        .textFieldStyle(.roundedBorder)
                        .listRowBackground(MajorTomTheme.Colors.surface)

                    if groupedAvailableKeys.isEmpty {
                        Text("All library keys are already active.")
                            .font(MajorTomTheme.Typography.caption)
                            .foregroundStyle(MajorTomTheme.Colors.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, MajorTomTheme.Spacing.sm)
                    } else {
                        ForEach(groupedAvailableKeys, id: \.0) { group, keys in
                            GroupHeader(group: group)
                                .listRowBackground(MajorTomTheme.Colors.surface)

                            ForEach(keys) { key in
                                HStack(spacing: MajorTomTheme.Spacing.md) {
                                    Text(key.label)
                                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                                        .foregroundStyle(MajorTomTheme.Colors.textPrimary)
                                        .frame(minWidth: 36, alignment: .center)

                                    Text(key.description ?? key.id)
                                        .font(MajorTomTheme.Typography.caption)
                                        .foregroundStyle(MajorTomTheme.Colors.textSecondary)
                                        .lineLimit(1)

                                    Spacer()

                                    Button {
                                        HapticService.buttonTap()
                                        addKey(key.id)
                                    } label: {
                                        Image(systemName: "plus.circle.fill")
                                            .font(.system(size: 20))
                                            .foregroundStyle(MajorTomTheme.Colors.accent)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .listRowBackground(MajorTomTheme.Colors.surface)
                            }
                        }
                    }
                },
                label: {
                    Label("Add a key", systemImage: "plus.square")
                        .foregroundStyle(MajorTomTheme.Colors.accent)
                }
            )
        }
        .listRowBackground(MajorTomTheme.Colors.surface)
    }

    // MARK: - Actions

    private func addKey(_ id: String) {
        if activeTab == .accessory {
            keybarViewModel.addAccessoryKey(id: id)
        } else {
            keybarViewModel.addSpecialtyKey(id: id)
        }
    }

    private func removeKey(_ id: String) {
        if activeTab == .accessory {
            keybarViewModel.removeAccessoryKey(id: id)
        } else {
            keybarViewModel.removeSpecialtyKey(id: id)
        }
    }

    private func moveKeys(from source: IndexSet, to destination: Int) {
        HapticService.buttonTap()
        if activeTab == .accessory {
            keybarViewModel.moveAccessoryKey(from: source, to: destination)
        } else {
            keybarViewModel.moveSpecialtyKey(from: source, to: destination)
        }
    }
}

// MARK: - Group Header

/// Display name for a KeyGroup in the "Add Key" picker.
private struct GroupHeader: View {
    let group: KeyGroup

    var body: some View {
        Text(groupName)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(MajorTomTheme.Colors.textTertiary)
            .textCase(.uppercase)
    }

    private var groupName: String {
        switch group {
        case .modifier: "Modifiers"
        case .edit: "Edit"
        case .nav: "Navigation"
        case .symbol: "Symbols"
        case .ctrl: "Ctrl Combos"
        case .tmux: "Tmux"
        case .function: "Function Keys"
        }
    }
}
