/**
 * Integration tests for `/shell/:tabId` route.
 *
 * Stands up a real Fastify instance on an ephemeral port, connects a
 * real `ws` client, and exchanges messages against the `PtyAdapter`.
 * Dev-mode AUTH_TOKEN auth is used to bypass JWT minting.
 */
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import Fastify, { type FastifyInstance } from 'fastify';
import cookie from '@fastify/cookie';
import websocket from '@fastify/websocket';
import { WebSocket } from 'ws';
import type { AddressInfo } from 'node:net';
import { PtyAdapter } from '../../adapters/pty-adapter.js';
import { createShellRoute } from '../shell.js';

const AUTH_TOKEN = 'test-auth-token';

let app: FastifyInstance;
let adapter: PtyAdapter;
let port: number;

/** Wait for an assertion to pass within timeoutMs. */
async function waitFor(fn: () => void | Promise<void>, timeoutMs = 2_000, intervalMs = 25) {
  const start = Date.now();
  let lastErr: unknown;
  while (Date.now() - start < timeoutMs) {
    try {
      await fn();
      return;
    } catch (err) {
      lastErr = err;
      await new Promise((r) => setTimeout(r, intervalMs));
    }
  }
  throw lastErr;
}

function wsUrl(path: string): string {
  return `ws://127.0.0.1:${port}${path}`;
}

/**
 * Wrap a raw WebSocket with a persistent message buffer attached BEFORE
 * `open` fires, so the server's immediate `attached` frame is not lost
 * in the gap between open and consumer listener registration.
 */
interface BufferedWs {
  ws: WebSocket;
  readonly messages: Array<{ data: Buffer; binary: boolean }>;
  waitForMessages(n: number, timeoutMs?: number): Promise<void>;
  waitForClose(timeoutMs?: number): Promise<number>;
  binary(): Buffer;
  close(): void;
}

async function openWs(
  path: string,
  opts: { awaitOpen?: boolean } = {},
): Promise<BufferedWs> {
  const ws = new WebSocket(wsUrl(path));
  const messages: Array<{ data: Buffer; binary: boolean }> = [];
  ws.on('message', (data: Buffer, isBinary: boolean) => {
    messages.push({ data, binary: isBinary });
  });

  const closePromise = new Promise<number>((resolve) => {
    ws.once('close', (code) => resolve(code));
  });
  // Swallow post-open errors; tests that expect errors already listen.
  ws.on('error', () => { /* silent */ });

  if (opts.awaitOpen !== false) {
    await new Promise<void>((resolve, reject) => {
      ws.once('open', () => resolve());
      ws.once('close', (code) => reject(new Error(`WS closed before open: ${code}`)));
      ws.once('error', (err) => reject(err));
    });
  }

  return {
    ws,
    messages,
    async waitForMessages(n: number, timeoutMs = 2_000) {
      const start = Date.now();
      while (messages.length < n) {
        if (Date.now() - start > timeoutMs) {
          throw new Error(
            `Timed out waiting for ${n} messages (got ${messages.length})`,
          );
        }
        await new Promise((r) => setTimeout(r, 25));
      }
    },
    async waitForClose(timeoutMs = 5_000) {
      return Promise.race([
        closePromise,
        new Promise<number>((_, reject) =>
          setTimeout(() => reject(new Error('Timed out waiting for close')), timeoutMs),
        ),
      ]);
    },
    binary() {
      return Buffer.concat(messages.filter((m) => m.binary).map((m) => m.data));
    },
    close() {
      ws.close();
    },
  };
}

/** Same shape as openWs but swallows pre-open close — used for tests that
 *  deliberately expect the server to reject before upgrade completes. */
function openWsExpectingClose(path: string): Promise<number> {
  const ws = new WebSocket(wsUrl(path));
  return new Promise((resolve) => {
    ws.on('error', () => { /* ignore */ });
    ws.once('close', (code) => resolve(code));
  });
}

