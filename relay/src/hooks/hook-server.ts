/**
 * Major Tom — Hook HTTP Server
 *
 * Plain Node `http` server (NOT Fastify) that handles inbound POSTs from
 * the installed shell hook scripts. Lives on its own loopback-only port
 * (default 9091, env `HOOK_PORT`) so the hooks can curl the relay
 * without going through Cloudflare or auth.
 *
 * Phase 13 Wave 2 added:
 *   - Routing-mode awareness via `X-MT-Mode` / `X-MT-Tab` headers
 *   - tool_use_id-based dedup (same id arriving twice attaches to the
 *     same pending entry instead of creating a second)
 *   - Bypass-mode escape hatch for Claude Code #37420 (defensive — the
 *     shell script also checks, but a manual curl probe might not)
 *   - SubagentStart placeholder endpoint
 *   - Push notification fire on enqueue
 */
import { createServer, type IncomingMessage, type ServerResponse } from 'node:http';
import { logger } from '../utils/logger.js';
import { ApprovalQueue } from './approval-queue.js';
import type { NotificationBatcher } from '../push/notification-batcher.js';

function readBody(req: IncomingMessage, maxBytes = 65_536): Promise<string> {
  return new Promise((resolve, reject) => {
    const chunks: Buffer[] = [];
    let size = 0;
    req.on('data', (chunk: Buffer) => {
      size += chunk.length;
      if (size > maxBytes) {
        req.destroy();
        reject(Object.assign(new Error('Request body too large'), { code: 'BODY_TOO_LARGE' }));
        return;
      }
      chunks.push(chunk);
    });
    req.on('end', () => resolve(Buffer.concat(chunks).toString('utf-8')));
    req.on('error', reject);
  });
}

function sendJson(res: ServerResponse, status: number, body: unknown): void {
  res.writeHead(status, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify(body));
}

/**
 * Inspect a hook header value, normalize, and validate against an allow-list.
 * Hook scripts are trusted (loopback only) but a malformed header still
 * shouldn't crash the server.
 */
function readHeader<T extends string>(
  req: IncomingMessage,
  name: string,
  allowed: readonly T[],
  fallback: T,
): T {
  const raw = req.headers[name.toLowerCase()];
  const value = Array.isArray(raw) ? raw[0] : raw;
  if (typeof value === 'string' && (allowed as readonly string[]).includes(value)) {
    return value as T;
  }
  return fallback;
}

const ROUTING_MODES = ['local', 'remote', 'hybrid'] as const;
type RoutingMode = (typeof ROUTING_MODES)[number];

/**
 * Map our internal ApprovalDecision to Claude Code's hook envelope shape.
 * Claude Code's permissionDecision is `'allow' | 'deny' | 'ask'`. Our
 * `'skip'` and `'allow_always'` collapse to `'ask'` and `'allow'` resp.
 */
function decisionToPermissionDecision(decision: string): 'allow' | 'deny' | 'ask' {
  if (decision === 'allow' || decision === 'allow_always') return 'allow';
  if (decision === 'deny') return 'deny';
  return 'ask';
}

interface HookServerDeps {
  approvalQueue: ApprovalQueue;
  notificationBatcher?: NotificationBatcher;
}

// ── Hook HTTP Server ────────────────────────────────────────
// Claude Code hook scripts POST to these endpoints.
// pre-tool-use blocks until the iOS app sends an approval decision.

