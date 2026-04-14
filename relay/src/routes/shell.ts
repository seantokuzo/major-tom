/**
 * Shell WebSocket route — `/shell/:tabId`.
 *
 * Streams a plain PTY (one per tab) over WebSocket via `PtyAdapter`.
 * Replaces the v1 tmux-backed implementation. Backing PTY persists
 * through a 30-min disconnect grace so iOS app backgrounding does not
 * lose state. See `docs/TERMINAL-PROTOCOL-SPEC.md`.
 *
 * Auth mirrors the main `/ws` route: session cookie primary, dev-only
 * AUTH_TOKEN fallback, WKWebView JWT fallback via `?token=`.
 */
import type { FastifyPluginAsync } from 'fastify';
import type { WebSocket } from 'ws';
import { verifySessionToken, SESSION_COOKIE } from '../auth/session.js';
import type { PtyAdapter, PtyClient } from '../adapters/pty-adapter.js';
import { MAJOR_TOM_CONFIG_DIR } from '../installer/install-hooks.js';
import { logger } from '../utils/logger.js';

interface ShellRouteDeps {
  ptyAdapter: PtyAdapter;
}

interface ShellAuthResult {
  authed: boolean;
  email?: string;
}

/**
 * Shared auth logic for shell routes. Checks (in order):
 *  1. Dev-mode legacy AUTH_TOKEN via `?token=`
 *  2. Session cookie
 *  3. JWT fallback via `?token=` (WKWebView cookie-injection edge cases)
 */
async function authenticateShellRequest(
  sessionCookie: string | undefined,
  queryToken: string | undefined,
): Promise<ShellAuthResult> {
  const legacyAuthToken = process.env['AUTH_TOKEN'];
  const isDevMode = process.env['NODE_ENV'] !== 'production';

  if (isDevMode && queryToken && legacyAuthToken && queryToken === legacyAuthToken) {
    return { authed: true };
  }

  if (sessionCookie) {
    try {
      const payload = await verifySessionToken(sessionCookie);
      return { authed: true, email: payload.email };
    } catch {
      // Fall through to token fallback
    }
  }

  if (queryToken && queryToken !== legacyAuthToken) {
    try {
      const payload = await verifySessionToken(queryToken);
      return { authed: true, email: payload.email };
    } catch {
      // Token invalid
    }
  }

  return { authed: false };
}

/** Valid tabIds: 1-64 chars of `[a-zA-Z0-9._-]`. */
const TAB_ID_RE = /^[a-zA-Z0-9._-]{1,64}$/;
const DIM_MIN = 2;
const DIM_MAX = 500;

/**
 * Parse and clamp a query-string dimension. Returns undefined if missing,
 * throws a 400-friendly marker via returning null if invalid so the caller
 * can distinguish "unset → use default" from "invalid → reject request".
 */
function parseDim(raw: string | undefined): { ok: true; value: number | undefined } | { ok: false } {
  if (raw === undefined || raw === '') return { ok: true, value: undefined };
  const n = Number(raw);
  if (!Number.isFinite(n)) return { ok: false };
  const floored = Math.floor(n);
  if (floored < DIM_MIN || floored > DIM_MAX) return { ok: false };
  return { ok: true, value: floored };
}

/** Wrap a ws.WebSocket in the minimal `PtyClient` shape. */
function toPtyClient(socket: WebSocket): PtyClient {
  return socket as unknown as PtyClient;
}

/**
 * Build the per-PTY env extras. Only injected on first spawn — subsequent
 * reattaches to the same tabId keep whatever env was set originally.
 */
function buildEnvExtras(tabId: string): Record<string, string> {
  const hookPort = process.env['HOOK_PORT'] ?? '9091';
  return {
    MAJOR_TOM_TAB_ID: tabId,
    CLAUDE_CONFIG_DIR: MAJOR_TOM_CONFIG_DIR,
    MAJOR_TOM_CONFIG_DIR: MAJOR_TOM_CONFIG_DIR,
    MAJOR_TOM_APPROVAL: process.env['MAJOR_TOM_APPROVAL'] ?? 'local',
    MAJOR_TOM_RELAY_PORT: hookPort,
  };
}

