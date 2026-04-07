import { Session, type AdapterType, type SessionInfo, type SessionMeta } from './session.js';
import { SessionPersistence } from './session-persistence.js';
import type { TranscriptEntry } from './session-transcript.js';
import { logger } from '../utils/logger.js';

export class SessionNotFoundError extends Error {
  constructor(sessionId: string) {
    super(`Session not found: ${sessionId}`);
    this.name = 'SessionNotFoundError';
  }
}

/**
 * A TabHandle is the relay's view of one live PTY tab (one tmux window).
 *
 * Wave 1: identity + attach-time metadata, so tab listings and future
 * approval routing (Wave 2 hybrid mode → tmux send-keys) have something
 * to target.
 */
export interface TabHandle {
  tabId: string;
  /** OS pid of the tmux attach-session process feeding this WS. */
  pid: number;
  attachedAt: Date;
  /** Wave 2 will track this to debounce hybrid-mode keystroke injection. */
  lastPtyInputAt?: Date;
}

export class SessionManager {
  private sessions = new Map<string, Session>();
  private persistedMetas = new Map<string, SessionMeta>();
  private persistedWorkingDirs = new Map<string, string>();
  /**
   * Wave 1: relay-global map of live PTY tabs.
   *
   * The outer key is the `tabId` (tmux window name); the inner map is
   * keyed by the OS pid of each `attach-session` client. Tracking
   * multiple handles per tabId is required because `/shell/:tabId`
   * deliberately allows concurrent attaches (multi-device viewing) —
   * a single-handle Map would let device A's close handler evict
   * device B's still-live registration. Caught by Copilot review on
   * PR #89.
   */
  private tabs = new Map<string, Map<number, TabHandle>>();

  constructor(private persistence: SessionPersistence) {}

  // ── PTY tab registry (Wave 1 — Phase 13 "The Shell") ────────

  /** Pick the most recently attached handle from a per-pid map. */
  private latestHandle(handles: Map<number, TabHandle>): TabHandle | undefined {
    let latest: TabHandle | undefined;
    for (const handle of handles.values()) {
      if (!latest || handle.attachedAt.getTime() > latest.attachedAt.getTime()) {
        latest = handle;
      }
    }
    return latest;
  }

  registerTab(handle: TabHandle): void {
    let handles = this.tabs.get(handle.tabId);
    if (!handles) {
      handles = new Map<number, TabHandle>();
      this.tabs.set(handle.tabId, handles);
    }
    handles.set(handle.pid, handle);
    logger.info({ tabId: handle.tabId, pid: handle.pid, attachCount: handles.size }, 'PTY tab registered');
  }

  /**
   * Unregister a single attach (`pid`) from a `tabId`. The tab entry is
   * removed only when its last attach drops, so a `close` from one
   * device cannot evict another device's still-live registration.
   * Calling without `pid` drops every attach for the tab — only used by
   * shutdown paths.
   */
  unregisterTab(tabId: string, pid?: number): void {
    const handles = this.tabs.get(tabId);
    if (!handles) return;
    if (pid === undefined) {
      this.tabs.delete(tabId);
      logger.info({ tabId }, 'PTY tab fully unregistered');
      return;
    }
    if (!handles.delete(pid)) {
      logger.debug({ tabId, stalePid: pid }, 'Stale unregisterTab ignored');
      return;
    }
    if (handles.size === 0) {
      this.tabs.delete(tabId);
    }
    logger.info({ tabId, pid, remaining: handles.size }, 'PTY tab attach unregistered');
  }

  /** Returns the most recent handle for a tabId, or undefined. */
  getTab(tabId: string): TabHandle | undefined {
    const handles = this.tabs.get(tabId);
    if (!handles) return undefined;
    return this.latestHandle(handles);
  }

  /** Returns one handle per live tab (most recent attach wins). */
  listTabs(): TabHandle[] {
    const out: TabHandle[] = [];
    for (const handles of this.tabs.values()) {
      const latest = this.latestHandle(handles);
      if (latest) out.push(latest);
    }
    return out;
  }

  /** On startup, load persisted session metadata from disk */
  async restoreFromDisk(): Promise<void> {
    const metas = await this.persistence.listPersisted();
    for (const meta of metas) {
      // Only store if not already live
      if (!this.sessions.has(meta.id)) {
        this.persistedMetas.set(meta.id, {
          ...meta.metadata,
          status: 'closed', // Persisted sessions are always closed
        });
        if (meta.workingDir) {
          this.persistedWorkingDirs.set(meta.id, meta.workingDir);
        }
      }
    }
    logger.info({ count: this.persistedMetas.size }, 'Restored persisted session metadata');
  }

  create(adapter: AdapterType, workingDir: string): Session {
    const session = new Session(adapter, workingDir);
    this.sessions.set(session.id, session);
    logger.info({ sessionId: session.id, adapter, workingDir }, 'Session created');
    return session;
  }

  get(sessionId: string): Session {
    const session = this.sessions.get(sessionId);
    if (!session) {
      throw new SessionNotFoundError(sessionId);
    }
    return session;
  }

  tryGet(sessionId: string): Session | undefined {
    return this.sessions.get(sessionId);
  }

  /** Check if a session exists only in persisted storage (not live) */
  isPersistedOnly(sessionId: string): boolean {
    return !this.sessions.has(sessionId) && this.persistedMetas.has(sessionId);
  }

  list(): SessionInfo[] {
    return [...this.sessions.values()].map((s) => s.toInfo());
  }

  listMeta(): SessionMeta[] {
    // Merge live sessions with persisted, live wins on conflict
    const result = new Map<string, SessionMeta>();

    // Add persisted first (lower priority)
    for (const [id, meta] of this.persistedMetas) {
      result.set(id, meta);
    }

    // Live sessions overwrite persisted
    for (const session of this.sessions.values()) {
      result.set(session.id, session.toMeta());
    }

    return [...result.values()];
  }

  /** Get persisted metadata for a closed session */
  getPersistedMeta(sessionId: string): SessionMeta | undefined {
    return this.persistedMetas.get(sessionId);
  }

  /** Get the working directory for any session (live or persisted) */
  getWorkingDir(sessionId: string): string | undefined {
    const live = this.sessions.get(sessionId);
    if (live) return live.workingDir;
    return this.persistedWorkingDirs.get(sessionId);
  }

  async getPersistedTranscript(sessionId: string): Promise<TranscriptEntry[]> {
    const persisted = await this.persistence.load(sessionId);
    return persisted?.transcript ?? [];
  }

  close(sessionId: string): void {
    const session = this.sessions.get(sessionId);
    if (session) {
      session.close();
      logger.info({ sessionId }, 'Session closed');
    }
  }

  destroy(sessionId: string): void {
    this.sessions.delete(sessionId);
    logger.info({ sessionId }, 'Session destroyed');
  }

  activeCount(): number {
    return [...this.sessions.values()].filter((s) => s.status === 'active').length;
  }

  getPersistence(): SessionPersistence {
    return this.persistence;
  }
}
