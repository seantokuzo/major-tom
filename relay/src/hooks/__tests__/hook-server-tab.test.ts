/**
 * End-to-end integration test for the Tab-Keyed Offices wave 2 pathway:
 *
 *   POST /hooks/session-start   → SessionManager + TabRegistry mutate,
 *                                  tab.session.started + session.info
 *                                  broadcast.
 *   POST /hooks/stop            → Session closes, tab flips to idle,
 *                                  tab.session.ended + session.ended
 *                                  broadcast.
 *   PtyAdapter onTabClosed      → TabRegistry.tabClosed clears state and
 *                                  tab.closed fires on the broadcast bus.
 *
 * Spins up the real hook-server bound to a free loopback port so the HTTP
 * layer is exercised alongside the TabBridge dispatch. SessionPersistence
 * is stubbed — nothing touches the user's ~/.major-tom/ dir.
 */
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import type { Server } from 'node:http';
import type { AddressInfo } from 'node:net';

import { createHookServer } from '../hook-server.js';
import { ApprovalQueue } from '../approval-queue.js';
import { TabRegistry } from '../../tabs/tab-registry.js';
import { SessionManager } from '../../sessions/session-manager.js';
import { PtyAdapter, type PtyClient } from '../../adapters/pty-adapter.js';
import type { SessionPersistence } from '../../sessions/session-persistence.js';
import type { ServerMessage } from '../../protocol/messages.js';

const stubPersistence = {} as SessionPersistence;

async function post(
  url: string,
  body: unknown,
  headers: Record<string, string> = {},
): Promise<{ status: number; body: string }> {
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', ...headers },
    body: JSON.stringify(body),
  });
  return { status: res.status, body: await res.text() };
}

function makeMockPtyClient(): PtyClient {
  return {
    OPEN: 1,
    readyState: 1,
    send: () => {},
    close: () => {},
  } as PtyClient;
}

