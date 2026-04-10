import Collections
import Foundation

/// Observable log storage with ring buffer, level filtering, and text search.
///
/// Capped at `maxEntries` to prevent unbounded memory growth.
/// Uses `Deque` for O(1) front eviction under steady-state log ingestion.
/// Caches filtered results to avoid redundant O(n) recomputation.
@Observable
final class LogStore {
    /// Maximum entries before old ones are evicted.
    let maxEntries: Int

    /// All stored log entries (deque, oldest first). O(1) removeFirst.
    private(set) var entries: Deque<LogEntry> = []

    /// Which log levels are currently visible.
    var activeLevels: Set<LogEntry.LogLevel> = Set(LogEntry.LogLevel.allCases) {
        didSet { invalidateFilterCache() }
    }

    /// Case-insensitive search text applied to the message field.
    var searchText: String = "" {
        didSet { invalidateFilterCache() }
    }

    /// Cached filtered entries — recomputed lazily when inputs change.
    private var cachedFilteredEntries: [LogEntry]?

    /// Filtered entries based on active levels and search text.
    var filteredEntries: [LogEntry] {
        if let cached = cachedFilteredEntries { return cached }

        let result: [LogEntry] = entries.filter { entry in
            guard activeLevels.contains(entry.level) else { return false }

            if !searchText.isEmpty {
                return entry.message.localizedCaseInsensitiveContains(searchText)
            }

            return true
        }
        cachedFilteredEntries = result
        return result
    }

    init(maxEntries: Int = 10_000) {
        self.maxEntries = maxEntries
    }

    // MARK: - Mutations

    /// Parse a raw stdout/stderr line and append the resulting LogEntry.
    /// Ignores empty lines.
    func append(_ line: String) {
        guard let entry = LogEntry.parse(line: line) else { return }

        entries.append(entry)

        // Evict oldest entries when over capacity (O(1) with Deque)
        while entries.count > maxEntries {
            entries.removeFirst()
        }

        invalidateFilterCache()
    }

    /// Toggle a specific log level on or off.
    func toggleLevel(_ level: LogEntry.LogLevel) {
        if activeLevels.contains(level) {
            activeLevels.remove(level)
        } else {
            activeLevels.insert(level)
        }
    }

    /// Clear all stored log entries.
    func clear() {
        entries.removeAll()
        invalidateFilterCache()
    }

    // MARK: - Private

    private func invalidateFilterCache() {
        cachedFilteredEntries = nil
    }
}
