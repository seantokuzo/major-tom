/**
 * Unit tests for `PtyAdapter`.
 *
 * Spawns `cat` (echoes stdin to stdout) instead of a real interactive
 * shell so tests stay fast and deterministic. The PTY layer's line
 * discipline echoes input as well as cat's output, so an `echo hello\n`
 * produces both the local echo and cat's playback in the data stream.
 */
import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import {
  PtyAdapter,
  RingBuffer,
  type PtyClient,
  type AttachOptions,
  DEFAULT_INPUT_MAX_BYTES,
} from '../pty-adapter.js';

// ── Mock client ─────────────────────────────────────────────

interface MockClient extends PtyClient {
  sent: Array<{ data: string | Buffer; binary: boolean }>;
  closed: { code?: number; reason?: string } | undefined;
  /** Called after `close` to simulate the WS settling closed. */
  markClosed(): void;
}

function makeClient(): MockClient {
  const c: MockClient = {
    OPEN: 1,
    readyState: 1,
    sent: [],
    closed: undefined,
    send(data, opts) {
      this.sent.push({ data, binary: opts?.binary === true });
    },
    close(code, reason) {
      this.closed = { code, reason };
    },
    markClosed() {
      (this as { readyState: number }).readyState = 3;
    },
  };
  return c;
}

const ATTACH_DEFAULTS: AttachOptions = { cols: 80, rows: 24 };

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

/** Build an adapter that spawns `cat` so PTYs stay alive and echo cleanly. */
function makeAdapter(overrides: Partial<ConstructorParameters<typeof PtyAdapter>[0]> = {}) {
  return new PtyAdapter({
    shell: '/bin/cat',
    shellArgs: [],
    graceMs: 200,
    bufferBytes: 1024,
    inputMaxBytes: 256,
    ...overrides,
  });
}

let adapter: PtyAdapter;

beforeEach(() => {
  adapter = makeAdapter();
});

afterEach(() => {
  adapter.dispose();
});

// ── 1. RingBuffer eviction (helper class) ──────────────────

describe('RingBuffer', () => {
  it('keeps everything under the cap', () => {
    const r = new RingBuffer(100);
    r.push(Buffer.alloc(40, 'a'));
    r.push(Buffer.alloc(40, 'b'));
    expect(r.size).toBe(80);
    expect(r.drain().length).toBe(80);
  });

  it('FIFO-evicts oldest chunks when over cap', () => {
    const r = new RingBuffer(100);
    r.push(Buffer.alloc(60, 'a'));
    r.push(Buffer.alloc(60, 'b'));
    expect(r.size).toBe(60);
    expect(r.drain().toString()).toBe('b'.repeat(60));
  });
});

// ── PtyAdapter behavior ─────────────────────────────────────

describe('PtyAdapter.attach', () => {
  it('spawns PTY on first attach and sends attached:false', () => {
    const client = makeClient();
    const out = adapter.attach('tab-1', client, ATTACH_DEFAULTS);
    expect(out).toEqual({ kind: 'attached', restored: false });
    expect(adapter.has('tab-1')).toBe(true);
    expect(client.sent[0]).toBeDefined();
    expect(client.sent[0]?.binary).toBe(false);
    expect(JSON.parse(client.sent[0]!.data as string)).toEqual({
      type: 'attached',
      tabId: 'tab-1',
      restored: false,
    });
  });

  it('rejects a second viewer on an already-attached tab', () => {
    const a = makeClient();
    const b = makeClient();
    expect(adapter.attach('tab-1', a, ATTACH_DEFAULTS).kind).toBe('attached');
    const out = adapter.attach('tab-1', b, ATTACH_DEFAULTS);
    expect(out).toEqual({ kind: 'rejected', reason: 'already-attached' });
    // Reject should NOT have queued an attached message on b.
    expect(b.sent.length).toBe(0);
  });

  it('attach for unknown tabId after grace expiry just spawns fresh', async () => {
    const client = makeClient();
    const first = adapter.attach('orphan', client, ATTACH_DEFAULTS);
    expect(first.kind).toBe('attached');
    adapter.detach('orphan', client);
    await waitFor(() => expect(adapter.has('orphan')).toBe(false), 1_500);

    const client2 = makeClient();
    const second = adapter.attach('orphan', client2, ATTACH_DEFAULTS);
    expect(second).toEqual({ kind: 'attached', restored: false });
  });
});

