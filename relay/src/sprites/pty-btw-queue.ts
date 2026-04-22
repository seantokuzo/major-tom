/**
 * PtyBtwQueue — Per-subagent FIFO for `/btw` sprite messages routed into
 * PTY-backed claude sessions (the daily iOS flow).
 *
 * Why a separate queue from `BtwQueue`:
 *   `BtwQueue` injects a new user turn via the in-process Anthropic SDK
 *   session. PTY sessions have no SDK worker — claude runs as a child
 *   process inside an xterm PTY per tab. The only way to feed it a new
 *   user turn is to write the framed text to the PTY's stdin as if the
 *   user typed it.
 *
 * Design:
 *   - One queue per process; keyed by subagentId → FIFO of entries.
 *   - At enqueue we resolve `sessionId → tabId` via `TabRegistry`. Missing
 *     tab → drop with `Agent dismissed — response unavailable` (Option 2
 *     from the Wave A plan; avoids the ambiguous "No active session" text).
 *   - Only one entry per subagent is awaiting a response at a time.
 *     Anything queued behind waits until the current entry finalizes.
 *   - Injection is a direct `adapter.write(tabId, constrainedText + '\n')`.
 *     We do NOT use a literal `/btw` slash command — the SDK path sends
 *     `constrainedText` as a normal user turn, and claude TUI accepts the
 *     same text identically.
 *   - Response correlation taps `adapter.onOutput(tabId, ...)`. A 2s
 *     quiet-period settle-timer fires finalize; a hard 30s max-wait
 *     backs it up in case the subagent is buried in a long-running tool.
 *     The captured output is stripped of ANSI escapes and truncated to
 *     the tail (claude's final answer tends to sit at the end).
 *
 * Events:
 *   injected  — the framed text has been written into the PTY
 *   responded — settle/max-wait fired; `text` carries the cleaned reply
 *   dropped   — entry was abandoned (tab gone, subagent dismissed, etc.)
 */

import { EventEmitter } from 'node:events';
import { logger } from '../utils/logger.js';
import { buildConstrainedText } from './btw-queue.js';

export type PtyBtwEntryStatus = 'queued' | 'awaiting_response';

export interface PtyBtwEnqueueInput {
  sessionId: string;
  subagentId: string;
  spriteHandle: string;
  messageId: string;
  userText: string;
  role: string;
  task: string;
}

export type PtyBtwEnqueueResult =
  | { kind: 'accepted'; entry: PtyBtwQueueEntry }
  | { kind: 'no-tab'; reason: string };

export interface PtyBtwQueueEntry {
  sessionId: string;
  tabId: string;
  subagentId: string;
  spriteHandle: string;
  messageId: string;
  userText: string;
  constrainedText: string;
  queuedAt: number;
  status: PtyBtwEntryStatus;
  injectedAt?: number;
}

/** Internal mutable state kept alongside an entry but not exposed. */
interface EntryPrivate {
  output: string[];
  settleTimer?: ReturnType<typeof setTimeout>;
  maxWaitTimer?: ReturnType<typeof setTimeout>;
}

export interface PtyBtwQueueEventMap {
  injected: {
    sessionId: string;
    tabId: string;
    subagentId: string;
    spriteHandle: string;
    messageId: string;
  };
  responded: {
    sessionId: string;
    tabId: string;
    subagentId: string;
    spriteHandle: string;
    messageId: string;
    text: string;
  };
  dropped: {
    sessionId: string;
    tabId: string;
    subagentId: string;
    spriteHandle: string;
    messageId: string;
    reason: string;
  };
}

export interface PtyBtwQueueOptions {
  /** Quiet period after last output chunk before we finalize. Default 2s. */
  settleMs?: number;
  /** Hard cap from inject to finalize. Default 30s. */
  maxWaitMs?: number;
  /** Response text truncation cap. Default 1200 chars. */
  maxResponseChars?: number;
  /** Smallest delay between inject and the earliest finalize. Default 250ms. */
  minWaitMs?: number;
}

export interface PtyBtwAdapter {
  write(tabId: string, data: string | Buffer): boolean;
  onOutput(tabId: string, listener: (chunk: Buffer) => void): () => void;
  has(tabId: string): boolean;
}

export interface PtyBtwTabRegistry {
  getTabForSession(sessionId: string): { tabId: string } | undefined;
}

export interface PtyBtwQueueDeps {
  adapter: PtyBtwAdapter;
  tabRegistry: PtyBtwTabRegistry;
}

type Listener<T> = (payload: T) => void;

