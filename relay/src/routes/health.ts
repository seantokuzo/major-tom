import type { FastifyPluginAsync } from 'fastify';
import type { SessionManager } from '../sessions/session-manager.js';
import type { ApprovalQueue } from '../hooks/approval-queue.js';
import type { HealthMonitor } from '../health/health-monitor.js';

interface HealthDeps {
  sessionManager: SessionManager;
  approvalQueue: ApprovalQueue;
  healthMonitor: HealthMonitor;
}

/**
 * Health check route — public, no auth.
 * Includes per-session process health status from HealthMonitor.
 */
export function createHealthRoutes(deps: HealthDeps): FastifyPluginAsync {
  return async (fastify) => {
    fastify.get('/health', async () => {
      return {
        status: 'ok',
        sessions: deps.sessionManager.list(),
        pendingApprovals: deps.approvalQueue.size,
        processHealth: deps.healthMonitor.getHealthStatuses(),
      };
    });
  };
}