beforeEach(async () => {
  process.env['AUTH_TOKEN'] = AUTH_TOKEN;
  process.env['NODE_ENV'] = 'development';

  adapter = new PtyAdapter({
    shell: '/bin/cat',
    shellArgs: [],
    graceMs: 5_000,
    bufferBytes: 1024,
    inputMaxBytes: 64,
  });

  app = Fastify({ logger: false });
  await app.register(cookie);
  await app.register(websocket, {
    options: { clientTracking: true, maxPayload: 1024 * 1024 },
  });
  await app.register(createShellRoute({ ptyAdapter: adapter }));

  await app.listen({ host: '127.0.0.1', port: 0 });
  const address = app.server.address() as AddressInfo;
  port = address.port;
});

afterEach(async () => {
  adapter.dispose();
  await app.close();
});

// ── Auth ─────────────────────────────────────────────────────

describe('WS /shell/:tabId — auth', () => {
  it('rejects WS with no auth', async () => {
    const code = await openWsExpectingClose('/shell/tab-1?cols=80&rows=24');
    expect(code).toBe(1008);
  });

  it('accepts WS with ?token=AUTH_TOKEN and receives attached:false', async () => {
    const buf = await openWs(`/shell/tab-1?token=${AUTH_TOKEN}&cols=80&rows=24`);
    await buf.waitForMessages(1);
    const frame = JSON.parse(buf.messages[0]!.data.toString('utf-8'));
    expect(frame).toEqual({ type: 'attached', tabId: 'tab-1', restored: false });
    buf.close();
  });
});

// ── Data / control ───────────────────────────────────────────

describe('WS /shell/:tabId — data / control', () => {
  it('binary input flows through cat and echoes back', async () => {
    const buf = await openWs(`/shell/tab-1?token=${AUTH_TOKEN}&cols=80&rows=24`);
    await buf.waitForMessages(1);

    buf.ws.send(Buffer.from('hello\n'), { binary: true });

    await waitFor(() => {
      expect(buf.binary().toString('utf-8')).toContain('hello');
    });
    buf.close();
  });

  it('resize control frame does not throw', async () => {
    const buf = await openWs(`/shell/tab-1?token=${AUTH_TOKEN}&cols=80&rows=24`);
    await buf.waitForMessages(1);
    buf.ws.send(JSON.stringify({ type: 'resize', cols: 132, rows: 50 }));
    await new Promise((r) => setTimeout(r, 50));
    expect(buf.ws.readyState).toBe(WebSocket.OPEN);
    buf.close();
  });

  it('kill control frame terminates PTY and evicts the tab', async () => {
    const buf = await openWs(`/shell/kill-me?token=${AUTH_TOKEN}&cols=80&rows=24`);
    await buf.waitForMessages(1);
    buf.ws.send(JSON.stringify({ type: 'kill' }));
    await waitFor(() => expect(adapter.has('kill-me')).toBe(false));
    buf.close();
  });

  it('refresh control frame is silently ignored (spec v2 removed op)', async () => {
    const buf = await openWs(`/shell/tab-1?token=${AUTH_TOKEN}&cols=80&rows=24`);
    await buf.waitForMessages(1);
    buf.ws.send(JSON.stringify({ type: 'refresh' }));
    await new Promise((r) => setTimeout(r, 50));
    expect(buf.ws.readyState).toBe(WebSocket.OPEN);
    buf.close();
  });

  it('oversized binary input frame closes WS with 1009', async () => {
    const buf = await openWs(`/shell/tab-1?token=${AUTH_TOKEN}&cols=80&rows=24`);
    await buf.waitForMessages(1);
    buf.ws.send(Buffer.alloc(65, 'x'), { binary: true });
    const code = await buf.waitForClose();
    expect(code).toBe(1009);
  });

  it('WS close leaves session in DETACHED state (attached:false) during grace', async () => {
    const buf = await openWs(`/shell/tab-grace?token=${AUTH_TOKEN}&cols=80&rows=24`);
    await buf.waitForMessages(1);
    buf.close();
    await buf.waitForClose();

    await waitFor(() => {
      const t = adapter.listTabs().find((x) => x.tabId === 'tab-grace');
      expect(t).toBeDefined();
      expect(t!.attached).toBe(false);
    }, 2_000);
  });
});

