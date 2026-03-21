// Prompt template store — reactive state for saved prompt templates
// Uses Svelte 5 runes ($state, $derived)

const STORAGE_KEY = 'mt-prompt-templates';
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
    this.loadFromStorage();
  }

  // ── Persistence ───────────────────────────────────────────

  private loadFromStorage(): void {
    if (typeof window === 'undefined') return;
    try {
      const raw = localStorage.getItem(STORAGE_KEY);
      if (raw) {
        const parsed = JSON.parse(raw);
        if (Array.isArray(parsed)) {
          const now = new Date().toISOString();
          this.templates = parsed
            .filter(
              (entry: unknown): entry is Record<string, unknown> =>
                typeof entry === 'object' &&
                entry !== null &&
                typeof (entry as Record<string, unknown>).name === 'string' &&
                typeof (entry as Record<string, unknown>).content === 'string'
            )
            .map((entry) => ({
              id: typeof entry.id === 'string' ? entry.id : uid(),
              name: entry.name as string,
              content: entry.content as string,
              category: typeof entry.category === 'string' ? entry.category : undefined,
              usageCount: typeof entry.usageCount === 'number' ? entry.usageCount : 0,
              createdAt: typeof entry.createdAt === 'string' ? entry.createdAt : now,
              updatedAt: typeof entry.updatedAt === 'string' ? entry.updatedAt : now,
            }))
            .slice(0, MAX_TEMPLATES);
        }
      }
    } catch {
      // Corrupted data — start fresh
    }
  }

  private persist(): void {
    if (typeof window === 'undefined') return;
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(this.templates));
    } catch {
      // localStorage unavailable or quota exceeded
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
