/**
 * PtyAdapter — plain PTY per tab, no multiplexer.
 *
 * Replaces the tmux-backed Wave 1 adapter. Holds an in-memory map of
 * PTY sessions keyed by tabId, with a configurable 30-min disconnect
 * grace + per-session ring buffer for replay on reattach.
 *
 * State machine per session:
 *   IDLE → ACTIVE (first attach spawns PTY)
 *   ACTIVE ↔ DETACHED (viewer comes/goes; PTY persists)
 *   DETACHED → TERMINATED (grace timer fires)
 *   ACTIVE → TERMINATED (kill or natural PTY exit)
 *
 * Multi-device simultaneous attach is OUT OF SCOPE — second viewer on an
 * already-attached tab is rejected. See `// FUTURE: multi-user` markers
 * for the path forward when team-server mode lands.
 *
 * Spec: docs/TERMINAL-PROTOCOL-SPEC.md
 */
import * as pty from 'node-pty';
import type { IPty } from 'node-pty';
import { homedir } from 'node:os';
import { logger } from '../utils/logger.js';

/** Max bytes per client→server input frame. Spec: env MAJOR_TOM_PTY_INPUT_MAX. */
export const DEFAULT_INPUT_MAX_BYTES = 64 * 1024;
/** Per-tab ring buffer cap. Spec: env MAJOR_TOM_PTY_BUFFER_BYTES. */
export const DEFAULT_BUFFER_BYTES = 256 * 1024;
/** Grace timer between WS detach and PTY kill. Spec: env MAJOR_TOM_PTY_GRACE_MS. */
export const DEFAULT_GRACE_MS = 30 * 60 * 1000;
/** Time SIGTERM has to land before SIGKILL escalation. */
const SIGKILL_DELAY_MS = 5_000;

/**
 * Minimal duck-typed WebSocket interface so the adapter can be unit-tested
 * without standing up a real `ws.WebSocket`. The real ws.WebSocket satisfies
 * this trivially.
 */
export interface PtyClient {
  readonly readyState: number;
  readonly OPEN: number;
  send(data: string | Buffer, opts?: { binary?: boolean }): void;
  close(code?: number, reason?: string): void;
}

export interface AttachOptions {
  cols: number;
  rows: number;
  /**
   * Per-spawn env extras merged into the new PTY's environment.
   * Only consulted on first spawn; reattach to an existing session ignores
   * this (the PTY's env is fixed at spawn time).
   */
  envExtras?: Record<string, string>;
}

export type AttachOutcome =
  | { kind: 'attached'; restored: boolean }
  | { kind: 'rejected'; reason: 'already-attached' };

export interface TabInfo {
  tabId: string;
  attached: boolean;
  lastActivityAt: string;
}

export interface PtyAdapterOptions {
  graceMs?: number;
  bufferBytes?: number;
  inputMaxBytes?: number;
  cwd?: string;
  /** Override for `process.env`. Defaults to `process.env`. */
  env?: Record<string, string | undefined>;
  /** Explicit shell path. Defaults to `env.SHELL || '/bin/bash'`. */
  shell?: string;
  /** Args to pass to the shell. Defaults to `['-l']` (login shell). */
  shellArgs?: string[];
  /** Spawn injection point — tests pass a stub or a script like `cat`. */
  spawn?: (file: string, args: string[], opts: pty.IPtyForkOptions) => IPty;
}

/**
 * FIFO byte ring with a hard cap. When `push` would exceed `max`, the
 * oldest chunks are evicted (whole-chunk granularity — we don't slice
 * inside a chunk because PTY data may contain partial UTF-8 sequences).
 */
export class RingBuffer {
  private chunks: Buffer[] = [];
  private bytes = 0;
  constructor(private readonly max: number) {}

  push(chunk: Buffer): void {
    if (chunk.length === 0) return;
    this.chunks.push(chunk);
    this.bytes += chunk.length;
    while (this.bytes > this.max && this.chunks.length > 0) {
      const dropped = this.chunks.shift();
      if (dropped) this.bytes -= dropped.length;
    }
  }

  drain(): Buffer {
    if (this.chunks.length === 0) return Buffer.alloc(0);
    return Buffer.concat(this.chunks);
  }

  get size(): number {
    return this.bytes;
  }
}

interface PtySession {
  tabId: string;
  pty: IPty;
  ring: RingBuffer;
  viewer?: PtyClient;
  graceTimer?: ReturnType<typeof setTimeout>;
  lastActivityAt: number;
  exited: boolean;
}

export class PtyAdapter {
  private readonly sessions = new Map<string, PtySession>();
  private readonly graceMs: number;
  private readonly bufferBytes: number;
  private readonly inputMaxBytes: number;
  private readonly cwd: string;
  private readonly env: Record<string, string | undefined>;
  private readonly shell: string;
  private readonly shellArgs: string[];
  private readonly spawnFn: (file: string, args: string[], opts: pty.IPtyForkOptions) => IPty;