export function createShellRoute(deps: ShellRouteDeps): FastifyPluginAsync {
  const { ptyAdapter } = deps;

  return async (fastify) => {
    fastify.get<{
      Params: { tabId: string };
      Querystring: { token?: string; cols?: string; rows?: string };
    }>(
      '/shell/:tabId',
      { websocket: true },
      async (socket, request) => {
        const { tabId } = request.params;
        if (!TAB_ID_RE.test(tabId)) {
          logger.warn({ tabId, ip: request.ip }, 'Shell WS rejected — invalid tabId');
          socket.close(1008, 'Invalid tabId');
          return;
        }

        const sessionCookie = request.cookies?.[SESSION_COOKIE];
        const { token: queryToken, cols: colsQ, rows: rowsQ } = request.query;

        const { authed, email } = await authenticateShellRequest(sessionCookie, queryToken);
        if (!authed) {
          logger.warn({ tabId, ip: request.ip }, 'Shell WS unauthenticated — closing');
          socket.close(1008, 'Authentication required');
          return;
        }

        const parsedCols = parseDim(colsQ);
        const parsedRows = parseDim(rowsQ);
        if (!parsedCols.ok || !parsedRows.ok) {
          logger.warn({ tabId, colsQ, rowsQ }, 'Shell WS rejected — invalid cols/rows');
          socket.close(1008, 'Invalid cols/rows');
          return;
        }
        const cols = parsedCols.value ?? 80;
        const rows = parsedRows.value ?? 24;

        const client = toPtyClient(socket);
        const outcome = ptyAdapter.attach(tabId, client, {
          cols,
          rows,
          envExtras: buildEnvExtras(tabId),
        });
        if (outcome.kind === 'rejected') {
          try {
            socket.send(JSON.stringify({ type: 'error', message: 'tab already attached' }));
          } catch {
            // peer gone
          }
          socket.close(4001, 'tab already attached');
          return;
        }

        logger.info({ tabId, email, ip: request.ip, restored: outcome.restored }, 'Shell WS attached');

        socket.on('message', (msg: Buffer, isBinary: boolean) => {
          if (isBinary) {
            const ok = ptyAdapter.sendInput(tabId, msg);
            if (!ok) {
              logger.warn({ tabId, size: msg.length }, 'Closing WS — input frame exceeds limit');
              socket.close(1009, 'Input frame too large');
            }
            return;
          }
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
                Number.isFinite(rawCols) && rawCols >= DIM_MIN && rawCols <= DIM_MAX &&
                Number.isFinite(rawRows) && rawRows >= DIM_MIN && rawRows <= DIM_MAX
              ) {
                ptyAdapter.resize(tabId, Math.floor(rawCols), Math.floor(rawRows));
              }
              return;
            }
            case 'input': {
              const data = typeof ctrl['data'] === 'string' ? (ctrl['data'] as string) : '';
              if (data.length === 0) return;
              const buf = Buffer.from(data, 'utf-8');
              const ok = ptyAdapter.sendInput(tabId, buf);
              if (!ok) {
                socket.close(1009, 'Input frame too large');
              }
              return;
            }
            case 'kill': {
              logger.info({ tabId }, 'Client requested kill');
              ptyAdapter.kill(tabId);
              return;
            }
            case 'refresh': {
              // v2 spec: silently ignored. Was a tmux redraw hack.
              return;
            }
            default:
              logger.debug({ tabId, type: ctrl['type'] }, 'Ignoring unknown control frame');
          }
        });

        const onCloseOrError = () => {
          ptyAdapter.detach(tabId, client);
        };
        socket.on('close', onCloseOrError);
        socket.on('error', onCloseOrError);
      },
    );

    // GET /shell/tabs — new shape: [{tabId, attached, lastActivityAt}]
    fastify.get<{ Querystring: { token?: string } }>(
      '/shell/tabs',
      async (request, reply) => {
        const sessionCookie = request.cookies?.[SESSION_COOKIE];
        const { token: queryToken } = request.query;

        const { authed } = await authenticateShellRequest(sessionCookie, queryToken);
        if (!authed) {
          return reply.code(401).send({ error: 'Authentication required' });
        }

        return ptyAdapter.listTabs();
      },
    );

    // POST /shell/:tabId/kill — 204 on success, 404 on unknown tabId.
    fastify.post<{ Params: { tabId: string }; Querystring: { token?: string } }>(
      '/shell/:tabId/kill',
      async (request, reply) => {
        const { tabId } = request.params;
        if (!TAB_ID_RE.test(tabId)) {
          return reply.code(400).send({ error: 'Invalid tabId' });
        }

        const sessionCookie = request.cookies?.[SESSION_COOKIE];
        const { token: queryToken } = request.query;

        const { authed, email } = await authenticateShellRequest(sessionCookie, queryToken);
        if (!authed) {
          return reply.code(401).send({ error: 'Authentication required' });
        }

        if (!ptyAdapter.has(tabId)) {
          return reply.code(404).send({ error: 'tabId not found' });
        }

        ptyAdapter.kill(tabId);
        logger.info({ tabId, email, ip: request.ip }, 'Shell tab killed via REST fallback');
        return reply.code(204).send();
      },
    );
  };
}
