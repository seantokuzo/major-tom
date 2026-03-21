import { createServer } from 'node:http';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { WebSocketServer, WebSocket } from 'ws';
import { logger } from './utils/logger.js';
import { readBody, sendJson, getCorsOrigin, requireAuth } from './utils/http-helpers.js';
import { getAuthToken, getAllowedOrigins } from './utils/auth.js';
import { SessionManager } from './sessions/session-manager.js';
import { ClaudeCliAdapter } from './adapters/claude-cli.adapter.js';
import { ApprovalQueue } from './hooks/approval-queue.js';
import { eventBus } from './events/event-bus.js';
import { agentTracker } from './events/agent-tracker.js';
import { encodeServerMessage, safeDecode } from './protocol/codec.js';
import { createStaticHandler } from './static.js';
import { PushManager } from './push/push-manager.js';
import { NotificationBatcher } from './push/notification-batcher.js';
import type { ClientMessage, ServerMessage } from './protocol/messages.js';
import type { PushSubscriptionData } from './push/push-manager.js';

// ── Configuration ───────────────────────────────────────────

const WS_PORT = parseInt(process.env['WS_PORT'] ?? '9090', 10);
const CLAUDE_WORK_DIR = process.env['CLAUDE_WORK_DIR'] ?? process.cwd();
const DISABLE_STATIC = process.env['NO_STATIC'] === '1' || process.argv.includes('--no-static');
const AUTH_TOKEN = getAuthToken();
const ALLOWED_ORIGINS = getAllowedOrigins();

// ── Core services ───────────────────────────────────────────

const sessionManager = new SessionManager();
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

  // CORS preflight for push endpoints
  if (req.method === 'OPTIONS' && url.startsWith('/push/')) {
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
  if (token !== AUTH_TOKEN) {
    socket.write('HTTP/1.1 401 Unauthorized\r\n\r\n');
    socket.destroy();
    return;
  }
  wss.handleUpgrade(req, socket, head, (ws) => wss.emit('connection', ws, req));
});

// Track connected clients
const clients = new Set<WebSocket>();

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

wss.on('connection', (ws, req) => {
  const ip = req.socket.remoteAddress;
  logger.info({ ip }, 'iOS client connected');

  (ws as WebSocket & { isAlive: boolean }).isAlive = true;
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

// ── Message routing ─────────────────────────────────────────

async function handleClientMessage(message: ClientMessage, ws: WebSocket): Promise<void> {
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
      logger.info('Workspace tree not yet implemented');
      sendToClient(ws, { type: 'workspace.tree.response', files: [] });
      break;
    }

    case 'context.add': {
      logger.info({ path: message.path }, 'Context add not yet implemented');
      break;
    }

    case 'settings.approval': {
      // TODO: Add authentication — currently any connected client can change approval mode.
      // Auth will be addressed in a dedicated security phase (token-based or session-scoped).
      approvalQueue.setMode(message.mode, message.delaySeconds);
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
  broadcast({
    type: 'tool.start',
    sessionId: info.sessionId,
    tool: info.tool,
    input: info.input,
  });
});

cliAdapter.on('tool-complete', (result) => {
  broadcast({
    type: 'tool.complete',
    sessionId: result.sessionId,
    tool: result.tool,
    output: result.output,
    success: result.success,
  });
});

cliAdapter.on('session-result', (result) => {
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

  // Dispose adapters
  await cliAdapter.dispose();

  // Close servers and wait for them to finish
  await Promise.all([
    new Promise<void>((resolve) => wss.close(() => resolve())),
    new Promise<void>((resolve) => httpServer.close(() => resolve())),
  ]);

  clearInterval(heartbeatInterval);
  notificationBatcher.dispose();
  eventBus.removeAllListeners();

  logger.info('Shutdown complete');
  process.exit(0);
}

process.on('SIGINT', () => { void shutdown('SIGINT'); });
process.on('SIGTERM', () => { void shutdown('SIGTERM'); });

// ── Start ───────────────────────────────────────────────────

httpServer.listen(WS_PORT, () => {
  logger.info(
    { wsPort: WS_PORT, staticServing: serveStatic !== null },
    'Major Tom relay server started',
  );
});