  constructor(opts: PtyAdapterOptions = {}) {
    this.graceMs = opts.graceMs ?? DEFAULT_GRACE_MS;
    this.bufferBytes = opts.bufferBytes ?? DEFAULT_BUFFER_BYTES;
    this.inputMaxBytes = opts.inputMaxBytes ?? DEFAULT_INPUT_MAX_BYTES;
    this.env = opts.env ?? process.env;
    this.cwd = opts.cwd ?? this.env['HOME'] ?? homedir();
    this.shell = opts.shell ?? this.env['SHELL'] ?? '/bin/bash';
    this.shellArgs = opts.shellArgs ?? ['-l'];
    this.spawnFn = opts.spawn ?? pty.spawn;
  }

  /**
   * Attach a client to `tabId`. Behavior:
   * - IDLE (no session): spawn PTY, register, send `attached:false`.
   * - DETACHED (PTY alive in grace): cancel timer, send `attached:true`,
   *   replay ring buffer.
   * - ACTIVE with another viewer: reject. Caller should send
   *   `{type:"error"}` and close WS with code 4001.
   *
   * Spec: docs/TERMINAL-PROTOCOL-SPEC.md § Lifecycle State Machine.
   */
  attach(tabId: string, client: PtyClient, opts: AttachOptions): AttachOutcome {
    let session = this.sessions.get(tabId);
    if (session && session.viewer && session.viewer !== client) {
      // FUTURE: multi-user — replace this rejection with a viewer-set
      // broadcast so multiple devices can co-view the same tab.
      logger.warn({ tabId }, 'Attach rejected — tab already has a viewer');
      return { kind: 'rejected', reason: 'already-attached' };
    }

    let restored = false;
    if (session) {
      if (session.graceTimer) {
        clearTimeout(session.graceTimer);
        session.graceTimer = undefined;
      }
      session.viewer = client;
      restored = true;
      logger.info({ tabId }, 'Reattached within grace');
    } else {
      session = this.spawnSession(tabId, opts);
      session.viewer = client;
      logger.info({ tabId, pid: session.pty.pid }, 'Fresh PTY attached');
    }

    this.sendJson(client, { type: 'attached', tabId, restored });
    if (restored) {
      const replay = session.ring.drain();
      if (replay.length > 0) this.sendBinary(client, replay);
    }
    session.lastActivityAt = Date.now();
    return { kind: 'attached', restored };
  }

  /**
   * Detach the given client from `tabId`. PTY persists; grace timer starts.
   * If `client` doesn't match the session's current viewer (stale callback,
   * re-attach race), no-op.
   */
  detach(tabId: string, client: PtyClient): void {
    const session = this.sessions.get(tabId);
    if (!session) return;
    if (session.viewer !== client) return;
    session.viewer = undefined;
    if (session.graceTimer) clearTimeout(session.graceTimer);
    session.graceTimer = setTimeout(() => {
      const current = this.sessions.get(tabId);
      if (!current || current !== session) return;
      if (current.viewer) return;
      logger.info({ tabId, graceMs: this.graceMs }, 'Grace expired — terminating PTY');
      this.kill(tabId);
    }, this.graceMs);
    logger.info({ tabId, graceMs: this.graceMs }, 'Client detached — grace timer started');
  }

  /**
   * Forward a raw input frame from the client to the PTY.
   * Returns `false` when oversized — caller should close WS with 1009.
   */
  sendInput(tabId: string, buf: Buffer): boolean {
    if (buf.length > this.inputMaxBytes) {
      logger.warn(
        { tabId, frameBytes: buf.length, limit: this.inputMaxBytes },
        'PTY input frame exceeds limit',
      );
      return false;
    }
    const session = this.sessions.get(tabId);
    if (!session) return true;
    try {
      (session.pty as unknown as { write(d: Buffer): void }).write(buf);
      session.lastActivityAt = Date.now();
    } catch (err) {
      logger.warn({ err, tabId }, 'PTY write failed');
    }
    return true;
  }

  /**
   * Direct write — used by the hook approval handler to inject
   * `decision + '\n'` into the PTY when the user resolves an approval
   * from the phone. Bypasses the input frame cap (decisions are tiny).
   * Returns true on success, false if the tabId has no session.
   */
  write(tabId: string, data: string | Buffer): boolean {
    const session = this.sessions.get(tabId);
    if (!session) return false;
    try {
      const buf = typeof data === 'string' ? Buffer.from(data, 'utf-8') : data;
      (session.pty as unknown as { write(d: Buffer): void }).write(buf);
      session.lastActivityAt = Date.now();
      return true;
    } catch (err) {
      logger.warn({ err, tabId }, 'PTY direct write failed');
      return false;
    }
  }

  /** Resize the PTY. Bounds enforcement happens at the route layer. */
  resize(tabId: string, cols: number, rows: number): void {
    const session = this.sessions.get(tabId);
    if (!session) return;
    try {
      session.pty.resize(cols, rows);
      session.lastActivityAt = Date.now();
    } catch (err) {
      logger.warn({ err, tabId, cols, rows }, 'PTY resize failed');
    }
  }