// ── Validation ───────────────────────────────────────────────

describe('WS /shell/:tabId — validation', () => {
  it('invalid tabId (regex rejected chars) closes with 1008', async () => {
    // Slash is outside the [a-zA-Z0-9._-] regex → route closes with 1008
    // before the WS upgrade resolves data events. We bypass the URL
    // segment by using a query-param smuggle style: `/shell/bad%2Fid`
    // keeps `:tabId` = `bad/id`.
    const code = await openWsExpectingClose(
      `/shell/bad%2Fid?token=${AUTH_TOKEN}&cols=80&rows=24`,
    );
    expect(code).toBe(1008);
  });

  it('invalid cols (out of bounds) closes with 1008', async () => {
    const code = await openWsExpectingClose(
      `/shell/tab-1?token=${AUTH_TOKEN}&cols=9999&rows=24`,
    );
    expect(code).toBe(1008);
  });

  it('second viewer on same tab is rejected with 4001', async () => {
    const a = await openWs(`/shell/duo?token=${AUTH_TOKEN}&cols=80&rows=24`);
    await a.waitForMessages(1);
    const code = await openWsExpectingClose(
      `/shell/duo?token=${AUTH_TOKEN}&cols=80&rows=24`,
    );
    expect(code).toBe(4001);
    a.close();
  });
});

// ── REST endpoints ───────────────────────────────────────────

describe('GET /shell/tabs', () => {
  it('401 without auth, [] with auth when no tabs', async () => {
    const unauth = await app.inject({ method: 'GET', url: '/shell/tabs' });
    expect(unauth.statusCode).toBe(401);

    const authed = await app.inject({ method: 'GET', url: `/shell/tabs?token=${AUTH_TOKEN}` });
    expect(authed.statusCode).toBe(200);
    expect(authed.json()).toEqual([]);
  });

  it('returns one entry per live tab in new shape', async () => {
    const buf = await openWs(`/shell/list-me?token=${AUTH_TOKEN}&cols=80&rows=24`);
    await buf.waitForMessages(1);

    const res = await app.inject({ method: 'GET', url: `/shell/tabs?token=${AUTH_TOKEN}` });
    expect(res.statusCode).toBe(200);
    const tabs = res.json() as Array<{ tabId: string; attached: boolean; lastActivityAt: string }>;
    const t = tabs.find((x) => x.tabId === 'list-me');
    expect(t).toBeDefined();
    expect(t!.attached).toBe(true);
    expect(typeof t!.lastActivityAt).toBe('string');
    buf.close();
  });
});

describe('POST /shell/:tabId/kill', () => {
  it('204 on known tab, kills PTY', async () => {
    const buf = await openWs(`/shell/rest-kill?token=${AUTH_TOKEN}&cols=80&rows=24`);
    await buf.waitForMessages(1);

    const res = await app.inject({
      method: 'POST',
      url: `/shell/rest-kill/kill?token=${AUTH_TOKEN}`,
    });
    expect(res.statusCode).toBe(204);

    await waitFor(() => expect(adapter.has('rest-kill')).toBe(false));
    buf.close();
  });

  it('404 on unknown tabId', async () => {
    const res = await app.inject({
      method: 'POST',
      url: `/shell/not-a-tab/kill?token=${AUTH_TOKEN}`,
    });
    expect(res.statusCode).toBe(404);
  });

  it('401 without auth', async () => {
    const res = await app.inject({ method: 'POST', url: '/shell/x/kill' });
    expect(res.statusCode).toBe(401);
  });

  it('400 on invalid tabId regex', async () => {
    const res = await app.inject({
      method: 'POST',
      url: `/shell/bad%2Fid/kill?token=${AUTH_TOKEN}`,
    });
    expect(res.statusCode).toBe(400);
  });
});
