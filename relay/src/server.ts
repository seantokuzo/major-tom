import { createServer } from 'node:http';
import { join, dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { WebSocketServer, WebSocket } from 'ws';
import { logger } from './utils/logger.js';
import { readBody, sendJson, getCorsOrigin, requireAuth } from './utils/http-helpers.js';
import { getAuthToken, getAllowedOrigins, validateAuthToken, deviceManager } from './utils/auth.js';
import { pinManager } from './auth/pin-manager.js';
import { runPairMode } from './cli/pair.js';
import { SessionManager } from './sessions/session-manager.js';
import { SessionPersistence } from './sessions/session-persistence.js';
import type { PersistedSession } from './sessions/session-persistence.js';
import { ClaudeCliAdapter } from './adapters/claude-cli.adapter.js';
import { ApprovalQueue } from './hooks/approval-queue.js';
import { eventBus } from './events/event-bus.js';
import { agentTracker } from './events/agent-tracker.js';
import { encodeServerMessage, safeDecode } from './protocol/codec.js';
import { truncateMetaField } from './sessions/session-transcript.js';
import { createStaticHandler } from './static.js';
import { PushManager } from './push/push-manager.js';
import { NotificationBatcher } from './push/notification-batcher.js';
import { scanWorkspaceTree } from './workspace/tree-scanner.js';
import { readFileSync } from 'node:fs';
import type { ClientMessage, ServerMessage } from './protocol/messages.js';
import type { PushSubscriptionData } from './push/push-manager.js';

// ── Configuration ───────────────────────────────────────────

const WS_PORT = parseInt(process.env['WS_PORT'] ?? '9090', 10);
const CLAUDE_WORK_DIR = process.env['CLAUDE_WORK_DIR'] ?? process.cwd();
const DISABLE_STATIC = process.env['NO_STATIC'] === '1' || process.argv.includes('--no-static');
const AUTH_TOKEN = getAuthToken();
const ALLOWED_ORIGINS = getAllowedOrigins();

// ── Core services ───────────────────────────────────────────

const sessionPersistence = new SessionPersistence();
const sessionManager = new SessionManager(sessionPersistence);
const approvalQueue = new ApprovalQueue();
const cliAdapter = new ClaudeCliAdapter(sessionManager, approvalQueue);
const pushManager = new PushManager();
const notificationBatcher = new NotificationBatcher(pushManager);

// ── Static file handler (serves PWA from web/dist/) ─────────

const __dirname = dirname(fileURLToPath(import.meta.url));
const WEB_DIST_DIR = join(__dirname, '..', '..', 'web', 'dist');

const serveStatic = DISABLE_STATIC ? null : createStaticHandler(WEB_DIST_DIR);

// ── HTTP server (health check + push endpoints + static PWA files) ───

const httpServer = createServer(async (req, res) => {
  const url = req.url ?? '/';

  const corsOrigin = getCorsOrigin(req, ALLOWED_ORIGINS);

  // CORS preflight for push and pair endpoints
  if (req.method === 'OPTIONS' && (url.startsWith('/push/') || url === '/pair')) {
    const headers: Record<string, string> = {
      'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, Authorization',
    };
    if (corsOrigin) {
      headers['Access-Control-Allow-Origin'] = corsOrigin;
      if (corsOrigin !== '*') {
        headers['Vary'] = 'Origin';
      }
    }
    res.writeHead(204, headers);
    res.end();
    return;
  }

  // Health check endpoint (public — no auth required)
  if (req.method === 'GET' && url === '/health') {
    sendJson(res, 200, {
      status: 'ok',
      sessions: sessionManager.list(),
      pendingApprovals: approvalQueue.size,
    }, corsOrigin ?? undefined);
    return;
  }

  // ── PIN pairing endpoint ─────────────────────────────────

  if (req.method === 'POST' && url === '/pair') {
    const clientIp = req.socket.remoteAddress ?? 'unknown';

    // Check rate limit
    const rateCheck = pinManager.checkRateLimit(clientIp);
    if (!rateCheck.allowed) {
      sendJson(res, 429, {
        error: 'Too many attempts',
        retryAfter: rateCheck.retryAfter,
      }, corsOrigin ?? undefined);
      return;
    }

    try {
      let body: string;
      try {
        body = await readBody(req);
      } catch (err) {
        if ((err as { code?: string }).code === 'BODY_TOO_LARGE') {
          sendJson(res, 413, { error: 'Request body too large' }, corsOrigin ?? undefined);
        } else {
          sendJson(res, 400, { error: 'Bad request' }, corsOrigin ?? undefined);
        }
        return;
      }

      const parsed = JSON.parse(body) as { pin?: unknown; deviceName?: unknown };
      if (!parsed.pin || !parsed.deviceName) {
        sendJson(res, 400, { error: 'Missing pin or deviceName' }, corsOrigin ?? undefined);
        return;
      }
      if (typeof parsed.pin !== 'string' || typeof parsed.deviceName !== 'string') {
        sendJson(res, 400, { error: 'pin and deviceName must be strings' }, corsOrigin ?? undefined);
        return;
      }

      // Sanitize device name: trim, strip control chars, enforce max length
      let deviceName = parsed.deviceName
        .trim()
        .replace(/[\x00-\x1f\x7f]/g, '')
        .slice(0, 100);
      if (!deviceName) {
        deviceName = 'Unknown Device';
      }

      // Record attempt for rate limiting (counts ALL attempts, not just failures)
      pinManager.recordFailedAttempt(clientIp);

      // Validate PIN first (don't consume yet)
      if (!pinManager.validatePin(parsed.pin)) {
        sendJson(res, 401, { error: 'Invalid or expired PIN' }, corsOrigin ?? undefined);
        return;
      }

      // Register device (might fail on persistence)
      let device;
      try {
        device = deviceManager.register(deviceName);
      } catch (err) {
        logger.error({ err }, 'Failed to register device');
        sendJson(res, 500, { error: 'Device registration failed' }, corsOrigin ?? undefined);
        return;
      }

      // Consume PIN after successful registration (TOCTOU guard)
      if (!pinManager.consumePin(parsed.pin, deviceName)) {
        // PIN was expired or claimed between validate and consume — rollback device
        deviceManager.revoke(device.id);
        sendJson(res, 409, { error: 'PIN expired or already claimed' }, corsOrigin ?? undefined);
        return;
      }

      logger.info({ deviceId: device.id, name: deviceName }, 'Device paired via PIN');

      sendJson(res, 200, {
        token: device.token,
        deviceId: device.id,
      }, corsOrigin ?? undefined);
    } catch (err: unknown) {
      logger.error({ err }, 'Failed to process pair request');
      sendJson(res, 400, { error: 'Invalid JSON body' }, corsOrigin ?? undefined);
    }
    return;
  }


  // ── Push notification endpoints ──────────────────────────

  // GET /push/vapid-key — returns the VAPID public key for client subscription (public)
  if (req.method === 'GET' && url === '/push/vapid-key') {
    sendJson(res, 200, { publicKey: pushManager.getVapidPublicKey() }, corsOrigin ?? undefined);
    return;
  }

  // POST /push/subscribe — stores a push subscription (auth required)
  if (req.method === 'POST' && url === '/push/subscribe') {
    if (!requireAuth(req, AUTH_TOKEN)) {
      sendJson(res, 401, { error: 'Unauthorized' }, corsOrigin ?? undefined);
      return;
    }
    try {
      let body: string;
      try {
        body = await readBody(req);
      } catch (err) {
        if ((err as { code?: string }).code === 'BODY_TOO_LARGE') {
          sendJson(res, 413, { error: 'Request body too large' }, corsOrigin ?? undefined);
        } else {
          sendJson(res, 400, { error: 'Bad request' }, corsOrigin ?? undefined);
        }
        return;
      }
      const sub = JSON.parse(body) as PushSubscriptionData;
      if (!sub?.endpoint || !sub.keys?.p256dh || !sub.keys?.auth) {
        sendJson(res, 400, { error: 'Invalid subscription: requires endpoint, keys.p256dh, keys.auth' }, corsOrigin ?? undefined);
        return;
      }
      pushManager.subscribe(sub);
      sendJson(res, 200, { status: 'ok' }, corsOrigin ?? undefined);
    } catch (err: unknown) {
      logger.error({ err }, 'Failed to process push subscribe');
      sendJson(res, 400, { error: 'Invalid JSON body' }, corsOrigin ?? undefined);
    }
    return;
  }

  // POST /push/unsubscribe — removes a push subscription (auth required)
  if (req.method === 'POST' && url === '/push/unsubscribe') {
    if (!requireAuth(req, AUTH_TOKEN)) {
      sendJson(res, 401, { error: 'Unauthorized' }, corsOrigin ?? undefined);
      return;
    }
    try {
      let body: string;
      try {
        body = await readBody(req);
      } catch (err) {
        if ((err as { code?: string }).code === 'BODY_TOO_LARGE') {
          sendJson(res, 413, { error: 'Request body too large' }, corsOrigin ?? undefined);
        } else {
          sendJson(res, 400, { error: 'Bad request' }, corsOrigin ?? undefined);
        }
        return;
      }
      const parsed = JSON.parse(body) as { endpoint?: string };
      if (!parsed.endpoint) {
        sendJson(res, 400, { error: 'Missing endpoint field' }, corsOrigin ?? undefined);
        return;
      }
      pushManager.unsubscribe(parsed.endpoint);
      sendJson(res, 200, { status: 'ok' }, corsOrigin ?? undefined);
    } catch (err: unknown) {
      logger.error({ err }, 'Failed to process push unsubscribe');
      sendJson(res, 400, { error: 'Invalid JSON body' }, corsOrigin ?? undefined);
    }
    return;
  }

  // Serve static PWA files if available
  if (serveStatic) {
    serveStatic(req, res)
      .then((handled) => {
        if (!handled) {
          res.writeHead(404);
          res.end('Not found');
        }
      })
      .catch((_err: unknown) => {
        res.writeHead(500);
        res.end('Internal server error');
      });
    return;
  }

  res.writeHead(404);
  res.end('Not found');
});

// ── WebSocket server (iOS app connects here) ────────────────

const wss = new WebSocketServer({ noServer: true });

httpServer.on('upgrade', (req, socket, head) => {
  let token: string | null = null;
  try {
    const url = new URL(req.url ?? '/', 'http://localhost');
    token = url.searchParams.get('token');
  } catch {
    socket.write('HTTP/1.1 400 Bad Request\r\n\r\n');
    socket.destroy();
    return;
  }
  if (!token || !validateAuthToken(token, AUTH_TOKEN)) {
    socket.write('HTTP/1.1 401 Unauthorized\r\n\r\n');
    socket.destroy();
    return;
  }
  wss.handleUpgrade(req, socket, head, (ws) => {
    (ws as AuthenticatedWebSocket).authToken = token;
    wss.emit('connection', ws, req);
  });
});

// Track connected clients with the token that authenticated them
interface AuthenticatedWebSocket extends WebSocket {
  authToken?: string;
}
const clients = new Set<AuthenticatedWebSocket>();

// Heartbeat: detect dead connections
function heartbeat(this: WebSocket) {
  (this as WebSocket & { isAlive: boolean }).isAlive = true;
}

const heartbeatInterval = setInterval(() => {
  wss.clients.forEach((ws) => {
    const conn = ws as WebSocket & { isAlive: boolean };
    if (conn.isAlive === false) {
      logger.info('Terminating dead WebSocket connection');
      return conn.terminate();
    }
    conn.isAlive = false;
    conn.ping();
  });
}, 30_000);

wss.on('close', () => {
  clearInterval(heartbeatInterval);
});

wss.on('connection', (ws: AuthenticatedWebSocket, req) => {
  const ip = req.socket.remoteAddress;
  logger.info({ ip }, 'iOS client connected');

  (ws as AuthenticatedWebSocket & { isAlive: boolean }).isAlive = true;
  ws.on('pong', heartbeat);
  clients.add(ws);

  ws.on('error', (err) => {
    logger.error({ err }, 'WebSocket error');
  });

  ws.on('close', () => {
    clients.delete(ws);
    logger.info({ ip }, 'iOS client disconnected');
  });

  ws.on('message', (data) => {
    const raw = data.toString();
    const message = safeDecode(raw);
    if (!message) return;

    handleClientMessage(message, ws).catch((err: unknown) => {
      logger.error({ err, type: message.type }, 'Error handling client message');
      sendToClient(ws, {
        type: 'error',
        code: 'HANDLER_ERROR',
        message: err instanceof Error ? err.message : 'Unknown error',
      });
    });
  });

  // Send connection status
  sendToClient(ws, {
    type: 'connection.status',
    status: 'connected',
    adapter: 'cli',
  });
});

// ── Persistence helpers ──────────────────────────────────────

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
  if (data) {
    sessionPersistence.save(data);
  }
}

