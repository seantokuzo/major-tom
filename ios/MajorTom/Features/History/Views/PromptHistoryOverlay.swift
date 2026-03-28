import SwiftUI

struct PromptHistoryOverlay: View {
    @Bindable var viewModel: PromptHistoryViewModel
    var onSelectEntry: (String) -> Void
    @Binding var isPresented: Bool

    @State private var showClearConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            // Handle bar
            handleBar

            // Search
            searchBar

            // History list
            if viewModel.filteredEntries.isEmpty {
                emptyState
            } else {
                historyList
            }
        }
        .background(MajorTomTheme.Colors.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: MajorTomTheme.Radius.large))
        .shadow(color: .black.opacity(0.4), radius: 20, y: -5)
        .confirmationDialog(
            "Clear History",
            isPresented: $showClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear All", role: .destructive) {
                viewModel.clearHistory()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete all prompt history.")
        }
    }

    // MARK: - Handle Bar

    private var handleBar: some View {
        VStack(spacing: MajorTomTheme.Spacing.sm) {
            RoundedRectangle(cornerRadius: 3)
                .fill(MajorTomTheme.Colors.textTertiary)
                .frame(width: 40, height: 5)
                .padding(.top, MajorTomTheme.Spacing.md)

            HStack {
                Text("Prompt History")
                    .font(MajorTomTheme.Typography.headline)
                    .foregroundStyle(MajorTomTheme.Colors.textPrimary)

                Spacer()

                if !viewModel.entries.isEmpty {
                    Button {
                        HapticService.buttonTap()
                        showClearConfirmation = true
                    } label: {
                        Text("Clear")
                            .font(MajorTomTheme.Typography.caption)
                            .foregroundStyle(MajorTomTheme.Colors.deny)
                    }
                }

                Button {
                    HapticService.buttonTap()
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(MajorTomTheme.Colors.textTertiary)
                }
            }
            .padding(.horizontal, MajorTomTheme.Spacing.lg)
        }
    }

    // MARK: - Search

    private var searchBar: some View {
        HStack(spacing: MajorTomTheme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(MajorTomTheme.Colors.textTertiary)

            TextField("Search history...", text: $viewModel.searchText)
                .font(MajorTomTheme.Typography.body)
                .foregroundStyle(MajorTomTheme.Colors.textPrimary)

            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(MajorTomTheme.Colors.textTertiary)
                }
            }
        }
        .padding(MajorTomTheme.Spacing.md)
        .background(MajorTomTheme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: MajorTomTheme.Radius.small))
        .padding(.horizontal, MajorTomTheme.Spacing.lg)
        .padding(.vertical, MajorTomTheme.Spacing.sm)
    }

    // MARK: - History List

    private var historyList: some View {
        List {
            ForEach(viewModel.filteredEntries) { entry in
                historyRow(entry)
                    .listRowBackground(Color.clear)
                    .listRowSeparatorTint(MajorTomTheme.Colors.textTertiary.opacity(0.2))
            }
            .onDelete { offsets in
                viewModel.removeEntries(at: offsets)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func historyRow(_ entry: PromptHistoryEntry) -> some View {
        Button {
            HapticService.buttonTap()
            onSelectEntry(entry.text)
            isPresented = false
        } label: {
            HStack(alignment: .top, spacing: MajorTomTheme.Spacing.md) {
                VStack(alignment: .leading, spacing: MajorTomTheme.Spacing.xs) {
                    Text(entry.truncatedText)
                        .font(MajorTomTheme.Typography.body)
                        .foregroundStyle(MajorTomTheme.Colors.textPrimary)
                        .lineLimit(2)

                    Text(entry.relativeTime)
                        .font(MajorTomTheme.Typography.caption)
                        .foregroundStyle(MajorTomTheme.Colors.textTertiary)
                }

                Spacer()

                Image(systemName: "arrow.turn.down.left")
                    .font(.caption)
                    .foregroundStyle(MajorTomTheme.Colors.textTertiary)
            }
            .padding(.vertical, MajorTomTheme.Spacing.xs)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: MajorTomTheme.Spacing.md) {
            Spacer()
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 36))
                .foregroundStyle(MajorTomTheme.Colors.textTertiary)

            Text(viewModel.searchText.isEmpty ? "No history yet" : "No matching prompts")
                .font(MajorTomTheme.Typography.headline)
                .foregroundStyle(MajorTomTheme.Colors.textSecondary)

            Text(viewModel.searchText.isEmpty
                 ? "Your sent prompts will appear here"
                 : "Try a different search term")
                .font(MajorTomTheme.Typography.caption)
                .foregroundStyle(MajorTomTheme.Colors.textTertiary)
            Spacer()
        }
        .padding(MajorTomTheme.Spacing.xl)
    }
}

#Preview {
    ZStack {
        MajorTomTheme.Colors.background
            .ignoresSafeArea()

        VStack {
            Spacer()
            PromptHistoryOverlay(
                viewModel: {
                    let vm = PromptHistoryViewModel()
                    vm.addEntry("Fix the bug in the authentication flow")
                    vm.addEntry("Refactor the WebSocket client to use async/await")
                    vm.addEntry("Add unit tests for the RelayService")
                    return vm
                }(),
                onSelectEntry: { _ in },
                isPresented: .constant(true)
            )
            .frame(height: 400)
        }
    }
    .preferredColorScheme(.dark)
}
