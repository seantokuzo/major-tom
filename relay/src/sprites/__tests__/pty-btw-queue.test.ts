/**
 * Unit tests for `PtyBtwQueue`.
 *
 * Uses fake timers + a stub adapter/registry so the 2s settle and 30s
 * max-wait timers exercise quickly and deterministically. Real PTY
 * integration is covered by the `PtyAdapter.onOutput` test in
 * pty-adapter.test.ts.
 */
import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import {
  PtyBtwQueue,
  cleanPtyResponse,
  stripAnsi,
  type PtyBtwAdapter,
  type PtyBtwTabRegistry,
} from '../pty-btw-queue.js';

// ── Stubs ─────────────────────────────────────────────────────

interface StubWrite {
  tabId: string;
  data: string;
}

interface StubAdapter extends PtyBtwAdapter {
  writes: StubWrite[];
  chunks: (tabId: string, chunk: string) => void;
  hasReturnsFalseFor: Set<string>;
  tabs: Set<string>;
}

function makeStubAdapter(): StubAdapter {
  const listeners = new Map<string, Set<(c: Buffer) => void>>();
  const writes: StubWrite[] = [];
  const hasReturnsFalseFor = new Set<string>();
  const tabs = new Set<string>();
  return {
    writes,
    hasReturnsFalseFor,
    tabs,
    has(tabId) {
      return tabs.has(tabId) && !hasReturnsFalseFor.has(tabId);
    },
    write(tabId, data) {
      if (hasReturnsFalseFor.has(tabId)) return false;
      writes.push({ tabId, data: typeof data === 'string' ? data : data.toString('utf8') });
      return true;
    },
    onOutput(tabId, listener) {
      let set = listeners.get(tabId);
      if (!set) {
        set = new Set();
        listeners.set(tabId, set);
      }
      set.add(listener);
      return () => {
        const s = listeners.get(tabId);
        if (s) s.delete(listener);
      };
    },
    chunks(tabId, chunk) {
      const set = listeners.get(tabId);
      if (!set) return;
      for (const l of set) l(Buffer.from(chunk, 'utf8'));
    },
  };
}

function makeStubRegistry(sessionToTab: Record<string, string>): PtyBtwTabRegistry {
  return {
    getTabForSession(sessionId) {
      const tabId = sessionToTab[sessionId];
      return tabId ? { tabId } : undefined;
    },
  };
}

const SAMPLE_INPUT = {
  sessionId: 'sess-1',
  subagentId: 'agent-1',
  spriteHandle: 'sprite-A',
  messageId: 'msg-1',
  userText: 'hey whats up',
  role: 'explore',
  task: 'map the codebase',
};

// ── enqueue / drain ───────────────────────────────────────────

