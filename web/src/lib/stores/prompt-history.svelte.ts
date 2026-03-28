// Prompt history store — deduplicated history with arrow-key navigation and search
// Uses Svelte 5 runes ($state)
// Persisted via IndexedDB (Dexie)

import { db, migrationReady, type DbPromptHistory } from '../db';

const MAX_ENTRIES = 200;

// ── History entry model ─────────────────────────────────────

export interface HistoryEntry {
  text: string;
  timestamp: string;
  count: number;
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
    this.loadFromDb();
  }

  // ── Persistence (IndexedDB) ────────────────────────────────

  private async loadFromDb(): Promise<void> {
    if (typeof window === 'undefined') return;
    await migrationReady;
    try {
      const rows = await db.promptHistory.toArray();
      if (rows.length > 0) {
        // Sort by timestamp descending (most recent first) to match the old LIFO behavior
        const sorted = rows
          .filter((r) => typeof r.text === 'string' && typeof r.timestamp === 'string')
          .sort((a, b) => b.timestamp.localeCompare(a.timestamp))
          .slice(0, MAX_ENTRIES);

        this.entries = sorted.map((r) => ({
          text: r.text,
          timestamp: r.timestamp,
          count: r.count,
        }));
      }
    } catch {
      // IndexedDB unavailable — start fresh
    }
  }

  /** Serialized persistence — each call chains on the previous to prevent overlapping transactions */
  private persistChain: Promise<void> = Promise.resolve();

  private persistToDb(): void {
    this.persistChain = this.persistChain.then(() => this.doPersistToDb()).catch(() => {});
  }

  private async doPersistToDb(): Promise<void> {
    if (typeof window === 'undefined') return;
    try {
      const rows: Omit<DbPromptHistory, 'id'>[] = this.entries.map((e) => ({
        text: e.text,
        timestamp: e.timestamp,
        count: e.count,
      }));
      await db.transaction('rw', db.promptHistory, async () => {
        await db.promptHistory.clear();
        if (rows.length > 0) {
          await db.promptHistory.bulkAdd(rows);
        }
      });
    } catch {
      // IndexedDB unavailable — degrade gracefully
    }
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

    this.persistToDb();
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
    this.persistToDb();
    this.resetNavigation();
  }
}

// Singleton instance
export const promptHistory = new PromptHistoryStore();
