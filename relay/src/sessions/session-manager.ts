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

export class SessionManager {
  private sessions = new Map<string, Session>();
  private persistedMetas = new Map<string, SessionMeta>();

  constructor(private persistence: SessionPersistence) {}

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
