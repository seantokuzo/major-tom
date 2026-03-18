import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { join, extname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { WebSocketServer, WebSocket } from 'ws';
import { logger } from './utils/logger.js';
import { SessionManager } from './sessions/session-manager.js';
import { ClaudeCliAdapter } from './adapters/claude-cli.adapter.js';
import { ApprovalQueue } from './hooks/approval-queue.js';
import { createHookServer } from './hooks/hook-server.js';
import { eventBus } from './events/event-bus.js';
import { encodeServerMessage, safeDecode } from './protocol/codec.js';
import type { ClientMessage, ServerMessage } from './protocol/messages.js';

// ── Static file serving ─────────────────────────────────────

const __dirname = fileURLToPath(new URL('.', import.meta.url));
const WEB_DIST = join(__dirname, '..', '..', 'web', 'dist');

const MIME_TYPES: Record<string, string> = {
  '.html': 'text/html',
  '.js': 'application/javascript',
  '.css': 'text/css',
  '.json': 'application/json',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.ico': 'image/x-icon',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
};

// ── Configuration ───────────────────────────────────────────

const WS_PORT = parseInt(process.env['WS_PORT'] ?? '9090', 10);
const HOOK_PORT = parseInt(process.env['HOOK_PORT'] ?? '9091', 10);
const CLAUDE_WORK_DIR = process.env['CLAUDE_WORK_DIR'] ?? process.cwd();

// ── Core services ───────────────────────────────────────────

const sessionManager = new SessionManager();
const cliAdapter = new ClaudeCliAdapter(sessionManager);
const approvalQueue = new ApprovalQueue();

// ── HTTP server (for health check + future REST endpoints) ──

const httpServer = createServer(async (req, res) => {
  const url = req.url ?? '/';

  // Health check endpoint
  if (req.method === 'GET' && url === '/health') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({
      status: 'ok',
      sessions: sessionManager.list(),
      pendingApprovals: approvalQueue.size,
    }));
    return;
  }

  // Serve PWA static files from web/dist/
  if (req.method === 'GET') {
    const filePath = url === '/' ? '/index.html' : url;
    const fullPath = join(WEB_DIST, filePath);

    // Security: prevent path traversal
    if (!fullPath.startsWith(WEB_DIST)) {
      res.writeHead(403);
      res.end('Forbidden');
      return;
    }

    try {
      const data = await readFile(fullPath);
      const ext = extname(fullPath);
      const contentType = MIME_TYPES[ext] ?? 'application/octet-stream';
      res.writeHead(200, { 'Content-Type': contentType });
      res.end(data);
      return;
    } catch {
      // SPA fallback: serve index.html for non-file routes
      if (!extname(filePath)) {
        try {
          const data = await readFile(join(WEB_DIST, 'index.html'));
          res.writeHead(200, { 'Content-Type': 'text/html' });
          res.end(data);
          return;
        } catch {
          // fall through to 404
        }
      }
    }
  }

  res.writeHead(404);
  res.end('Not found');
});

// ── WebSocket server (iOS app connects here) ────────────────

const wss = new WebSocketServer({ server: httpServer });

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
      // Route approval through the adapter's stdin (permission-prompt-tool stdio)
      // The requestId is the tool_use_id from the permission prompt
      // Map our decision vocabulary to Claude Code's expected format
      const ccDecision =
        message.decision === 'allow' || message.decision === 'allow_always' ? 'allow' :
        message.decision === 'deny' ? 'deny' : 'deny';

      // Find which session this approval belongs to
      // For now, send to all sessions (we'll refine with session tracking later)
      for (const sessionInfo of sessionManager.list()) {
        cliAdapter.sendPermissionResponse(sessionInfo.id, message.requestId, ccDecision);
      }

      // Also resolve in approval queue for hook-server compatibility
      approvalQueue.resolve(message.requestId, message.decision);
      break;
    }

    case 'cancel': {
      await cliAdapter.cancelOperation(message.sessionId);
      break;
    }

    case 'agent.message': {
      logger.info({ agentId: message.agentId }, 'Agent message forwarding not yet implemented');
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

cliAdapter.on('agent-lifecycle', (event) => {
  switch (event.event) {
    case 'spawn':
      broadcast({
        type: 'agent.spawn',
        agentId: event.agentId,
        parentId: event.parentId,
        task: event.task ?? '',
        role: event.role ?? 'subagent',
      });
      break;
    case 'working':
      broadcast({
        type: 'agent.working',
        agentId: event.agentId,
        task: event.task ?? '',
      });
      break;
    case 'idle':
      broadcast({ type: 'agent.idle', agentId: event.agentId });
      break;
    case 'complete':
      broadcast({
        type: 'agent.complete',
        agentId: event.agentId,
        result: event.result ?? '',
      });
      break;
    case 'dismissed':
      broadcast({ type: 'agent.dismissed', agentId: event.agentId });
      break;
  }
});

// Forward event bus messages to all clients
eventBus.on('server.message', (message: ServerMessage) => {
  broadcast(message);
});

// ── Hook HTTP server (Claude Code hooks POST here) ──────────

const hookServer = createHookServer(approvalQueue, HOOK_PORT);

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
    new Promise<void>((resolve) => hookServer.close(() => resolve())),
  ]);

  clearInterval(heartbeatInterval);
  eventBus.removeAllListeners();

  logger.info('Shutdown complete');
  process.exit(0);
}

process.on('SIGINT', () => { void shutdown('SIGINT'); });
process.on('SIGTERM', () => { void shutdown('SIGTERM'); });

// ── Start ───────────────────────────────────────────────────

httpServer.listen(WS_PORT, () => {
  logger.info({ wsPort: WS_PORT, hookPort: HOOK_PORT }, 'Major Tom relay server started');
});