describe('PtyBtwQueue — enqueue & drain', () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });
  afterEach(() => {
    vi.useRealTimers();
  });

  it('writes the framed text into the PTY and emits injected', async () => {
    const adapter = makeStubAdapter();
    adapter.tabs.add('tab-1');
    const registry = makeStubRegistry({ 'sess-1': 'tab-1' });
    const q = new PtyBtwQueue(
      { adapter, tabRegistry: registry },
      { settleMs: 50, maxWaitMs: 1_000, minWaitMs: 10 },
    );

    const injected: unknown[] = [];
    q.on('injected', (ev) => injected.push(ev));

    const result = q.enqueue(SAMPLE_INPUT);
    expect(result.kind).toBe('accepted');

    // Microtask drain needs one flush
    await Promise.resolve();
    expect(adapter.writes).toHaveLength(1);
    expect(adapter.writes[0]!.tabId).toBe('tab-1');
    expect(adapter.writes[0]!.data).toContain('non-blocking observation');
    expect(adapter.writes[0]!.data.endsWith('\n')).toBe(true);
    expect(injected).toHaveLength(1);
  });

  it('returns no-tab when the session has no PTY tab', () => {
    const adapter = makeStubAdapter();
    const registry = makeStubRegistry({});
    const q = new PtyBtwQueue({ adapter, tabRegistry: registry });

    const result = q.enqueue(SAMPLE_INPUT);
    expect(result.kind).toBe('no-tab');
    if (result.kind === 'no-tab') {
      expect(result.reason).toMatch(/dismissed/i);
    }
  });

  it('returns no-tab when the tab exists in registry but adapter lost it', () => {
    const adapter = makeStubAdapter();
    // Tab present in registry but NOT in adapter.tabs
    const registry = makeStubRegistry({ 'sess-1': 'tab-gone' });
    const q = new PtyBtwQueue({ adapter, tabRegistry: registry });

    const result = q.enqueue(SAMPLE_INPUT);
    expect(result.kind).toBe('no-tab');
  });

  it('captures output chunks and finalizes after settle with cleaned text', async () => {
    const adapter = makeStubAdapter();
    adapter.tabs.add('tab-1');
    const registry = makeStubRegistry({ 'sess-1': 'tab-1' });
    const q = new PtyBtwQueue(
      { adapter, tabRegistry: registry },
      { settleMs: 50, maxWaitMs: 10_000, minWaitMs: 1 },
    );

    const responses: { messageId: string; text: string }[] = [];
    q.on('responded', (ev) => responses.push({ messageId: ev.messageId, text: ev.text }));

    q.enqueue(SAMPLE_INPUT);
    await Promise.resolve(); // drain microtask
    // Adapter writes the framed text; fake echo + response in output
    const framed = adapter.writes[0]!.data;
    adapter.chunks('tab-1', framed);
    adapter.chunks('tab-1', '\u001b[32mI am reading ws.ts right now.\u001b[0m\n');

    // Still inside settle window
    expect(responses).toHaveLength(0);
    await vi.advanceTimersByTimeAsync(60);
    expect(responses).toHaveLength(1);
    expect(responses[0]!.text).toBe('I am reading ws.ts right now.');
  });

  it('falls back to max-wait finalize when output never settles', async () => {
    const adapter = makeStubAdapter();
    adapter.tabs.add('tab-1');
    const registry = makeStubRegistry({ 'sess-1': 'tab-1' });
    const q = new PtyBtwQueue(
      { adapter, tabRegistry: registry },
      { settleMs: 500, maxWaitMs: 200, minWaitMs: 50 },
    );

    const responses: string[] = [];
    q.on('responded', (ev) => responses.push(ev.text));

    q.enqueue(SAMPLE_INPUT);
    await Promise.resolve();
    // Keep pushing chunks faster than settleMs so settle never fires first
    for (let i = 0; i < 20; i++) {
      adapter.chunks('tab-1', 'still working...\n');
      await vi.advanceTimersByTimeAsync(20);
    }
    // Advance past max-wait
    await vi.advanceTimersByTimeAsync(250);
    expect(responses).toHaveLength(1);
    expect(responses[0]).toMatch(/still working/);
  });

  it('queues a second /btw for the same subagent until the first finalizes', async () => {
    const adapter = makeStubAdapter();
    adapter.tabs.add('tab-1');
    const registry = makeStubRegistry({ 'sess-1': 'tab-1' });
    const q = new PtyBtwQueue(
      { adapter, tabRegistry: registry },
      { settleMs: 30, maxWaitMs: 1_000, minWaitMs: 1 },
    );

    q.enqueue({ ...SAMPLE_INPUT, messageId: 'm1', userText: 'first' });
    q.enqueue({ ...SAMPLE_INPUT, messageId: 'm2', userText: 'second' });
    await Promise.resolve();

    // Only the first should have been injected
    expect(adapter.writes).toHaveLength(1);
    expect(adapter.writes[0]!.data).toContain('first');

    // Settle the first
    adapter.chunks('tab-1', 'reply to first\n');
    await vi.advanceTimersByTimeAsync(40);
    await Promise.resolve();

    // Now the second should drain
    expect(adapter.writes).toHaveLength(2);
    expect(adapter.writes[1]!.data).toContain('second');
  });

  it('drains a different subagent in parallel even if another is in flight', async () => {
    const adapter = makeStubAdapter();
    adapter.tabs.add('tab-1');
    const registry = makeStubRegistry({ 'sess-1': 'tab-1' });
    const q = new PtyBtwQueue(
      { adapter, tabRegistry: registry },
      { settleMs: 1_000, maxWaitMs: 10_000, minWaitMs: 1 },
    );

    q.enqueue({ ...SAMPLE_INPUT, subagentId: 'agent-A', messageId: 'mA' });
    q.enqueue({ ...SAMPLE_INPUT, subagentId: 'agent-B', messageId: 'mB' });
    await Promise.resolve();

    // Both subagents' head /btw should have been written
    expect(adapter.writes).toHaveLength(2);
  });
});

// ── drop paths ────────────────────────────────────────────────