describe('hook-server — Tab-Keyed Offices integration', () => {
  let server: Server;
  let port: number;
  let tabRegistry: TabRegistry;
  let sessionManager: SessionManager;
  let broadcasts: ServerMessage[];
  let userIdByTab: Map<string, string>;

  beforeEach(async () => {
    tabRegistry = new TabRegistry();
    sessionManager = new SessionManager(stubPersistence);
    broadcasts = [];
    userIdByTab = new Map([['tab-A', 'user-alice']]);

    server = createHookServer(
      {
        approvalQueue: new ApprovalQueue(60_000),
        tabBridge: {
          tabRegistry,
          sessionManager,
          broadcast: (msg) => broadcasts.push(msg),
          getUserIdForTab: (tabId) => userIdByTab.get(tabId),
        },
      },
      0, // ephemeral port
    );

    await new Promise<void>((resolve) => {
      server.once('listening', () => resolve());
    });
    port = (server.address() as AddressInfo).port;
  });

  afterEach(async () => {
    await new Promise<void>((resolve) => server.close(() => resolve()));
  });

  describe('POST /hooks/session-start', () => {
    it('400s when session_id is missing', async () => {
      const res = await post(
        `http://127.0.0.1:${port}/hooks/session-start`,
        { cwd: '/home/u/proj' },
        { 'X-MT-Tab': 'tab-A' },
      );
      expect(res.status).toBe(400);
    });

    it('acks 200 with no TabRegistry mutation when X-MT-Tab is missing (legacy path)', async () => {
      const res = await post(
        `http://127.0.0.1:${port}/hooks/session-start`,
        { session_id: 'sess-legacy', cwd: '/home/u/proj' },
      );
      expect(res.status).toBe(200);
      expect(res.body).toBe('{}');
      expect(tabRegistry.listTabs()).toHaveLength(0);
    });

    it('registers session + tab + broadcasts on happy path', async () => {
      const res = await post(
        `http://127.0.0.1:${port}/hooks/session-start`,
        { session_id: 'sess-1', cwd: '/home/u/proj' },
        { 'X-MT-Tab': 'tab-A' },
      );
      expect(res.status).toBe(200);
      expect(res.body).toBe('{}');

      const tab = tabRegistry.getTab('tab-A');
      expect(tab).toBeDefined();
      expect(tab!.userId).toBe('user-alice');
      expect(tab!.workingDir).toBe('/home/u/proj');
      expect(tab!.sessionIds.has('sess-1')).toBe(true);
      expect(tab!.status).toBe('active');

      const session = sessionManager.tryGet('sess-1');
      expect(session).toBeDefined();
      expect(session!.adapter).toBe('cli-external');

      const types = broadcasts.map((m) => m.type);
      expect(types).toContain('tab.session.started');
      expect(types).toContain('session.info');

      const started = broadcasts.find((m) => m.type === 'tab.session.started');
      expect(started).toMatchObject({
        type: 'tab.session.started',
        tabId: 'tab-A',
        sessionId: 'sess-1',
        workingDirName: 'proj',
      });
    });

    it('uses the caller-supplied session_id (not a UUID)', async () => {
      await post(
        `http://127.0.0.1:${port}/hooks/session-start`,
        { session_id: 'claude-caller-abc', cwd: '/any' },
        { 'X-MT-Tab': 'tab-A' },
      );
      expect(sessionManager.tryGet('claude-caller-abc')?.id).toBe('claude-caller-abc');
    });
  });

  describe('POST /hooks/stop', () => {
    it('400s when session_id is missing', async () => {
      const res = await post(`http://127.0.0.1:${port}/hooks/stop`, {});
      expect(res.status).toBe(400);
    });

    it('closes the session, idles the tab, broadcasts tab.session.ended', async () => {
      // Register first so there is something to stop.
      await post(
        `http://127.0.0.1:${port}/hooks/session-start`,
        { session_id: 'sess-1', cwd: '/home/u/proj' },
        { 'X-MT-Tab': 'tab-A' },
      );
      broadcasts.length = 0; // clear so the assertions below only see Stop events

      const res = await post(`http://127.0.0.1:${port}/hooks/stop`, { session_id: 'sess-1' });
      expect(res.status).toBe(200);

      expect(sessionManager.tryGet('sess-1')?.status).toBe('closed');
      expect(tabRegistry.getTab('tab-A')?.status).toBe('idle');
      expect(tabRegistry.getTab('tab-A')?.sessionIds.size).toBe(0);

      const types = broadcasts.map((m) => m.type);
      expect(types).toContain('tab.session.ended');
      expect(types).toContain('session.ended');
      const ended = broadcasts.find((m) => m.type === 'tab.session.ended');
      expect(ended).toMatchObject({ type: 'tab.session.ended', tabId: 'tab-A', sessionId: 'sess-1' });
    });

    it('tab survives Stop — only tabClosed hard-deletes it', async () => {
      await post(
        `http://127.0.0.1:${port}/hooks/session-start`,
        { session_id: 'sess-1', cwd: '/home/u/proj' },
        { 'X-MT-Tab': 'tab-A' },
      );
      await post(`http://127.0.0.1:${port}/hooks/stop`, { session_id: 'sess-1' });
      expect(tabRegistry.getTab('tab-A')).toBeDefined();
    });
  });

  describe('filters tab.list by userId (ws.ts responsibility; direct registry check)', () => {
    it('listTabs(userId) excludes tabs owned by a different user', async () => {
      userIdByTab.set('tab-A', 'user-alice');
      userIdByTab.set('tab-B', 'user-bob');
      await post(
        `http://127.0.0.1:${port}/hooks/session-start`,
        { session_id: 'sess-A', cwd: '/a' },
        { 'X-MT-Tab': 'tab-A' },
      );
      await post(
        `http://127.0.0.1:${port}/hooks/session-start`,
        { session_id: 'sess-B', cwd: '/b' },
        { 'X-MT-Tab': 'tab-B' },
      );

      const aliceTabs = tabRegistry.listTabs('user-alice');
      expect(aliceTabs).toHaveLength(1);
      expect(aliceTabs[0]!.tabId).toBe('tab-A');

      const bobTabs = tabRegistry.listTabs('user-bob');
      expect(bobTabs).toHaveLength(1);
      expect(bobTabs[0]!.tabId).toBe('tab-B');
    });
  });
});

describe('PtyAdapter onTabClosed → TabRegistry.tabClosed + tab.closed broadcast', () => {
  it('fires tabRegistry.tabClosed and emits tab.closed on grace-expire', async () => {
    const tabRegistry = new TabRegistry();
    const broadcasts: ServerMessage[] = [];
    const userIdCleared: string[] = [];

    const adapter = new PtyAdapter({
      shell: '/bin/cat',
      shellArgs: [],
      graceMs: 50,
      bufferBytes: 1024,
      inputMaxBytes: 256,
      onTabClosed: (tabId) => {
        userIdCleared.push(tabId);
        tabRegistry.tabClosed(tabId);
        broadcasts.push({ type: 'tab.closed', tabId });
      },
    });

    try {
      tabRegistry.registerSessionStart('sess-1', 'tab-Z', '/proj', 'user-alice');
      expect(tabRegistry.getTab('tab-Z')).toBeDefined();

      const client = makeMockPtyClient();
      adapter.attach('tab-Z', client, { cols: 80, rows: 24 });

      // Detach → grace starts → grace expires → evict → onTabClosed fires.
      adapter.detach('tab-Z', client);

      // Poll until the callback fires (grace + safety margin).
      const deadline = Date.now() + 2_000;
      while (Date.now() < deadline && !broadcasts.some((m) => m.type === 'tab.closed')) {
        await new Promise((r) => setTimeout(r, 20));
      }

      expect(broadcasts.map((m) => m.type)).toContain('tab.closed');
      expect(userIdCleared).toContain('tab-Z');
      expect(tabRegistry.getTab('tab-Z')).toBeUndefined();
    } finally {
      adapter.dispose();
    }
  });
});
