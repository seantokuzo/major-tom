// Sessions store — reactive state for session list and metadata
// Uses Svelte 5 runes ($state)

import type { SessionMeta } from '../protocol/messages';

class SessionsStore {
  sessions = $state<SessionMeta[]>([]);
  isLoading = $state(false);

  /** Called by relay store when session.list.response arrives */
  handleListResponse(sessions: SessionMeta[]): void {
    this.sessions = sessions;
    this.isLoading = false;
  }

  /** Mark as loading — actual send happens via relay store */
  markLoading(): void {
    this.isLoading = true;
  }
}

// Singleton instance
export const sessionsStore = new SessionsStore();