  /**
   * Immediate termination — bypasses grace. SIGTERM, then SIGKILL after
   * a 5s safety net if the PTY still hasn't exited.
   */
  kill(tabId: string): void {
    const session = this.sessions.get(tabId);
    if (!session) return;
    try {
      session.pty.kill('SIGTERM');
    } catch {
      // already dead
    }
    const sigkillTimer = setTimeout(() => {
      try { session.pty.kill('SIGKILL'); } catch { /* already dead */ }
    }, SIGKILL_DELAY_MS);
    sigkillTimer.unref();
    this.evict(tabId);
  }

  has(tabId: string): boolean {
    return this.sessions.has(tabId);
  }

  /**
   * Snapshot of all live tabs. Backs `GET /shell/tabs`.
   * Sorted by `lastActivityAt` descending so most recent appears first.
   */
  listTabs(): TabInfo[] {
    return [...this.sessions.values()]
      .map((s) => ({
        tabId: s.tabId,
        attached: s.viewer !== undefined,
        lastActivityAt: new Date(s.lastActivityAt).toISOString(),
      }))
      .sort((a, b) => (a.lastActivityAt < b.lastActivityAt ? 1 : -1));
  }

  /**
   * Stop all timers, kill all PTYs, drop the session map.
   * Tests call this in `afterEach`; production calls it from `onClose`.
   */
  dispose(): void {
    for (const [tabId, session] of this.sessions) {
      if (session.graceTimer) clearTimeout(session.graceTimer);
      try { session.pty.kill('SIGKILL'); } catch { /* ignore */ }
      this.sessions.delete(tabId);
      logger.debug({ tabId }, 'Adapter disposed — session cleared');
    }
  }

  private spawnSession(tabId: string, opts: AttachOptions): PtySession {
    const env: Record<string, string> = {};
    for (const [k, v] of Object.entries(this.env)) {
      if (typeof v === 'string') env[k] = v;
    }
    if (opts.envExtras) Object.assign(env, opts.envExtras);
    env['TERM'] = env['TERM'] ?? 'xterm-256color';
    env['COLORTERM'] = env['COLORTERM'] ?? 'truecolor';
    env['LANG'] = env['LANG'] ?? 'en_US.UTF-8';
    // Align PWD with the spawn cwd so shell prompts expanding `\W` (bash)
    // or equivalents render the correct basename on the very first prompt.
    // Without this, bash inherits whatever PWD the relay process has, and
    // the initial PS1 expansion can fall out of sync with the child's
    // actual working directory until the user runs `cd` or equivalent.
    env['PWD'] = this.cwd;

    const ptyProcess = this.spawnFn(this.shell, this.shellArgs, {
      name: 'xterm-256color',
      cols: opts.cols,
      rows: opts.rows,
      cwd: this.cwd,
      env,
      // Binary mode: node-pty's types claim `string` but with `encoding: null`
      // it emits Buffers. See microsoft/node-pty#489.
      encoding: null as unknown as undefined,
      handleFlowControl: true,
    });

    const session: PtySession = {
      tabId,
      pty: ptyProcess,
      ring: new RingBuffer(this.bufferBytes),
      lastActivityAt: Date.now(),
      exited: false,
    };
    this.sessions.set(tabId, session);

    (ptyProcess.onData as unknown as (cb: (data: string | Buffer) => void) => void)((data) => {
      const buf: Buffer = typeof data === 'string' ? Buffer.from(data, 'binary') : data;
      session.lastActivityAt = Date.now();
      if (session.viewer && session.viewer.readyState === session.viewer.OPEN) {
        // Live viewer gets the stream directly. Skip the ring on this
        // path — otherwise a reattach within grace would replay bytes
        // the client already rendered, visibly duplicating them in
        // xterm. Copilot caught this on PR #130 review.
        try {
          session.viewer.send(buf, { binary: true });
        } catch (err) {
          logger.warn({ err, tabId: session.tabId }, 'Failed to forward PTY data');
        }
      } else {
        // No live viewer — buffer for replay on reattach.
        session.ring.push(buf);
      }
    });

    ptyProcess.onExit(({ exitCode, signal }) => {
      if (session.exited) return;
      session.exited = true;
      logger.info({ tabId: session.tabId, exitCode, signal }, 'PTY exited');
      const v = session.viewer;
      if (v && v.readyState === v.OPEN) {
        try {
          this.sendJson(v, { type: 'exit', exitCode, signal });
          v.close(1000, 'pty-exited');
        } catch {
          // already closed
        }
      }
      this.evict(session.tabId);
    });

    return session;
  }

  private evict(tabId: string): void {
    const session = this.sessions.get(tabId);
    if (!session) return;
    if (session.graceTimer) {
      clearTimeout(session.graceTimer);
      session.graceTimer = undefined;
    }
    this.sessions.delete(tabId);
  }

  private sendJson(client: PtyClient, data: unknown): void {
    if (client.readyState !== client.OPEN) return;
    try {
      client.send(JSON.stringify(data));
    } catch {
      // peer gone — ignore
    }
  }

  private sendBinary(client: PtyClient, buf: Buffer): void {
    if (client.readyState !== client.OPEN) return;
    try {
      client.send(buf, { binary: true });
    } catch {
      // peer gone — ignore
    }
  }
}