// ── Message routing ─────────────────────────────────────────

async function handleClientMessage(message: ClientMessage, ws: AuthenticatedWebSocket): Promise<void> {
  switch (message.type) {
    case 'session.start': {
      const workDir = message.workingDir ?? CLAUDE_WORK_DIR;
      const session = await cliAdapter.start(workDir);
      sendToClient(ws, {
        type: 'session.info',
        sessionId: session.id,
        adapter: session.adapter,
        startedAt: session.startedAt,
      });
      break;
    }

    case 'session.attach': {
      // Check if this is a persisted-only session (closed, transcript replay only)
      if (sessionManager.isPersistedOnly(message.sessionId)) {
        // Send session.info so the client can update its sessionId
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
      const session = await cliAdapter.attach(message.sessionId);
      sendToClient(ws, {
        type: 'session.info',
        sessionId: session.id,
        adapter: session.adapter,
        startedAt: session.startedAt,
      });
      break;
    }

    case 'prompt': {
      // Append user message to transcript
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
      // Resolve the approval in the queue — the SDK's canUseTool callback
      // is blocking until this resolves
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
      // Look up specific session if provided, otherwise fall back to first active session
      const session = message.sessionId
        ? sessionManager.tryGet(message.sessionId)
        : (() => {
            const sessions = sessionManager.list();
            return sessions.length > 0 ? sessionManager.tryGet(sessions[0]!.id) : undefined;
          })();
      const workDir = session?.workingDir ?? CLAUDE_WORK_DIR;
      const tree = await scanWorkspaceTree(workDir, message.path);
      sendToClient(ws, {
        type: 'workspace.tree.response',
        files: tree.map(function mapNode(n): import('./protocol/messages.js').FileNode {
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

      // Guard against path traversal
      const resolved = resolve(session.workingDir, message.path);
      if (!resolved.startsWith(session.workingDir + '/') && resolved !== session.workingDir) {
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
      // TODO: Add authentication — currently any connected client can change approval mode.
      // Auth will be addressed in a dedicated security phase (token-based or session-scoped).
      approvalQueue.setMode(message.mode, message.delaySeconds);
      break;
    }

    case 'session.list': {
      const sessions = sessionManager.listMeta();
      sendToClient(ws, { type: 'session.list.response', sessions });
      break;
    }

    case 'device.list': {
      // Intentionally available to all authenticated tokens — single-user app,
      // all tokens are admin-equivalent by design. Revisit if multi-user is added.
      const devices = deviceManager.list().map((d) => ({
        id: d.id,
        name: d.name,
        createdAt: d.createdAt,
        lastSeenAt: d.lastSeenAt,
      }));
      sendToClient(ws, { type: 'device.list.response', devices });
      break;
    }

    case 'device.revoke': {
      // Look up the device's token before revoking so we can disconnect active sessions
      const deviceToRevoke = deviceManager.getById(message.deviceId);
      const revokedToken = deviceToRevoke?.token;
      const success = deviceManager.revoke(message.deviceId);
      sendToClient(ws, { type: 'device.revoke.response', deviceId: message.deviceId, success });

      // Close any active WebSocket connections authenticated with the revoked device's token
      if (success && revokedToken) {
        for (const client of clients) {
          if (client !== ws && client.authToken === revokedToken) {
            logger.info({ deviceId: message.deviceId }, 'Closing connection for revoked device');
            client.close(1008, 'Device revoked');
          }
        }
        // If the requester revoked its own token, close it too after the response was sent
        if (ws.authToken === revokedToken) {
          logger.info({ deviceId: message.deviceId }, 'Requester revoked own device — closing');
          ws.close(1008, 'Device revoked');
        }
      }
      break;
    }
  }
}

// ── Broadcasting ────────────────────────────────────────────

function sendToClient(ws: WebSocket, message: ServerMessage): void {
  if (ws.readyState === WebSocket.OPEN) {
    ws.send(encodeServerMessage(message));
  }
}

function broadcast(message: ServerMessage): void {
  const encoded = encodeServerMessage(message);
  for (const client of clients) {
    if (client.readyState === WebSocket.OPEN) {
      client.send(encoded);
    }
  }
}

// Forward adapter events to connected clients
cliAdapter.on('output', (sessionId: string, chunk: string) => {
  // Append to transcript
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
  // Accumulate stats on the session object
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
      broadcast({
        type: 'agent.working',
        agentId: event.agentId,
        task: event.task ?? '',
      });
      break;
    case 'idle':
      agentTracker.idle(event.agentId);
      broadcast({ type: 'agent.idle', agentId: event.agentId });
      break;
    case 'complete':
      agentTracker.complete(event.agentId, event.result ?? '');
      broadcast({
        type: 'agent.complete',
        agentId: event.agentId,
        result: event.result ?? '',
      });
      break;
    case 'dismissed':
      agentTracker.dismiss(event.agentId);
      broadcast({ type: 'agent.dismissed', agentId: event.agentId });
      break;
  }
});

// Forward event bus messages to all clients
eventBus.on('server.message', (message: ServerMessage) => {
  broadcast(message);
});

// ── Push notifications for approval requests ─────────────────

eventBus.on('approval.request', (message) => {
  notificationBatcher.addApprovalRequest(message.tool, message.requestId);
});

// ── Graceful shutdown ───────────────────────────────────────

async function shutdown(signal: string): Promise<void> {
  logger.info({ signal }, 'Shutting down...');

  // Close WebSocket connections
  wss.clients.forEach((client) => {
    client.close(1001, 'Server shutting down');
  });

  // Flush pending device registry writes
  deviceManager.flush();

  // Dispose adapters
  await cliAdapter.dispose();

  // Close servers and wait for them to finish
  await Promise.all([
    new Promise<void>((resolve) => wss.close(() => resolve())),
    new Promise<void>((resolve) => httpServer.close(() => resolve())),
  ]);

  // Flush pending persistence writes before disposing
  await sessionPersistence.saveAllImmediate((id) => buildPersistedSession(id));
  sessionPersistence.dispose();

  clearInterval(heartbeatInterval);
  notificationBatcher.dispose();
  eventBus.removeAllListeners();

  logger.info('Shutdown complete');
  process.exit(0);
}

process.on('SIGINT', () => { void shutdown('SIGINT'); });
process.on('SIGTERM', () => { void shutdown('SIGTERM'); });

// ── Start ───────────────────────────────────────────────────

// CLI pair mode: `node dist/server.js pair`
// Start HTTP server first (needed for POST /pair endpoint), then run pair flow
if (process.argv.includes('pair')) {
  sessionManager.restoreFromDisk().then(() => {
    httpServer.listen(WS_PORT, () => {
      logger.info({ wsPort: WS_PORT }, 'Major Tom relay server started (pair mode)');
      runPairMode()
        .then(() => shutdown('pair-complete'))
        .catch((err: unknown) => {
          logger.error({ err }, 'Pair mode failed');
          void shutdown('pair-error');
        });
    });
  }).catch((err: unknown) => {
    logger.error({ err }, 'Failed to restore sessions from disk, starting anyway');
    httpServer.listen(WS_PORT, () => {
      logger.info({ wsPort: WS_PORT }, 'Major Tom relay server started (pair mode)');
      runPairMode()
        .then(() => shutdown('pair-complete'))
        .catch((err2: unknown) => {
          logger.error({ err: err2 }, 'Pair mode failed');
          void shutdown('pair-error');
        });
    });
  });
} else {
  // Restore persisted session metadata on startup, then listen
  sessionManager.restoreFromDisk().then(() => {
    httpServer.listen(WS_PORT, () => {
      logger.info(
        { wsPort: WS_PORT, staticServing: serveStatic !== null },
        'Major Tom relay server started',
      );
    });
  }).catch((err: unknown) => {
    logger.error({ err }, 'Failed to restore sessions from disk, starting anyway');
    httpServer.listen(WS_PORT, () => {
      logger.info(
        { wsPort: WS_PORT, staticServing: serveStatic !== null },
        'Major Tom relay server started',
      );
    });
  });
}