export class PtyBtwQueue extends EventEmitter {
  private readonly bySubagent = new Map<string, PtyBtwQueueEntry[]>();
  private readonly byMessageId = new Map<string, PtyBtwQueueEntry>();
  private readonly privateState = new WeakMap<PtyBtwQueueEntry, EntryPrivate>();
  /** tabId → { unsub, refCount } — multiplex a single listener per tab. */
  private readonly tapsByTab = new Map<string, { unsub: () => void; refCount: number }>();
  private readonly settleMs: number;
  private readonly maxWaitMs: number;
  private readonly maxResponseChars: number;
  private readonly minWaitMs: number;

  constructor(
    private readonly deps: PtyBtwQueueDeps,
    opts: PtyBtwQueueOptions = {},
  ) {
    super();
    this.setMaxListeners(50);
    this.settleMs = opts.settleMs ?? 2_000;
    this.maxWaitMs = opts.maxWaitMs ?? 30_000;
    this.maxResponseChars = opts.maxResponseChars ?? 1200;
    this.minWaitMs = opts.minWaitMs ?? 250;
  }

  /**
   * Enqueue a /btw for a PTY-backed session. Resolves `sessionId → tabId`
   * upfront so the caller learns immediately if the tab is gone (no
   * separate "queued then quietly dropped" state).
   */
  enqueue(input: PtyBtwEnqueueInput): PtyBtwEnqueueResult {
    const tab = this.deps.tabRegistry.getTabForSession(input.sessionId);
    if (!tab || !this.deps.adapter.has(tab.tabId)) {
      return {
        kind: 'no-tab',
        reason: 'Agent dismissed — response unavailable',
      };
    }
    const entry: PtyBtwQueueEntry = {
      sessionId: input.sessionId,
      tabId: tab.tabId,
      subagentId: input.subagentId,
      spriteHandle: input.spriteHandle,
      messageId: input.messageId,
      userText: input.userText,
      constrainedText: buildConstrainedText({
        role: input.role,
        task: input.task,
        userText: input.userText,
      }),
      queuedAt: Date.now(),
      status: 'queued',
    };
    this.privateState.set(entry, { output: [] });
    this.byMessageId.set(entry.messageId, entry);
    const list = this.bySubagent.get(entry.subagentId) ?? [];
    list.push(entry);
    this.bySubagent.set(entry.subagentId, list);
    logger.info(
      {
        sessionId: entry.sessionId,
        tabId: entry.tabId,
        subagentId: entry.subagentId,
        spriteHandle: entry.spriteHandle,
        messageId: entry.messageId,
        queueDepth: list.length,
      },
      'PtyBtwQueue: enqueued',
    );
    // Drain on a microtask so the WS handler can emit the `queued` ack
    // before the PTY echoes the injected text.
    queueMicrotask(() => this.drainFor(entry.subagentId));
    return { kind: 'accepted', entry };
  }

  private drainFor(subagentId: string): void {
    const list = this.bySubagent.get(subagentId);
    if (!list || list.length === 0) return;
    if (list.some(e => e.status === 'awaiting_response')) return;
    const head = list.find(e => e.status === 'queued');
    if (!head) return;
    this.inject(head);
  }

  private inject(entry: PtyBtwQueueEntry): void {
    this.attachTap(entry.tabId);
    const ok = this.deps.adapter.write(entry.tabId, entry.constrainedText + '\n');
    if (!ok) {
      this.detachTap(entry.tabId);
      this.dropInternal(entry, 'PTY tab unavailable');
      return;
    }
    entry.status = 'awaiting_response';
    entry.injectedAt = Date.now();
    const priv = this.privateState.get(entry)!;
    priv.maxWaitTimer = setTimeout(() => {
      logger.warn(
        {
          sessionId: entry.sessionId,
          tabId: entry.tabId,
          subagentId: entry.subagentId,
          messageId: entry.messageId,
        },
        'PtyBtwQueue: max-wait reached, finalizing with whatever was captured',
      );
      this.finalize(entry, 'max-wait');
    }, this.maxWaitMs);
    // Seed a minWait settle so instant replies still get at least a beat
    // of capture time before we declare the turn done.
    priv.settleTimer = setTimeout(() => {
      this.finalize(entry, 'settled');
    }, Math.max(this.minWaitMs, this.settleMs));
    this.emit('injected', {
      sessionId: entry.sessionId,
      tabId: entry.tabId,
      subagentId: entry.subagentId,
      spriteHandle: entry.spriteHandle,
      messageId: entry.messageId,
    });
    logger.info(
      {
        sessionId: entry.sessionId,
        tabId: entry.tabId,
        subagentId: entry.subagentId,
        messageId: entry.messageId,
        textLen: entry.constrainedText.length,
      },
      'PtyBtwQueue: injected',
    );
  }