describe('PtyAdapter.sendInput / write', () => {
  it('forwards bytes to the PTY and echoes back via cat', async () => {
    const client = makeClient();
    adapter.attach('tab-1', client, ATTACH_DEFAULTS);
    expect(adapter.sendInput('tab-1', Buffer.from('hello\n'))).toBe(true);

    await waitFor(() => {
      const stream = Buffer.concat(
        client.sent.filter((s) => s.binary).map((s) => s.data as Buffer),
      ).toString('utf-8');
      expect(stream).toContain('hello');
    });
  });

  it('rejects oversized input frames without writing to PTY', () => {
    const client = makeClient();
    adapter.attach('tab-1', client, ATTACH_DEFAULTS);
    const huge = Buffer.alloc(257, 'x'); // adapter inputMaxBytes = 256
    expect(adapter.sendInput('tab-1', huge)).toBe(false);
  });

  it('write() injects bytes directly (hook approval inject path)', async () => {
    const client = makeClient();
    adapter.attach('tab-1', client, ATTACH_DEFAULTS);
    expect(adapter.write('tab-1', 'y\n')).toBe(true);

    await waitFor(() => {
      const stream = Buffer.concat(
        client.sent.filter((s) => s.binary).map((s) => s.data as Buffer),
      ).toString('utf-8');
      expect(stream).toContain('y');
    });
  });

  it('write() returns false for unknown tabId', () => {
    expect(adapter.write('does-not-exist', 'y\n')).toBe(false);
  });
});

describe('PtyAdapter.resize', () => {
  it('resizes the PTY without throwing', () => {
    const client = makeClient();
    adapter.attach('tab-1', client, ATTACH_DEFAULTS);
    expect(() => adapter.resize('tab-1', 132, 50)).not.toThrow();
  });
});

describe('PtyAdapter.detach + grace + ring buffer replay', () => {
  it('detach leaves session in DETACHED state then grace fires kill', async () => {
    const client = makeClient();
    adapter.attach('tab-1', client, ATTACH_DEFAULTS);
    adapter.detach('tab-1', client);
    expect(adapter.has('tab-1')).toBe(true); // still in grace

    await waitFor(() => expect(adapter.has('tab-1')).toBe(false), 1_500);
  });

  it('reattach within grace cancels timer + sends restored:true', async () => {
    const c1 = makeClient();
    adapter.attach('tab-1', c1, ATTACH_DEFAULTS);
    adapter.detach('tab-1', c1);

    const c2 = makeClient();
    const out = adapter.attach('tab-1', c2, ATTACH_DEFAULTS);
    expect(out).toEqual({ kind: 'attached', restored: true });
    expect(JSON.parse(c2.sent[0]!.data as string).restored).toBe(true);
  });

  it('only bytes produced while DETACHED are replayed on reattach (no dupes)', async () => {
    // Use a long grace so the PTY can't be reaped mid-test.
    const a = makeAdapter({ graceMs: 10_000 });
    try {
      const c1 = makeClient();
      a.attach('tab-1', c1, ATTACH_DEFAULTS);

      // While ATTACHED: send some data, wait for live echo. These bytes
      // go straight to the viewer and MUST NOT accumulate in the ring.
      a.sendInput('tab-1', Buffer.from('attached-phase\n'));
      await waitFor(() => {
        const seen = Buffer.concat(
          c1.sent.filter((s) => s.binary).map((s) => s.data as Buffer),
        ).toString('utf-8');
        expect(seen).toContain('attached-phase');
      });

      // Detach — PTY stays alive in grace. Subsequent PTY output now
      // buffers into the ring.
      a.detach('tab-1', c1);
      a.write('tab-1', 'detached-phase\n');

      // Give cat a tick to echo into the ring.
      await new Promise((r) => setTimeout(r, 150));

      const c2 = makeClient();
      const out = a.attach('tab-1', c2, ATTACH_DEFAULTS);
      expect(out).toEqual({ kind: 'attached', restored: true });
      const replay = Buffer.concat(
        c2.sent.filter((s) => s.binary).map((s) => s.data as Buffer),
      ).toString('utf-8');
      expect(replay).toContain('detached-phase');
      // Crucial: the attached-phase bytes must NOT be in the replay —
      // they were streamed live to c1, and replaying them to c2 would
      // visibly duplicate content the prior viewer already rendered.
      expect(replay).not.toContain('attached-phase');
    } finally {
      a.dispose();
    }
  });

  it('ring buffer caps at bufferBytes when over-pushed during DETACHED', async () => {
    const small = makeAdapter({ bufferBytes: 64, graceMs: 10_000 });
    try {
      const client = makeClient();
      small.attach('tab-1', client, ATTACH_DEFAULTS);
      // Detach first — subsequent PTY output then buffers into the ring.
      small.detach('tab-1', client);

      // Push enough bytes through cat to overflow the 64-byte ring.
      for (let i = 0; i < 10; i++) {
        small.write('tab-1', 'x'.repeat(50) + '\n');
      }

      // Give cat time to echo all chunks into the ring.
      await new Promise((r) => setTimeout(r, 300));

      const c2 = makeClient();
      small.attach('tab-1', c2, ATTACH_DEFAULTS);
      const replay = Buffer.concat(
        c2.sent.filter((s) => s.binary).map((s) => s.data as Buffer),
      );
      expect(replay.length).toBeGreaterThan(0);
      expect(replay.length).toBeLessThanOrEqual(64);
    } finally {
      small.dispose();
    }
  });
});

