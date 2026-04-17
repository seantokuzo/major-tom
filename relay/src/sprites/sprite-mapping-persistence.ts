// Sprite mapping persistence — saves/loads sprite-agent mappings to ~/.major-tom/sprite-mappings/
// Mirrors the pattern in sessions/session-persistence.ts
//
// Wave 6 — persistence cascade hardening.
//
// The resolution cascade (spec: "Relay Persistence & Cascade Fallback"):
//   1. Relay-authoritative (disk file) — primary source of truth.
//   2. Client-authoritative (iOS re-sends its mappings) — first fallback.
//   3. Best-effort rebuild (fresh allocation from current agent state) — always works.
//
// Failure modes this file guards against:
//   - Mapping file missing (ENOENT)        → `load()` returns null silently (expected: new session).
//   - Mapping file corrupt / garbage bytes → `load()` returns null + logs WARN so operators
//                                            notice; caller falls through to client-authoritative.
//   - Mapping file has wrong schema        → same as corrupt.
//   - Disk full during write (ENOSPC)      → `writeToDisk()` logs ERROR but does NOT throw. The
//                                            in-memory mapping survives, so on next client
//                                            reconnect iOS's re-sent mappings fill the gap
//                                            (client-authoritative resolution).
//   - Other I/O errors during write        → same as ENOSPC (logged, not thrown).
//
// Tests live in `__tests__/sprite-mapping-persistence.test.ts` + scenario tests in
// `__tests__/wave6-scenarios.test.ts`.

import {
  readdir,
  readFile,
  writeFile,
  unlink,
  mkdir,
} from 'node:fs/promises';
import { join } from 'node:path';
import { homedir } from 'node:os';
import { logger } from '../utils/logger.js';

// ── Persisted data schema ──────────────────────────────────

export interface PersistedSpriteMapping {
  spriteHandle: string;
  subagentId: string;
  canonicalRole: string;
  characterType: string;
  task: string;
  parentId?: string;
  deskIndex: number;
  linkedAt: string;
}

export interface PersistedSpriteMappingFile {
  version: 1;
  sessionId: string;
  updatedAt: string;
  roleBindings: Record<string, string>;
  mappings: PersistedSpriteMapping[];
}

// ── Constants ──────────────────────────────────────────────

const DEFAULT_MAPPINGS_DIR = join(homedir(), '.major-tom', 'sprite-mappings');
const DEBOUNCE_MS = 2000;

export interface SpriteMappingPersistenceOptions {
  /** Override the on-disk directory. Used by tests. */
  baseDir?: string;
  /** Inject filesystem operations. Used by tests to simulate ENOSPC / EIO / etc. */
  fs?: Partial<FsOps>;
}

export interface FsOps {
  readFile: typeof readFile;
  writeFile: typeof writeFile;
  readdir: typeof readdir;
  mkdir: typeof mkdir;
  unlink: typeof unlink;
}

const DEFAULT_FS: FsOps = { readFile, writeFile, readdir, mkdir, unlink };

/** Narrow a caught error to NodeJS.ErrnoException so we can read `.code`. */
function errnoCode(err: unknown): string | undefined {
  if (typeof err === 'object' && err !== null && 'code' in err) {
    const code = (err as { code: unknown }).code;
    if (typeof code === 'string') return code;
  }
  return undefined;
}

// ── SpriteMappingPersistence ───────────────────────────────

export class SpriteMappingPersistence {
  private debounceTimers = new Map<string, ReturnType<typeof setTimeout>>();
  private readonly mappingsDir: string;
  private readonly fs: FsOps;

  constructor(opts: SpriteMappingPersistenceOptions = {}) {
    this.mappingsDir = opts.baseDir ?? DEFAULT_MAPPINGS_DIR;
    this.fs = { ...DEFAULT_FS, ...opts.fs };
    void this.ensureDir();
  }

