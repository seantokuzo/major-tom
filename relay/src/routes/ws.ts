import type { FastifyPluginAsync } from 'fastify';
import { WebSocket } from 'ws';
import { resolve, relative, join, isAbsolute, basename } from 'node:path';
import { readFileSync, statSync } from 'node:fs';
import { realpath } from 'node:fs/promises';
import { homedir } from 'node:os';
import { verifySessionToken, SESSION_COOKIE, type SessionPayload } from '../auth/session.js';
import type { UserRegistry } from '../users/user-registry.js';
import { PresenceManager } from '../users/presence-manager.js';
import type { SessionManager } from '../sessions/session-manager.js';
import type { SessionPersistence, PersistedSession } from '../sessions/session-persistence.js';
import type { FleetManager } from '../fleet/fleet-manager.js';
import { NotificationDigest } from '../push/notification-digest.js';
import { scorePriority } from '../push/priority-scorer.js';
import type { NotificationConfigManager } from '../push/notification-config.js';
import type { PushManager } from '../push/push-manager.js';
import type { HealthMonitor } from '../health/health-monitor.js';
import { eventBus } from '../events/event-bus.js';
import { agentTracker } from '../events/agent-tracker.js';
import { encodeServerMessage, safeDecode } from '../protocol/codec.js';
import { truncateMetaField } from '../sessions/session-transcript.js';
import { EventBufferManager } from '../sessions/event-buffer.js';
import { scanWorkspaceTree } from '../workspace/tree-scanner.js';
import type { ClientMessage, ServerMessage, FileNode } from '../protocol/messages.js';
import { createFsHandlers, type FsServerMessage } from './fs.js';
import type { AnalyticsCollector } from '../analytics/analytics-collector.js';
import type { AchievementService } from '../achievements/achievement-service.js';
import { AnnotationStore } from '../annotations/annotation-store.js';
import { ActivityFeed } from '../users/activity-feed.js';
import { logger } from '../utils/logger.js';

interface WsDeps {
  sessionManager: SessionManager;
  sessionPersistence: SessionPersistence;
  fleetManager: FleetManager;
  pushManager: PushManager;
  healthMonitor: HealthMonitor;
  notificationConfigManager: NotificationConfigManager;
  analyticsCollector: AnalyticsCollector;
  achievementService: AchievementService;
  userRegistry: UserRegistry;
  annotationStore: AnnotationStore;
  activityFeed: ActivityFeed;
  claudeWorkDir: string;
}

/**
 * WebSocket route — handles all real-time communication.
 * Auth via session cookie (verified within the WebSocket handler logic).
 */