describe('PtyBtwQueue — drop paths', () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });
  afterEach(() => {
    vi.useRealTimers();
  });

  it('dropForSubagent clears queued + in-flight entries', async () => {
    const adapter = makeStubAdapter();
    adapter.tabs.add('tab-1');
    const registry = makeStubRegistry({ 'sess-1': 'tab-1' });
    const q = new PtyBtwQueue(
      { adapter, tabRegistry: registry },
      { settleMs: 5_000, maxWaitMs: 10_000, minWaitMs: 1 },
    );

    const drops: { messageId: string; reason: string }[] = [];
    q.on('dropped', (ev) => drops.push({ messageId: ev.messageId, reason: ev.reason }));

    q.enqueue({ ...SAMPLE_INPUT, messageId: 'mA' });
    q.enqueue({ ...SAMPLE_INPUT, messageId: 'mB' });
    await Promise.resolve();

    const dropped = q.dropForSubagent('agent-1', 'Subagent dismissed');
    expect(dropped).toBe(2);
    expect(drops.map(d => d.messageId).sort()).toEqual(['mA', 'mB']);
    expect(drops.every(d => d.reason === 'Subagent dismissed')).toBe(true);
    expect(q.size).toBe(0);
  });

  it('dropForTab clears entries and force-releases the tap', async () => {
    const adapter = makeStubAdapter();
    adapter.tabs.add('tab-1');
    const registry = makeStubRegistry({ 'sess-1': 'tab-1' });
    const q = new PtyBtwQueue(
      { adapter, tabRegistry: registry },
      { settleMs: 5_000, maxWaitMs: 10_000, minWaitMs: 1 },
    );

    q.enqueue(SAMPLE_INPUT);
    await Promise.resolve();

    const dropped = q.dropForTab('tab-1', 'PTY tab closed');
    expect(dropped).toBe(1);
    expect(q.size).toBe(0);

    // Subsequent chunks on the (now-gone) tap should be no-ops
    let rogue = false;
    q.on('responded', () => {
      rogue = true;
    });
    adapter.chunks('tab-1', 'late noise');
    await vi.advanceTimersByTimeAsync(6_000);
    expect(rogue).toBe(false);
  });

  it('drops when adapter.write returns false mid-flight', async () => {
    const adapter = makeStubAdapter();
    adapter.tabs.add('tab-1');
    const registry = makeStubRegistry({ 'sess-1': 'tab-1' });
    const q = new PtyBtwQueue({ adapter, tabRegistry: registry });

    const drops: string[] = [];
    q.on('dropped', (ev) => drops.push(ev.reason));

    adapter.hasReturnsFalseFor.add('tab-1'); // write() now returns false
    // But has() is still true at enqueue time since we removed tab-1 from the
    // false-set condition only during write. Work around by tweaking:
    adapter.hasReturnsFalseFor.delete('tab-1');
    // Simulate adapter.has true (for the enqueue check) but write false:
    const origWrite = adapter.write.bind(adapter);
    adapter.write = (tabId, data) => {
      if (tabId === 'tab-1') return false;
      return origWrite(tabId, data);
    };

    q.enqueue(SAMPLE_INPUT);
    await Promise.resolve();
    expect(drops).toHaveLength(1);
    expect(drops[0]).toMatch(/unavailable/i);
  });

  it('dispose clears all entries and listeners', async () => {
    const adapter = makeStubAdapter();
    adapter.tabs.add('tab-1');
    const registry = makeStubRegistry({ 'sess-1': 'tab-1' });
    const q = new PtyBtwQueue(
      { adapter, tabRegistry: registry },
      { settleMs: 5_000, maxWaitMs: 10_000, minWaitMs: 1 },
    );

    q.enqueue(SAMPLE_INPUT);
    await Promise.resolve();
    q.dispose();
    expect(q.size).toBe(0);

    // Any trailing timers should be no-ops
    await vi.advanceTimersByTimeAsync(11_000);
  });
});

// ── helpers ───────────────────────────────────────────────────

describe('stripAnsi', () => {
  it('strips SGR color codes', () => {
    expect(stripAnsi('\u001b[31mred\u001b[0m')).toBe('red');
  });
  it('strips cursor/erase CSI sequences', () => {
    expect(stripAnsi('\u001b[2J\u001b[H\u001b[K hello')).toBe(' hello');
  });
  it('strips OSC title escapes', () => {
    expect(stripAnsi('\u001b]0;terminal title\u0007hello')).toBe('hello');
  });
  it('leaves plain text intact', () => {
    expect(stripAnsi('hello world')).toBe('hello world');
  });
});

describe('cleanPtyResponse', () => {
  it('normalizes CR/LF to LF', () => {
    expect(cleanPtyResponse('line1\r\nline2\r\n', 'framed', 1000)).toBe('line1\nline2');
  });
  it('removes echoed framed text when present', () => {
    const framed =
      'The user sent a non-blocking observation via sprite tap to subagent "explore"';
    const raw = `${framed}\nresponse from claude here.\n`;
    expect(cleanPtyResponse(raw, framed, 1000)).toBe('response from claude here.');
  });
  it('truncates from the tail when exceeding maxChars', () => {
    const raw = 'a'.repeat(500) + 'TAIL-MARKER';
    const out = cleanPtyResponse(raw, 'unrelated framing', 50);
    expect(out.length).toBeLessThanOrEqual(50);
    expect(out.endsWith('TAIL-MARKER')).toBe(true);
  });
  it('collapses excessive blank lines', () => {
    expect(cleanPtyResponse('a\n\n\n\n\nb', 'framed', 1000)).toBe('a\n\nb');
  });
});
