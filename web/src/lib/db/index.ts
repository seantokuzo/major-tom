// Major Tom IndexedDB database — Dexie.js wrapper
// Replaces localStorage for chat messages, templates, prompt history, and settings.

import Dexie, { type EntityTable, type Table } from 'dexie';

// ── Stored models ───────────────────────────────────────────

export interface DbMessage {
  /** Session this message belongs to */
  sessionId: string;
  /** In-app message ID (e.g. "msg-1-17...") */
  messageId: string;
  role: 'user' | 'assistant' | 'tool' | 'system';
  content: string;
  timestamp: string; // ISO 8601
  toolMeta?: {
    tool: string;
    input?: Record<string, unknown>;
    output?: string;
    success?: boolean;
  };
}

export interface DbSessionMeta {
  /** Session ID — primary key */
  sessionId: string;
  name?: string;
  dir?: string;
  cost?: number;
  tokens?: number;
  lastActive: string; // ISO 8601
}

export interface DbTemplate {
  /** Template ID — primary key (e.g. "tpl-1-17...") */
  id: string;
  name: string;
  content: string;
  category?: string;
  usageCount: number;
  createdAt: string; // ISO 8601
  updatedAt: string; // ISO 8601
}

export interface DbPromptHistory {
  /** Auto-incremented primary key */
  id?: number;
  text: string;
  timestamp: string; // ISO 8601
  count: number;
}

export interface DbSetting {
  /** Setting key — primary key (e.g. "commandUsage") */
  key: string;
  value: unknown;
}

// ── Database class ──────────────────────────────────────────

class MajorTomDB extends Dexie {
  messages!: Table<DbMessage, [string, string]>;
  sessionMeta!: EntityTable<DbSessionMeta, 'sessionId'>;
  templates!: EntityTable<DbTemplate, 'id'>;
  promptHistory!: EntityTable<DbPromptHistory, 'id'>;
  settings!: EntityTable<DbSetting, 'key'>;

  constructor() {
    super('MajorTomDB');

    this.version(1).stores({
      // ++id = auto-increment PK, [sessionId+messageId] = compound index for per-session lookups
      messages: '++id, [sessionId+messageId], sessionId, timestamp',
      sessionMeta: 'sessionId, lastActive',
      templates: 'id, name, category, updatedAt',
      promptHistory: '++id, text, timestamp',
      settings: 'key',
    });

    // v2: promote [sessionId+messageId] to primary key so bulkPut upserts correctly
    this.version(2).stores({
      messages: '[sessionId+messageId], sessionId, timestamp',
    });
  }
}

// Singleton instance
export const db = new MajorTomDB();

// ── Migration helpers ───────────────────────────────────────

const MIGRATION_FLAGS = {
  messages: 'mt-idb-migrated-messages',
  templates: 'mt-idb-migrated-templates',
  promptHistory: 'mt-idb-migrated-prompt-history',
  commandUsage: 'mt-idb-migrated-command-usage',
} as const;

/**
 * Migrate localStorage data to IndexedDB on first load.
 * Each migration only runs once (tracked by a localStorage flag).
 * After successful migration, the original localStorage key is removed.
 */
export async function migrateFromLocalStorage(): Promise<void> {
  if (typeof window === 'undefined') return;

  const results = await Promise.allSettled([
    migrateMessages(),
    migrateTemplates(),
    migratePromptHistory(),
    migrateCommandUsage(),
  ]);

  for (const result of results) {
    if (result.status === 'rejected') {
      console.warn('[MajorTom DB] Migration task failed:', result.reason);
    }
  }
}

async function migrateMessages(): Promise<void> {
  const flag = MIGRATION_FLAGS.messages;
  if (localStorage.getItem(flag)) return;

  const raw = localStorage.getItem('mt-chat-messages');
  if (!raw) {
    localStorage.setItem(flag, '1');
    return;
  }

  try {
    const parsed = JSON.parse(raw) as Array<{
      id: string;
      role: 'user' | 'assistant' | 'tool' | 'system';
      content: string;
      timestamp: string;
      toolMeta?: { tool: string; input?: Record<string, unknown>; output?: string; success?: boolean };
    }>;

    if (Array.isArray(parsed) && parsed.length > 0) {
      // Use the stored session ID to key messages, or a fallback
      const sessionId = localStorage.getItem('mt-session-id') || '__migrated__';

      const rows: DbMessage[] = parsed.map((m) => ({
        sessionId,
        messageId: m.id,
        role: m.role,
        content: m.content,
        timestamp: m.timestamp,
        ...(m.toolMeta ? { toolMeta: m.toolMeta } : {}),
      }));

      await db.messages.bulkPut(rows);
    }

    localStorage.removeItem('mt-chat-messages');
    localStorage.setItem(flag, '1');
    console.log(`[MajorTom DB] Migrated ${parsed.length} messages from localStorage`);
  } catch (e) {
    console.warn('[MajorTom DB] Failed to migrate messages:', e);
  }
}