export function createWsRoute(deps: WsDeps): FastifyPluginAsync {
  const {
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
    claudeWorkDir,
  } = deps;

  const notificationDigest = new NotificationDigest(pushManager, notificationConfigManager);
  const eventBuffer = new EventBufferManager();
  const clients = new Set<WebSocket>();
  const presenceManager = new PresenceManager();

  // ── Achievement event wiring ────────────────────────────────
  // When an achievement unlocks, broadcast to all connected clients + record in analytics
  achievementService.onUnlock((payload) => {
    broadcastToAll({
      type: 'achievement.unlocked',
      achievementId: payload.achievementId,
      name: payload.name,
      description: payload.description,
      category: payload.category,
      icon: payload.icon,
      unlockedAt: payload.unlockedAt,
    });
    analyticsCollector.recordAchievementUnlocked({
      achievementId: payload.achievementId,
      achievementName: payload.name,
      category: payload.category,
    });
  });

  achievementService.onProgress((payload) => {
    broadcastToAll({
      type: 'achievement.progress',
      achievementId: payload.achievementId,
      name: payload.name,
      current: payload.current,
      target: payload.target,
      percentage: payload.percentage,
    });
  });

  // ── Approval timing tracker for Speed Demon achievement ────
  const approvalRequestTimes = new Map<string, number>();

  // ── Filesystem handlers (sandboxed browsing) ──────────────
  const fsHandlers = createFsHandlers((ws: WebSocket, msg: FsServerMessage) => {
    if (ws.readyState === WebSocket.OPEN) {
      ws.send(encodeServerMessage(msg as ServerMessage));
    }
  });

  // ── Session keepalive: 10-minute timeout when all clients disconnect ──
  const SESSION_TIMEOUT_MS = 10 * 60 * 1000; // 10 minutes
  /** Maps sessionId → Set of WebSocket clients attached to that session */
  const sessionClients = new Map<string, Set<WebSocket>>();
  /** Maps sessionId → cleanup timeout (fires when no clients remain) */
  const sessionTimeouts = new Map<string, ReturnType<typeof setTimeout>>();
  /** Maps WebSocket → sessionId for cleanup on disconnect */
  const clientSessions = new Map<WebSocket, string>();

  function trackClientSession(ws: WebSocket, sessionId: string): void {
    // Remove from previous session if switching
    const prevSessionId = clientSessions.get(ws);
    if (prevSessionId && prevSessionId !== sessionId) {
      untrackClientSession(ws);
    }

    clientSessions.set(ws, sessionId);
    let clientSet = sessionClients.get(sessionId);
    if (!clientSet) {
      clientSet = new Set();
      sessionClients.set(sessionId, clientSet);
    }
    clientSet.add(ws);

    // Update presence — track that this ws is watching this session
    presenceManager.watchSession(ws, sessionId);
    broadcastToAll({ type: 'presence.update', users: presenceManager.getAllPresence() });

    // Cancel any pending timeout — a client is connected
    const timeout = sessionTimeouts.get(sessionId);
    if (timeout) {
      clearTimeout(timeout);
      sessionTimeouts.delete(sessionId);
      logger.info({ sessionId }, 'Session timeout cancelled — client reconnected');
    }
  }

  function untrackClientSession(ws: WebSocket): void {
    const sessionId = clientSessions.get(ws);
    if (!sessionId) return;
    clientSessions.delete(ws);

    // Clear watching state so presence doesn't show stale session
    presenceManager.unwatchSession(ws);

    const clientSet = sessionClients.get(sessionId);
    if (clientSet) {
      clientSet.delete(ws);
      if (clientSet.size === 0) {
        sessionClients.delete(sessionId);
        startSessionTimeout(sessionId);
      }
    }
  }

  function startSessionTimeout(sessionId: string): void {
    // Don't double-set
    if (sessionTimeouts.has(sessionId)) return;
    // Only timeout sessions that actually have an SDK session
    if (!fleetManager.hasSession(sessionId)) return;

    logger.info({ sessionId, timeoutMs: SESSION_TIMEOUT_MS }, 'All clients disconnected — starting session timeout');

    const timeout = setTimeout(() => {
      sessionTimeouts.delete(sessionId);
      // Check again — a client might have reconnected in the meantime
      const clientSet = sessionClients.get(sessionId);
      if (clientSet && clientSet.size > 0) return;

      logger.info({ sessionId }, 'Session timeout fired — destroying abandoned session');
      fleetManager.destroySession(sessionId);
      healthMonitor.untrackSession(sessionId);
      eventBuffer.removeSession(sessionId);
      sessionManager.close(sessionId);

      // Persist before cleanup
      const data = buildPersistedSession(sessionId);
      if (data) sessionPersistence.save(data);
      sessionManager.destroy(sessionId);
    }, SESSION_TIMEOUT_MS);

    sessionTimeouts.set(sessionId, timeout);
  }

  // ── Helpers ──────────────────────────────────────────────

  function sendToClient(ws: WebSocket, message: ServerMessage): void {
    if (ws.readyState === WebSocket.OPEN) {
      ws.send(encodeServerMessage(message));
    }
  }

  /** Broadcast a session-scoped message to clients attached to that session */
  function broadcastToSession(sessionId: string, message: ServerMessage): void {
    const seq = eventBuffer.record(sessionId, message);
    message.seq = seq;
    const encoded = encodeServerMessage(message);
    const sessionWs = sessionClients.get(sessionId);
    if (sessionWs) {
      for (const client of sessionWs) {
        if (client.readyState === WebSocket.OPEN) {
          client.send(encoded);
        }
      }
    }
  }

  /** Broadcast a global message to ALL connected clients */
  function broadcastToAll(message: ServerMessage): void {
    const encoded = encodeServerMessage(message);
    for (const client of clients) {
      if (client.readyState === WebSocket.OPEN) {
        client.send(encoded);
      }
    }
  }

  function buildPersistedSession(sessionId: string): PersistedSession | null {
    const session = sessionManager.tryGet(sessionId);
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
  }

  function triggerPersistence(sessionId: string): void {
    const data = buildPersistedSession(sessionId);
    if (data) sessionPersistence.save(data);
  }

  // ── Message Router ───────────────────────────────────────

  // ── Role-based message guards ─────────────────────────────
  const VIEWER_ALLOWED: Set<string> = new Set([
    'session.attach', 'session.list', 'session.resume', 'achievement.list',
    'fleet.status', 'workspace.tree', 'fs.ls', 'fs.readFile', 'fs.cwd',
    'presence.watch', 'presence.unwatch', 'user.list', 'activity.list',
    'annotation.list',
  ]);
  const ADMIN_ONLY: Set<string> = new Set([
    'user.invite', 'user.revoke', 'user.updateRole',
  ]);

  async function handleClientMessage(message: ClientMessage, ws: WebSocket): Promise<void> {
    // Role-based access control — deny if role is missing
    const userRole = presenceManager.getUserRole(ws);
    if (!userRole) {
      sendToClient(ws, { type: 'error', code: 'FORBIDDEN', message: 'Role missing — access denied' });
      return;
    }
    if (userRole === 'viewer' && !VIEWER_ALLOWED.has(message.type)) {
      sendToClient(ws, { type: 'error', code: 'FORBIDDEN', message: 'Viewers cannot perform this action' });
      return;
    }
    if (ADMIN_ONLY.has(message.type) && userRole !== 'admin') {
      sendToClient(ws, { type: 'error', code: 'FORBIDDEN', message: 'Admin access required' });
      return;
    }

    switch (message.type) {
      case 'session.start': {
        let workDir = message.workingDir ?? claudeWorkDir;

        // Validate workingDir against filesystem sandbox if provided
        if (message.workingDir) {
          const sandboxRoot = fsHandlers.sandboxRoot;
          // Resolve ~ prefix and make absolute
          let resolved = message.workingDir;
          if (resolved.startsWith('~')) {
            resolved = join(homedir(), resolved.slice(1));
          }
          resolved = resolve(sandboxRoot, resolved);

          // Use path.relative() boundary check to prevent prefix attacks
          // (e.g., sandboxRoot "/home/u/Documents" accepting "/home/u/Documents_evil")
          const rel = relative(sandboxRoot, resolved);
          if (resolved !== sandboxRoot && (rel.startsWith('..') || isAbsolute(rel))) {
            sendToClient(ws, {
              type: 'error',
              code: 'INVALID_WORKING_DIR',
              message: `Working directory is outside sandbox: ${message.workingDir}`,
            });
            break;
          }

          // Resolve symlinks and verify real path is also within sandbox
          try {
            let realSandbox: string;
            try {
              realSandbox = await realpath(sandboxRoot);
            } catch {
              realSandbox = sandboxRoot;
            }
            const realResolved = await realpath(resolved);
            const realRel = relative(realSandbox, realResolved);
            if (realResolved !== realSandbox && (realRel.startsWith('..') || isAbsolute(realRel))) {
              sendToClient(ws, {
                type: 'error',
                code: 'INVALID_WORKING_DIR',
                message: `Working directory resolves outside sandbox: ${message.workingDir}`,
              });
              break;
            }
          } catch {
            // Path doesn't exist yet — the CLI adapter will fail with a proper error
          }
          workDir = resolved;
        }

        const session = await fleetManager.start(workDir);
        healthMonitor.trackSession(session.id);
        trackClientSession(ws, session.id);

        // Set session owner
        const startUserId = presenceManager.getUserId(ws);
        if (startUserId) {
          session.setOwner(startUserId);
          const startUser = await userRegistry.getUser(startUserId);
          const startUserName = startUser?.name ?? startUser?.email ?? 'Unknown';
          activityFeed.record(startUserId, startUserName, 'started session', session.id);
        }

        // Record session start in analytics
        analyticsCollector.recordSessionStart({
          sessionId: session.id,
          workingDir: workDir,
        });
        // Track achievement: session started
        achievementService.checkEvent('session.start');
        sendToClient(ws, {
          type: 'session.info',
          sessionId: session.id,
          adapter: session.adapter,
          startedAt: session.startedAt,
        });
        break;
      }

      case 'session.attach': {
        if (sessionManager.isPersistedOnly(message.sessionId)) {
          const meta = sessionManager.getPersistedMeta(message.sessionId);
          if (meta) {
            sendToClient(ws, {
              type: 'session.info',
              sessionId: message.sessionId,
              adapter: meta.adapter ?? 'cli',
              startedAt: meta.startedAt ?? new Date().toISOString(),
            });
          }
          const transcript = await sessionManager.getPersistedTranscript(message.sessionId);
          sendToClient(ws, {
            type: 'session.history',
            sessionId: message.sessionId,
            entries: transcript,
          });
          break;
        }
        // Try to attach — distinguish not-found from other failures
        let session;
        try {
          session = await fleetManager.attach(message.sessionId);
        } catch (err: unknown) {
          const msg = err instanceof Error ? err.message : String(err);
          const isNotFound = msg.includes('not found') || msg.includes('SESSION_NOT_FOUND');
          if (isNotFound) {
            sendToClient(ws, {
              type: 'error',
              code: 'SESSION_NOT_FOUND',
              message: `Session not found: ${message.sessionId}`,
            });
          } else {
            logger.error({ err, sessionId: message.sessionId }, 'Failed to attach to CLI session');
            sendToClient(ws, {
              type: 'error',
              code: 'SESSION_ATTACH_FAILED',
              message: `Failed to attach to session: ${message.sessionId}`,
            });
          }
          break;
        }
        trackClientSession(ws, session.id);
        sendToClient(ws, {
          type: 'session.info',
          sessionId: session.id,
          adapter: session.adapter,
          startedAt: session.startedAt,
        });
        // Re-broadcast pending approvals (with priority)
        const pending = fleetManager.getPendingApprovals();
        for (const req of pending) {
          const reqPriority = scorePriority(req.tool, req.description, req.details);
          sendToClient(ws, {
            type: 'approval.request',
            requestId: req.requestId,
            tool: req.tool,
            description: req.description,
            details: req.details,
            priority: reqPriority,
          });
        }
        break;
      }

      case 'session.end': {
        // Cancel any pending timeout for this session
        const endTimeout = sessionTimeouts.get(message.sessionId);
        if (endTimeout) {
          clearTimeout(endTimeout);
          sessionTimeouts.delete(message.sessionId);
        }
        sessionClients.delete(message.sessionId);

        const session = sessionManager.tryGet(message.sessionId);
        if (session) {
          // Record session end in analytics
          analyticsCollector.recordSessionEnd({
            sessionId: session.id,
            totalCost: session.totalCost,
            totalTokens: session.inputTokens + session.outputTokens,
            durationMs: session.totalDuration,
            turnCount: session.turnCount,
          });
          // Track achievement: session ended with cost/duration data
          achievementService.checkEvent('session.end', {
            durationMs: session.totalDuration,
            costUsd: session.totalCost,
          });
          triggerPersistence(message.sessionId);
          sessionManager.close(message.sessionId);
        }
        // Properly destroy the SDK session (kills Claude process in worker)
        if (fleetManager.hasSession(message.sessionId)) {
          fleetManager.destroySession(message.sessionId);
        }
        healthMonitor.untrackSession(message.sessionId);
        // Broadcast BEFORE removing buffer — broadcastToSession() records events by sessionId,
        // so removing first would recreate a fresh (leaked) buffer for this session.
        broadcastToSession(message.sessionId, { type: 'session.ended', sessionId: message.sessionId });
        eventBuffer.removeSession(message.sessionId);
        break;
      }

      case 'session.resume': {
        const resumeSessionId = message.sessionId;
        const lastSeq = message.lastSeq ?? 0;

        // Check if session exists (live or persisted)
        const liveSession = sessionManager.tryGet(resumeSessionId);
        const isPersistedOnly = sessionManager.isPersistedOnly(resumeSessionId);

        if (!liveSession && !isPersistedOnly) {
          sendToClient(ws, {
            type: 'session.resume.response',
            sessionId: resumeSessionId,
            success: false,
            replayedCount: 0,
            currentSeq: 0,
          });
          break;
        }

        // Track this client for the session
        trackClientSession(ws, resumeSessionId);

        // Send session info first
        if (liveSession) {
          sendToClient(ws, {
            type: 'session.info',
            sessionId: liveSession.id,
            adapter: liveSession.adapter,
            startedAt: liveSession.startedAt,
          });
        } else {
          const meta = sessionManager.getPersistedMeta(resumeSessionId);
          if (meta) {
            sendToClient(ws, {
              type: 'session.info',
              sessionId: resumeSessionId,
              adapter: meta.adapter ?? 'cli',
              startedAt: meta.startedAt ?? new Date().toISOString(),
            });
          }
        }

        // For persisted-only sessions the event buffer is empty (no live stream).
        // Send the persisted transcript as session.history so the client has context,
        // mirroring what session.attach does.
        if (isPersistedOnly) {
          const transcript = await sessionManager.getPersistedTranscript(resumeSessionId);
          sendToClient(ws, {
            type: 'session.history',
            sessionId: resumeSessionId,
            entries: transcript,
          });
        }

        // Replay missed events from the event buffer
        const missedEvents = eventBuffer.getEventsAfter(resumeSessionId, lastSeq);
        for (const buffered of missedEvents) {
          sendToClient(ws, buffered.message);
        }

        // Re-broadcast pending approvals (with priority) — they may not be in the
        // event buffer if the client disconnected before the approval was queued
        const pendingApprovals = fleetManager.getPendingApprovals();
        for (const req of pendingApprovals) {
          const resumePriority = scorePriority(req.tool, req.description, req.details);
          sendToClient(ws, {
            type: 'approval.request',
            requestId: req.requestId,
            tool: req.tool,
            description: req.description,
            details: req.details,
            priority: resumePriority,
          });
        }

        // Send current permission mode
        const modeState = fleetManager.permissionFilter.getMode();
        sendToClient(ws, {
          type: 'permission.mode',
          mode: modeState.mode,
          delaySeconds: modeState.delaySeconds,
          godSubMode: modeState.godSubMode,
        });

        const currentSeq = eventBuffer.getCurrentSeq(resumeSessionId);
        sendToClient(ws, {
          type: 'session.resume.response',
          sessionId: resumeSessionId,
          success: true,
          replayedCount: missedEvents.length,
          currentSeq,
        });

        logger.info(
          {
            sessionId: resumeSessionId,
            lastSeq,
            replayedCount: missedEvents.length,
            currentSeq,
          },
          'Session resumed — replayed missed events',
        );
        break;
      }

      case 'prompt': {
        const promptSession = sessionManager.tryGet(message.sessionId);
        if (promptSession) {
          promptSession.transcript.append({
            type: 'user',
            content: message.text,
            timestamp: new Date().toISOString(),
          });
          triggerPersistence(message.sessionId);
        }
        await fleetManager.sendPrompt(message.sessionId, message.text, message.context);
        break;
      }

      case 'approval': {
        fleetManager.resolveApproval(message.requestId, message.decision);
        // Broadcast who resolved the approval
        const approverUserId = presenceManager.getUserId(ws);
        if (approverUserId) {
          const approverUser = await userRegistry.getUser(approverUserId);
          broadcastToAll({
            type: 'approval.resolved',
            requestId: message.requestId,
            decision: message.decision,
            resolvedBy: {
              userId: approverUserId,
              name: approverUser?.name,
            },
          });
          // Record in activity feed
          const approverName = approverUser?.name ?? approverUser?.email ?? 'Unknown';
          const approvalAction = message.decision === 'deny' ? 'denied' : 'approved';
          activityFeed.record(approverUserId, approverName, `${approvalAction} approval`);
        }
        // Track achievement: approval decisions with timing for Speed Demon
        if (message.decision === 'allow' || message.decision === 'allow_always') {
          const sentAt = approvalRequestTimes.get(message.requestId);
          const approvalDurationMs = sentAt ? Date.now() - sentAt : undefined;
          approvalRequestTimes.delete(message.requestId);
          achievementService.checkEvent('approval.granted', {
            source: message.source,
            durationMs: approvalDurationMs,
          });
        } else if (message.decision === 'deny') {
          approvalRequestTimes.delete(message.requestId);
          achievementService.checkEvent('approval.denied');
        }
        break;
      }

      case 'cancel': {
        await fleetManager.cancelOperation(message.sessionId);
        break;
      }

      case 'agent.message': {
        await fleetManager.sendAgentMessage(message.sessionId, message.agentId, message.text);
        break;
      }

      case 'workspace.tree': {
        const session = message.sessionId
          ? sessionManager.tryGet(message.sessionId)
          : (() => {
              const sessions = sessionManager.list();
              return sessions.length > 0 ? sessionManager.tryGet(sessions[0]!.id) : undefined;
            })();
        const workDir = session?.workingDir ?? claudeWorkDir;
        const resolvedTreePath = message.path ? resolve(workDir, message.path) : workDir;
        const relTreePath = relative(workDir, resolvedTreePath);
        if (relTreePath.startsWith('..')) {
          sendToClient(ws, { type: 'workspace.tree.response', files: [] });
          break;
        }
        const tree = await scanWorkspaceTree(workDir, message.path);
        sendToClient(ws, {
          type: 'workspace.tree.response',
          files: tree.map(function mapNode(n): FileNode {
            return {
              name: n.name,
              path: n.path,
              isDirectory: n.type === 'directory',
              children: n.children?.map(mapNode),
            };
          }),
        });
        break;
      }

      case 'context.add': {
        const session = sessionManager.tryGet(message.sessionId);
        if (!session) {
          sendToClient(ws, {
            type: 'context.add.response',
            path: message.path,
            success: false,
            error: 'Session not found',
            totalContextSize: 0,
          });
          break;
        }
        if (message.contextType !== 'file') {
          sendToClient(ws, {
            type: 'context.add.response',
            path: message.path,
            success: false,
            error: `Unsupported contextType: '${message.contextType}'. Only 'file' is supported.`,
            totalContextSize: session.contextSize,
          });
          break;
        }
        const resolved = resolve(session.workingDir, message.path);
        const rel = relative(session.workingDir, resolved);
        if (rel.startsWith('..') || rel.startsWith('/')) {
          sendToClient(ws, {
            type: 'context.add.response',
            path: message.path,
            success: false,
            error: 'Invalid path',
            totalContextSize: session.contextSize,
          });
          break;
        }
        try {
          const MAX_FILE_BYTES = 50 * 1024;
          const stat = statSync(resolved);
          if (stat.size > MAX_FILE_BYTES) {
            sendToClient(ws, {
              type: 'context.add.response',
              path: message.path,
              success: false,
              error: `File exceeds 50 KB limit (${(stat.size / 1024).toFixed(1)} KB)`,
              totalContextSize: session.contextSize,
            });
            break;
          }
          const content = readFileSync(resolved, 'utf-8');
          const result = session.addContextFile(message.path, content);
          if (result.ok) {
            // Forward to worker so it can prepend context to prompts
            fleetManager.addContextFile(message.sessionId, message.path, content);
          }
          sendToClient(ws, {
            type: 'context.add.response',
            path: message.path,
            success: result.ok,
            error: result.error,
            totalContextSize: session.contextSize,
          });
        } catch (err) {
          sendToClient(ws, {
            type: 'context.add.response',
            path: message.path,
            success: false,
            error: err instanceof Error ? err.message : 'Failed to read file',
            totalContextSize: session.contextSize,
          });
        }
        break;
      }

      case 'context.remove': {
        const session = sessionManager.tryGet(message.sessionId);
        if (!session) {
          sendToClient(ws, {
            type: 'context.remove.response',
            path: message.path,
            success: false,
            error: 'Session not found',
            totalContextSize: 0,
          });
          break;
        }
        session.removeContextFile(message.path);
        fleetManager.removeContextFile(message.sessionId, message.path);
        sendToClient(ws, {
          type: 'context.remove.response',
          path: message.path,
          success: true,
          totalContextSize: session.contextSize,
        });
        break;
      }

      case 'settings.approval': {
        // Update parent-side filter + broadcast to all fleet workers
        // (workers handle their own approval queue flushing via ipc:permission.mode)
        fleetManager.setPermissionMode(message.mode, message.delaySeconds, message.godSubMode);
        const permFilter = fleetManager.permissionFilter;

        // Track achievement: god mode enabled
        if (message.mode === 'god') {
          achievementService.checkEvent('god_mode.enabled');
        }

        // Clear parent-side pending approval mirror when workers auto-flush
        // (god mode auto-allows all; smart mode may auto-allow some)
        if (message.mode === 'god' || message.mode === 'smart') {
          fleetManager.clearPendingApprovals();
        }

        // Broadcast updated mode to all clients
        broadcastToAll({
          type: 'permission.mode',
          mode: message.mode,
          delaySeconds: permFilter.getMode().delaySeconds,
          godSubMode: permFilter.getMode().godSubMode,
        });
        break;
      }

      case 'session.list': {
        const sessions = sessionManager.listMeta();
        sendToClient(ws, { type: 'session.list.response', sessions });
        break;
      }

      // ── Fleet status ─────────────────────────────────────
      case 'fleet.status': {
        const fleet = fleetManager.getFleetStatus();
        let aggregateCost = 0;
        let aggregateInput = 0;
        let aggregateOutput = 0;

        const enrichedWorkers = fleet.workers.map((w) => {
          const workerSessionIds = fleetManager.getWorkerSessionIds(w.workerId);
          const sessions = workerSessionIds.map((sid) => {
            const session = sessionManager.tryGet(sid);
            if (session) {
              const meta = session.toMeta();
              aggregateCost += meta.totalCost;
              aggregateInput += meta.inputTokens;
              aggregateOutput += meta.outputTokens;
              return {
                sessionId: sid,
                status: meta.status,
                totalCost: meta.totalCost,
                turnCount: meta.turnCount,
                inputTokens: meta.inputTokens,
                outputTokens: meta.outputTokens,
              };
            }
            return {
              sessionId: sid,
              status: 'unknown',
              totalCost: 0,
              turnCount: 0,
              inputTokens: 0,
              outputTokens: 0,
            };
          });

          return {
            workerId: w.workerId,
            workingDir: w.workingDir,
            dirName: basename(w.workingDir),
            sessionCount: w.sessionCount,
            uptimeMs: w.uptimeMs,
            restartCount: w.restartCount,
            healthy: w.healthy,
            sessions,
          };
        });

        sendToClient(ws, {
          type: 'fleet.status.response',
          totalWorkers: fleet.totalWorkers,
          totalSessions: fleet.totalSessions,
          aggregateCost,
          aggregateTokens: {
            input: aggregateInput,
            output: aggregateOutput,
          },
          workers: enrichedWorkers,
        });
        break;
      }

      // ── Filesystem browsing ──────────────────────────────
      case 'fs.ls': {
        await fsHandlers.handleFsLs(ws, message);
        break;
      }

      case 'fs.readFile': {
        await fsHandlers.handleFsReadFile(ws, message);
        break;
      }

      case 'fs.cwd': {
        fsHandlers.handleFsCwd(ws);
        break;
      }

      // ── Achievements ────────────────────────────────────────
      case 'achievement.list': {
        const achievements = achievementService.getAllStatus();
        sendToClient(ws, {
          type: 'achievement.list.response',
          achievements,
          totalCount: achievementService.getTotalCount(),
          unlockedCount: achievementService.getUnlockedCount(),
        });
        break;
      }

      // ── Presence ──────────────────────────────────────────
      case 'presence.watch': {
        presenceManager.watchSession(ws, message.sessionId);
        broadcastToAll({ type: 'presence.update', users: presenceManager.getAllPresence() });
        break;
      }

      case 'presence.unwatch': {
        presenceManager.unwatchSession(ws);
        broadcastToAll({ type: 'presence.update', users: presenceManager.getAllPresence() });
        break;
      }

      // ── User management ────────────────────────────────────
      case 'user.list': {
        const users = await userRegistry.listUsers();
        sendToClient(ws, {
          type: 'user.list.response',
          users: users.map((u) => ({
            id: u.id,
            email: u.email,
            name: u.name,
            picture: u.picture,
            role: u.role,
            isOnline: presenceManager.isOnline(u.id),
            lastLoginAt: u.lastLoginAt,
          })),
        });
        break;
      }

      case 'user.invite': {
        const inviterUserId = presenceManager.getUserId(ws);
        if (!inviterUserId) break;
        try {
          const invite = await userRegistry.generateInviteCode(message.role, inviterUserId);
          sendToClient(ws, {
            type: 'user.invite.response',
            code: invite.code,
            expiresAt: invite.expiresAt,
            success: true,
          });
        } catch (err) {
          sendToClient(ws, {
            type: 'user.invite.response',
            code: '',
            expiresAt: '',
            success: false,
            error: err instanceof Error ? err.message : String(err),
          });
        }
        break;
      }

      case 'user.revoke': {
        await userRegistry.deleteUser(message.userId);
        // Disconnect all active WebSocket connections for the revoked user
        presenceManager.disconnectUser(message.userId);
        sendToClient(ws, {
          type: 'user.revoke.response',
          userId: message.userId,
          success: true,
        });
        broadcastToAll({ type: 'presence.update', users: presenceManager.getAllPresence() });
        break;
      }

      case 'user.updateRole': {
        await userRegistry.updateUser(message.userId, { role: message.role });
        // Update cached role in PresenceManager so connected sockets reflect the change
        presenceManager.updateUserRole(message.userId, message.role);
        broadcastToAll({
          type: 'user.roleUpdated',
          userId: message.userId,
          role: message.role,
        });
        break;
      }

      case 'activity.list': {
        const entries = activityFeed.getRecent(50);
        sendToClient(ws, {
          type: 'activity.feed',
          entries,
        });
        break;
      }

      // ── Annotations ──────────────────────────────────────────
      case 'annotation.add': {
        const annotatorUserId = presenceManager.getUserId(ws);
        if (!annotatorUserId) break;

        // Validate session exists (live or persisted)
        if (!sessionManager.tryGet(message.sessionId) && !sessionManager.isPersistedOnly(message.sessionId)) {
          sendToClient(ws, { type: 'error', code: 'SESSION_NOT_FOUND', message: 'Cannot annotate — session not found' });
          break;
        }

        const annotatorUser = await userRegistry.getUser(annotatorUserId);
        const annotatorName = annotatorUser?.name ?? annotatorUser?.email ?? 'Unknown';

        const annotation = await annotationStore.addAnnotation(message.sessionId, {
          userId: annotatorUserId,
          userName: annotatorName,
          turnIndex: message.turnIndex,
          text: message.text,
          mentions: message.mentions ?? [],
        });

        broadcastToSession(message.sessionId, {
          type: 'annotation.added',
          sessionId: message.sessionId,
          annotation,
        });

        // Record activity
        activityFeed.record(annotatorUserId, annotatorName, 'annotated session', message.sessionId);

        // Send push notifications for @mentions
        for (const mentionedId of annotation.mentions) {
          if (presenceManager.isOnline(mentionedId)) continue; // They'll see it live
          // TODO: Send push notification to mentioned user
        }
        break;
      }

      case 'annotation.list': {
        const annotations = await annotationStore.getAnnotations(message.sessionId);
        sendToClient(ws, {
          type: 'annotation.list.response',
          sessionId: message.sessionId,
          annotations,
        });
        break;
      }

      // ── Session handoff ────────────────────────────────────
      case 'session.handoff': {
        const handoffUserId = presenceManager.getUserId(ws);
        if (!handoffUserId) break;

        const handoffSession = sessionManager.tryGet(message.sessionId);
        if (!handoffSession) {
          sendToClient(ws, {
            type: 'session.handoff.response',
            sessionId: message.sessionId,
            fromUserId: handoffUserId,
            toUserId: message.toUserId,
            success: false,
            error: 'Session not found',
          });
          break;
        }

        // Only owner or admin can hand off; missing ownerId = non-transferable for non-admins
        const handoffUserRole = presenceManager.getUserRole(ws);
        if (handoffUserRole !== 'admin') {
          if (!handoffSession.ownerId || handoffSession.ownerId !== handoffUserId) {
            sendToClient(ws, {
              type: 'session.handoff.response',
              sessionId: message.sessionId,
              fromUserId: handoffUserId,
              toUserId: message.toUserId,
              success: false,
              error: 'Only the session owner or admin can hand off',
            });
            break;
          }
        }

        // Verify target user exists
        const targetUser = await userRegistry.getUser(message.toUserId);
        if (!targetUser) {
          sendToClient(ws, {
            type: 'session.handoff.response',
            sessionId: message.sessionId,
            fromUserId: handoffUserId,
            toUserId: message.toUserId,
            success: false,
            error: 'Target user not found',
          });
          break;
        }

        handoffSession.setOwner(message.toUserId);

        const handoffUser = await userRegistry.getUser(handoffUserId);
        const handoffUserName = handoffUser?.name ?? handoffUser?.email ?? 'Unknown';
        activityFeed.record(handoffUserId, handoffUserName, `handed off session to ${targetUser.name ?? targetUser.email}`, message.sessionId);

        // Send response only to the requesting client
        sendToClient(ws, {
          type: 'session.handoff.response',
          sessionId: message.sessionId,
          fromUserId: handoffUserId,
          toUserId: message.toUserId,
          success: true,
        });

        // Broadcast ownership change to session watchers
        broadcastToSession(message.sessionId, {
          type: 'session.ownership.changed',
          sessionId: message.sessionId,
          fromUserId: handoffUserId,
          toUserId: message.toUserId,
        });
        break;
      }

      // Device list/revoke removed — replaced by Google OAuth single-user auth
    }
  }

  // ── Adapter → Broadcast Event Wiring ─────────────────────

  const serverMessageHandler = (message: ServerMessage) => {
    // Route session-scoped messages to session clients, others to all
    if ('sessionId' in message && typeof message.sessionId === 'string') {
      broadcastToSession(message.sessionId, message);
    } else {
      broadcastToAll(message);
    }
  };

  function wireAdapterEvents(): void {
    fleetManager.on('output', (sessionId: string, chunk: string) => {
      const session = sessionManager.tryGet(sessionId);
      if (session) {
        session.transcript.append({
          type: 'assistant',
          content: chunk,
          timestamp: new Date().toISOString(),
        });
        triggerPersistence(sessionId);
      }
      broadcastToSession(sessionId, { type: 'output', sessionId, chunk, format: 'plain' });
    });

    fleetManager.on('approval-request', (request) => {
      const priority = scorePriority(request.tool, request.description, request.details);
      // Track when approval request was sent for Speed Demon timing
      approvalRequestTimes.set(request.requestId, Date.now());
      // Approval requests go to all clients — any user might need to approve
      broadcastToAll({
        type: 'approval.request',
        requestId: request.requestId,
        tool: request.tool,
        description: request.description,
        details: request.details,
        priority,
      });
      // Use smart notification digest for priority-aware push notifications
      const rawFilePath = request.details?.['file_path'];
      const rawCommand = request.details?.['command'];
      const target = (typeof rawFilePath === 'string' ? rawFilePath : undefined)
        ?? (typeof rawCommand === 'string' ? rawCommand : undefined)
        ?? request.description;
      void notificationDigest.processNotification(
        request.tool,
        target.slice(0, 200),
        priority.level,
        request.requestId,
      );
    });

    fleetManager.on('auto-allow', (event) => {
      broadcastToAll({
        type: 'approval.auto',
        tool: event.tool,
        description: event.description,
        reason: event.reason,
        toolUseId: event.toolUseId,
      });
    });

    fleetManager.on('tool-start', (info) => {
      const session = sessionManager.tryGet(info.sessionId);
      if (session) {
        session.transcript.append({
          type: 'tool',
          content: `Tool start: ${info.tool}`,
          timestamp: new Date().toISOString(),
          meta: { tool: info.tool, input: truncateMetaField(info.input) },
        });
        triggerPersistence(info.sessionId);
      }
      // Track tool usage for analytics
      analyticsCollector.trackToolUsage(info.sessionId, info.tool);
      // Track achievement: tool usage
      achievementService.checkEvent('tool.start', { tool: info.tool });
      broadcastToSession(info.sessionId, {
        type: 'tool.start',
        sessionId: info.sessionId,
        tool: info.tool,
        input: info.input,
      });
    });

    fleetManager.on('tool-complete', (result) => {
      const session = sessionManager.tryGet(result.sessionId);
      if (session) {
        session.transcript.append({
          type: 'tool',
          content: `Tool complete: ${result.tool} (${result.success ? 'success' : 'failed'})`,
          timestamp: new Date().toISOString(),
          meta: { tool: result.tool, output: truncateMetaField(result.output), success: result.success },
        });
        triggerPersistence(result.sessionId);
      }
      broadcastToSession(result.sessionId, {
        type: 'tool.complete',
        sessionId: result.sessionId,
        tool: result.tool,
        output: result.output,
        success: result.success,
      });
    });

    fleetManager.on('session-result', (result) => {
      const session = sessionManager.tryGet(result.sessionId);
      if (session) {
        session.addResult({
          costUsd: result.costUsd,
          numTurns: result.numTurns,
          durationMs: result.durationMs,
          inputTokens: result.inputTokens,
          outputTokens: result.outputTokens,
        });
        session.transcript.append({
          type: 'result',
          content: `Turn complete: $${result.costUsd.toFixed(4)}, ${result.numTurns} turns, ${result.durationMs}ms`,
          timestamp: new Date().toISOString(),
          meta: {
            costUsd: result.costUsd,
            numTurns: result.numTurns,
            durationMs: result.durationMs,
            inputTokens: result.inputTokens,
            outputTokens: result.outputTokens,
          },
        });
        triggerPersistence(result.sessionId);
      }
      // Record turn in analytics JSONL
      const workerInfo = fleetManager.getWorkerForSessionId?.(result.sessionId);
      analyticsCollector.recordTurnComplete({
        sessionId: result.sessionId,
        workerId: workerInfo?.workerId,
        inputTokens: result.inputTokens ?? 0,
        outputTokens: result.outputTokens ?? 0,
        cost: result.costUsd,
        durationMs: result.durationMs,
      });
      broadcastToSession(result.sessionId, {
        type: 'session.result',
        sessionId: result.sessionId,
        costUsd: result.costUsd,
        numTurns: result.numTurns,
        durationMs: result.durationMs,
        inputTokens: result.inputTokens,
        outputTokens: result.outputTokens,
      });
    });

    fleetManager.on('agent-lifecycle', (event) => {
      switch (event.event) {
        case 'spawn':
          agentTracker.spawn(event.agentId, event.role ?? 'subagent', event.task ?? '', event.parentId);
          // Track achievement: agent spawned
          achievementService.checkEvent('agent.spawn');
          broadcastToAll({
            type: 'agent.spawn',
            agentId: event.agentId,
            parentId: event.parentId,
            task: event.task ?? '',
            role: event.role ?? 'subagent',
          });
          break;
        case 'working':
          agentTracker.working(event.agentId, event.task ?? '');
          broadcastToAll({ type: 'agent.working', agentId: event.agentId, task: event.task ?? '' });
          break;
        case 'idle':
          agentTracker.idle(event.agentId);
          broadcastToAll({ type: 'agent.idle', agentId: event.agentId });
          break;
        case 'complete':
          agentTracker.complete(event.agentId, event.result ?? '');
          broadcastToAll({ type: 'agent.complete', agentId: event.agentId, result: event.result ?? '' });
          break;
        case 'dismissed':
          agentTracker.dismiss(event.agentId);
          broadcastToAll({ type: 'agent.dismissed', agentId: event.agentId });
          break;
      }
    });

    // ── Fleet worker lifecycle events ──────────────────────
    fleetManager.on('worker-spawned', (info) => {
      analyticsCollector.recordWorkerStart({
        workerId: info.workerId,
        workingDir: info.workingDir,
      });
      // Track achievement: fleet mode started (worker spawn implies fleet)
      achievementService.checkEvent('fleet.started');
      broadcastToAll({
        type: 'fleet.worker.spawned',
        workerId: info.workerId,
        workingDir: info.workingDir,
        dirName: info.dirName,
      });
    });

    fleetManager.on('worker-crashed', (info) => {
      analyticsCollector.recordWorkerStop({
        workerId: info.workerId,
        reason: `crashed (restart #${info.restartCount})`,
      });
      // Track achievement: survived a worker crash
      achievementService.checkEvent('worker.crashed');
      broadcastToAll({
        type: 'fleet.worker.crashed',
        workerId: info.workerId,
        workingDir: info.workingDir,
        dirName: info.dirName,
        restartCount: info.restartCount,
      });
    });

    fleetManager.on('worker-restarted', (info) => {
      analyticsCollector.recordWorkerStart({
        workerId: info.workerId,
        workingDir: info.workingDir,
      });
      broadcastToAll({
        type: 'fleet.worker.restarted',
        workerId: info.workerId,
        workingDir: info.workingDir,
        dirName: info.dirName,
        restartCount: info.restartCount,
      });
    });

    eventBus.on('server.message', serverMessageHandler);
  }

  // ── Plugin Registration ──────────────────────────────────

  return async (fastify) => {
    // Wire adapter events once
    wireAdapterEvents();

    // Shared socket setup — wires up event handlers after auth succeeds
    function setupSocket(socket: WebSocket, ip: string, sessionPayload?: SessionPayload): void {
      (socket as WebSocket & { isAlive: boolean }).isAlive = true;
      socket.on('pong', () => {
        (socket as WebSocket & { isAlive: boolean }).isAlive = true;
      });
      clients.add(socket);

      // Register presence if we have user identity
      if (sessionPayload) {
        presenceManager.connect(socket, sessionPayload);
        broadcastToAll({ type: 'presence.update', users: presenceManager.getAllPresence() });
      }

      socket.on('error', (err) => {
        logger.error({ err }, 'WebSocket error');
      });

      socket.on('close', () => {
        clients.delete(socket);
        // Disconnect from presence before untracking session
        const disconnectResult = presenceManager.disconnect(socket);
        untrackClientSession(socket);
        if (disconnectResult) {
          broadcastToAll({ type: 'presence.update', users: presenceManager.getAllPresence() });
        }
        logger.info({ ip }, 'Client disconnected');
      });

      socket.on('message', (data) => {
        const raw = data.toString();
        const message = safeDecode(raw);
        if (!message) return;

        handleClientMessage(message, socket).catch((err: unknown) => {
          logger.error({ err, type: message.type }, 'Error handling client message');
          sendToClient(socket, {
            type: 'error',
            code: 'HANDLER_ERROR',
            message: err instanceof Error ? err.message : 'Unknown error',
          });
        });
      });

      // Send connection status
      sendToClient(socket, {
        type: 'connection.status',
        status: 'connected',
        adapter: 'cli',
      });

      // Send current permission mode so client can sync
      const modeState = fleetManager.permissionFilter.getMode();
      sendToClient(socket, {
        type: 'permission.mode',
        mode: modeState.mode,
        delaySeconds: modeState.delaySeconds,
        godSubMode: modeState.godSubMode,
      });
    }

    // WebSocket route with session cookie auth (+ legacy token fallback for dev)
    fastify.get('/ws', { websocket: true }, (socket, request) => {
      // Auth check: session cookie (primary) or ?token=AUTH_TOKEN (dev-only fallback)
      const sessionCookie = request.cookies?.[SESSION_COOKIE];
      const { token: rawQueryToken } = request.query as { token?: string | string[] };
      const queryToken = Array.isArray(rawQueryToken) ? undefined : rawQueryToken;
      const legacyAuthToken = process.env['AUTH_TOKEN'];
      const isDevMode = process.env['NODE_ENV'] !== 'production';

      // Legacy token auth: dev-only, if ?token= matches AUTH_TOKEN env var, skip OAuth
      if (isDevMode && queryToken && legacyAuthToken && queryToken === legacyAuthToken) {
        const ip = request.ip;
        logger.info({ ip }, 'Client connected via WebSocket (legacy token auth, dev mode)');
        setupSocket(socket, ip);
        return;
      }

      if (!sessionCookie) {
        logger.warn({ ip: request.ip }, 'WS connection attempt without session cookie');
        socket.close(1008, 'Authentication required');
        return;
      }

      verifySessionToken(sessionCookie)
        .then(async (payload) => {
          // For tokens without userId (legacy), look up user by email in registry
          if (!payload.userId) {
            const user = await userRegistry.getUserByEmail(payload.email);
            if (user) {
              payload.userId = user.id;
              payload.role = user.role;
            } else if (!userRegistry.isEmpty()) {
              // Registry has users but this token doesn't map to any — reject
              logger.warn({ email: payload.email }, 'WS connection rejected — token does not map to a registered user');
              socket.close(1008, 'User not registered');
              return;
            }
          }

          // Authenticated — set up connection
          const ip = request.ip;
          logger.info({ ip, email: payload.email, userId: payload.userId }, 'Client connected via WebSocket');
          setupSocket(socket, ip, payload);
        })
        .catch(() => {
          socket.close(1008, 'Invalid session');
        });
    });

    // Heartbeat interval
    const heartbeatInterval = setInterval(() => {
      for (const client of clients) {
        const conn = client as WebSocket & { isAlive: boolean };
        if (conn.isAlive === false) {
          logger.info('Terminating dead WebSocket connection');
          conn.terminate();
          clients.delete(client);
          continue;
        }
        conn.isAlive = false;
        conn.ping();
      }
    }, 30_000);

    // Cleanup on server close
    fastify.addHook('onClose', () => {
      clearInterval(heartbeatInterval);
      notificationDigest.dispose();
      eventBuffer.dispose();
      eventBus.off('server.message', serverMessageHandler);
      // Clear all session timeouts
      for (const timeout of sessionTimeouts.values()) {
        clearTimeout(timeout);
      }
      sessionTimeouts.clear();
      sessionClients.clear();
      clientSessions.clear();
      for (const client of clients) {
        client.close(1001, 'Server shutting down');
      }
      clients.clear();
    });
  };
}
