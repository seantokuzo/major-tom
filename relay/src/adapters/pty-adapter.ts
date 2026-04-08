/**
 * PTY adapter — streams a tmux-attached pseudo-terminal over a WebSocket.
 *
 * Wave 1 scope: raw byte streaming, resize control, disposed guard,
 * multi-device attach via tmux's native window sharing. Wave 2 adds
 * CLAUDE_CONFIG_DIR + MAJOR_TOM_APPROVAL env plumbing.
 */
import * as pty from 'node-pty';
import type { IPty } from 'node-pty';
import type { WebSocket } from 'ws';
import { homedir } from 'node:os';
import { randomBytes } from 'node:crypto';
import { logger } from '../utils/logger.js';
import {
  MAJOR_TOM_SOCKET,
  createWindow,
  createViewSession,
  killSession,
  killWindow,
} from '../utils/tmux-cli.js';
import { tmuxBootstrap } from './tmux-bootstrap.js';
import { MAJOR_TOM_CONFIG_DIR } from '../installer/install-hooks.js';

export interface PtyAttachOptions {
  tabId: string;
  cols?: number;
  rows?: number;
}

/**
 * Hard cap on how much data a single client→server binary frame may
 * push into the PTY. The WebSocket-level `maxPayload` was bumped to
 * 8 MiB so the relay can stream large server→client redraws, but the
 * client→server direction has no legitimate need for big frames —
 * paste of an entire 8 MiB blob would be an attack, not a use case.
 * Caught by Copilot review on PR #89.
 */
const MAX_PTY_INPUT_BYTES = 64 * 1024;

export interface PtyHandle {
  tabId: string;
  /**
   * Unique per-attach tmux view session name (e.g. `view-t1-a3bf91c2`).
   * Created at attach time as a grouped session sharing the master session's
   * window set but tracking its OWN "current window" slot, so a second
   * client's attach can't pull this client's view onto a different window.
   * Killed in `dispose()` — killing a grouped session leaves the shared
   * windows alive because they belong to the master session.
   */
  viewSessionId: string;
  pty: IPty;
  socket: WebSocket;
  disposed: boolean;
  createdAt: Date;
}

// node-pty's `onData` is typed as `IEvent<string>` regardless of `encoding`.
// At runtime with `encoding: null` it emits `Buffer`. We keep the cast local
// so callers don't need to think about it.
// See microsoft/node-pty#489.
type PtyDataHandler = (data: string | Buffer) => void;

/**
 * Spawn a tmux attach into `tabId`, wire it to `socket`, and return the
 * handle. The handle is `disposed = true` once either side closes — writes
 * after disposal are a silent no-op (write-after-kill crash guard on macOS).
 *
 * Wave 2.6 change: each attach now creates its OWN grouped tmux "view"
 * session (`view-<tabId>-<randhex>`) which shares the master session's
 * window set but tracks an independent "current window" slot. This is the
 * fix for the session-handling bug where a second WS attaching with
 * `-t major-tom:t2` would forcibly switch every other client's view from
 * t1 to t2 (the master session has one shared current-window slot; a
 * grouped session is the tmux-native way to get per-client isolation).
 *
 * Callers may await tmuxBootstrap.ensure() first so route-level failures
 * surface from the WS handler with clean error reporting, but this function
 * still performs an idempotent bootstrap re-check before attaching as a
 * defensive guard against the tmux server being killed externally between
 * the route's bootstrap call and our spawn (Copilot review nit on PR #89).
 */
