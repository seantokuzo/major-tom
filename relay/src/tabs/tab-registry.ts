// Tab Registry — tracks iOS terminal tabs and the Claude sessions running inside
// them. Spec: docs/PHASE-TAB-KEYED-OFFICES.md §4.1.
//
// An Office is one-to-one with a tab; dogs persist at tab lifetime, humans cycle
// with the sessions running inside. This registry is the source of truth for that
// mapping on the relay side.
//
// Disk persistence is optional (opt-in via constructor). When configured, every
// session-lifecycle mutation triggers a fire-and-forget save; tabClosed deletes
// the tab's on-disk file. restoreFromDisk() on app bootstrap rehydrates known
// tabs but clears their session state (no live sessions survive a relay
// restart — the first SessionStart hook afterward re-fills them).

import { logger } from '../utils/logger.js';
import type { TabRegistryPersistence } from './tab-registry-persistence.js';

export type TabStatus = 'active' | 'idle' | 'closed';

export interface TabMeta {
  tabId: string;
  userId: string | undefined;
  workingDir: string | undefined;
  createdAt: string;
  lastSeenAt: string;
  sessionIds: Set<string>;
  status: TabStatus;
}

export class TabRegistry {
  private tabs = new Map<string, TabMeta>();
  /** sessionId → tabId reverse index for O(1) lookup. */
  private sessionToTab = new Map<string, string>();

  constructor(private readonly persistence?: TabRegistryPersistence) {}

  /**
   * Rehydrate known tabs from disk. Live sessions do not survive a relay
   * restart — the restored tabs start with sessionIds = {} and status 'idle';
   * the first SessionStart hook after restart re-populates them.
   */
  async restoreFromDisk(): Promise<void> {
    if (!this.persistence) return;
    const files = await this.persistence.loadAll();
    for (const f of files) {
      const meta: TabMeta = {
        tabId: f.tabId,
        userId: f.userId,
        workingDir: f.workingDir,
        createdAt: f.createdAt,
        lastSeenAt: f.lastSeenAt,
        sessionIds: new Set<string>(),
        status: 'idle',
      };
      this.tabs.set(f.tabId, meta);
    }
    logger.info({ count: files.length }, 'TabRegistry restored from disk');
  }

  /**
   * Record that a claude session just started inside a tab. Creates the TabMeta
   * on first call for a given tabId.
   */
  registerSessionStart(
    sessionId: string,
    tabId: string,
    cwd: string,
    userId?: string,
  ): TabMeta {
    const now = new Date().toISOString();
    let tab = this.tabs.get(tabId);
    if (!tab) {
      tab = {
        tabId,
        userId,
        workingDir: cwd,
        createdAt: now,
        lastSeenAt: now,
        sessionIds: new Set<string>(),
        status: 'active',
      };
      this.tabs.set(tabId, tab);
      logger.info({ tabId, userId, cwd }, 'Tab registered (first SessionStart)');
    } else {
      tab.lastSeenAt = now;
      if (!tab.userId && userId) tab.userId = userId;
      if (!tab.workingDir && cwd) tab.workingDir = cwd;
    }
    tab.sessionIds.add(sessionId);
    tab.status = 'active';
    this.sessionToTab.set(sessionId, tabId);
    this.schedulePersist(tab);
    return tab;
  }

  /**
   * Record that a claude session ended. Leaves the TabMeta alive — tab persists
   * until the PTY closes. If this was the last session, the tab flips to 'idle'.
   */
  registerSessionEnd(sessionId: string): TabMeta | undefined {
    const tabId = this.sessionToTab.get(sessionId);
    if (!tabId) return undefined;
    this.sessionToTab.delete(sessionId);
    const tab = this.tabs.get(tabId);
    if (!tab) return undefined;
    tab.sessionIds.delete(sessionId);
    tab.lastSeenAt = new Date().toISOString();
    if (tab.sessionIds.size === 0 && tab.status !== 'closed') {
      tab.status = 'idle';
    }
    this.schedulePersist(tab);
    return tab;
  }

  /**
   * Hard teardown: PTY grace expired. Removes the TabMeta and clears the reverse
   * index for any still-registered sessions in that tab.
   */
  tabClosed(tabId: string): TabMeta | undefined {
    const tab = this.tabs.get(tabId);
    if (!tab) return undefined;
    for (const sid of tab.sessionIds) {
      this.sessionToTab.delete(sid);
    }
    this.tabs.delete(tabId);
    if (this.persistence) {
      void this.persistence.delete(tabId);
    }
    logger.info({ tabId }, 'Tab closed (PTY grace expired)');
    return tab;
  }

  /** Look up the tab that owns a given session. */
  getTabForSession(sessionId: string): TabMeta | undefined {
    const tabId = this.sessionToTab.get(sessionId);
    if (!tabId) return undefined;
    return this.tabs.get(tabId);
  }

  /** Fetch a TabMeta by tabId. */
  getTab(tabId: string): TabMeta | undefined {
    return this.tabs.get(tabId);
  }

  /**
   * List all known tabs, optionally filtered by owner userId. When `userId` is
   * undefined, returns every tab (useful for diagnostics; call sites that need
   * sandboxing must pass a userId).
   */
  listTabs(userId?: string): TabMeta[] {
    const all = [...this.tabs.values()];
    if (userId === undefined) return all;
    return all.filter((t) => t.userId === userId);
  }

  /** Bump lastSeenAt without mutating sessions or status. */
  touch(tabId: string): void {
    const tab = this.tabs.get(tabId);
    if (!tab) return;
    tab.lastSeenAt = new Date().toISOString();
  }

  private schedulePersist(tab: TabMeta): void {
    if (!this.persistence) return;
    void this.persistence.save(tab);
  }
}
