/**
 * Fastify app factory — creates and configures the Major Tom relay server.
 */
import Fastify from 'fastify';
import { logger } from './utils/logger.js';

// Plugins
import { corsPlugin } from './plugins/cors.js';
import { cookiePlugin } from './plugins/cookie.js';
import { securityPlugin } from './plugins/security.js';
import { websocketPlugin } from './plugins/websocket.js';
import { staticPlugin } from './plugins/static.js';
import { authPlugin } from './plugins/auth.js';

// Routes
import { authRoutes } from './routes/auth.js';
import { createHealthRoutes } from './routes/health.js';
import { createPushRoutes } from './routes/push.js';
import { createNotificationConfigRoutes } from './routes/notification-config.js';
import { createAnalyticsRoutes } from './routes/analytics.js';
import { createWsRoute } from './routes/ws.js';

// Services
import { SessionManager } from './sessions/session-manager.js';
import { SessionPersistence } from './sessions/session-persistence.js';
import { FleetManager } from './fleet/fleet-manager.js';
import { PushManager } from './push/push-manager.js';
import { NotificationConfigManager } from './push/notification-config.js';
import { HealthMonitor } from './health/health-monitor.js';
import { AnalyticsCollector } from './analytics/analytics-collector.js';
import { getSessionSecret } from './auth/session.js';

export interface AppConfig {
  port: number;
  claudeWorkDir: string;
}

export async function buildApp(config: AppConfig) {
  // Initialize session secret early (auto-generates if needed)
  getSessionSecret();

  // ── Core services ──────────────────────────────────────
  const sessionPersistence = new SessionPersistence();
  const sessionManager = new SessionManager(sessionPersistence);
  const fleetManager = new FleetManager(sessionManager);
  const pushManager = new PushManager();
  const notificationConfigManager = new NotificationConfigManager();
  const healthMonitor = new HealthMonitor(fleetManager, sessionManager);
  const analyticsCollector = new AnalyticsCollector();

  // Start health monitoring
  healthMonitor.start();

  // Restore persisted data
  await sessionManager.restoreFromDisk().catch((err: unknown) => {
    logger.error({ err }, 'Failed to restore sessions from disk, starting anyway');
  });
  await pushManager.restoreFromDisk().catch((err: unknown) => {
    logger.error({ err }, 'Failed to restore push subscriptions from disk, starting anyway');
  });

  // ── Fastify instance ───────────────────────────────────
  const app = Fastify({
    logger: {
      level: process.env['LOG_LEVEL'] ?? 'info',
      name: 'major-tom-relay',
    },
    trustProxy: true, // Behind Cloudflare Tunnel
    bodyLimit: 65_536, // 64 KB max body (matches old readBody limit)
  });

  // ── Register plugins (order matters) ───────────────────

  // 1. CORS (must be first — handles preflight)
  await app.register(corsPlugin);

  // 2. Cookie parsing
  await app.register(cookiePlugin);

  // 3. Security headers + rate limiting
  await app.register(securityPlugin);

  // 4. Auth (session JWT verification — depends on cookie)
  await app.register(authPlugin);

  // 5. WebSocket support
  await app.register(websocketPlugin);

  // ── Register routes ────────────────────────────────────

  // Auth routes (public — Google OAuth login/logout/check)
  await app.register(authRoutes);

  // Health check (public)
  await app.register(createHealthRoutes({ sessionManager, fleetManager, healthMonitor }));

  // Push notifications (mix of public + auth-required)
  await app.register(createPushRoutes({ pushManager }));

  // Notification config (auth-required)
  await app.register(createNotificationConfigRoutes({ notificationConfigManager }));
  // Analytics API (auth required)
  await app.register(createAnalyticsRoutes({ analyticsCollector }));

  // WebSocket (auth via session cookie on upgrade)
  await app.register(createWsRoute({
    sessionManager,
    sessionPersistence,
    fleetManager,
    pushManager,
    healthMonitor,
    notificationConfigManager,
    analyticsCollector,
    claudeWorkDir: config.claudeWorkDir,
  }));

  // 6. Static file serving + SPA fallback (must be LAST — catches unmatched routes)
  await app.register(staticPlugin);

  // ── Graceful shutdown ──────────────────────────────────

  app.addHook('onClose', async () => {
    logger.info('Shutting down services...');
    healthMonitor.dispose();
    await analyticsCollector.flush();
    await fleetManager.dispose();
    await sessionPersistence.saveAllImmediate((id) => {
      const session = sessionManager.tryGet(id);
      if (!session) return null;
      return {
        id: session.id,
        adapter: session.adapter,
        workingDir: session.workingDir,
        status: session.status,
        startedAt: session.startedAt,
        metadata: session.toMeta(),
        transcript: session.transcript.getAll(),
      };
    });
    sessionPersistence.dispose();
    await pushManager.dispose();
    logger.info('Shutdown complete');
  });

  return app;
}