  private attachTap(tabId: string): void {
    const existing = this.tapsByTab.get(tabId);
    if (existing) {
      existing.refCount++;
      return;
    }
    const unsub = this.deps.adapter.onOutput(tabId, (chunk) => this.onChunk(tabId, chunk));
    this.tapsByTab.set(tabId, { unsub, refCount: 1 });
  }

  private detachTap(tabId: string): void {
    const existing = this.tapsByTab.get(tabId);
    if (!existing) return;
    existing.refCount -= 1;
    if (existing.refCount > 0) return;
    try {
      existing.unsub();
    } catch (err) {
      logger.warn({ err, tabId }, 'PtyBtwQueue: onOutput unsub threw');
    }
    this.tapsByTab.delete(tabId);
  }

  private onChunk(tabId: string, chunk: Buffer): void {
    const text = chunk.toString('utf8');
    for (const entry of this.byMessageId.values()) {
      if (entry.tabId !== tabId) continue;
      if (entry.status !== 'awaiting_response') continue;
      const priv = this.privateState.get(entry);
      if (!priv) continue;
      priv.output.push(text);
      if (priv.settleTimer) clearTimeout(priv.settleTimer);
      priv.settleTimer = setTimeout(() => this.finalize(entry, 'settled'), this.settleMs);
    }
  }

  private finalize(entry: PtyBtwQueueEntry, why: 'settled' | 'max-wait'): void {
    if (entry.status !== 'awaiting_response') return;
    const priv = this.privateState.get(entry);
    if (priv) {
      if (priv.settleTimer) clearTimeout(priv.settleTimer);
      if (priv.maxWaitTimer) clearTimeout(priv.maxWaitTimer);
    }
    const raw = priv ? priv.output.join('') : '';
    const text = cleanPtyResponse(raw, entry.constrainedText, this.maxResponseChars);
    const subagentId = entry.subagentId;
    this.remove(entry);
    this.detachTap(entry.tabId);
    this.emit('responded', {
      sessionId: entry.sessionId,
      tabId: entry.tabId,
      subagentId: entry.subagentId,
      spriteHandle: entry.spriteHandle,
      messageId: entry.messageId,
      text:
        text ||
        (why === 'max-wait'
          ? '(Agent did not respond — check the terminal tab)'
          : '(No response text captured — check the terminal tab)'),
    });
    logger.info(
      {
        sessionId: entry.sessionId,
        tabId: entry.tabId,
        subagentId: entry.subagentId,
        messageId: entry.messageId,
        why,
        rawLen: raw.length,
        textLen: text.length,
      },
      'PtyBtwQueue: finalized response',
    );
    queueMicrotask(() => this.drainFor(subagentId));
  }

  private dropInternal(entry: PtyBtwQueueEntry, reason: string): void {
    const priv = this.privateState.get(entry);
    if (priv) {
      if (priv.settleTimer) clearTimeout(priv.settleTimer);
      if (priv.maxWaitTimer) clearTimeout(priv.maxWaitTimer);
    }
    const wasAwaiting = entry.status === 'awaiting_response';
    this.remove(entry);
    if (wasAwaiting) this.detachTap(entry.tabId);
    this.emit('dropped', {
      sessionId: entry.sessionId,
      tabId: entry.tabId,
      subagentId: entry.subagentId,
      spriteHandle: entry.spriteHandle,
      messageId: entry.messageId,
      reason,
    });
    logger.info(
      {
        sessionId: entry.sessionId,
        tabId: entry.tabId,
        subagentId: entry.subagentId,
        messageId: entry.messageId,
        reason,
        wasAwaiting,
      },
      'PtyBtwQueue: dropped',
    );
  }

  private remove(entry: PtyBtwQueueEntry): void {
    this.byMessageId.delete(entry.messageId);
    const list = this.bySubagent.get(entry.subagentId);
    if (list) {
      const idx = list.indexOf(entry);
      if (idx >= 0) list.splice(idx, 1);
      if (list.length === 0) this.bySubagent.delete(entry.subagentId);
    }
    this.privateState.delete(entry);
  }

  /** Drop a specific entry by its messageId. Emits 'dropped'. */
  dropByMessageId(messageId: string, reason: string): PtyBtwQueueEntry | undefined {
    const entry = this.byMessageId.get(messageId);
    if (!entry) return undefined;
    this.dropInternal(entry, reason);
    return entry;
  }

  /** Drop all entries for a subagent. Emits 'dropped' per entry. */
  dropForSubagent(subagentId: string, reason: string): number {
    const list = this.bySubagent.get(subagentId);
    if (!list || list.length === 0) return 0;
    const snapshot = [...list];
    for (const entry of snapshot) this.dropInternal(entry, reason);
    return snapshot.length;
  }

