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
import { createAuthRoutes } from './routes/auth.js';
import { createHealthRoutes } from './routes/health.js';
import { createPushRoutes } from './routes/push.js';
import { createNotificationConfigRoutes } from './routes/notification-config.js';
import { createAnalyticsRoutes } from './routes/analytics.js';
import { createAchievementRoutes } from './routes/achievements.js';
import { createWsRoute } from './routes/ws.js';
import { createShellRoute } from './routes/shell.js';
import { tmuxBootstrap, TmuxMissingError, TmuxVersionError } from './adapters/tmux-bootstrap.js';

// Services
import { SessionManager } from './sessions/session-manager.js';
import { SessionPersistence } from './sessions/session-persistence.js';
import { FleetManager } from './fleet/fleet-manager.js';
import { PushManager } from './push/push-manager.js';
import { NotificationConfigManager } from './push/notification-config.js';
import { HealthMonitor } from './health/health-monitor.js';
import { AnalyticsCollector } from './analytics/analytics-collector.js';
import { AchievementService } from './achievements/achievement-service.js';
import { UserRegistry } from './users/user-registry.js';
import { AnnotationStore } from './annotations/annotation-store.js';
import { ActivityFeed } from './users/activity-feed.js';
import { SandboxGuard } from './security/sandbox-guard.js';
import { AuditLog } from './security/audit-log.js';
import { RateLimiter } from './security/rate-limiter.js';
import { getSessionSecret } from './auth/session.js';
import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { homedir } from 'node:os';

declare module 'fastify' {
  interface FastifyInstance {
    userRegistry?: UserRegistry;
  }
}

export interface AppConfig {
  port: number;
  claudeWorkDir: string;
  multiUserEnabled: boolean;
  authGoogleEnabled: boolean;
  authPinEnabled: boolean;
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
  const achievementService = new AchievementService();

  // Multi-user services — only created when multi-user mode is enabled
  const userRegistry = config.multiUserEnabled ? new UserRegistry() : undefined;
  const annotationStore = config.multiUserEnabled ? new AnnotationStore() : undefined;
  const activityFeed = config.multiUserEnabled ? new ActivityFeed() : undefined;
  const sandboxGuard = config.multiUserEnabled ? new SandboxGuard() : undefined;

  // Security services — only created when multi-user mode is enabled
  const auditLog = config.multiUserEnabled ? new AuditLog() : undefined;
  const rateLimiter = config.multiUserEnabled ? new RateLimiter() : undefined;

  // Start health monitoring
  healthMonitor.start();

  // Restore persisted data
  await sessionManager.restoreFromDisk().catch((err: unknown) => {
    logger.error({ err }, 'Failed to restore sessions from disk, starting anyway');
  });
  await pushManager.restoreFromDisk().catch((err: unknown) => {
    logger.error({ err }, 'Failed to restore push subscriptions from disk, starting anyway');
  });
  await achievementService.load().catch((err: unknown) => {
    logger.error({ err }, 'Failed to load achievement state from disk, starting fresh');
  });
  if (userRegistry) {
    await userRegistry.load().catch((err: unknown) => {
      logger.error({ err }, 'Failed to load user registry from disk, starting fresh');
    });
  }
  if (annotationStore) {
    await annotationStore.ensureDir().catch((err: unknown) => {
      logger.error({ err }, 'Failed to create annotations directory, starting anyway');
    });
  }
  if (sandboxGuard) {
    await sandboxGuard.load().catch((err: unknown) => {
      logger.error({ err }, 'Failed to load sandbox config from disk, starting fresh');
    });
  }
  if (auditLog) {
    await auditLog.init().catch((err: unknown) => {
      logger.error({ err }, 'Failed to initialize audit log, starting anyway');
    });
  }
  if (rateLimiter) {
    // Load rate limit config from ~/.major-tom/config.json if it exists
    try {
      const configPath = join(homedir(), '.major-tom', 'config.json');
      const raw = await readFile(configPath, 'utf-8');
      const configData = JSON.parse(raw) as Record<string, unknown>;
      if (configData['rateLimits'] && typeof configData['rateLimits'] === 'object') {
        rateLimiter.fromJSON(configData['rateLimits'] as { roles?: Record<string, { promptsPerMinute: number; approvalsPerMinute: number }>; userOverrides?: Record<string, Partial<{ promptsPerMinute: number; approvalsPerMinute: number }>> });
        logger.info('Loaded rate limit config from disk');
      }
    } catch {
      // Config file doesn't exist or is malformed — use defaults
    }
  }

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

  // ── Decorate with shared services ──────────────────────
  if (userRegistry) {
    app.decorate('userRegistry', userRegistry);
  }

  // ── Register routes ────────────────────────────────────

  // Auth routes (public — Google OAuth login/logout/check)
  await app.register(createAuthRoutes({
    userRegistry,
    auditLog,
    multiUserEnabled: config.multiUserEnabled,
    authGoogleEnabled: config.authGoogleEnabled,
    authPinEnabled: config.authPinEnabled,
  }));

  // Health check (public)
  await app.register(createHealthRoutes({ sessionManager, fleetManager, healthMonitor }));

  // Push notifications (mix of public + auth-required)
  await app.register(createPushRoutes({ pushManager }));

  // Notification config (auth-required)
  await app.register(createNotificationConfigRoutes({ notificationConfigManager }));
  // Analytics API (auth required)
  await app.register(createAnalyticsRoutes({ analyticsCollector }));

  // Achievement API (auth required)
  await app.register(createAchievementRoutes({ achievementService }));

  // Shell WebSocket — Phase 13 "The Shell"
  // Eager tmux bootstrap so the first `/shell/:tabId` attach doesn't race.
  // Non-fatal: if tmux is missing on dev boxes without the shell experience,
  // we warn and continue. The shell route still rechecks lazily per connect.
  try {
    await tmuxBootstrap.ensure();
  } catch (err) {
    if (err instanceof TmuxMissingError || err instanceof TmuxVersionError) {
      logger.warn({ err: (err as Error).message }, 'tmux unavailable — shell route will be degraded');
    } else {
      logger.error({ err }, 'Unexpected tmux bootstrap error');
    }
  }
  await app.register(createShellRoute({ sessionManager }));

  // WebSocket (auth via session cookie on upgrade)
  await app.register(createWsRoute({
    sessionManager,
    sessionPersistence,
    fleetManager,
    pushManager,
    healthMonitor,
    notificationConfigManager,
    analyticsCollector,
    achievementService,
    userRegistry,
    annotationStore,
    activityFeed,
    sandboxGuard,
    auditLog,
    rateLimiter,
    claudeWorkDir: config.claudeWorkDir,
    multiUserEnabled: config.multiUserEnabled,
  }));

  // 6. Static file serving + SPA fallback (must be LAST — catches unmatched routes)
  await app.register(staticPlugin);

  // ── Graceful shutdown ──────────────────────────────────

  app.addHook('onClose', async () => {
    logger.info('Shutting down services...');
    healthMonitor.dispose();
    await achievementService.flush();
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
        ownerId: session.ownerId,
        metadata: session.toMeta(),
        transcript: session.transcript.getAll(),
      };
    });
    sessionPersistence.dispose();
    if (annotationStore) {
      await annotationStore.flush();
      annotationStore.dispose();
    }
    if (userRegistry) {
      await userRegistry.flush();
      userRegistry.dispose();
    }
    if (sandboxGuard) {
      await sandboxGuard.flush();
      sandboxGuard.dispose();
    }
    await pushManager.dispose();
    logger.info('Shutdown complete');
  });

  return app;
}