  private async ensureDir(): Promise<void> {
    try {
      await this.fs.mkdir(this.mappingsDir, { recursive: true });
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
    return join(this.mappingsDir, `${safe}.json`);
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

  /**
   * Serialize + write mapping file to disk.
   *
   * Wave 6 — never throws. The in-memory mapping is the primary source for
   * live clients; disk is an optimization for cold-reconnect. If the write
   * fails (disk full, permission, etc.) we log with enough detail for the
   * operator to diagnose, and let the next client reconnect repopulate via
   * iOS's client-authoritative cascade.
   */
  private async writeToDisk(data: PersistedSpriteMappingFile): Promise<boolean> {
    try {
      await this.ensureDir();
      const json = JSON.stringify(data, null, 2);
      await this.fs.writeFile(this.filePath(data.sessionId), json, 'utf-8');
      logger.debug(
        { sessionId: data.sessionId, mappingCount: data.mappings.length },
        'Sprite mapping persisted to disk',
      );
      return true;
    } catch (err) {
      const code = errnoCode(err);
      // ENOSPC (disk full) is the canonical degraded-disk failure the spec
      // calls out. Log it at ERROR with an explicit marker so operators
      // can grep for it, and make clear the cascade will take over.
      if (code === 'ENOSPC') {
        logger.error(
          { err, sessionId: data.sessionId, code },
          'Sprite mapping write failed: disk full (ENOSPC). ' +
            'In-memory mapping is preserved; client-authoritative fallback will rebuild on reconnect.',
        );
      } else {
        logger.error(
          { err, sessionId: data.sessionId, code },
          'Sprite mapping write failed. ' +
            'In-memory mapping is preserved; client-authoritative fallback will rebuild on reconnect.',
        );
      }
      return false;
    }
  }

  /**
   * Load a mapping file from disk.
   *
   * Returns:
   *   - `{...file}` when a valid file is present.
   *   - `null` when the file is missing (ENOENT — normal for a new session),
   *     unreadable (EACCES, EIO), or corrupt (parse error / schema mismatch).
   *
   * Wave 6: corrupt + unreadable cases are logged at WARN so operators see
   * them; missing is silent (it's the normal case). All failure modes fall
   * through to client-authoritative in ws.ts (iOS re-sends its mappings on
   * reconnect).
   */
  async load(sessionId: string): Promise<PersistedSpriteMappingFile | null> {
    let raw: string;
    try {
      raw = await this.fs.readFile(this.filePath(sessionId), 'utf-8');
    } catch (err) {
      const code = errnoCode(err);
      if (code === 'ENOENT') {
        // Expected: first load for a new session.
        return null;
      }
      // Real I/O problem (EACCES, EISDIR, EIO, ...). Log with enough detail
      // that operators can diagnose, and return null so caller falls through
      // to client-authoritative.
      logger.warn(
        { err, sessionId, code },
        'Sprite mapping read failed — falling through to client-authoritative',
      );
      return null;
    }

    let parsed: unknown;
    try {
      parsed = JSON.parse(raw);
    } catch (err) {
      // File exists but contents are not valid JSON (corruption on disk,
      // partial-write from a previous crash, manual tampering, ...).
      logger.warn(
        { err, sessionId },
        'Sprite mapping file contains invalid JSON — ignoring, client-authoritative fallback will rebuild',
      );
      return null;
    }

    if (
      typeof parsed !== 'object' ||
      parsed === null ||
      (parsed as { version?: unknown }).version !== 1 ||
      typeof (parsed as { sessionId?: unknown }).sessionId !== 'string'
    ) {
      logger.warn(
        { sessionId },
        'Sprite mapping file has invalid schema — ignoring, client-authoritative fallback will rebuild',
      );
      return null;
    }
    const file = parsed as PersistedSpriteMappingFile;

    if (!Array.isArray(file.mappings)) {
      logger.warn(
        { sessionId },
        'Sprite mapping file has non-array mappings — ignoring, client-authoritative fallback will rebuild',
      );
      return null;
    }

    // Migrate old field names (agentId→subagentId, role→canonicalRole) + supply defaults
    for (const m of file.mappings) {
      const raw = m as unknown as Record<string, unknown>;
      if (raw['agentId'] && !raw['subagentId']) {
        raw['subagentId'] = raw['agentId'];
        delete raw['agentId'];
      }
      if (raw['role'] && !raw['canonicalRole']) {
        raw['canonicalRole'] = raw['role'];
        delete raw['role'];
      }
      if (!raw['task']) raw['task'] = '';
    }
    return file;
  }

  async delete(sessionId: string): Promise<void> {
    // Cancel any pending debounced write for this session
    const existing = this.debounceTimers.get(sessionId);
    if (existing) {
      clearTimeout(existing);
      this.debounceTimers.delete(sessionId);
    }
    try {
      await this.fs.unlink(this.filePath(sessionId));
      logger.info({ sessionId }, 'Sprite mapping file deleted');
    } catch (err) {
      const code = errnoCode(err);
      if (code === 'ENOENT') {
        // File may not exist -- that's fine (already gone).
        return;
      }
      logger.warn(
        { err, sessionId, code },
        'Sprite mapping delete failed — file will be reaped on next cold boot',
      );
    }
  }

  /** Delete all mapping files (relay graceful shutdown) */
  async deleteAll(): Promise<void> {
    try {
      await this.ensureDir();
      const files = await this.fs.readdir(this.mappingsDir);
      for (const file of files) {
        if (!file.endsWith('.json')) continue;
        try {
          await this.fs.unlink(join(this.mappingsDir, file));
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
      const files = await this.fs.readdir(this.mappingsDir);
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