  /** Drop all entries in the session. Emits 'dropped' per entry. */
  dropForSession(sessionId: string, reason: string): number {
    let count = 0;
    for (const entry of [...this.byMessageId.values()]) {
      if (entry.sessionId !== sessionId) continue;
      this.dropInternal(entry, reason);
      count += 1;
    }
    return count;
  }

  /** Drop all entries tied to a PTY tab. Used by onTabClosed. */
  dropForTab(tabId: string, reason: string): number {
    let count = 0;
    for (const entry of [...this.byMessageId.values()]) {
      if (entry.tabId !== tabId) continue;
      this.dropInternal(entry, reason);
      count += 1;
    }
    const existing = this.tapsByTab.get(tabId);
    if (existing) {
      // The PTY is gone — unsubscribing via the adapter would no-op, but
      // clear our bookkeeping so a future enqueue with a new tabId of the
      // same id (unlikely but possible) starts clean.
      try {
        existing.unsub();
      } catch {
        /* ignore */
      }
      this.tapsByTab.delete(tabId);
    }
    return count;
  }

  sizeFor(subagentId: string): number {
    return this.bySubagent.get(subagentId)?.length ?? 0;
  }

  get size(): number {
    return this.byMessageId.size;
  }

  dispose(): void {
    for (const entry of [...this.byMessageId.values()]) {
      const priv = this.privateState.get(entry);
      if (priv) {
        if (priv.settleTimer) clearTimeout(priv.settleTimer);
        if (priv.maxWaitTimer) clearTimeout(priv.maxWaitTimer);
      }
    }
    for (const tap of this.tapsByTab.values()) {
      try {
        tap.unsub();
      } catch {
        /* ignore */
      }
    }
    this.bySubagent.clear();
    this.byMessageId.clear();
    this.tapsByTab.clear();
    this.removeAllListeners();
  }

  override on<K extends keyof PtyBtwQueueEventMap>(
    event: K,
    listener: Listener<PtyBtwQueueEventMap[K]>,
  ): this;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  override on(event: string, listener: (...args: any[]) => void): this {
    return super.on(event, listener);
  }

  override emit<K extends keyof PtyBtwQueueEventMap>(
    event: K,
    payload: PtyBtwQueueEventMap[K],
  ): boolean;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  override emit(event: string, ...args: any[]): boolean {
    return super.emit(event, ...args);
  }
}

// ── Helpers ────────────────────────────────────────────────────

/**
 * Strip common ANSI escape sequences from `s`. Covers CSI (`\x1b[...`),
 * OSC titles (`\x1b]...BEL or ST`), DCS/APC/PM/SOS (`\x1b[PX^_]...\x1b\\`),
 * and lone single-char escapes (e.g. `\x1b=`). Not a full parser — good
 * enough for claude TUI output, which is mostly CSI + SGR.
 */
export function stripAnsi(s: string): string {
  return (
    s
      // eslint-disable-next-line no-control-regex
      .replace(/\u001b\][^\u0007]*(?:\u0007|\u001b\\)/g, '')
      // eslint-disable-next-line no-control-regex
      .replace(/\u001b[PX^_][\s\S]*?\u001b\\/g, '')
      // eslint-disable-next-line no-control-regex
      .replace(/\u001b\[[0-?]*[ -/]*[@-~]/g, '')
      // eslint-disable-next-line no-control-regex
      .replace(/\u001b[@-Z\\-_]/g, '')
  );
}

/**
 * Turn raw PTY bytes into something the sprite bubble can render. Strips
 * ANSI, normalizes CR/LF, drops the echoed framed text if we can find it,
 * and truncates to the tail (claude's actual answer tends to sit at the
 * end of the captured block after any tool/thinking output).
 */
export function cleanPtyResponse(raw: string, framedText: string, maxChars: number): string {
  let text = stripAnsi(raw);
  text = text.replace(/\r\n/g, '\n').replace(/\r/g, '\n');
  text = text
    .split('\n')
    .map(l => l.replace(/[ \t]+$/, ''))
    .join('\n');
  // Drop the echoed input if we can find it. The TUI sometimes wraps/re-
  // flows the line, so we match on the first chunk of the framed text and
  // trust the length to jump past the rest.
  const fingerprint = framedText.slice(0, 40).trim();
  if (fingerprint.length > 0) {
    const idx = text.indexOf(fingerprint);
    if (idx >= 0) {
      const after = text.slice(idx + framedText.length);
      if (after.trim().length > 0) text = after;
    }
  }
  text = text.replace(/\n{3,}/g, '\n\n').trim();
  if (text.length > maxChars) text = text.slice(-maxChars);
  return text;
}
