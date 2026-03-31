/**
 * Presence Manager — tracks which users are connected and what they're watching.
 * Supports multiple connections per user (e.g. phone + laptop).
 */
import { WebSocket } from 'ws';
import type { UserPresenceInfo, UserRole } from './types.js';
import type { SessionPayload } from '../auth/session.js';

export class PresenceManager {
  /** ws → userId */
  private wsToUser = new Map<WebSocket, string>();
  /** userId → set of connections */
  private userConnections = new Map<string, Set<WebSocket>>();
  /** userId → presence info */
  private userInfo = new Map<string, UserPresenceInfo>();
  /** ws → sessionId being watched */
  private wsToSession = new Map<WebSocket, string>();

  /** Register a new WebSocket connection with user identity */
  connect(ws: WebSocket, payload: SessionPayload): void {
    const userId = payload.userId ?? payload.sub;
    const email = payload.email;
    const role = (payload.role ?? 'admin') as UserRole;

    this.wsToUser.set(ws, userId);

    let connections = this.userConnections.get(userId);
    if (!connections) {
      connections = new Set();
      this.userConnections.set(userId, connections);
    }
    connections.add(ws);

    // Create or update presence info
    if (!this.userInfo.has(userId)) {
      this.userInfo.set(userId, {
        userId,
        email,
        role,
        connectedAt: new Date().toISOString(),
      });
    }
  }

  /** Unregister a WebSocket connection */
  disconnect(ws: WebSocket): { userId: string; wasLastConnection: boolean } | null {
    const userId = this.wsToUser.get(ws);
    if (!userId) return null;

    this.wsToUser.delete(ws);
    this.wsToSession.delete(ws);

    const connections = this.userConnections.get(userId);
    if (connections) {
      connections.delete(ws);
      if (connections.size === 0) {
        this.userConnections.delete(userId);
        this.userInfo.delete(userId);
        return { userId, wasLastConnection: true };
      }
    }

    // Recalculate the user's watchingSessionId from remaining connections
    this.recalcWatching(userId);

    return { userId, wasLastConnection: false };
  }

  /** Track that a connection is watching a specific session */
  watchSession(ws: WebSocket, sessionId: string): void {
    this.wsToSession.set(ws, sessionId);
    const userId = this.wsToUser.get(ws);
    if (userId) {
      this.recalcWatching(userId);
    }
  }

  /** Stop watching any session */
  unwatchSession(ws: WebSocket): void {
    this.wsToSession.delete(ws);
    const userId = this.wsToUser.get(ws);
    if (userId) {
      this.recalcWatching(userId);
    }
  }

  /** Get all users currently watching a specific session */
  getSessionWatchers(sessionId: string): UserPresenceInfo[] {
    const watcherIds = new Set<string>();
    const watchers: UserPresenceInfo[] = [];

    for (const [ws, sid] of this.wsToSession) {
      if (sid === sessionId) {
        const userId = this.wsToUser.get(ws);
        if (userId && !watcherIds.has(userId)) {
          watcherIds.add(userId);
          const info = this.userInfo.get(userId);
          if (info) watchers.push(info);
        }
      }
    }

    return watchers;
  }

  /** Get all online users' presence info */
  getAllPresence(): UserPresenceInfo[] {
    return [...this.userInfo.values()];
  }

  /** Get userId for a WebSocket connection */
  getUserId(ws: WebSocket): string | undefined {
    return this.wsToUser.get(ws);
  }

  /** Get user's role */
  getUserRole(ws: WebSocket): UserRole | undefined {
    const userId = this.wsToUser.get(ws);
    if (!userId) return undefined;
    return this.userInfo.get(userId)?.role;
  }

  /** Check if user is online */
  isOnline(userId: string): boolean {
    return this.userConnections.has(userId);
  }

  /** Get session a specific ws is watching */
  getWatchingSession(ws: WebSocket): string | undefined {
    return this.wsToSession.get(ws);
  }

  /** Recalculate watching session for a user (most recent ws wins) */
  private recalcWatching(userId: string): void {
    const info = this.userInfo.get(userId);
    if (!info) return;

    const connections = this.userConnections.get(userId);
    if (!connections) {
      info.watchingSessionId = undefined;
      return;
    }

    // Use the last connection's session (most recently set)
    let lastSession: string | undefined;
    for (const ws of connections) {
      const sid = this.wsToSession.get(ws);
      if (sid) lastSession = sid;
    }
    info.watchingSessionId = lastSession;
  }
}
