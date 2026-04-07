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
import { logger } from '../utils/logger.js';
import {
  MAJOR_TOM_SESSION,
  MAJOR_TOM_SOCKET,
  createWindow,
} from '../utils/tmux-cli.js';
import { tmuxBootstrap } from './tmux-bootstrap.js';

export interface PtyAttachOptions {
  tabId: string;
  cols?: number;
  rows?: number;
}

export interface PtyHandle {
  tabId: string;
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
  await createWindow(tabId);

  const env: NodeJS.ProcessEnv = {
    ...process.env,
    LANG: process.env['LANG'] ?? 'en_US.UTF-8',
    TERM: 'xterm-256color',
    COLORTERM: 'truecolor',
    MAJOR_TOM_TAB_ID: tabId,
  };

  const ptyProcess: IPty = pty.spawn(
    'tmux',
    [
      '-L', MAJOR_TOM_SOCKET,
      'attach-session',
      // No `-d`: allow concurrent tmux clients so the same shell window
      // can be observed from multiple devices (laptop + phone) at once.
      // Caught by Copilot review on PR #89 — `-d` would forcibly kick
      // every other attached client, defeating multi-device viewing.
      '-t', `${MAJOR_TOM_SESSION}:${tabId}`,
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

  const handle: PtyHandle = {
    tabId,
    pty: ptyProcess,
    socket,
    disposed: false,
    createdAt: new Date(),
  };

  logger.info(
    { tabId, pid: ptyProcess.pid, cols, rows },
    'PTY attached to tmux window',
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
    handle.disposed = true;
    logger.info({ tabId, exitCode, signal }, 'PTY exited');
    if (socket.readyState === socket.OPEN) {
      try {
        socket.send(JSON.stringify({ type: 'exit', exitCode, signal }));
        socket.close(1000, 'pty-exited');
      } catch {
        // socket already gone — ignore
      }
    }
  });

  // ── socket → PTY (binary = data, text = control JSON) ───────
  socket.on('message', (msg: Buffer, isBinary: boolean) => {
    if (handle.disposed) return;
    if (isBinary) {
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
        const data = typeof ctrl['data'] === 'string' ? (ctrl['data'] as string) : '';
        if (data.length > 0) writeSafe(handle, Buffer.from(data, 'utf-8'));
        return;
      }
      default:
        logger.debug({ tabId, type: ctrl['type'] }, 'Ignoring unknown control frame');
    }
  });

  socket.on('close', () => dispose(handle, 'socket-closed'));
  socket.on('error', (err) => {
    logger.warn({ err, tabId }, 'Socket error on PTY session');
    dispose(handle, 'socket-error');
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
    logger.warn({ err, tabId: handle.tabId }, 'PTY write failed — marking disposed');
    handle.disposed = true;
  }
}

/** Tear down the PTY exactly once. Safe to call from any exit path. */
export function dispose(handle: PtyHandle, reason: string): void {
  if (handle.disposed) return;
  handle.disposed = true;
  logger.info({ tabId: handle.tabId, reason }, 'Disposing PTY handle');
  try {
    handle.pty.kill();
  } catch (err) {
    logger.debug({ err, tabId: handle.tabId }, 'PTY kill threw (likely already dead)');
  }
  // NOTE: we deliberately do NOT destroy the tmux window here — closing the
  // WebSocket only detaches the attach-session client. The real `claude`
  // process keeps running inside tmux, which is the whole point of Phase 13.
}