export async function attachPty(
  socket: WebSocket,
  options: PtyAttachOptions,
): Promise<PtyHandle> {
  const { tabId } = options;
  const cols = options.cols && options.cols > 0 ? options.cols : 80;
  const rows = options.rows && options.rows > 0 ? options.rows : 24;

  // Defensive re-check: the route already bootstrapped, but the tmux server
  // could have been killed externally in the gap before we spawn.
  await tmuxBootstrap.ensure();

  // Env vars that need to reach the SHELL inside the tmux window — must
  // be injected at `new-window -e` time, not on the tmux client. Wave 2:
  //
  //   CLAUDE_CONFIG_DIR    — points Claude Code at our private config dir
  //                          so the installed PreToolUse hook fires.
  //   MAJOR_TOM_CONFIG_DIR — same path, kept under a separate name so the
  //                          hook script can read approval-mode.json from
  //                          a stable place even if Claude Code remaps
  //                          CLAUDE_CONFIG_DIR.
  //   MAJOR_TOM_APPROVAL   — fallback default mode (the hook script
  //                          re-reads approval-mode.json on every call,
  //                          this is just the no-jq fallback).
  //   MAJOR_TOM_RELAY_PORT — internal hook HTTP server port. The hook
  //                          script POSTs to 127.0.0.1:<port>/hooks/...
  //                          NOT the WS port. Defaults to 9091, matching
  //                          server.ts's HOOK_PORT default.
  //   MAJOR_TOM_TAB_ID     — already injected pre-Wave-2; the hook script
  //                          forwards it as `X-MT-Tab` so the relay knows
  //                          which tmux window to target for hybrid mode.
  const hookPort = process.env['HOOK_PORT'] ?? '9091';
  await createWindow(tabId, {
    MAJOR_TOM_TAB_ID: tabId,
    CLAUDE_CONFIG_DIR: MAJOR_TOM_CONFIG_DIR,
    MAJOR_TOM_CONFIG_DIR: MAJOR_TOM_CONFIG_DIR,
    MAJOR_TOM_APPROVAL: process.env['MAJOR_TOM_APPROVAL'] ?? 'local',
    MAJOR_TOM_RELAY_PORT: hookPort,
  });

  // Create a unique per-attach grouped view session. Unique suffix so two
  // devices viewing the same tabId concurrently each get their own
  // current-window slot (no cross-contamination). 8 hex chars = 32 bits of
  // randomness, vastly more than enough to avoid collisions at human-scale
  // attach rates.
  const viewSessionId = `view-${tabId}-${randomBytes(4).toString('hex')}`;
  try {
    await createViewSession(viewSessionId, tabId);
  } catch (err) {
    logger.error(
      { err, tabId, viewSessionId },
      'Failed to create grouped view session — aborting PTY attach',
    );
    throw err;
  }

  // Env vars below only affect the tmux *client* process (this attach-
  // session), not the inner shell. We still set TERM/COLORTERM so xterm.js
  // negotiates a 256-color truecolor stream with the client side.
  const env: NodeJS.ProcessEnv = {
    ...process.env,
    LANG: process.env['LANG'] ?? 'en_US.UTF-8',
    TERM: 'xterm-256color',
    COLORTERM: 'truecolor',
  };

  // Wrap pty.spawn in try/catch so a spawn failure can clean up the
  // grouped view session we just created — otherwise a failed attach
  // would leak a `view-*` session inside the master tmux server forever
  // (no handle exists yet, so socket.on('close') → dispose() won't run).
  // Caught by Copilot PR #94 review.
  let ptyProcess: IPty;
  try {
    ptyProcess = pty.spawn(
      'tmux',
      [
        '-L', MAJOR_TOM_SOCKET,
        'attach-session',
        // No `-d`: allow concurrent tmux clients so the same shell window
        // can be observed from multiple devices (laptop + phone) at once.
        // Caught by Copilot review on PR #89 — `-d` would forcibly kick
        // every other attached client, defeating multi-device viewing.
        //
        // Wave 2.6: target the view session, NOT the master. Each attach
        // has its own grouped view session so current-window switches in
        // one client do not drag other clients along.
        '-t', viewSessionId,
      ],
      {
        name: 'xterm-256color',
        cols,
        rows,
        cwd: process.env['HOME'] ?? homedir(),
        env: env as { [key: string]: string },
        // Binary mode: `encoding: null` tells node-pty to emit Buffers on
        // onData. Types claim it's `string`, see #489 — we cast the handler.
        encoding: null as unknown as undefined,
        handleFlowControl: true,
      },
    );
  } catch (err) {
    logger.error(
      { err, tabId, viewSessionId },
      'pty.spawn failed after view session created — cleaning up grouped session',
    );
    try {
      await killSession(viewSessionId);
    } catch (cleanupErr) {
      logger.warn(
        { err: cleanupErr, viewSessionId },
        'Failed to clean up view session after pty.spawn failure',
      );
    }
    throw err;
  }

  const handle: PtyHandle = {
    tabId,
    viewSessionId,
    pty: ptyProcess,
    socket,
    disposed: false,
    createdAt: new Date(),
  };

  logger.info(
    { tabId, viewSessionId, pid: ptyProcess.pid, cols, rows },
    'PTY attached to tmux window via grouped view session',
  );

  // ── PTY → socket (binary frames) ────────────────────────────
  (ptyProcess.onData as unknown as (cb: PtyDataHandler) => void)((data) => {
    if (handle.disposed) return;
    if (socket.readyState !== socket.OPEN) return;
    const buf: Buffer =
      typeof data === 'string' ? Buffer.from(data, 'binary') : data;
    try {
      socket.send(buf, { binary: true });
    } catch (err) {
      logger.warn({ err, tabId }, 'Failed to forward PTY data to socket');
    }
  });

  ptyProcess.onExit(({ exitCode, signal }) => {
    if (handle.disposed) return;
    logger.info({ tabId, exitCode, signal }, 'PTY exited');
    // Notify the client with exit details BEFORE disposing. We intentionally
    // do NOT flip handle.disposed here — dispose() is the single source of
    // truth for that flag. Flipping it early meant the subsequent
    // socket.on('close') dispose call would short-circuit and `killSession`
    // would never run on the natural PTY-exit path, leaking the grouped
    // view session inside the master tmux server. Caught by Copilot PR #94
    // review.
    if (socket.readyState === socket.OPEN) {
      try {
        socket.send(JSON.stringify({ type: 'exit', exitCode, signal }));
        socket.close(1000, 'pty-exited');
      } catch {
        // socket already gone — ignore
      }
    }
    void dispose(handle, 'pty-exited');
  });

  // ── socket → PTY (binary = data, text = control JSON) ───────
  socket.on('message', (msg: Buffer, isBinary: boolean) => {
    if (handle.disposed) return;
    if (isBinary) {
      // App-level cap: 8 MiB maxPayload is for server→client redraws,
      // not for the client to push 8 MiB into the PTY in one frame.
      if (msg.length > MAX_PTY_INPUT_BYTES) {
        logger.warn(
          { tabId, frameBytes: msg.length, limit: MAX_PTY_INPUT_BYTES },
          'PTY input frame exceeds limit — dropping',
        );
        return;
      }
      writeSafe(handle, msg);
      return;
    }
    // Text frame: control message
    let ctrl: Record<string, unknown>;
    try {
      ctrl = JSON.parse(msg.toString('utf-8')) as Record<string, unknown>;
    } catch (err) {
      logger.warn({ err, tabId }, 'Invalid control JSON from client');
      return;
    }
    switch (ctrl['type']) {
      case 'resize': {
        const rawCols = Number(ctrl['cols']);
        const rawRows = Number(ctrl['rows']);
        if (
          Number.isFinite(rawCols) && rawCols >= 2 && rawCols <= 500 &&
          Number.isFinite(rawRows) && rawRows >= 2 && rawRows <= 500
        ) {
          try {
            ptyProcess.resize(Math.floor(rawCols), Math.floor(rawRows));
          } catch (err) {
            logger.warn({ err, tabId, cols: rawCols, rows: rawRows }, 'PTY resize failed');
          }
        }
        return;
      }
      case 'input': {
        // Allow clients to send text input as a JSON control frame too,
        // in case their WS impl can't do binary easily (e.g. debug tools).
        // Same MAX_PTY_INPUT_BYTES cap as the binary path so we can't
        // be flooded via the JSON channel either.
        const data = typeof ctrl['data'] === 'string' ? (ctrl['data'] as string) : '';
        if (data.length === 0) return;
        const buf = Buffer.from(data, 'utf-8');
        if (buf.length > MAX_PTY_INPUT_BYTES) {
          logger.warn(
            { tabId, frameBytes: buf.length, limit: MAX_PTY_INPUT_BYTES },
            'PTY JSON input frame exceeds limit — dropping',
          );
          return;
        }
        writeSafe(handle, buf);
        return;
      }
      case 'refresh': {
        // Bug 4: nudge tmux into repainting the visible window. When the
        // web client swaps between CLI tabs (display: none on the hidden
        // pane), tmux never repaints the off-screen window, so on
        // reactivation the xterm buffer shows stale content. A 1-col
        // resize wobble forces tmux to emit a full redraw without the
        // client needing to know tmux is involved at all.
        const currentCols = ptyProcess.cols;
        const currentRows = ptyProcess.rows;
        if (
          Number.isFinite(currentCols) && Number.isFinite(currentRows) &&
          currentCols > 2 && currentRows > 2
        ) {
          try {
            ptyProcess.resize(currentCols - 1, currentRows);
            ptyProcess.resize(currentCols, currentRows);
          } catch (err) {
            logger.warn(
              { err, tabId, cols: currentCols, rows: currentRows },
              'PTY refresh (resize wobble) failed',
            );
          }
        }
        return;
      }
      case 'kill': {
        // Wave 2.6: user deliberately closed the CLI tab (UI confirm modal
        // already in front of this path). Kill the underlying tmux WINDOW,
        // not just the view session — otherwise the shared window would
        // leak inside the master session forever, which is the "forgotten
        // sessions hanging around" problem the user called out.
        //
        // Fire-and-forget: tmux killing the window will naturally cause
        // every attached view session's PTY to exit (shell receives SIGHUP),
        // which triggers onExit → dispose() → socket close. We don't need
        // to reply to the client.
        logger.info({ tabId, viewSessionId }, 'Client requested kill-window');
        killWindow(tabId).catch((err) => {
          logger.warn({ err, tabId }, 'kill-window failed');
        });
        return;
      }
      default:
        logger.debug({ tabId, type: ctrl['type'] }, 'Ignoring unknown control frame');
    }
  });

  socket.on('close', () => {
    void dispose(handle, 'socket-closed');
  });
  socket.on('error', (err) => {
    logger.warn({ err, tabId }, 'Socket error on PTY session');
    void dispose(handle, 'socket-error');
  });

  return handle;
}

