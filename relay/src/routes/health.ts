import type { FastifyPluginAsync, FastifyRequest } from 'fastify';
import type { SessionManager } from '../sessions/session-manager.js';
import type { FleetManager } from '../fleet/fleet-manager.js';
import type { HealthMonitor } from '../health/health-monitor.js';
import { listWindows } from '../utils/tmux-cli.js';
import { logger } from '../utils/logger.js';

interface HealthDeps {
  sessionManager: SessionManager;
  fleetManager: FleetManager;
  healthMonitor: HealthMonitor;
}

/**
 * Connected WebSocket client info for the admin status endpoint.
 * Populated by the WS route via `setClientTracker`.
 */
export interface AdminClientInfo {
  ip: string;
  userAgent: string;
  connectedAt: string;
}

/** Callback type for the WS route to supply live client info. */
export type ClientTrackerFn = () => AdminClientInfo[];

/** Set by ws.ts so the admin endpoint can enumerate connected clients. */
let clientTracker: ClientTrackerFn = () => [];

export function setClientTracker(fn: ClientTrackerFn): void {
  clientTracker = fn;
}

/**
 * Health check route — public, no auth.
 * Includes per-session process health status from HealthMonitor
 * and fleet worker status from FleetManager.
 *
 * Also provides `/api/admin/status` — a richer admin endpoint for
 * Ground Control's dashboard (connected clients, memory, uptime, tmux).
 */
export function createHealthRoutes(deps: HealthDeps): FastifyPluginAsync {
  return async (fastify) => {
    // ── Lightweight health probe (public) ──────────────────
    fastify.get('/health', async () => {
      const fleetStatus = deps.fleetManager.getFleetStatus();
      return {
        status: 'ok',
        sessions: deps.sessionManager.list(),
        pendingApprovals: deps.fleetManager.pendingApprovalCount,
        processHealth: deps.healthMonitor.getHealthStatuses(),
        fleet: {
          totalWorkers: fleetStatus.totalWorkers,
          totalSessions: fleetStatus.totalSessions,
          workers: fleetStatus.workers,
        },
      };
    });

    // ── Admin status endpoint (no auth — localhost only) ───
    // Ground Control polls this from the same machine, so auth is
    // unnecessary. The endpoint is intentionally kept unauthenticated
    // to avoid coupling Ground Control to the relay's session cookie /
    // PIN flow — it's a management tool, not a user-facing client.
    fastify.get('/api/admin/status', async (request: FastifyRequest, reply) => {
      // Enforce loopback-only access — reject non-localhost requests
      const clientIp = request.ip;
      const isLoopback = clientIp === '127.0.0.1' || clientIp === '::1' || clientIp === '::ffff:127.0.0.1';
      if (!isLoopback) {
        logger.warn({ ip: clientIp }, 'Rejected non-loopback request to /api/admin/status');
        return reply.code(403).send({ error: 'Forbidden — loopback only' });
      }

      const sessions = deps.sessionManager.list();
      const mem = process.memoryUsage();

      // tmux window count — best-effort, non-blocking
      let tmuxWindowCount = 0;
      try {
        const windows = await listWindows();
        tmuxWindowCount = windows.length;
      } catch {
        // tmux may not be running — that's fine
      }

      return {
        status: 'ok',
        uptime: process.uptime(),
        clients: clientTracker(),
        sessions: sessions.map((s) => ({
          sessionId: s.id,
          workDir: s.workingDir,
          status: s.status,
          startedAt: s.startedAt,
        })),
        memory: {
          rss: mem.rss,
          heapUsed: mem.heapUsed,
          heapTotal: mem.heapTotal,
          external: mem.external,
        },
        tmuxWindowCount,
      };
    });
  };
}
