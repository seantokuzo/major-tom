import Foundation

@Observable
@MainActor
final class TemplateViewModel {
    var templates: [PromptTemplate] = []
    var searchText = ""
    var selectedCategory: TemplateCategory?

    private let storageKey = "majortom.prompt_templates"

    init() {
        loadTemplates()
    }

    // MARK: - Filtered Results

    var filteredTemplates: [PromptTemplate] {
        var result = templates

        if let category = selectedCategory {
            result = result.filter { $0.category == category }
        }

        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.name.lowercased().contains(query) ||
                $0.content.lowercased().contains(query)
            }
        }

        // Sort by most used, then most recent
        return result.sorted { a, b in
            if a.usageCount != b.usageCount {
                return a.usageCount > b.usageCount
            }
            return a.createdAt > b.createdAt
        }
    }

    // MARK: - CRUD

    func addTemplate(name: String, content: String, category: TemplateCategory) {
        let template = PromptTemplate(
            name: name,
            content: content,
            category: category
        )
        templates.append(template)
        saveTemplates()
    }

    func updateTemplate(_ template: PromptTemplate) {
        guard let index = templates.firstIndex(where: { $0.id == template.id }) else { return }
        templates[index] = template
        saveTemplates()
    }

    func deleteTemplate(_ template: PromptTemplate) {
        templates.removeAll { $0.id == template.id }
        saveTemplates()
    }

    func deleteTemplates(at offsets: IndexSet) {
        let sorted = filteredTemplates
        for index in offsets {
            let template = sorted[index]
            templates.removeAll { $0.id == template.id }
        }
        saveTemplates()
    }

    func useTemplate(_ template: PromptTemplate) -> String {
        guard let index = templates.firstIndex(where: { $0.id == template.id }) else {
            return template.content
        }
        templates[index].usageCount += 1
        templates[index].lastUsedAt = Date()
        saveTemplates()
        return templates[index].content
    }

    // MARK: - Persistence

    private func loadTemplates() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([PromptTemplate].self, from: data) else {
            // Load default templates on first launch
            templates = Self.defaultTemplates
            saveTemplates()
            return
        }
        templates = decoded
    }

    private func saveTemplates() {
        guard let data = try? JSONEncoder().encode(templates) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    // MARK: - Defaults

    static let defaultTemplates: [PromptTemplate] = [
        PromptTemplate(
            name: "Explain Code",
            content: "Explain this code in detail, including what it does and why:",
            category: .general
        ),
        PromptTemplate(
            name: "Find Bug",
            content: "There's a bug in this code. Help me find and fix it:",
            category: .debug
        ),
        PromptTemplate(
            name: "Add Tests",
            content: "Write comprehensive unit tests for:",
            category: .test
        ),
        PromptTemplate(
            name: "Refactor",
            content: "Refactor this code to be more readable and maintainable:",
            category: .refactor
        ),
        PromptTemplate(
            name: "Code Review",
            content: "Review this code for potential issues, best practices, and improvements:",
            category: .review
        ),
        PromptTemplate(
            name: "Debug Error",
            content: "I'm getting this error. Help me understand and fix it:",
            category: .debug
        ),
    ]
}