/** Write bytes to the PTY, dropping the write if disposed. */
function writeSafe(handle: PtyHandle, data: Buffer): void {
  if (handle.disposed) return;
  try {
    // node-pty types say write() takes a string, but in binary mode it
    // accepts a Buffer. The lib toString('binary')s internally, so we
    // pass bytes unchanged. See microsoft/node-pty#489.
    (handle.pty as unknown as { write: (d: Buffer) => void }).write(data);
  } catch (err) {
    // Route through dispose() rather than flipping `handle.disposed = true`
    // directly. Flipping the flag here meant the subsequent socket.on('close')
    // dispose call would short-circuit on `if (handle.disposed) return;`, so
    // `killSession(handle.viewSessionId)` never ran on the write-error teardown
    // path — leaking the per-attach grouped view session. Same class of bug
    // as the Round 1 onExit fix. Caught by Copilot PR #94 review round 3.
    logger.warn({ err, tabId: handle.tabId }, 'PTY write failed — disposing handle');
    void dispose(handle, 'pty-write-failed');
  }
}

/**
 * Tear down the PTY exactly once. Safe to call from any exit path.
 *
 * Wave 2.6: also kills the per-attach grouped view session. Killing a
 * grouped session does NOT kill the shared windows — those belong to the
 * master `major-tom` session and survive until someone explicitly
 * `killWindow`s them (that's what the `kill` control frame does when the
 * user closes a CLI tab via the confirmation modal). So relay restarts,
 * WS reconnects, and stray browser-tab closures still leave the real
 * `claude` process running inside its tmux window, which is the whole
 * point of Phase 13.
 */
export async function dispose(handle: PtyHandle, reason: string): Promise<void> {
  if (handle.disposed) return;
  handle.disposed = true;
  logger.info({ tabId: handle.tabId, viewSessionId: handle.viewSessionId, reason }, 'Disposing PTY handle');
  try {
    handle.pty.kill();
  } catch (err) {
    logger.debug({ err, tabId: handle.tabId }, 'PTY kill threw (likely already dead)');
  }
  try {
    await killSession(handle.viewSessionId);
  } catch (err) {
    logger.debug(
      { err, tabId: handle.tabId, viewSessionId: handle.viewSessionId },
      'kill view session threw (likely already gone)',
    );
  }
}
