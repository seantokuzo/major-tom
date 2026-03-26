import Foundation

@Observable
@MainActor
final class PromptHistoryViewModel {
    var entries: [PromptHistoryEntry] = []
    var searchText = ""

    private let storageKey = "majortom.prompt_history"
    private let maxEntries = 100

    init() {
        loadHistory()
    }

    // MARK: - Filtered Results

    var filteredEntries: [PromptHistoryEntry] {
        guard !searchText.isEmpty else { return entries }
        let query = searchText.lowercased()
        return entries.filter { $0.text.lowercased().contains(query) }
    }

    // MARK: - Operations

    func addEntry(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Remove duplicate if exists
        entries.removeAll { $0.text == trimmed }

        // Add to front
        let entry = PromptHistoryEntry(text: trimmed)
        entries.insert(entry, at: 0)

        // Trim to max
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }

        saveHistory()
    }

    func removeEntry(_ entry: PromptHistoryEntry) {
        entries.removeAll { $0.id == entry.id }
        saveHistory()
    }

    func removeEntries(at offsets: IndexSet) {
        let filtered = filteredEntries
        for index in offsets {
            let entry = filtered[index]
            entries.removeAll { $0.id == entry.id }
        }
        saveHistory()
    }

    func clearHistory() {
        entries.removeAll()
        saveHistory()
    }

    // MARK: - Persistence

    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([PromptHistoryEntry].self, from: data) else {
            return
        }
        entries = decoded
    }

    private func saveHistory() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}

// MARK: - Model

struct PromptHistoryEntry: Identifiable, Codable, Equatable {
    let id: UUID
    let text: String
    let timestamp: Date

    init(id: UUID = UUID(), text: String, timestamp: Date = Date()) {
        self.id = id
        self.text = text
        self.timestamp = timestamp
    }

    var relativeTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }

    var truncatedText: String {
        if text.count <= 80 {
            return text
        }
        return String(text.prefix(80)) + "..."
    }
}
