// Prompt template store — reactive state for saved prompt templates
// Uses Svelte 5 runes ($state, $derived)
// Persisted via IndexedDB (Dexie)

import { db, type DbTemplate } from '../db';

const MAX_TEMPLATES = 100;

// ── Template model ──────────────────────────────────────────

export interface PromptTemplate {
  id: string;
  name: string;
  content: string;
  category?: string;
  usageCount: number;
  createdAt: string;
  updatedAt: string;
}

// ── Template store ──────────────────────────────────────────

let nextId = 0;
function uid(): string {
  return `tpl-${++nextId}-${Date.now()}`;
}

class TemplateStore {
  templates = $state<PromptTemplate[]>([]);

  /** Serialization chain — ensures only one persist runs at a time */
  private persistChain: Promise<void> = Promise.resolve();

  /** All unique categories from existing templates */
  categories = $derived(
    [...new Set(this.templates.map((t) => t.category).filter(Boolean))] as string[]
  );

  /** Templates sorted by usage count (most-used first), then by name */
  sorted = $derived(
    [...this.templates].sort((a, b) => {
      if (b.usageCount !== a.usageCount) return b.usageCount - a.usageCount;
      return a.name.localeCompare(b.name);
    })
  );

  constructor() {
    this.loadFromDb();
  }

  // ── Persistence (IndexedDB) ────────────────────────────────

  private async loadFromDb(): Promise<void> {
    if (typeof window === 'undefined') return;
    try {
      const rows = await db.templates.toArray();
      if (rows.length > 0) {
        this.templates = rows.slice(0, MAX_TEMPLATES).map((row) => ({
          id: row.id,
          name: row.name,
          content: row.content,
          category: row.category,
          usageCount: row.usageCount,
          createdAt: row.createdAt,
          updatedAt: row.updatedAt,
        }));
      }
    } catch {
      // IndexedDB unavailable — start fresh
    }
  }

  private persist(): void {
    // Chain persists so overlapping calls don't race (clear + bulkPut is not atomic across calls)
    this.persistChain = this.persistChain.then(() => this.doPersist()).catch(() => {});
  }

  private async doPersist(): Promise<void> {
    if (typeof window === 'undefined') return;
    try {
      const rows: DbTemplate[] = this.templates.map((t) => ({
        id: t.id,
        name: t.name,
        content: t.content,
        category: t.category,
        usageCount: t.usageCount,
        createdAt: t.createdAt,
        updatedAt: t.updatedAt,
      }));
      await db.transaction('rw', db.templates, async () => {
        await db.templates.clear();
        if (rows.length > 0) {
          await db.templates.bulkPut(rows);
        }
      });
    } catch {
      // IndexedDB unavailable or quota exceeded
    }
  }

  // ── CRUD ──────────────────────────────────────────────────

  add(name: string, content: string, category?: string): PromptTemplate | null {
    if (this.templates.length >= MAX_TEMPLATES) {
      return null; // Caller should warn user
    }

    const now = new Date().toISOString();
    const template: PromptTemplate = {
      id: uid(),
      name: name.trim(),
      content: content.trim(),
      category: category?.trim() || undefined,
      usageCount: 0,
      createdAt: now,
      updatedAt: now,
    };

    this.templates.push(template);
    this.persist();
    return template;
  }

  update(id: string, updates: Partial<Pick<PromptTemplate, 'name' | 'content' | 'category'>>): boolean {
    const template = this.templates.find((t) => t.id === id);
    if (!template) return false;

    if (updates.name !== undefined) template.name = updates.name.trim();
    if (updates.content !== undefined) template.content = updates.content.trim();
    if (updates.category !== undefined) template.category = updates.category?.trim() || undefined;
    template.updatedAt = new Date().toISOString();

    this.persist();
    return true;
  }

  delete(id: string): boolean {
    const idx = this.templates.findIndex((t) => t.id === id);
    if (idx === -1) return false;

    this.templates.splice(idx, 1);
    this.persist();
    return true;
  }

  /** Record a usage and return the template */
  use(id: string): PromptTemplate | undefined {
    const template = this.templates.find((t) => t.id === id);
    if (!template) return undefined;

    template.usageCount++;
    template.updatedAt = new Date().toISOString();
    this.persist();
    return template;
  }

  // ── Search ────────────────────────────────────────────────

  search(query: string): PromptTemplate[] {
    const q = query.toLowerCase().trim();
    if (!q) return this.sorted;

    return this.sorted.filter(
      (t) =>
        t.name.toLowerCase().includes(q) ||
        t.content.toLowerCase().includes(q) ||
        (t.category && t.category.toLowerCase().includes(q))
    );
  }

  /** Check if at capacity */
  get atLimit(): boolean {
    return this.templates.length >= MAX_TEMPLATES;
  }

  get count(): number {
    return this.templates.length;
  }
}

// Singleton instance
export const templates = new TemplateStore();