describe('PtyAdapter.kill + listTabs', () => {
  it('kill terminates PTY immediately and evicts session', async () => {
    const client = makeClient();
    adapter.attach('tab-1', client, ATTACH_DEFAULTS);
    expect(adapter.has('tab-1')).toBe(true);
    adapter.kill('tab-1');
    expect(adapter.has('tab-1')).toBe(false);
  });

  it('listTabs returns one entry per session with attached flag', () => {
    const c1 = makeClient();
    const c2 = makeClient();
    adapter.attach('a', c1, ATTACH_DEFAULTS);
    adapter.attach('b', c2, ATTACH_DEFAULTS);
    adapter.detach('b', c2);

    const tabs = adapter.listTabs();
    const byId = new Map(tabs.map((t) => [t.tabId, t]));
    expect(byId.get('a')?.attached).toBe(true);
    expect(byId.get('b')?.attached).toBe(false);
  });
});

describe('PtyAdapter natural exit', () => {
  it('PTY natural exit broadcasts {type:"exit"}, closes WS, evicts', async () => {
    // Use spawn injection so we can fire an exit synthetically — relying
    // on a real `exit` keystroke through `cat` exits abruptly under PTY
    // EOF semantics, which is flaky in CI. Synthetic exit via the mock
    // is the deterministic path.
    const onDataCbs: Array<(d: string | Buffer) => void> = [];
    const onExitCbs: Array<(e: { exitCode: number; signal?: number }) => void> = [];
    const fakePty = {
      pid: 12345,
      cols: 80,
      rows: 24,
      onData(cb: (d: string | Buffer) => void) { onDataCbs.push(cb); },
      onExit(cb: (e: { exitCode: number; signal?: number }) => void) { onExitCbs.push(cb); },
      kill: vi.fn(),
      resize: vi.fn(),
      write: vi.fn(),
    };
    const a = new PtyAdapter({
      // Cast — the spawn signature only needs a constructor that returns an IPty-like.
      spawn: (() => fakePty) as never,
      graceMs: 5_000,
    });
    try {
      const client = makeClient();
      a.attach('tab-1', client, ATTACH_DEFAULTS);
      onExitCbs[0]?.({ exitCode: 0, signal: undefined as unknown as number });

      // Last text frame should be the exit message.
      const exitFrame = client.sent.find(
        (s) => !s.binary && (s.data as string).includes('"exit"'),
      );
      expect(exitFrame).toBeDefined();
      expect(JSON.parse(exitFrame!.data as string).type).toBe('exit');
      expect(client.closed?.code).toBe(1000);
      expect(a.has('tab-1')).toBe(false);
    } finally {
      a.dispose();
    }
  });
});

