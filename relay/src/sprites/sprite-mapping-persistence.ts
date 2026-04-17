// Sprite mapping persistence — saves/loads sprite-agent mappings to ~/.major-tom/sprite-mappings/
// Mirrors the pattern in sessions/session-persistence.ts

import { readdir, readFile, writeFile, unlink, mkdir } from 'node:fs/promises';
import { join } from 'node:path';
import { homedir } from 'node:os';
import { logger } from '../utils/logger.js';

// ── Persisted data schema ──────────────────────────────────

export interface PersistedSpriteMapping {
  spriteHandle: string;
  agentId: string;
  role: string;
  characterType: string;
  deskIndex: number;
  linkedAt: string;
}

export interface PersistedSpriteMappingFile {
  version: 1;
  sessionId: string;
  updatedAt: string;
  roleBindings: Record<string, string>;
  mappings: PersistedSpriteMapping[];
  nextDeskIndex: number;
}

// ── Constants ──────────────────────────────────────────────

const MAPPINGS_DIR = join(homedir(), '.major-tom', 'sprite-mappings');
const DEBOUNCE_MS = 2000;

// ── SpriteMappingPersistence ───────────────────────────────

export class SpriteMappingPersistence {
  private debounceTimers = new Map<string, ReturnType<typeof setTimeout>>();

  constructor() {
    void this.ensureDir();
  }

  private async ensureDir(): Promise<void> {
    try {
      await mkdir(MAPPINGS_DIR, { recursive: true });
    } catch (err) {
      logger.error({ err }, 'Failed to create sprite-mappings directory');
    }
  }

  private filePath(sessionId: string): string {
    // Sanitize sessionId to prevent path traversal (same as SessionPersistence)
    const safe = sessionId.replace(/[^a-zA-Z0-9\-]/g, '');
    if (!safe || safe !== sessionId) {
      throw new Error(`Invalid session ID for sprite mapping: ${sessionId}`);
    }
    return join(MAPPINGS_DIR, `${safe}.json`);
  }

  /** Debounced save -- waits 2s after last call before writing */
  save(data: PersistedSpriteMappingFile): void {
    const existing = this.debounceTimers.get(data.sessionId);
    if (existing) clearTimeout(existing);

    const timer = setTimeout(() => {
      this.debounceTimers.delete(data.sessionId);
      void this.writeToDisk(data);
    }, DEBOUNCE_MS);

    this.debounceTimers.set(data.sessionId, timer);
  }

  /** Immediate save -- bypasses debounce (for shutdown / critical updates) */
  async saveImmediate(data: PersistedSpriteMappingFile): Promise<void> {
    const existing = this.debounceTimers.get(data.sessionId);
    if (existing) {
      clearTimeout(existing);
      this.debounceTimers.delete(data.sessionId);
    }
    await this.writeToDisk(data);
  }

  private async writeToDisk(data: PersistedSpriteMappingFile): Promise<void> {
    try {
      await this.ensureDir();
      const json = JSON.stringify(data, null, 2);
      await writeFile(this.filePath(data.sessionId), json, 'utf-8');
      logger.debug({ sessionId: data.sessionId, mappingCount: data.mappings.length }, 'Sprite mapping persisted to disk');
    } catch (err) {
      logger.error({ err, sessionId: data.sessionId }, 'Failed to persist sprite mapping');
    }
  }

  async load(sessionId: string): Promise<PersistedSpriteMappingFile | null> {
    try {
      const raw = await readFile(this.filePath(sessionId), 'utf-8');
      const parsed = JSON.parse(raw) as PersistedSpriteMappingFile;
      // Basic schema validation
      if (parsed.version !== 1 || !parsed.sessionId) {
        logger.warn({ sessionId }, 'Sprite mapping file has invalid schema — ignoring');
        return null;
      }
      return parsed;
    } catch {
      return null;
    }
  }

  async delete(sessionId: string): Promise<void> {
    // Cancel any pending debounced write for this session
    const existing = this.debounceTimers.get(sessionId);
    if (existing) {
      clearTimeout(existing);
      this.debounceTimers.delete(sessionId);
    }
    try {
      await unlink(this.filePath(sessionId));
      logger.info({ sessionId }, 'Sprite mapping file deleted');
    } catch {
      // File may not exist -- that's fine
    }
  }

  /** Delete all mapping files (relay graceful shutdown) */
  async deleteAll(): Promise<void> {
    try {
      await this.ensureDir();
      const files = await readdir(MAPPINGS_DIR);
      for (const file of files) {
        if (!file.endsWith('.json')) continue;
        try {
          await unlink(join(MAPPINGS_DIR, file));
        } catch {
          // Best effort
        }
      }
      logger.info('All sprite mapping files deleted (shutdown)');
    } catch {
      // Directory might not exist
    }
  }

  /**
   * List sessionIds that have persisted mapping files.
   * Used on cold boot to cross-reference against live sessions
   * and clean up stale files.
   */
  async listStale(isLiveSession: (sessionId: string) => boolean): Promise<string[]> {
    const stale: string[] = [];
    try {
      await this.ensureDir();
      const files = await readdir(MAPPINGS_DIR);
      for (const file of files) {
        if (!file.endsWith('.json')) continue;
        const sessionId = file.replace('.json', '');
        if (!isLiveSession(sessionId)) {
          stale.push(sessionId);
        }
      }
    } catch {
      // Directory might not exist
    }
    return stale;
  }

  /** Cancel all pending debounced writes */
  dispose(): void {
    for (const timer of this.debounceTimers.values()) {
      clearTimeout(timer);
    }
    this.debounceTimers.clear();
  }
}
