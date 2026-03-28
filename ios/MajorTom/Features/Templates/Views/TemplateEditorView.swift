import SwiftUI

struct TemplateEditorView: View {
    @Bindable var viewModel: TemplateViewModel
    var existingTemplate: PromptTemplate?

    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var content = ""
    @State private var category: TemplateCategory = .general

    private var isEditing: Bool { existingTemplate != nil }
    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Template name", text: $name)
                        .foregroundStyle(MajorTomTheme.Colors.textPrimary)
                } header: {
                    Text("Name")
                        .foregroundStyle(MajorTomTheme.Colors.textSecondary)
                }
                .listRowBackground(MajorTomTheme.Colors.surface)

                Section {
                    Picker("Category", selection: $category) {
                        ForEach(TemplateCategory.allCases) { cat in
                            Label(cat.rawValue, systemImage: cat.icon)
                                .tag(cat)
                        }
                    }
                    .foregroundStyle(MajorTomTheme.Colors.textPrimary)
                } header: {
                    Text("Category")
                        .foregroundStyle(MajorTomTheme.Colors.textSecondary)
                }
                .listRowBackground(MajorTomTheme.Colors.surface)

                Section {
                    TextEditor(text: $content)
                        .foregroundStyle(MajorTomTheme.Colors.textPrimary)
                        .frame(minHeight: 120)
                        .scrollContentBackground(.hidden)
                } header: {
                    Text("Prompt Content")
                        .foregroundStyle(MajorTomTheme.Colors.textSecondary)
                }
                .listRowBackground(MajorTomTheme.Colors.surface)
            }
            .scrollContentBackground(.hidden)
            .background(MajorTomTheme.Colors.background)
            .navigationTitle(isEditing ? "Edit Template" : "New Template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(MajorTomTheme.Colors.textSecondary)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(isEditing ? "Save" : "Create") {
                        HapticService.buttonTap()
                        saveTemplate()
                        dismiss()
                    }
                    .foregroundStyle(isValid ? MajorTomTheme.Colors.accent : MajorTomTheme.Colors.textTertiary)
                    .disabled(!isValid)
                }
            }
            .onAppear {
                if let template = existingTemplate {
                    name = template.name
                    content = template.content
                    category = template.category
                }
            }
        }
    }

    private func saveTemplate() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)

        if var existing = existingTemplate {
            existing.name = trimmedName
            existing.content = trimmedContent
            existing.category = category
            viewModel.updateTemplate(existing)
        } else {
            viewModel.addTemplate(
                name: trimmedName,
                content: trimmedContent,
                category: category
            )
        }
    }
}

#Preview {
    TemplateEditorView(viewModel: TemplateViewModel())
        .preferredColorScheme(.dark)
}

#Preview("Edit Mode") {
    TemplateEditorView(
        viewModel: TemplateViewModel(),
        existingTemplate: PromptTemplate(
            name: "Test Template",
            content: "This is test content",
            category: .debug
        )
    )
    .preferredColorScheme(.dark)
}
