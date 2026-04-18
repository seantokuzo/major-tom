import { describe, it, expect, beforeEach } from 'vitest';
import { TabRegistry } from '../tab-registry.js';

describe('TabRegistry', () => {
  let registry: TabRegistry;

  beforeEach(() => {
    registry = new TabRegistry();
  });

  describe('registerSessionStart', () => {
    it('creates a TabMeta on first SessionStart for a tabId', () => {
      registry.registerSessionStart('sess-1', 'tab-A', '/home/u/proj', 'user-1');
      const tab = registry.getTab('tab-A');
      expect(tab).toBeDefined();
      expect(tab!.tabId).toBe('tab-A');
      expect(tab!.userId).toBe('user-1');
      expect(tab!.workingDir).toBe('/home/u/proj');
      expect(tab!.sessionIds.has('sess-1')).toBe(true);
      expect(tab!.status).toBe('active');
      expect(tab!.createdAt).toMatch(/^\d{4}-\d{2}-\d{2}T/);
      expect(tab!.lastSeenAt).toBe(tab!.createdAt);
    });

    it('re-uses the existing TabMeta on subsequent SessionStarts for the same tab', async () => {
      registry.registerSessionStart('sess-1', 'tab-A', '/proj', 'user-1');
      const created = registry.getTab('tab-A')!.createdAt;
      await new Promise((r) => setTimeout(r, 5));
      registry.registerSessionStart('sess-2', 'tab-A', '/proj', 'user-1');
      const tab = registry.getTab('tab-A')!;
      expect(tab.createdAt).toBe(created);
      expect(tab.lastSeenAt >= created).toBe(true);
      expect(tab.sessionIds.size).toBe(2);
      expect(tab.sessionIds.has('sess-1')).toBe(true);
      expect(tab.sessionIds.has('sess-2')).toBe(true);
    });

    it('upgrades unknown userId / workingDir when a later start supplies them', () => {
      registry.registerSessionStart('sess-1', 'tab-A', '', undefined);
      const before = registry.getTab('tab-A')!;
      expect(before.userId).toBeUndefined();
      expect(before.workingDir).toBe('');

      registry.registerSessionStart('sess-2', 'tab-A', '/proj', 'user-1');
      const after = registry.getTab('tab-A')!;
      expect(after.userId).toBe('user-1');
      expect(after.workingDir).toBe('/proj');
    });

    it('does not downgrade a known userId when a later start omits it', () => {
      registry.registerSessionStart('sess-1', 'tab-A', '/proj', 'user-1');
      registry.registerSessionStart('sess-2', 'tab-A', '/proj', undefined);
      expect(registry.getTab('tab-A')!.userId).toBe('user-1');
    });

    it('flips a previously-idle tab back to active on a new session', () => {
      registry.registerSessionStart('sess-1', 'tab-A', '/proj', 'user-1');
      registry.registerSessionEnd('sess-1');
      expect(registry.getTab('tab-A')!.status).toBe('idle');

      registry.registerSessionStart('sess-2', 'tab-A', '/proj', 'user-1');
      expect(registry.getTab('tab-A')!.status).toBe('active');
    });
  });

  describe('registerSessionEnd', () => {
    it('removes the session from the tab', () => {
      registry.registerSessionStart('sess-1', 'tab-A', '/proj', 'user-1');
      registry.registerSessionEnd('sess-1');
      expect(registry.getTab('tab-A')!.sessionIds.has('sess-1')).toBe(false);
    });

    it('flips the tab to idle when the last session ends', () => {
      registry.registerSessionStart('sess-1', 'tab-A', '/proj', 'user-1');
      registry.registerSessionEnd('sess-1');
      const tab = registry.getTab('tab-A')!;
      expect(tab.status).toBe('idle');
      expect(tab.sessionIds.size).toBe(0);
    });

    it('keeps the tab active while other sessions are running', () => {
      registry.registerSessionStart('sess-1', 'tab-A', '/proj', 'user-1');
      registry.registerSessionStart('sess-2', 'tab-A', '/proj', 'user-1');
      registry.registerSessionEnd('sess-1');
      expect(registry.getTab('tab-A')!.status).toBe('active');
      expect(registry.getTab('tab-A')!.sessionIds.has('sess-2')).toBe(true);
    });

    it('leaves the TabMeta in place so the Office can persist', () => {
      registry.registerSessionStart('sess-1', 'tab-A', '/proj', 'user-1');
      registry.registerSessionEnd('sess-1');
      expect(registry.getTab('tab-A')).toBeDefined();
    });

    it('is a no-op for an unknown sessionId', () => {
      expect(() => registry.registerSessionEnd('ghost')).not.toThrow();
      expect(registry.registerSessionEnd('ghost')).toBeUndefined();
    });

    it('clears the reverse-lookup index for the ended session', () => {
      registry.registerSessionStart('sess-1', 'tab-A', '/proj', 'user-1');
      registry.registerSessionEnd('sess-1');
      expect(registry.getTabForSession('sess-1')).toBeUndefined();
    });
  });

  describe('tabClosed', () => {
    it('removes the TabMeta entirely', () => {
      registry.registerSessionStart('sess-1', 'tab-A', '/proj', 'user-1');
      registry.tabClosed('tab-A');
      expect(registry.getTab('tab-A')).toBeUndefined();
    });

    it('clears the reverse-lookup for any still-registered sessions', () => {
      registry.registerSessionStart('sess-1', 'tab-A', '/proj', 'user-1');
      registry.registerSessionStart('sess-2', 'tab-A', '/proj', 'user-1');
      registry.tabClosed('tab-A');
      expect(registry.getTabForSession('sess-1')).toBeUndefined();
      expect(registry.getTabForSession('sess-2')).toBeUndefined();
    });

    it('is a no-op for an unknown tabId', () => {
      expect(() => registry.tabClosed('ghost')).not.toThrow();
      expect(registry.tabClosed('ghost')).toBeUndefined();
    });

    it('returns the tab that was closed', () => {
      registry.registerSessionStart('sess-1', 'tab-A', '/proj', 'user-1');
      const closed = registry.tabClosed('tab-A');
      expect(closed?.tabId).toBe('tab-A');
    });
  });

  describe('getTabForSession (reverse lookup)', () => {
    it('returns the tab that owns a session', () => {
      registry.registerSessionStart('sess-1', 'tab-A', '/proj', 'user-1');
      const tab = registry.getTabForSession('sess-1');
      expect(tab?.tabId).toBe('tab-A');
    });

    it('returns undefined for an unknown session', () => {
      expect(registry.getTabForSession('ghost')).toBeUndefined();
    });

    it('returns undefined after the session ends', () => {
      registry.registerSessionStart('sess-1', 'tab-A', '/proj', 'user-1');
      registry.registerSessionEnd('sess-1');
      expect(registry.getTabForSession('sess-1')).toBeUndefined();
    });
  });

  describe('listTabs', () => {
    it('returns all tabs when no userId filter is passed', () => {
      registry.registerSessionStart('sess-1', 'tab-A', '/proj', 'user-1');
      registry.registerSessionStart('sess-2', 'tab-B', '/other', 'user-2');
      const all = registry.listTabs();
      expect(all).toHaveLength(2);
      expect(all.map((t) => t.tabId).sort()).toEqual(['tab-A', 'tab-B']);
    });

    it('filters by userId', () => {
      registry.registerSessionStart('sess-1', 'tab-A', '/proj', 'user-1');
      registry.registerSessionStart('sess-2', 'tab-B', '/other', 'user-2');
      registry.registerSessionStart('sess-3', 'tab-C', '/third', 'user-1');
      const mine = registry.listTabs('user-1');
      expect(mine).toHaveLength(2);
      expect(mine.map((t) => t.tabId).sort()).toEqual(['tab-A', 'tab-C']);
    });

    it('excludes tabs owned by a different user', () => {
      registry.registerSessionStart('sess-1', 'tab-A', '/proj', 'user-1');
      registry.registerSessionStart('sess-2', 'tab-B', '/other', 'user-2');
      const mine = registry.listTabs('user-1');
      expect(mine).toHaveLength(1);
      expect(mine[0]!.tabId).toBe('tab-A');
    });

    it('does not include tabs with undefined userId when filtered', () => {
      registry.registerSessionStart('sess-1', 'tab-A', '/proj', undefined);
      const mine = registry.listTabs('user-1');
      expect(mine).toHaveLength(0);
    });
  });

  describe('touch', () => {
    it('bumps lastSeenAt', async () => {
      registry.registerSessionStart('sess-1', 'tab-A', '/proj', 'user-1');
      const before = registry.getTab('tab-A')!.lastSeenAt;
      await new Promise((r) => setTimeout(r, 5));
      registry.touch('tab-A');
      expect(registry.getTab('tab-A')!.lastSeenAt > before).toBe(true);
    });

    it('does not mutate sessions or status', () => {
      registry.registerSessionStart('sess-1', 'tab-A', '/proj', 'user-1');
      registry.touch('tab-A');
      const tab = registry.getTab('tab-A')!;
      expect(tab.status).toBe('active');
      expect(tab.sessionIds.has('sess-1')).toBe(true);
    });

    it('is a no-op for an unknown tabId', () => {
      expect(() => registry.touch('ghost')).not.toThrow();
    });
  });

  describe('full lifecycle (spec scenarios L2 → L5 → L6 → L7)', () => {
    it('walks through register → end → re-register → close', () => {
      // L2: first SessionStart creates the tab
      registry.registerSessionStart('sess-1', 'tab-A', '/proj', 'user-1');
      expect(registry.getTab('tab-A')!.status).toBe('active');

      // L5: claude exits gracefully, tab goes idle
      registry.registerSessionEnd('sess-1');
      expect(registry.getTab('tab-A')!.status).toBe('idle');
      expect(registry.getTab('tab-A')!.sessionIds.size).toBe(0);

      // L6: user runs claude again in the same tab — same TabMeta, new session
      const createdAt = registry.getTab('tab-A')!.createdAt;
      registry.registerSessionStart('sess-2', 'tab-A', '/proj', 'user-1');
      expect(registry.getTab('tab-A')!.status).toBe('active');
      expect(registry.getTab('tab-A')!.createdAt).toBe(createdAt);
      expect(registry.getTab('tab-A')!.sessionIds.has('sess-2')).toBe(true);

      // L7: user closes the terminal tab → hard teardown
      registry.tabClosed('tab-A');
      expect(registry.getTab('tab-A')).toBeUndefined();
      expect(registry.getTabForSession('sess-2')).toBeUndefined();
    });
  });
});
