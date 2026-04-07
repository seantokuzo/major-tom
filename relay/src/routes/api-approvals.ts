/**
 * Phase 13 Wave 2 — REST endpoints for shell-side approvals.
 *
 * The PWA hits these for:
 *   1. Cold-start fetch on boot — `GET /api/approvals/pending` returns
 *      every approval still in flight, so a freshly-opened PWA can show
 *      the latest one even if the SW push notification was missed.
 *   2. Decision POST from the SW notification action buttons — those
 *      can't go through the WebSocket because the SW context might not
 *      have an active WS at all.
 *   3. Mode switching — `POST /api/settings/approval-mode` rewrites
 *      `approval-mode.json` so the next hook script invocation picks
 *      up the new routing mode (no relay restart).
 *
 * Routes are session-protected. The hook server itself listens on a
 * separate Node http port (9091) and is loopback-only.
 */
import type { FastifyPluginAsync } from 'fastify';
import { writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { requireSession } from '../plugins/auth.js';
import type { ApprovalQueue } from '../hooks/approval-queue.js';
import { MAJOR_TOM_CONFIG_DIR } from '../installer/install-hooks.js';
import { logger } from '../utils/logger.js';

interface ApiApprovalsDeps {
  shellApprovalQueue: ApprovalQueue;
}

type RoutingMode = 'local' | 'remote' | 'hybrid';
type DecisionLite = 'allow' | 'deny';

function isRoutingMode(value: unknown): value is RoutingMode {
  return value === 'local' || value === 'remote' || value === 'hybrid';
}

function isDecisionLite(value: unknown): value is DecisionLite {
  return value === 'allow' || value === 'deny';
}

export function createApiApprovalsRoutes(
  deps: ApiApprovalsDeps,
): FastifyPluginAsync {
  return async (fastify) => {
    // ── GET /api/approvals/pending ───────────────────────────
    // Cold-start safety net for PWAs that come back online and
    // missed the original `enqueue` broadcast.
    fastify.get(
      '/api/approvals/pending',
      { preHandler: requireSession },
      async () => {
        return { pending: deps.shellApprovalQueue.getPendingDetails() };
      },
    );

    // ── POST /api/approvals/:id/decision ─────────────────────
    // Endpoint the SW notification actions hit. Body: { decision }.
    // Hybrid-mode resolves go through resolveHybrid (tmux send-keys);
    // everything else through plain resolve().
    fastify.post<{
      Params: { id: string };
      Body: { decision?: unknown };
    }>(
      '/api/approvals/:id/decision',
      { preHandler: requireSession },
      async (request, reply) => {
        const requestId = request.params.id;
        const decision = request.body?.decision;
        if (!isDecisionLite(decision)) {
          return reply.code(400).send({ error: 'decision must be "allow" or "deny"' });
        }
        if (!deps.shellApprovalQueue.isPending(requestId)) {
          // It may have already been resolved (the cache will catch
          // duplicate enqueues but the API should also gracefully no-op).
          return reply.code(404).send({ error: 'No pending approval with that id' });
        }
        const pending = deps.shellApprovalQueue.getPendingDetails().find(
          (p) => p.requestId === requestId,
        );
        const isHybrid = pending?.routingMode === 'hybrid' && pending.tabId;
        if (isHybrid && pending?.tabId) {
          await deps.shellApprovalQueue.resolveHybrid(requestId, decision, pending.tabId);
        } else {
          deps.shellApprovalQueue.resolve(requestId, decision);
        }
        return { ok: true, requestId, decision };
      },
    );

    // ── POST /api/settings/approval-mode ─────────────────────
    // Persists the routing mode to `approval-mode.json` so the next
    // shell hook invocation picks it up. In-flight approvals keep
    // whatever routingMode they were enqueued with — only fresh hook
    // invocations see the new mode.
    fastify.post<{ Body: { mode?: unknown } }>(
      '/api/settings/approval-mode',
      { preHandler: requireSession },
      async (request, reply) => {
        const mode = request.body?.mode;
        if (!isRoutingMode(mode)) {
          return reply.code(400).send({ error: 'mode must be "local", "remote", or "hybrid"' });
        }
        const path = join(MAJOR_TOM_CONFIG_DIR, 'approval-mode.json');
        const payload = { mode, updatedAt: new Date().toISOString() };
        try {
          await writeFile(path, JSON.stringify(payload, null, 2) + '\n', 'utf-8');
          logger.info({ mode, path }, 'Approval routing mode updated');
        } catch (err) {
          logger.error({ err, path }, 'Failed to write approval-mode.json');
          return reply.code(500).send({ error: 'Failed to persist approval mode' });
        }
        return { ok: true, mode };
      },
    );

    // ── GET /api/settings/approval-mode ──────────────────────
    // PWA reads the current mode on boot so the segmented control
    // shows the right pill highlighted. Falls back to 'local' if the
    // file is missing or unreadable.
    fastify.get(
      '/api/settings/approval-mode',
      { preHandler: requireSession },
      async () => {
        const path = join(MAJOR_TOM_CONFIG_DIR, 'approval-mode.json');
        try {
          const { readFile } = await import('node:fs/promises');
          const raw = await readFile(path, 'utf-8');
          const parsed = JSON.parse(raw) as { mode?: unknown };
          if (isRoutingMode(parsed.mode)) {
            return { mode: parsed.mode };
          }
        } catch {
          // missing or malformed — fall through to default
        }
        return { mode: 'local' as RoutingMode };
      },
    );
  };
}
