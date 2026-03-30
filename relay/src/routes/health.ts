import type { FastifyPluginAsync } from 'fastify';
import type { SessionManager } from '../sessions/session-manager.js';
import type { FleetManager } from '../fleet/fleet-manager.js';
import type { HealthMonitor } from '../health/health-monitor.js';

interface HealthDeps {
  sessionManager: SessionManager;
  fleetManager: FleetManager;
  healthMonitor: HealthMonitor;
}

/**
 * Health check route — public, no auth.
 * Includes per-session process health status from HealthMonitor
 * and fleet worker status from FleetManager.
 */
export function createHealthRoutes(deps: HealthDeps): FastifyPluginAsync {
  return async (fastify) => {
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
  };
}
