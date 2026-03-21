import { Session, type AdapterType, type SessionInfo, type SessionMeta } from './session.js';
import { logger } from '../utils/logger.js';

export class SessionNotFoundError extends Error {
  constructor(sessionId: string) {
    super(`Session not found: ${sessionId}`);
    this.name = 'SessionNotFoundError';
  }
}

export class SessionManager {
  private sessions = new Map<string, Session>();

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

  list(): SessionInfo[] {
    return [...this.sessions.values()].map((s) => s.toInfo());
  }

  listMeta(): SessionMeta[] {
    return [...this.sessions.values()].map((s) => s.toMeta());
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
}
