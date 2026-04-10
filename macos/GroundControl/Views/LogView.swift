import SwiftUI

/// Live log viewer with level filtering, text search, and auto-scroll.
///
/// Displays pino JSON log entries as structured rows with color-coded level badges.
/// Auto-scrolls to the bottom by default; user can toggle via the toolbar button.
struct LogView: View {
    let logStore: LogStore

    @State private var autoScroll = true
    @State private var expandedEntries: Set<UUID> = []
    @State private var prettyJSONCache = PrettyJSONCache()

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            logList
        }
    }

    // MARK: - Toolbar

    @ViewBuilder
    private var toolbar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                // Level filter toggles
                ForEach(LogEntry.LogLevel.allCases, id: \.rawValue) { level in
                    LevelToggle(
                        level: level,
                        isActive: logStore.activeLevels.contains(level),
                        action: { logStore.toggleLevel(level) }
                    )
                }

                Spacer()

                // Entry count
                Text("\(logStore.filteredEntries.count) / \(logStore.entries.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                // Auto-scroll indicator
                Button {
                    autoScroll.toggle()
                } label: {
                    Image(systemName: autoScroll ? "arrow.down.to.line" : "pause")
                        .font(.caption)
                        .foregroundStyle(autoScroll ? .blue : .secondary)
                }
                .buttonStyle(.plain)
                .help(autoScroll ? "Auto-scroll on (click to pause)" : "Auto-scroll paused (click to resume)")

                // Clear button
                Button {
                    logStore.clear()
                    expandedEntries.removeAll()
                    prettyJSONCache.clear()
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear all logs")
            }

            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Filter logs...", text: Binding(
                    get: { logStore.searchText },
                    set: { logStore.searchText = $0 }
                ))
                .textFieldStyle(.plain)

                if !logStore.searchText.isEmpty {
                    Button {
                        logStore.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(6)
            .background(.quaternary)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Log List

    @ViewBuilder
    private var logList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(logStore.filteredEntries) { entry in
                        LogRowView(
                            entry: entry,
                            isExpanded: expandedEntries.contains(entry.id),
                            prettyJSONCache: prettyJSONCache,
                            onToggleExpand: {
                                if expandedEntries.contains(entry.id) {
                                    expandedEntries.remove(entry.id)
                                } else {
                                    expandedEntries.insert(entry.id)
                                }
                            }
                        )
                        .id(entry.id)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 1)
                    }
                }
            }
            .font(.system(.body, design: .monospaced))
            .onChange(of: logStore.filteredEntries.count) {
                if autoScroll, let lastEntry = logStore.filteredEntries.last {
                    withAnimation(.easeOut(duration: 0.1)) {
                        proxy.scrollTo(lastEntry.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: autoScroll) {
                if autoScroll, let lastEntry = logStore.filteredEntries.last {
                    withAnimation(.easeOut(duration: 0.1)) {
                        proxy.scrollTo(lastEntry.id, anchor: .bottom)
                    }
                }
            }
        }
    }
}

// MARK: - Log Row

/// Thread-safe cache for pretty-printed JSON strings keyed by log entry ID.
final class PrettyJSONCache {
    private var cache: [UUID: String] = [:]
    private let lock = NSLock()

    func get(_ id: UUID, rawJSON: String) -> String {
        lock.lock()
        if let cached = cache[id] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let result: String
        if let data = rawJSON.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data),
           let pretty = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
           let str = String(data: pretty, encoding: .utf8) {
            result = str
        } else {
            result = rawJSON
        }

        lock.lock()
        cache[id] = result
        lock.unlock()
        return result
    }

    func clear() {
        lock.lock()
        cache.removeAll()
        lock.unlock()
    }
}

/// A single log entry row with timestamp, level badge, message, and expandable JSON.
private struct LogRowView: View {
    let entry: LogEntry
    let isExpanded: Bool
    let prettyJSONCache: PrettyJSONCache
    let onToggleExpand: () -> Void

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                // Timestamp
                Text(Self.timeFormatter.string(from: entry.timestamp))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 85, alignment: .leading)

                // Level badge
                LevelBadge(level: entry.level)

                // Message
                Text(entry.message)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(isExpanded ? nil : 1)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Expand/collapse if there's raw JSON to show
                if !entry.extra.isEmpty || entry.rawJSON.contains("{") {
                    Button {
                        onToggleExpand()
                    } label: {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Expanded JSON details
            if isExpanded {
                Text(prettyJSON)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .padding(.leading, 91) // align under message
                    .padding(.top, 2)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture {
            if !entry.extra.isEmpty || entry.rawJSON.contains("{") {
                onToggleExpand()
            }
        }
    }

    private var prettyJSON: String {
        prettyJSONCache.get(entry.id, rawJSON: entry.rawJSON)
    }
}

// MARK: - Level Badge

/// Color-coded pill badge for a log level.
private struct LevelBadge: View {
    let level: LogEntry.LogLevel

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: level.sfSymbol)
                .font(.system(size: 8))
            Text(level.displayName)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
        }
        .foregroundStyle(level.color)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(level.color.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .frame(width: 70, alignment: .center)
    }
}

// MARK: - Level Toggle

/// Toolbar toggle button for a log level filter.
private struct LevelToggle: View {
    let level: LogEntry.LogLevel
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(level.displayName)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(isActive ? level.color : .secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(isActive ? level.color.opacity(0.15) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(isActive ? level.color.opacity(0.3) : Color.secondary.opacity(0.2), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}
