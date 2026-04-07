/**
 * Shell WebSocket route — `/shell/:tabId`.
 *
 * Streams a tmux-backed pseudo-terminal to the client. The tmux server
 * is dedicated (`-L major-tom`) so our sessions survive WS reconnects
 * and relay restarts. Auth mirrors the main `/ws` route: session cookie
 * primary, dev-only AUTH_TOKEN fallback.
 *
 * Wave 1 intentionally keeps this minimal — no approval pipeline, no
 * sprite wiring, no env injection for Claude hooks. That's Wave 2+.
 */
import type { FastifyPluginAsync } from 'fastify';
import { verifySessionToken, SESSION_COOKIE } from '../auth/session.js';
import type { SessionManager } from '../sessions/session-manager.js';
import { attachPty } from '../adapters/pty-adapter.js';
import { tmuxBootstrap } from '../adapters/tmux-bootstrap.js';
import { logger } from '../utils/logger.js';

interface ShellRouteDeps {
  sessionManager: SessionManager;
}

/** Valid tabIds: 1-64 chars of `[a-zA-Z0-9._-]`. Defensive against path abuse. */
const TAB_ID_RE = /^[a-zA-Z0-9._-]{1,64}$/;

/** Same bounds as the runtime resize handler in pty-adapter.ts. */
const DIM_MIN = 2;
const DIM_MAX = 500;

/**
 * Clamp a query-string dimension into the same [2, 500] range we enforce
 * on runtime resize control frames. Returns undefined for missing/invalid
 * input so the PTY adapter falls back to its default. Caught by Copilot
 * review on PR #89 — unbounded values would let an authed client force
 * an oversized PTY allocation.
 */
function clampDim(raw: string | undefined): number | undefined {
  if (raw === undefined) return undefined;
  const n = Number(raw);
  if (!Number.isFinite(n)) return undefined;
  return Math.max(DIM_MIN, Math.min(DIM_MAX, Math.floor(n)));
}

export function createShellRoute(deps: ShellRouteDeps): FastifyPluginAsync {
  const { sessionManager } = deps;

  return async (fastify) => {
    fastify.get<{ Params: { tabId: string }; Querystring: { token?: string; cols?: string; rows?: string } }>(
      '/shell/:tabId',
      { websocket: true },
      async (socket, request) => {
        const { tabId } = request.params;
        if (!TAB_ID_RE.test(tabId)) {
          logger.warn({ tabId, ip: request.ip }, 'Shell WS rejected — invalid tabId');
          socket.close(1008, 'Invalid tabId');
          return;
        }

        // ── Auth ──────────────────────────────────────────────
        const sessionCookie = request.cookies?.[SESSION_COOKIE];
        const { token: queryToken, cols: colsQ, rows: rowsQ } = request.query;
        const legacyAuthToken = process.env['AUTH_TOKEN'];
        const isDevMode = process.env['NODE_ENV'] !== 'production';

        let authed = false;
        let email: string | undefined;

        if (isDevMode && queryToken && legacyAuthToken && queryToken === legacyAuthToken) {
          authed = true;
        } else if (sessionCookie) {
          try {
            const payload = await verifySessionToken(sessionCookie);
            authed = true;
            email = payload.email;
          } catch {
            authed = false;
          }
        }

        if (!authed) {
          logger.warn({ tabId, ip: request.ip }, 'Shell WS unauthenticated — closing');
          socket.close(1008, 'Authentication required');
          return;
        }

        // ── Bootstrap (idempotent, lazy) ──────────────────────
        try {
          await tmuxBootstrap.ensure();
        } catch (err) {
          logger.error({ err, tabId }, 'tmux bootstrap failed — cannot attach shell');
          try {
            socket.send(JSON.stringify({ type: 'error', message: (err as Error).message }));
          } catch { /* ignore */ }
          socket.close(1011, 'tmux unavailable');
          return;
        }

        // Optional initial cols/rows so the first redraw isn't at 80x24,
        // clamped to the same bounds enforced on resize control frames.
        const cols = clampDim(colsQ);
        const rows = clampDim(rowsQ);

        try {
          const handle = await attachPty(socket, {
            tabId,
            ...(cols !== undefined ? { cols } : {}),
            ...(rows !== undefined ? { rows } : {}),
          });

          // Register the tab on the session manager so future waves can
          // coordinate (approvals, hybrid keystroke injection, tab UI).
          // Pass the pid to cleanup so a stale close from an older socket
          // cannot evict the handle of a newer attach against the same id.
          const ourPid = handle.pty.pid;
          sessionManager.registerTab({
            tabId,
            pid: ourPid,
            attachedAt: handle.createdAt,
          });

          const cleanup = () => {
            sessionManager.unregisterTab(tabId, ourPid);
          };
          socket.on('close', cleanup);
          socket.on('error', cleanup);

          logger.info({ tabId, email, ip: request.ip }, 'Shell WS attached');
        } catch (err) {
          logger.error({ err, tabId }, 'Failed to attach PTY');
          try {
            socket.send(JSON.stringify({ type: 'error', message: (err as Error).message }));
          } catch { /* ignore */ }
          socket.close(1011, 'pty attach failed');
        }
      },
    );
  };
}
