// Session persistence — saves/loads session data to ~/.major-tom/sessions/

import { readdir, readFile, writeFile, unlink, mkdir } from 'node:fs/promises';
import { join } from 'node:path';
import { homedir } from 'node:os';
import { logger } from '../utils/logger.js';
import type { SessionMeta } from './session.js';
import type { TranscriptEntry } from './session-transcript.js';

export interface PersistedSession {
  id: string;
  adapter: string;
  workingDir: string;
  status: string;
  startedAt: string;
  metadata: SessionMeta;
  transcript: TranscriptEntry[];
}

export type PersistedSessionMeta = Omit<PersistedSession, 'transcript'>;

const SESSIONS_DIR = join(homedir(), '.major-tom', 'sessions');
const DEBOUNCE_MS = 2000;

export class SessionPersistence {
  private debounceTimers = new Map<string, ReturnType<typeof setTimeout>>();

  constructor() {
    // Ensure sessions directory exists on construction
    void this.ensureDir();
  }

  private async ensureDir(): Promise<void> {
    try {
      await mkdir(SESSIONS_DIR, { recursive: true });
    } catch (err) {
      logger.error({ err }, 'Failed to create sessions directory');
    }
  }

  private filePath(sessionId: string): string {
    // Sanitize sessionId to prevent path traversal
    const safe = sessionId.replace(/[^a-zA-Z0-9\-]/g, '');
    if (!safe || safe !== sessionId) {
      throw new Error(`Invalid session ID: ${sessionId}`);
    }
    return join(SESSIONS_DIR, `${safe}.json`);
  }

  /** Debounced save — waits 2s after last call before writing */
  save(session: PersistedSession): void {
    const existing = this.debounceTimers.get(session.id);
    if (existing) clearTimeout(existing);

    const timer = setTimeout(() => {
      this.debounceTimers.delete(session.id);
      void this.writeToDisk(session);
    }, DEBOUNCE_MS);

    this.debounceTimers.set(session.id, timer);
  }

  /** Immediate save — bypasses debounce (for shutdown) */
  async saveImmediate(session: PersistedSession): Promise<void> {
    const existing = this.debounceTimers.get(session.id);
    if (existing) {
      clearTimeout(existing);
      this.debounceTimers.delete(session.id);
    }
    await this.writeToDisk(session);
  }

  private async writeToDisk(session: PersistedSession): Promise<void> {
    try {
      await this.ensureDir();
      const data = JSON.stringify(session, null, 2);
      await writeFile(this.filePath(session.id), data, 'utf-8');
      logger.debug({ sessionId: session.id }, 'Session persisted to disk');
    } catch (err) {
      logger.error({ err, sessionId: session.id }, 'Failed to persist session');
    }
  }

  async load(sessionId: string): Promise<PersistedSession | null> {
    try {
      const data = await readFile(this.filePath(sessionId), 'utf-8');
      return JSON.parse(data) as PersistedSession;
    } catch {
      return null;
    }
  }

  async listPersisted(): Promise<PersistedSessionMeta[]> {
    try {
      await this.ensureDir();
      const files = await readdir(SESSIONS_DIR);
      const metas: PersistedSessionMeta[] = [];

      for (const file of files) {
        if (!file.endsWith('.json')) continue;
        try {
          const data = await readFile(join(SESSIONS_DIR, file), 'utf-8');
          const parsed = JSON.parse(data) as PersistedSession;
          // Return without transcript for listing efficiency
          const { transcript: _, ...meta } = parsed;
          metas.push(meta);
        } catch {
          // Skip corrupt files
          logger.warn({ file }, 'Skipping corrupt session file');
        }
      }

      return metas;
    } catch {
      return [];
    }
  }

  async delete(sessionId: string): Promise<void> {
    try {
      await unlink(this.filePath(sessionId));
      logger.info({ sessionId }, 'Persisted session deleted');
    } catch {
      // File may not exist — that's fine
    }
  }

  /** Flush all pending debounced writes immediately (call before dispose) */
  async saveAllImmediate(buildSession: (id: string) => PersistedSession | null): Promise<void> {
    const pendingIds = [...this.debounceTimers.keys()];
    for (const id of pendingIds) {
      const timer = this.debounceTimers.get(id);
      if (timer) clearTimeout(timer);
      this.debounceTimers.delete(id);
      const session = buildSession(id);
      if (session) {
        await this.writeToDisk(session);
      }
    }
  }

  /** Cancel all pending debounced writes */
  dispose(): void {
    for (const timer of this.debounceTimers.values()) {
      clearTimeout(timer);
    }
    this.debounceTimers.clear();
  }
}
