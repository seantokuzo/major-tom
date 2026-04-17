// Tab persistence — survives relay restart so Offices can re-open at the
// point they were when the relay went down. Mirrors sprite-mapping-persistence.ts
// but one file per tab, keyed by tabId.
//
// Failure modes:
//   - ENOENT on read    → silent null (new tab, expected).
//   - Corrupt / bad schema → logged at WARN, ignored (falls through to "new tab").
//   - ENOSPC / EIO on write → logged at WARN, NOT thrown. In-memory state is the
//     live source of truth; disk is an optimization for relay restart. Losing a
//     write just means that tab won't rehydrate after restart, which degrades
//     gracefully — the next SessionStart hook re-registers it.

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
import type { TabMeta, TabStatus } from './tab-registry.js';

export interface PersistedTabFile {
  version: 1;
  tabId: string;
  userId?: string;
  workingDir?: string;
  createdAt: string;
  lastSeenAt: string;
  sessionIds: string[];
  status: TabStatus;
}

const DEFAULT_TABS_DIR = join(homedir(), '.major-tom', 'tabs');

export interface FsOps {
  readFile: typeof readFile;
  writeFile: typeof writeFile;
  readdir: typeof readdir;
  mkdir: typeof mkdir;
  unlink: typeof unlink;
}

const DEFAULT_FS: FsOps = { readFile, writeFile, readdir, mkdir, unlink };

export interface TabRegistryPersistenceOptions {
  baseDir?: string;
  fs?: Partial<FsOps>;
}

function errnoCode(err: unknown): string | undefined {
  if (typeof err === 'object' && err !== null && 'code' in err) {
    const code = (err as { code: unknown }).code;
    if (typeof code === 'string') return code;
  }
  return undefined;
}

export class TabRegistryPersistence {
  private readonly tabsDir: string;
  private readonly fs: FsOps;

  constructor(opts: TabRegistryPersistenceOptions = {}) {
    this.tabsDir = opts.baseDir ?? DEFAULT_TABS_DIR;
    this.fs = { ...DEFAULT_FS, ...opts.fs };
  }

  /** Accessor used by tests to verify the on-disk layout. */
  get baseDir(): string {
    return this.tabsDir;
  }

  private filePath(tabId: string): string {
    const safe = tabId.replace(/[^a-zA-Z0-9\-_]/g, '');
    if (!safe || safe !== tabId) {
      throw new Error(`Invalid tabId for persistence: ${tabId}`);
    }
    return join(this.tabsDir, `${safe}.json`);
  }

  private async ensureDir(): Promise<void> {
    try {
      await this.fs.mkdir(this.tabsDir, { recursive: true });
    } catch (err) {
      logger.error({ err }, 'Failed to create tabs directory');
    }
  }

  /** Write current TabMeta to disk. Never throws. */
  async save(meta: TabMeta): Promise<void> {
    const file: PersistedTabFile = {
      version: 1,
      tabId: meta.tabId,
      ...(meta.userId !== undefined ? { userId: meta.userId } : {}),
      ...(meta.workingDir !== undefined ? { workingDir: meta.workingDir } : {}),
      createdAt: meta.createdAt,
      lastSeenAt: meta.lastSeenAt,
      sessionIds: [...meta.sessionIds],
      status: meta.status,
    };
    try {
      await this.ensureDir();
      await this.fs.writeFile(
        this.filePath(meta.tabId),
        JSON.stringify(file, null, 2),
        'utf-8',
      );
      logger.debug({ tabId: meta.tabId, sessionCount: file.sessionIds.length }, 'Tab persisted');
    } catch (err) {
      const code = errnoCode(err);
      logger.warn(
        { err, tabId: meta.tabId, code },
        'TabRegistry save failed — in-memory state preserved, next SessionStart re-registers',
      );
    }
  }

  async load(tabId: string): Promise<PersistedTabFile | null> {
    let raw: string;
    try {
      raw = await this.fs.readFile(this.filePath(tabId), 'utf-8');
    } catch (err) {
      const code = errnoCode(err);
      if (code === 'ENOENT') return null;
      logger.warn({ err, tabId, code }, 'Tab persistence read failed');
      return null;
    }

    let parsed: unknown;
    try {
      parsed = JSON.parse(raw);
    } catch (err) {
      logger.warn({ err, tabId }, 'Tab persistence file is invalid JSON — ignoring');
      return null;
    }

    if (!isValidPersistedFile(parsed)) {
      logger.warn({ tabId }, 'Tab persistence file has invalid schema — ignoring');
      return null;
    }
    return parsed;
  }

  async loadAll(): Promise<PersistedTabFile[]> {
    const results: PersistedTabFile[] = [];
    let entries: string[];
    try {
      await this.ensureDir();
      entries = await this.fs.readdir(this.tabsDir);
    } catch (err) {
      logger.warn({ err }, 'TabRegistry loadAll readdir failed — starting empty');
      return results;
    }
    for (const entry of entries) {
      if (!entry.endsWith('.json')) continue;
      const tabId = entry.slice(0, -5);
      const loaded = await this.load(tabId);
      if (loaded) results.push(loaded);
    }
    return results;
  }

  async delete(tabId: string): Promise<void> {
    try {
      await this.fs.unlink(this.filePath(tabId));
    } catch (err) {
      const code = errnoCode(err);
      if (code === 'ENOENT') return;
      logger.warn({ err, tabId, code }, 'Tab persistence delete failed');
    }
  }
}

function isValidPersistedFile(v: unknown): v is PersistedTabFile {
  if (typeof v !== 'object' || v === null) return false;
  const o = v as Record<string, unknown>;
  if (o['version'] !== 1) return false;
  if (typeof o['tabId'] !== 'string') return false;
  if (typeof o['createdAt'] !== 'string') return false;
  if (typeof o['lastSeenAt'] !== 'string') return false;
  if (!Array.isArray(o['sessionIds'])) return false;
  if ((o['sessionIds'] as unknown[]).some((s) => typeof s !== 'string')) return false;
  const status = o['status'];
  if (status !== 'active' && status !== 'idle' && status !== 'closed') return false;
  if (o['userId'] !== undefined && typeof o['userId'] !== 'string') return false;
  if (o['workingDir'] !== undefined && typeof o['workingDir'] !== 'string') return false;
  return true;
}