describe('PtyAdapter shell selection', () => {
  it('falls back to /bin/bash when SHELL is unset (and no shell override)', () => {
    let captured: string | undefined;
    const fakePty = {
      pid: 1, cols: 80, rows: 24,
      onData() {}, onExit() {}, kill: vi.fn(), resize: vi.fn(), write: vi.fn(),
    };
    const env: Record<string, string | undefined> = {}; // no SHELL
    const a = new PtyAdapter({
      env,
      spawn: ((file: string) => {
        captured = file;
        return fakePty;
      }) as never,
    });
    try {
      a.attach('tab-1', makeClient(), ATTACH_DEFAULTS);
      expect(captured).toBe('/bin/bash');
    } finally {
      a.dispose();
    }
  });

  it('honors SHELL env when set', () => {
    let captured: string | undefined;
    const fakePty = {
      pid: 1, cols: 80, rows: 24,
      onData() {}, onExit() {}, kill: vi.fn(), resize: vi.fn(), write: vi.fn(),
    };
    const a = new PtyAdapter({
      env: { SHELL: '/usr/bin/zsh' },
      spawn: ((file: string) => {
        captured = file;
        return fakePty;
      }) as never,
    });
    try {
      a.attach('tab-1', makeClient(), ATTACH_DEFAULTS);
      expect(captured).toBe('/usr/bin/zsh');
    } finally {
      a.dispose();
    }
  });
});

describe('PtyAdapter spawn env prep', () => {
  it('sets PWD to the spawn cwd so first prompt \\W expands correctly', () => {
    let capturedEnv: Record<string, string> | undefined;
    const fakePty = {
      pid: 1, cols: 80, rows: 24,
      onData() {}, onExit() {}, kill: vi.fn(), resize: vi.fn(), write: vi.fn(),
    };
    const a = new PtyAdapter({
      cwd: '/Users/tester/projects/demo',
      env: { SHELL: '/bin/bash', HOME: '/Users/tester' },
      spawn: ((_file: string, _args: string[], opts: { env: Record<string, string> }) => {
        capturedEnv = opts.env;
        return fakePty;
      }) as never,
    });
    try {
      a.attach('tab-1', makeClient(), ATTACH_DEFAULTS);
      expect(capturedEnv?.PWD).toBe('/Users/tester/projects/demo');
    } finally {
      a.dispose();
    }
  });

  it('reattach within grace does NOT re-run env prep (first-spawn only)', () => {
    const envSpawns: Array<Record<string, string>> = [];
    const fakePty = {
      pid: 1, cols: 80, rows: 24,
      onData() {}, onExit() {}, kill: vi.fn(), resize: vi.fn(), write: vi.fn(),
    };
    const a = new PtyAdapter({
      cwd: '/tmp/work',
      graceMs: 5_000,
      env: { SHELL: '/bin/bash' },
      spawn: ((_file: string, _args: string[], opts: { env: Record<string, string> }) => {
        envSpawns.push(opts.env);
        return fakePty;
      }) as never,
    });
    try {
      const c1 = makeClient();
      a.attach('tab-1', c1, ATTACH_DEFAULTS);
      a.detach('tab-1', c1);
      a.attach('tab-1', makeClient(), ATTACH_DEFAULTS); // reattach
      expect(envSpawns.length).toBe(1);
      expect(envSpawns[0]?.PWD).toBe('/tmp/work');
    } finally {
      a.dispose();
    }
  });
});

describe('PtyAdapter constants', () => {
  it('default input max matches the spec', () => {
    expect(DEFAULT_INPUT_MAX_BYTES).toBe(64 * 1024);
  });
});
