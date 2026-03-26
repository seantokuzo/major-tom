import SwiftUI

struct TemplateListView: View {
    @Bindable var viewModel: TemplateViewModel
    var onSelectTemplate: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var showEditor = false
    @State private var editingTemplate: PromptTemplate?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Category filter
                categoryFilter

                // Template list
                if viewModel.filteredTemplates.isEmpty {
                    emptyState
                } else {
                    templateList
                }
            }
            .background(MajorTomTheme.Colors.background)
            .navigationTitle("Templates")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $viewModel.searchText, prompt: "Search templates")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(MajorTomTheme.Colors.accent)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        HapticService.buttonTap()
                        editingTemplate = nil
                        showEditor = true
                    } label: {
                        Image(systemName: "plus")
                            .foregroundStyle(MajorTomTheme.Colors.accent)
                    }
                }
            }
            .sheet(isPresented: $showEditor) {
                TemplateEditorView(
                    viewModel: viewModel,
                    existingTemplate: editingTemplate
                )
            }
        }
    }

    // MARK: - Category Filter

    private var categoryFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: MajorTomTheme.Spacing.sm) {
                // "All" chip
                categoryChip(label: "All", icon: "square.grid.2x2", isSelected: viewModel.selectedCategory == nil) {
                    viewModel.selectedCategory = nil
                }

                ForEach(TemplateCategory.allCases) { category in
                    categoryChip(
                        label: category.rawValue,
                        icon: category.icon,
                        isSelected: viewModel.selectedCategory == category
                    ) {
                        viewModel.selectedCategory = category
                    }
                }
            }
            .padding(.horizontal, MajorTomTheme.Spacing.lg)
            .padding(.vertical, MajorTomTheme.Spacing.md)
        }
        .background(MajorTomTheme.Colors.surface)
    }

    private func categoryChip(label: String, icon: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            HapticService.buttonTap()
            action()
        } label: {
            HStack(spacing: MajorTomTheme.Spacing.xs) {
                Image(systemName: icon)
                    .font(.caption)
                Text(label)
                    .font(MajorTomTheme.Typography.caption)
            }
            .padding(.horizontal, MajorTomTheme.Spacing.md)
            .padding(.vertical, MajorTomTheme.Spacing.sm)
            .background(
                isSelected
                    ? MajorTomTheme.Colors.accent.opacity(0.2)
                    : MajorTomTheme.Colors.surfaceElevated
            )
            .foregroundStyle(
                isSelected
                    ? MajorTomTheme.Colors.accent
                    : MajorTomTheme.Colors.textSecondary
            )
            .clipShape(Capsule())
        }
    }

    // MARK: - Template List

    private var templateList: some View {
        List {
            ForEach(viewModel.filteredTemplates) { template in
                templateRow(template)
                    .listRowBackground(MajorTomTheme.Colors.surface)
                    .listRowSeparatorTint(MajorTomTheme.Colors.textTertiary.opacity(0.3))
            }
            .onDelete { offsets in
                viewModel.deleteTemplates(at: offsets)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func templateRow(_ template: PromptTemplate) -> some View {
        Button {
            HapticService.buttonTap()
            let content = viewModel.useTemplate(template)
            onSelectTemplate(content)
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: MajorTomTheme.Spacing.xs) {
                HStack {
                    Image(systemName: template.category.icon)
                        .font(.caption)
                        .foregroundStyle(MajorTomTheme.Colors.accent)

                    Text(template.name)
                        .font(MajorTomTheme.Typography.headline)
                        .foregroundStyle(MajorTomTheme.Colors.textPrimary)

                    Spacer()

                    if template.usageCount > 0 {
                        Text("\(template.usageCount) uses")
                            .font(MajorTomTheme.Typography.caption)
                            .foregroundStyle(MajorTomTheme.Colors.textTertiary)
                    }
                }

                Text(template.content)
                    .font(MajorTomTheme.Typography.body)
                    .foregroundStyle(MajorTomTheme.Colors.textSecondary)
                    .lineLimit(2)
            }
            .padding(.vertical, MajorTomTheme.Spacing.xs)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                viewModel.deleteTemplate(template)
            } label: {
                Label("Delete", systemImage: "trash")
            }

            Button {
                editingTemplate = template
                showEditor = true
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(MajorTomTheme.Colors.accent)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: MajorTomTheme.Spacing.lg) {
            Spacer()
            Image(systemName: "doc.text")
                .font(.system(size: 48))
                .foregroundStyle(MajorTomTheme.Colors.textTertiary)

            Text("No templates found")
                .font(MajorTomTheme.Typography.headline)
                .foregroundStyle(MajorTomTheme.Colors.textSecondary)

            Text("Create a template to save prompts you use often")
                .font(MajorTomTheme.Typography.body)
                .foregroundStyle(MajorTomTheme.Colors.textTertiary)
                .multilineTextAlignment(.center)

            Button {
                HapticService.buttonTap()
                showEditor = true
            } label: {
                Text("Create Template")
                    .font(MajorTomTheme.Typography.headline)
                    .padding(.horizontal, MajorTomTheme.Spacing.xl)
                    .padding(.vertical, MajorTomTheme.Spacing.md)
                    .background(MajorTomTheme.Colors.accent)
                    .foregroundStyle(.black)
                    .clipShape(Capsule())
            }
            Spacer()
        }
        .padding(MajorTomTheme.Spacing.xl)
    }
}

#Preview {
    TemplateListView(
        viewModel: TemplateViewModel(),
        onSelectTemplate: { _ in }
    )
    .preferredColorScheme(.dark)
}
