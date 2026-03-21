// Prompt history store — deduplicated history with arrow-key navigation and search
// Uses Svelte 5 runes ($state)

const STORAGE_KEY = 'mt-prompt-history';
const MAX_ENTRIES = 200;

// ── History entry model ─────────────────────────────────────

export interface HistoryEntry {
  text: string;
  timestamp: string;
  count: number;
}

// ── Serialization helpers ───────────────────────────────────

function loadFromStorage(): HistoryEntry[] {
  if (typeof window === 'undefined') return [];
  try {
    const json = localStorage.getItem(STORAGE_KEY);
    if (!json) return [];
    const parsed = JSON.parse(json);
    if (!Array.isArray(parsed)) return [];
    const entries = parsed
      .filter((item: unknown): item is HistoryEntry => {
        if (typeof item !== 'object' || item === null) return false;
        const c = item as { text?: unknown; timestamp?: unknown; count?: unknown };
        return typeof c.text === 'string' && typeof c.timestamp === 'string'
          && typeof c.count === 'number' && Number.isFinite(c.count);
      })
      .slice(0, MAX_ENTRIES);
    return entries;
  } catch {
    return [];
  }
}

function saveToStorage(entries: HistoryEntry[]): void {
  if (typeof window === 'undefined') return;
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(entries));
  } catch {
    // localStorage unavailable or quota exceeded — degrade gracefully
  }
}

// ── Prompt history store ────────────────────────────────────

class PromptHistoryStore {
  entries = $state<HistoryEntry[]>([]);

  /** Current navigation index. -1 = not navigating (user is typing fresh input) */
  private navIndex = -1;
  /** Saved input text before navigation started */
  private savedInput = '';
  /** Whether we're currently in navigation mode */
  private navigating = false;

  constructor() {
    this.entries = loadFromStorage();
  }

  // ── Mutations ─────────────────────────────────────────────

  /** Add a prompt to history. Deduplicates: same text updates timestamp + count. */
  add(text: string): void {
    const trimmed = text.trim();
    if (!trimmed) return;

    const existingIndex = this.entries.findIndex((e) => e.text === trimmed);

    if (existingIndex >= 0) {
      // Deduplicate: update timestamp + increment count, move to front
      const existing = this.entries[existingIndex];
      const updated: HistoryEntry = {
        text: existing.text,
        timestamp: new Date().toISOString(),
        count: existing.count + 1,
      };
      this.entries.splice(existingIndex, 1);
      this.entries.unshift(updated);
    } else {
      // New entry at front
      this.entries.unshift({
        text: trimmed,
        timestamp: new Date().toISOString(),
        count: 1,
      });

      // FIFO eviction when over max
      if (this.entries.length > MAX_ENTRIES) {
        this.entries.length = MAX_ENTRIES;
      }
    }

    this.persist();
    this.resetNavigation();
  }

  /** Search history entries by case-insensitive substring match. */
  search(query: string): HistoryEntry[] {
    const q = query.toLowerCase().trim();
    if (!q) return this.entries;
    return this.entries.filter((e) => e.text.toLowerCase().includes(q));
  }

  /**
   * Navigate through history (arrow-up / arrow-down).
   * Returns the entry text to display, or null if at the end of navigation.
   */
  navigate(direction: 'up' | 'down', currentInput: string): string | null {
    if (this.entries.length === 0) return null;

    if (!this.navigating) {
      if (direction === 'down') return null; // Can't go down if not navigating
      // Start navigating — save current input
      this.navigating = true;
      this.savedInput = currentInput;
      this.navIndex = 0;
      return this.entries[0].text;
    }

    if (direction === 'up') {
      const nextIndex = this.navIndex + 1;
      if (nextIndex >= this.entries.length) return this.entries[this.navIndex].text; // Already at oldest
      this.navIndex = nextIndex;
      return this.entries[this.navIndex].text;
    } else {
      // direction === 'down'
      const nextIndex = this.navIndex - 1;
      if (nextIndex < 0) {
        // Back to user's original input
        this.navigating = false;
        this.navIndex = -1;
        return this.savedInput;
      }
      this.navIndex = nextIndex;
      return this.entries[this.navIndex].text;
    }
  }

  /** Reset navigation state (called when user types). */
  resetNavigation(): void {
    this.navigating = false;
    this.navIndex = -1;
    this.savedInput = '';
  }

  /** Whether currently navigating through history. */
  get isNavigating(): boolean {
    return this.navigating;
  }

  /** Clear all history entries. */
  clear(): void {
    this.entries = [];
    this.persist();
    this.resetNavigation();
  }

  // ── Persistence ───────────────────────────────────────────

  private persist(): void {
    saveToStorage(this.entries);
  }
}

// Singleton instance
export const promptHistory = new PromptHistoryStore();