export function createHookServer(
  approvalQueueOrDeps: ApprovalQueue | HookServerDeps,
  port: number,
) {
  // Backwards-compat: legacy callers pass an ApprovalQueue directly.
  // Wave 2 callers pass a deps object.
  const deps: HookServerDeps =
    approvalQueueOrDeps instanceof ApprovalQueue
      ? { approvalQueue: approvalQueueOrDeps }
      : approvalQueueOrDeps;
  const { approvalQueue, notificationBatcher } = deps;

  const server = createServer(async (req, res) => {
    const url = req.url ?? '';
    const method = req.method ?? '';

    try {
      // Health check
      if (method === 'GET' && url === '/health') {
        sendJson(res, 200, { status: 'ok', pendingApprovals: approvalQueue.size });
        return;
      }

      // ── Pre-tool-use ─────────────────────────────────────
      // Phase 13 Wave 2: routing-mode aware. The shell hook script sets
      // `X-MT-Mode` and `X-MT-Tab` headers. We branch on mode:
      //   local  — fire a notification, return 'ask' (TUI keeps owning)
      //   remote — block until phone resolves, return real decision
      //   hybrid — fire a notification, return 'ask', AND let the relay's
      //            send-keys race resolve the TUI prompt if phone wins
      if (method === 'POST' && url === '/hooks/pre-tool-use') {
        const body = await readBody(req);
        let hookData: Record<string, unknown>;
        try {
          hookData = JSON.parse(body) as Record<string, unknown>;
        } catch {
          sendJson(res, 400, { error: 'Invalid JSON in hook payload' });
          return;
        }

        // Bypass-mode escape hatch — Claude Code #37420. If the shell
        // hook script missed this (it shouldn't, but defensive), we
        // catch it server-side and return 'allow' instead of 'ask'.
        const permissionMode = hookData['permission_mode'];
        if (permissionMode === 'bypassPermissions') {
          logger.warn(
            { tool: hookData['tool_name'] },
            'Bypass mode detected at hook server — returning allow (Claude Code #37420 escape)',
          );
          sendJson(res, 200, {
            hookSpecificOutput: {
              hookEventName: 'PreToolUse',
              permissionDecision: 'allow',
            },
          });
          return;
        }

        const tool = (hookData['tool_name'] as string) ?? 'unknown';
        const toolInput = hookData['tool_input'] as Record<string, unknown> | undefined;
        const toolUseId = (hookData['tool_use_id'] as string) ?? '';
        if (!toolUseId) {
          // Without a tool_use_id we can't dedup or correlate the SDK +
          // hook intercept paths. Reject with 400 so the shell script
          // surfaces a useful error.
          sendJson(res, 400, { error: 'Missing tool_use_id in hook payload' });
          return;
        }

        const routingMode = readHeader<RoutingMode>(
          req,
          'X-MT-Mode',
          ROUTING_MODES,
          'local',
        );
        const tabIdHeader = req.headers['x-mt-tab'];
        const tabId =
          typeof tabIdHeader === 'string'
            ? tabIdHeader
            : Array.isArray(tabIdHeader)
              ? tabIdHeader[0]
              : undefined;

        const description = toolInput ? JSON.stringify(toolInput) : '';

        // Fire push (best-effort, never blocks the response).
        if (notificationBatcher) {
          notificationBatcher.addApprovalRequest(tool, toolUseId);
        }

        // Enqueue with the Wave 2 routing-aware entrypoint. Dedup is
        // handled inside the queue using toolUseId.
        // Local + hybrid don't BLOCK the hook — they fire-and-forget
        // the enqueue and immediately return 'ask'. The PWA picks up
        // the enqueue via the eventBus broadcast.
        if (routingMode === 'local' || routingMode === 'hybrid') {
          // We still call enqueueAndWait so the queue knows about the
          // entry (for the PWA to fetch via /api/approvals/pending and
          // for hybrid send-keys resolution). We just don't await it.
          void approvalQueue.enqueueAndWait({
            dedupKey: toolUseId,
            source: 'hook',
            routingMode,
            tool,
            description,
            details: hookData,
            ...(tabId && { tabId }),
          });
          sendJson(res, 200, {
            hookSpecificOutput: {
              hookEventName: 'PreToolUse',
              permissionDecision: 'ask',
            },
          });
          return;
        }

        // routingMode === 'remote' — BLOCK until the phone resolves.
        const decision = await approvalQueue.enqueueAndWait({
          dedupKey: toolUseId,
          source: 'hook',
          routingMode: 'remote',
          tool,
          description,
          details: hookData,
          ...(tabId && { tabId }),
        });

        sendJson(res, 200, {
          hookSpecificOutput: {
            hookEventName: 'PreToolUse',
            permissionDecision: decisionToPermissionDecision(decision),
          },
        });
        return;
      }

      // ── Subagent-start (Wave 2 placeholder) ──────────────
      // Wave 3 will use this to broadcast spawn-time agent metadata to
      // the PWA so the sprite layer can show subagents as they're born.
      if (method === 'POST' && url === '/hooks/subagent-start') {
        const body = await readBody(req);
        try {
          const payload = JSON.parse(body) as Record<string, unknown>;
          logger.info(
            { tabId: req.headers['x-mt-tab'], session: payload['session_id'] },
            'SubagentStart hook received',
          );
        } catch {
          // ignore — Wave 2 just logs the event
        }
        sendJson(res, 200, {});
        return;
      }

      // ── Post-tool-use (legacy) ───────────────────────────
      if (method === 'POST' && url === '/hooks/post-tool-use') {
        const body = await readBody(req);
        let hookData: Record<string, unknown>;
        try {
          hookData = JSON.parse(body) as Record<string, unknown>;
        } catch {
          sendJson(res, 400, { error: 'Invalid JSON in hook payload' });
          return;
        }
        // Wave 2: post-tool-use is best-effort logging only — the SDK
        // adapter has its own tool.complete event path, and the shell
        // hook flow doesn't have post hooks installed yet.
        logger.debug(
          { sessionId: hookData['session_id'], tool: hookData['tool_name'] },
          'post-tool-use hook received',
        );
        sendJson(res, 200, { status: 'ok' });
        return;
      }

      // ── Notification (legacy) ────────────────────────────
      if (method === 'POST' && url === '/hooks/notification') {
        const body = await readBody(req);
        let hookData: Record<string, unknown>;
        try {
          hookData = JSON.parse(body) as Record<string, unknown>;
        } catch {
          sendJson(res, 400, { error: 'Invalid JSON in hook payload' });
          return;
        }
        logger.info({ payload: hookData }, 'Notification hook received');
        sendJson(res, 200, { status: 'ok' });
        return;
      }

      // 404
      sendJson(res, 404, { error: 'Not found' });
    } catch (err) {
      if ((err as { code?: string }).code === 'BODY_TOO_LARGE') {
        sendJson(res, 413, { error: 'Request body too large' });
        return;
      }
      logger.error({ err, url, method }, 'Hook server error');
      sendJson(res, 500, { error: 'Internal server error' });
    }
  });

  // Loopback only — these endpoints are trusted by Claude Code's hook
  // scripts inside our tmux windows, no authentication. NEVER bind to
  // 0.0.0.0 or expose this port through Cloudflare.
  server.listen(port, '127.0.0.1', () => {
    logger.info({ port, host: '127.0.0.1' }, 'Hook HTTP server listening');
  });

  return server;
}
