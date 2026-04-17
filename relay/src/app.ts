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
import { createApiApprovalsRoutes } from './routes/api-approvals.js';
import { createPreferencesRoutes } from './routes/preferences.js';
import { PtyAdapter } from './adapters/pty-adapter.js';

// Phase 13 Wave 2 — shell-side approval routing
import { ApprovalQueue } from './hooks/approval-queue.js';
import { createHookServer } from './hooks/hook-server.js';
import { installHooks } from './installer/install-hooks.js';
import { eventBus } from './events/event-bus.js';
import { NotificationBatcher } from './push/notification-batcher.js';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import type { Server as HttpServer } from 'node:http';

const execFileAsync = promisify(execFile);

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
import { SpriteMappingPersistence } from './sprites/sprite-mapping-persistence.js';
import { SpriteMapper } from './sprites/sprite-mapper.js';
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
  /**
   * Hook HTTP server port (Phase 13 Wave 2). The shell hook script
   * (`pretooluse.sh`) curls 127.0.0.1:HOOK_PORT/hooks/pre-tool-use.
   * Defaults to 9091 in `server.ts` (env var `HOOK_PORT`).
   */
  hookPort: number;
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
  const spriteMappingPersistence = new SpriteMappingPersistence();
  const spriteMapper = new SpriteMapper();

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

  // ── Phase 13 Wave 2 — shell-side approval routing ──────
  // The relay-level ApprovalQueue is distinct from per-session worker
  // queues. PTY-spawned `claude` flows through hooks (not workers), so
  // it doesn't share state with worker IPC. The queue extends EventEmitter
  // and broadcasts 'enqueue'/'resolve' events, which the WS layer
  // subscribes to via the eventBus 'server.message' catch-all.
  //
  // Timeout is 600s to match the hook script's `curl --max-time 600` and
  // settings.json `timeout: 600` — otherwise remote-mode approvals would
  // get auto-denied at the queue's default 5-minute mark while the hook
  // is still happily waiting another 5 minutes.
  const shellApprovalQueue = new ApprovalQueue(600_000);

  // Install (or self-heal) the Major-Tom-private hook scripts. Idempotent
  // and hash-versioned. NEVER touches the user's real ~/.claude/.
  try {
    installHooks();
  } catch (err) {
    logger.error({ err }, 'Hook installer failed — shell approval routing degraded');
  }

  // Probe `jq` — required by the shell hook for per-invocation mode
  // reading. If missing the hook falls back to the MAJOR_TOM_APPROVAL
  // env var, but the user wouldn't be able to switch modes from the PWA.
  // Loud warning, never fatal.
  try {
    await execFileAsync('jq', ['--version']);
  } catch {
    logger.warn(
      'jq not found on PATH — Phase 13 hook scripts will fall back to MAJOR_TOM_APPROVAL env var. ' +
      'Install with `brew install jq` to enable PWA mode switching.',
    );
  }

  // Notification batcher used by BOTH Wave 2 intercept paths (shell hook
  // and SDK canUseTool) so rapid-fire approvals collapse into a single
  // push instead of spamming the device's lockscreen. Single instance
  // shared across the relay so the batch window is global.
  const shellNotificationBatcher = new NotificationBatcher(pushManager);

  // Start the hook HTTP server. Plain Node http (not Fastify) — it
  // serves a tiny number of routes that need to block long-lived
  // connections (`--max-time 600` in remote mode), and Fastify's
  // request lifecycle plays poorly with that pattern.
  let hookHttpServer: HttpServer | undefined;
  try {
    hookHttpServer = createHookServer(
      {
        approvalQueue: shellApprovalQueue,
        notificationBatcher: shellNotificationBatcher,
        // Phase 13 Wave 3 — route PTY-originated SubagentStart/Stop
        // hook events through the same agent-lifecycle fanout the SDK
        // adapter uses. ws.ts:1662-1693 already listens on
        // fleetManager.on('agent-lifecycle') and does the full
        // tracker + broadcast dance.
        reportAgentLifecycle: (event) => fleetManager.reportAgentLifecycle(event),
      },
      config.hookPort,
    );
  } catch (err) {
    logger.error({ err, port: config.hookPort }, 'Failed to start hook HTTP server');
  }

  // Wire approval-queue events into the eventBus so the WS layer
  // broadcasts them to all connected PWAs. The eventBus 'server.message'
  // catch-all forwards to the existing serverMessageHandler in ws.ts.
  shellApprovalQueue.on('enqueue', (payload: {
    requestId: string;
    tool: string;
    description: string;
    details: Record<string, unknown>;
    source?: 'sdk' | 'hook';
    routingMode?: 'local' | 'remote' | 'hybrid';
    tabId?: string;
  }) => {
    eventBus.emit('approval.request', {
      type: 'approval.request',
      requestId: payload.requestId,
      tool: payload.tool,
      description: payload.description,
      details: payload.details,
      ...(payload.routingMode && { routingMode: payload.routingMode }),
      ...(payload.source && { source: payload.source }),
      ...(payload.tabId && { tabId: payload.tabId }),
    });
  });
  shellApprovalQueue.on('resolve', (payload: { requestId: string; decision: string }) => {
    // Broadcast resolve so other PWAs/devices clear their overlay.
    // Single-user mode: no resolvedBy attribution. Multi-user mode would
    // already broadcast a richer version through the WS handler at ws.ts:725.
    eventBus.emit('server.message', {
      type: 'approval.resolved',
      requestId: payload.requestId,
      decision: payload.decision,
    });
  });

  // ── Fastify instance ───────────────────────────────────
  const app = Fastify({
    logger: {
      level: process.env['LOG_LEVEL'] ?? 'info',
      name: 'major-tom-relay',
      // Redact JWTs from request URLs so ?token= values never appear in
      // logs. The shell route accepts a session JWT as a query-param
      // fallback for WKWebView cookie edge cases — without this,
      // Fastify's default request serializer would log the full URL
      // including the credential. Caught by Copilot PR #97 review.
      serializers: {
        req(request: { method?: string; url?: string; hostname?: string; remoteAddress?: string; remotePort?: number }) {
          return {
            method: request.method,
            // Strip ?token=<value> from the logged URL
            url: request.url?.replace(/([?&])token=[^&]*/g, '$1token=REDACTED'),
            hostname: request.hostname,
            remoteAddress: request.remoteAddress,
            remotePort: request.remotePort,
          };
        },
      },
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

  // ── Shell PTY adapter ──────────────────────────────────
  // Instantiated before any route that references it (health + shell).
  // The adapter owns the in-memory session map, grace timers, and ring
  // buffer. Env vars:
  //   MAJOR_TOM_PTY_GRACE_MS      (default 30 min)
  //   MAJOR_TOM_PTY_BUFFER_BYTES  (default 256 KiB)
  //   MAJOR_TOM_PTY_INPUT_MAX     (default 64 KiB)
  const parseNonNegativeInt = (raw: string | undefined): number | undefined => {
    if (raw === undefined) return undefined;
    const n = Number(raw);
    return Number.isFinite(n) && n >= 0 ? n : undefined;
  };
  const ptyAdapter = new PtyAdapter({
    graceMs: parseNonNegativeInt(process.env['MAJOR_TOM_PTY_GRACE_MS']),
    bufferBytes: parseNonNegativeInt(process.env['MAJOR_TOM_PTY_BUFFER_BYTES']),
    inputMaxBytes: parseNonNegativeInt(process.env['MAJOR_TOM_PTY_INPUT_MAX']),
    cwd: config.claudeWorkDir,
  });
  shellApprovalQueue.setHybridWriter((tabId, data) => ptyAdapter.write(tabId, data));

  // Health check (public)
  await app.register(createHealthRoutes({ sessionManager, fleetManager, healthMonitor, ptyAdapter }));

  // Push notifications (mix of public + auth-required)
  await app.register(createPushRoutes({ pushManager }));

  // Notification config (auth-required)
  await app.register(createNotificationConfigRoutes({ notificationConfigManager }));
  // Analytics API (auth required)
  await app.register(createAnalyticsRoutes({ analyticsCollector }));

  // Achievement API (auth required)
  await app.register(createAchievementRoutes({ achievementService }));

  // User preferences (cross-device sync — keybar layout, font size)
  await app.register(createPreferencesRoutes({
    userRegistry,
    multiUserEnabled: config.multiUserEnabled,
  }));

  // Shell WebSocket — registered after `createPreferencesRoutes` so its
  // path doesn't collide with any earlier catch-all. PtyAdapter was
  // constructed earlier so the health route could report tab counts.
  await app.register(createShellRoute({ ptyAdapter }));

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
    shellApprovalQueue,
    spriteMappingPersistence,
    spriteMapper,
  }));

  // Phase 13 Wave 2 — REST endpoints for approvals (cold-start fetch
  // and SW-action POSTs that can't go through the WebSocket).
  // Rate limiter + audit log are threaded in so the REST decision
  // endpoint has parity with the WebSocket handler in ws.ts.
  await app.register(createApiApprovalsRoutes({
    shellApprovalQueue,
    rateLimiter,
    auditLog,
  }));

  // 6. Static file serving + SPA fallback (must be LAST — catches unmatched routes)
  await app.register(staticPlugin);

  // ── Graceful shutdown ──────────────────────────────────

  app.addHook('onClose', async () => {
    logger.info('Shutting down services...');
    ptyAdapter.dispose();
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
    // Sprite mapping cleanup: delete all mapping files on graceful shutdown
    // (all sessions are gone, mappings are meaningless without live agents)
    await spriteMappingPersistence.deleteAll();
    spriteMappingPersistence.dispose();
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
    shellNotificationBatcher.dispose();
    if (hookHttpServer) {
      await new Promise<void>((resolve) => {
        hookHttpServer!.close((err) => {
          if (err) {
            logger.warn({ err }, 'Hook HTTP server close error');
          }
          resolve();
        });
      });
      logger.info('Hook HTTP server closed');
    }
    logger.info('Shutdown complete');
  });

  return app;
}
