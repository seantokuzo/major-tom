// Presence store — tracks online team members and session watchers
import type { PresenceUpdateMessage } from '../protocol/messages';

export interface UserPresence {
  userId: string;
  email: string;
  name?: string;
  picture?: string;
  role: string;
  connectedAt: string;
  watchingSessionId?: string;
}

class PresenceStore {
  users = $state<UserPresence[]>([]);

  /** Get users watching a specific session */
  watchersFor(sessionId: string): UserPresence[] {
    return this.users.filter(u => u.watchingSessionId === sessionId);
  }

  /** Get all online users */
  get onlineUsers(): UserPresence[] {
    return this.users;
  }

  /** Get online count */
  get onlineCount(): number {
    return this.users.length;
  }

  /** Handle presence.update from relay */
  handleUpdate(message: PresenceUpdateMessage): void {
    this.users = message.users.map(u => ({
      userId: u.userId,
      email: u.email,
      name: u.name,
      picture: u.picture,
      role: u.role,
      connectedAt: u.connectedAt,
      watchingSessionId: u.watchingSessionId,
    }));
  }

  /** Clear all presence data (on disconnect) */
  clear(): void {
    this.users = [];
  }
}

export const presenceStore = new PresenceStore();