async function migrateTemplates(): Promise<void> {
  const flag = MIGRATION_FLAGS.templates;
  if (localStorage.getItem(flag)) return;

  const raw = localStorage.getItem('mt-prompt-templates');
  if (!raw) {
    localStorage.setItem(flag, '1');
    return;
  }

  try {
    const parsed = JSON.parse(raw);
    if (Array.isArray(parsed) && parsed.length > 0) {
      const rows: DbTemplate[] = parsed
        .filter(
          (entry: unknown): entry is Record<string, unknown> =>
            typeof entry === 'object' &&
            entry !== null &&
            typeof (entry as Record<string, unknown>).name === 'string' &&
            typeof (entry as Record<string, unknown>).content === 'string',
        )
        .map((entry) => {
          const now = new Date().toISOString();
          const id = typeof entry.id === 'string' && entry.id ? entry.id : `tpl-mig-${Date.now()}-${Math.random().toString(36).slice(2)}`;
          const cat = typeof entry.category === 'string' ? entry.category.trim() : undefined;
          const rawCount = typeof entry.usageCount === 'number' ? entry.usageCount : 0;
          const usageCount = Number.isFinite(rawCount) && rawCount >= 0 ? rawCount : 0;
          return {
            id,
            name: entry.name as string,
            content: entry.content as string,
            category: cat || undefined,
            usageCount,
            createdAt: typeof entry.createdAt === 'string' ? entry.createdAt : now,
            updatedAt: typeof entry.updatedAt === 'string' ? entry.updatedAt : now,
          };
        });

      await db.templates.bulkPut(rows);
    }

    localStorage.removeItem('mt-prompt-templates');
    localStorage.setItem(flag, '1');
    console.log(`[MajorTom DB] Migrated templates from localStorage`);
  } catch (e) {
    console.warn('[MajorTom DB] Failed to migrate templates:', e);
  }
}

async function migratePromptHistory(): Promise<void> {
  const flag = MIGRATION_FLAGS.promptHistory;
  if (localStorage.getItem(flag)) return;

  const raw = localStorage.getItem('mt-prompt-history');
  if (!raw) {
    localStorage.setItem(flag, '1');
    return;
  }

  try {
    const parsed = JSON.parse(raw);
    if (Array.isArray(parsed) && parsed.length > 0) {
      const rows: DbPromptHistory[] = parsed
        .filter((item: unknown): item is { text: string; timestamp: string; count: number } => {
          if (typeof item !== 'object' || item === null) return false;
          const c = item as { text?: unknown; timestamp?: unknown; count?: unknown };
          return typeof c.text === 'string' && typeof c.timestamp === 'string' && typeof c.count === 'number';
        })
        .map((item) => ({
          text: item.text,
          timestamp: item.timestamp,
          count: item.count,
        }));

      await db.promptHistory.bulkAdd(rows);
    }

    localStorage.removeItem('mt-prompt-history');
    localStorage.setItem(flag, '1');
    console.log(`[MajorTom DB] Migrated prompt history from localStorage`);
  } catch (e) {
    console.warn('[MajorTom DB] Failed to migrate prompt history:', e);
  }
}

async function migrateCommandUsage(): Promise<void> {
  const flag = MIGRATION_FLAGS.commandUsage;
  if (localStorage.getItem(flag)) return;

  const raw = localStorage.getItem('mt-command-usage');
  if (!raw) {
    localStorage.setItem(flag, '1');
    return;
  }

  try {
    const parsed = JSON.parse(raw);
    if (typeof parsed === 'object' && parsed !== null) {
      await db.settings.put({ key: 'commandUsage', value: parsed });
    }

    localStorage.removeItem('mt-command-usage');
    localStorage.setItem(flag, '1');
    console.log(`[MajorTom DB] Migrated command usage from localStorage`);
  } catch (e) {
    console.warn('[MajorTom DB] Failed to migrate command usage:', e);
  }
}

// ── TTL Purging ─────────────────────────────────────────────

const DEFAULT_TTL_DAYS = 30;

/**
 * Purge messages and sessionMeta older than the configured TTL.
 * Templates and prompt history are user-created content and are NOT purged.
 * Runs on app startup.
 */
export async function purgeOldData(ttlDays: number = DEFAULT_TTL_DAYS): Promise<void> {
  if (typeof window === 'undefined') return;

  const cutoff = new Date();
  cutoff.setDate(cutoff.getDate() - ttlDays);
  const cutoffIso = cutoff.toISOString();

  try {
    // Purge old messages
    const oldMessages = await db.messages
      .where('timestamp')
      .below(cutoffIso)
      .count();

    if (oldMessages > 0) {
      await db.messages
        .where('timestamp')
        .below(cutoffIso)
        .delete();
      console.log(`[MajorTom DB] Purged ${oldMessages} messages older than ${ttlDays} days`);
    }

    // Purge old session metadata
    const oldSessions = await db.sessionMeta
      .where('lastActive')
      .below(cutoffIso)
      .count();

    if (oldSessions > 0) {
      await db.sessionMeta
        .where('lastActive')
        .below(cutoffIso)
        .delete();
      console.log(`[MajorTom DB] Purged ${oldSessions} session metadata entries older than ${ttlDays} days`);
    }

    if (oldMessages === 0 && oldSessions === 0) {
      console.log(`[MajorTom DB] No stale data to purge (TTL: ${ttlDays} days)`);
    }
  } catch (e) {
    console.warn('[MajorTom DB] Purge failed:', e);
  }
}
