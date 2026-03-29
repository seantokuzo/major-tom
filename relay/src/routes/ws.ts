import type { FastifyPluginAsync } from 'fastify';
import { WebSocket } from 'ws';
import { resolve, relative, join, isAbsolute } from 'node:path';
import { readFileSync, statSync } from 'node:fs';
import { realpath } from 'node:fs/promises';
import { homedir } from 'node:os';
import { verifySessionToken, SESSION_COOKIE } from '../auth/session.js';
import type { SessionManager } from '../sessions/session-manager.js';
import type { SessionPersistence, PersistedSession } from '../sessions/session-persistence.js';
import type { ClaudeCliAdapter } from '../adapters/claude-cli.adapter.js';
import type { ApprovalQueue } from '../hooks/approval-queue.js';
import { NotificationBatcher } from '../push/notification-batcher.js';
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
import { logger } from '../utils/logger.js';

interface WsDeps {
  sessionManager: SessionManager;
  sessionPersistence: SessionPersistence;
  cliAdapter: ClaudeCliAdapter;
  approvalQueue: ApprovalQueue;
  pushManager: PushManager;
  healthMonitor: HealthMonitor;
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
    cliAdapter,
    approvalQueue,
    pushManager,
    healthMonitor,
    claudeWorkDir,
  } = deps;

  const notificationBatcher = new NotificationBatcher(pushManager);
  const eventBuffer = new EventBufferManager();
  const clients = new Set<WebSocket>();

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
    if (!cliAdapter.hasSession(sessionId)) return;

    logger.info({ sessionId, timeoutMs: SESSION_TIMEOUT_MS }, 'All clients disconnected — starting session timeout');

    const timeout = setTimeout(() => {
      sessionTimeouts.delete(sessionId);
      // Check again — a client might have reconnected in the meantime
      const clientSet = sessionClients.get(sessionId);
      if (clientSet && clientSet.size > 0) return;

      logger.info({ sessionId }, 'Session timeout fired — destroying abandoned session');
      cliAdapter.destroySession(sessionId);
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

  function broadcast(message: ServerMessage): void {
    // Record in event buffer for session resume support.
    // Extract sessionId from the message if present.
    const sessionId = extractSessionId(message);
    if (sessionId) {
      eventBuffer.record(sessionId, message);
    }

    const encoded = encodeServerMessage(message);
    for (const client of clients) {
      if (client.readyState === WebSocket.OPEN) {
        client.send(encoded);
      }
    }
  }

  /** Extract sessionId from a server message, if present */
  function extractSessionId(message: ServerMessage): string | undefined {
    // Most message types have sessionId directly
    if ('sessionId' in message && typeof message.sessionId === 'string') {
      return message.sessionId;
    }
    return undefined;
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
      metadata: session.toMeta(),
      transcript: session.transcript.getAll(),
    };
  }

  function triggerPersistence(sessionId: string): void {
    const data = buildPersistedSession(sessionId);
    if (data) sessionPersistence.save(data);
  }

  // ── Message Router ───────────────────────────────────────

  async function handleClientMessage(message: ClientMessage, ws: WebSocket): Promise<void> {
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

        const session = await cliAdapter.start(workDir);
        healthMonitor.trackSession(session.id);
        trackClientSession(ws, session.id);
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
          session = await cliAdapter.attach(message.sessionId);
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
        // Re-broadcast pending approvals
        const pending = approvalQueue.getPendingDetails();
        for (const req of pending) {
          sendToClient(ws, {
            type: 'approval.request',
            requestId: req.requestId,
            tool: req.tool,
            description: req.description,
            details: req.details,
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
          triggerPersistence(message.sessionId);
          sessionManager.close(message.sessionId);
        }
        // Properly destroy the SDK session (kills Claude process)
        if (cliAdapter.hasSession(message.sessionId)) {
          cliAdapter.destroySession(message.sessionId);
        }
        healthMonitor.untrackSession(message.sessionId);
        eventBuffer.removeSession(message.sessionId);
        broadcast({ type: 'session.ended', sessionId: message.sessionId });
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

        // Replay missed events from the event buffer
        const missedEvents = eventBuffer.getEventsAfter(resumeSessionId, lastSeq);
        for (const buffered of missedEvents) {
          sendToClient(ws, buffered.message);
        }

        // Re-broadcast pending approvals (they may not be in the event buffer
        // if the client disconnected before the approval was queued)
        const pendingApprovals = approvalQueue.getPendingDetails();
        for (const req of pendingApprovals) {
          sendToClient(ws, {
            type: 'approval.request',
            requestId: req.requestId,
            tool: req.tool,
            description: req.description,
            details: req.details,
          });
        }

        // Send current permission mode
        const modeState = cliAdapter.permissionFilter.getMode();
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
        await cliAdapter.sendPrompt(message.sessionId, message.text, message.context);
        break;
      }

      case 'approval': {
        approvalQueue.resolve(message.requestId, message.decision);
        break;
      }

      case 'cancel': {
        await cliAdapter.cancelOperation(message.sessionId);
        break;
      }

      case 'agent.message': {
        await cliAdapter.sendAgentMessage(message.sessionId, message.agentId, message.text);
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
        sendToClient(ws, {
          type: 'context.remove.response',
          path: message.path,
          success: true,
          totalContextSize: session.contextSize,
        });
        break;
      }

      case 'settings.approval': {
        // Map high-level permission modes to queue-level modes
        const permFilter = cliAdapter.permissionFilter;
        permFilter.setMode(message.mode, message.delaySeconds, message.godSubMode);

        // When switching modes mid-response, re-evaluate pending approvals:
        // - God mode: flush ALL pending (auto-allow everything)
        // - Smart mode: flush pending that the filter would now auto-allow
        // - Delay mode: ApprovalQueue.setMode('delay') attaches delay timers
        // - Manual mode: pending stay queued (already in manual queue)
        if (message.mode === 'god') {
          approvalQueue.flushPending();
        } else if (message.mode === 'smart') {
          approvalQueue.flushMatching((tool, details) => {
            const input = (details?.['tool_input'] as Record<string, unknown>) ?? {};
            return permFilter.check(tool, input).allowed;
          });
        }

        const queueMode = message.mode === 'delay' ? 'delay' : 'manual';
        approvalQueue.setMode(queueMode, message.delaySeconds);

        // Broadcast updated mode to all clients
        broadcast({
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

      // Device list/revoke removed — replaced by Google OAuth single-user auth
    }
  }

  // ── Adapter → Broadcast Event Wiring ─────────────────────

  const serverMessageHandler = (message: ServerMessage) => {
    broadcast(message);
  };

  function wireAdapterEvents(): void {
    cliAdapter.on('output', (sessionId: string, chunk: string) => {
      const session = sessionManager.tryGet(sessionId);
      if (session) {
        session.transcript.append({
          type: 'assistant',
          content: chunk,
          timestamp: new Date().toISOString(),
        });
        triggerPersistence(sessionId);
      }
      broadcast({ type: 'output', sessionId, chunk, format: 'plain' });
    });

    cliAdapter.on('approval-request', (request) => {
      broadcast({
        type: 'approval.request',
        requestId: request.requestId,
        tool: request.tool,
        description: request.description,
        details: request.details,
      });
      notificationBatcher.addApprovalRequest(request.tool, request.requestId);
    });

    cliAdapter.on('auto-allow', (event) => {
      broadcast({
        type: 'approval.auto',
        tool: event.tool,
        description: event.description,
        reason: event.reason,
        toolUseId: event.toolUseId,
      });
    });

    cliAdapter.on('tool-start', (info) => {
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
      broadcast({
        type: 'tool.start',
        sessionId: info.sessionId,
        tool: info.tool,
        input: info.input,
      });
    });

    cliAdapter.on('tool-complete', (result) => {
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
      broadcast({
        type: 'tool.complete',
        sessionId: result.sessionId,
        tool: result.tool,
        output: result.output,
        success: result.success,
      });
    });

    cliAdapter.on('session-result', (result) => {
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
      broadcast({
        type: 'session.result',
        sessionId: result.sessionId,
        costUsd: result.costUsd,
        numTurns: result.numTurns,
        durationMs: result.durationMs,
        inputTokens: result.inputTokens,
        outputTokens: result.outputTokens,
      });
    });

    cliAdapter.on('agent-lifecycle', (event) => {
      switch (event.event) {
        case 'spawn':
          agentTracker.spawn(event.agentId, event.role ?? 'subagent', event.task ?? '', event.parentId);
          broadcast({
            type: 'agent.spawn',
            agentId: event.agentId,
            parentId: event.parentId,
            task: event.task ?? '',
            role: event.role ?? 'subagent',
          });
          break;
        case 'working':
          agentTracker.working(event.agentId, event.task ?? '');
          broadcast({ type: 'agent.working', agentId: event.agentId, task: event.task ?? '' });
          break;
        case 'idle':
          agentTracker.idle(event.agentId);
          broadcast({ type: 'agent.idle', agentId: event.agentId });
          break;
        case 'complete':
          agentTracker.complete(event.agentId, event.result ?? '');
          broadcast({ type: 'agent.complete', agentId: event.agentId, result: event.result ?? '' });
          break;
        case 'dismissed':
          agentTracker.dismiss(event.agentId);
          broadcast({ type: 'agent.dismissed', agentId: event.agentId });
          break;
      }
    });

    eventBus.on('server.message', serverMessageHandler);
  }

  // ── Plugin Registration ──────────────────────────────────

  return async (fastify) => {
    // Wire adapter events once
    wireAdapterEvents();

    // Shared socket setup — wires up event handlers after auth succeeds
    function setupSocket(socket: WebSocket, ip: string): void {
      (socket as WebSocket & { isAlive: boolean }).isAlive = true;
      socket.on('pong', () => {
        (socket as WebSocket & { isAlive: boolean }).isAlive = true;
      });
      clients.add(socket);

      socket.on('error', (err) => {
        logger.error({ err }, 'WebSocket error');
      });

      socket.on('close', () => {
        clients.delete(socket);
        untrackClientSession(socket);
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
      const modeState = cliAdapter.permissionFilter.getMode();
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
        .then((payload) => {
          // PIN-authed sessions (sub === 'pin-user') bypass email check
          const allowedEmail = process.env['ALLOWED_EMAIL'];
          if (allowedEmail && payload.sub !== 'pin-user' && payload.email.toLowerCase() !== allowedEmail.toLowerCase()) {
            logger.warn({ email: payload.email }, 'WS connection from non-allowed email');
            socket.close(1008, 'Access denied');
            return;
          }

          // Authenticated — set up connection
          const ip = request.ip;
          logger.info({ ip, email: payload.email }, 'Client connected via WebSocket');
          setupSocket(socket, ip);
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
      notificationBatcher.dispose();
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
