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
  /** ws → monotonic sequence when watch was set (for ordering) */
  private wsWatchSeq = new Map<WebSocket, number>();
  private watchSeqCounter = 0;

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

    // Always update presence info (refresh role/email on reconnect)
    const existing = this.userInfo.get(userId);
    this.userInfo.set(userId, {
      userId,
      email,
      role,
      connectedAt: existing?.connectedAt ?? new Date().toISOString(),
      watchingSessionId: existing?.watchingSessionId,
    });
  }

  /** Unregister a WebSocket connection */
  disconnect(ws: WebSocket): { userId: string; wasLastConnection: boolean } | null {
    const userId = this.wsToUser.get(ws);
    if (!userId) return null;

    this.wsToUser.delete(ws);
    this.wsToSession.delete(ws);
    this.wsWatchSeq.delete(ws);

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
    this.wsWatchSeq.set(ws, ++this.watchSeqCounter);
    const userId = this.wsToUser.get(ws);
    if (userId) {
      this.recalcWatching(userId);
    }
  }

  /** Stop watching any session */
  unwatchSession(ws: WebSocket): void {
    this.wsToSession.delete(ws);
    this.wsWatchSeq.delete(ws);
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

  /** Disconnect all sockets for a user (e.g. on revoke) */
  disconnectUser(userId: string): void {
    const connections = this.userConnections.get(userId);
    if (!connections) return;
    // Close all connections — the 'close' handler will clean up maps
    for (const ws of [...connections]) {
      ws.close(1008, 'User revoked');
    }
  }

  /** Update cached role for a connected user */
  updateUserRole(userId: string, role: UserRole): void {
    const info = this.userInfo.get(userId);
    if (info) {
      info.role = role;
    }
  }

  /** Check if user is online */
  isOnline(userId: string): boolean {
    return this.userConnections.has(userId);
  }

  /** Get session a specific ws is watching */
  getWatchingSession(ws: WebSocket): string | undefined {
    return this.wsToSession.get(ws);
  }

  /** Recalculate watching session for a user (most recent watch wins by sequence) */
  private recalcWatching(userId: string): void {
    const info = this.userInfo.get(userId);
    if (!info) return;

    const connections = this.userConnections.get(userId);
    if (!connections) {
      info.watchingSessionId = undefined;
      return;
    }

    // Use the connection with the highest watch sequence (most recently set)
    let lastSession: string | undefined;
    let highestSeq = -1;
    for (const ws of connections) {
      const sid = this.wsToSession.get(ws);
      const seq = this.wsWatchSeq.get(ws) ?? 0;
      if (sid && seq > highestSeq) {
        highestSeq = seq;
        lastSession = sid;
      }
    }
    info.watchingSessionId = lastSession;
  }
}
