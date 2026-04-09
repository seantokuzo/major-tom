import Foundation

/// Observable log storage with ring buffer, level filtering, and text search.
///
/// Capped at `maxEntries` to prevent unbounded memory growth.
/// Provides a filtered view based on active level toggles and search text.
@Observable
final class LogStore {
    /// Maximum entries before old ones are evicted.
    let maxEntries: Int

    /// All stored log entries (ring buffer, oldest first).
    private(set) var entries: [LogEntry] = []

    /// Which log levels are currently visible.
    var activeLevels: Set<LogEntry.LogLevel> = Set(LogEntry.LogLevel.allCases)

    /// Case-insensitive search text applied to the message field.
    var searchText: String = ""

    /// Filtered entries based on active levels and search text.
    var filteredEntries: [LogEntry] {
        entries.filter { entry in
            guard activeLevels.contains(entry.level) else { return false }

            if !searchText.isEmpty {
                return entry.message.localizedCaseInsensitiveContains(searchText)
            }

            return true
        }
    }

    init(maxEntries: Int = 10_000) {
        self.maxEntries = maxEntries
        entries.reserveCapacity(min(maxEntries, 1_000))
    }

    // MARK: - Mutations

    /// Parse a raw stdout/stderr line and append the resulting LogEntry.
    /// Ignores empty lines.
    func append(_ line: String) {
        guard let entry = LogEntry.parse(line: line) else { return }

        entries.append(entry)

        // Evict oldest entries when over capacity
        if entries.count > maxEntries {
            let overflow = entries.count - maxEntries
            entries.removeFirst(overflow)
        }
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
        entries.removeAll(keepingCapacity: true)
    }
}
