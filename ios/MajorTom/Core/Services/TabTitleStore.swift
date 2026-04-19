import Foundation

/// Shared single-source-of-truth for user-supplied terminal-tab titles.
///
/// Bidirectional rename: the terminal tab bar and the Office Manager both
/// read and write through this store, so renaming from either side is
/// reflected everywhere immediately.
///
/// Storage format: `[tabId: userTitle]` in UserDefaults under
/// `mt-terminal-tab-user-titles` (same key the terminal used previously,
/// so existing user renames survive the refactor).
@MainActor
@Observable
final class TabTitleStore {
    private static let defaultsKey = "mt-terminal-tab-user-titles"

    /// User-supplied titles keyed by tabId. Empty string / nil is never
    /// persisted — absence from the dictionary means "fall back to the
    /// shell-supplied or relay-supplied name."
    private(set) var titles: [String: String]

    init() {
        let raw = UserDefaults.standard.dictionary(forKey: Self.defaultsKey) as? [String: String]
        self.titles = raw ?? [:]
    }

    /// Returns the user-supplied title for `tabId`, or nil if none set.
    func title(for tabId: String) -> String? {
        titles[tabId]
    }

    /// Upsert or clear the user title for `tabId`. Passing nil or an
    /// empty/whitespace string clears the override.
    func setTitle(_ newTitle: String?, for tabId: String) {
        let trimmed = newTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let t = trimmed, !t.isEmpty {
            titles[tabId] = t
        } else {
            titles.removeValue(forKey: tabId)
        }
        persist()
    }

    /// Drop all entries for tabIds that no longer exist. Called when
    /// TerminalViewModel prunes its tab list.
    func prune(keeping validTabIds: Set<String>) {
        let before = titles.count
        titles = titles.filter { validTabIds.contains($0.key) }
        if titles.count != before {
            persist()
        }
    }

    private func persist() {
        let defaults = UserDefaults.standard
        if titles.isEmpty {
            defaults.removeObject(forKey: Self.defaultsKey)
        } else {
            defaults.set(titles, forKey: Self.defaultsKey)
        }
    }
}
