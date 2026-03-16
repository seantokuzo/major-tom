import { createServer, type IncomingMessage, type ServerResponse } from 'node:http';
import { randomUUID } from 'node:crypto';
import { logger } from '../utils/logger.js';
import { ApprovalQueue } from './approval-queue.js';
import { eventBus } from '../events/event-bus.js';

// ── Hook HTTP Server ────────────────────────────────────────
// Claude Code hook scripts POST to these endpoints.
// pre-tool-use blocks until the iOS app sends an approval decision.

function readBody(req: IncomingMessage): Promise<string> {
  return new Promise((resolve, reject) => {
    const chunks: Buffer[] = [];
    req.on('data', (chunk: Buffer) => chunks.push(chunk));
    req.on('end', () => resolve(Buffer.concat(chunks).toString('utf-8')));
    req.on('error', reject);
  });
}

function sendJson(res: ServerResponse, status: number, body: unknown): void {
  res.writeHead(status, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify(body));
}

export function createHookServer(approvalQueue: ApprovalQueue, port: number) {
  const server = createServer(async (req, res) => {
    const url = req.url ?? '';
    const method = req.method ?? '';

    try {
      // Health check
      if (method === 'GET' && url === '/health') {
        sendJson(res, 200, { status: 'ok', pendingApprovals: approvalQueue.size });
        return;
      }

      // Pre-tool-use: blocks until iOS app sends decision
      if (method === 'POST' && url === '/hooks/pre-tool-use') {
        const body = await readBody(req);
        let hookData: Record<string, unknown>;
        try {
          hookData = JSON.parse(body) as Record<string, unknown>;
        } catch {
          sendJson(res, 400, { error: 'Invalid JSON in hook payload' });
          return;
        }
        const requestId = randomUUID();
        // Claude Code hook payload fields — will verify against actual schema
        const tool = (hookData['tool_name'] as string) ?? 'unknown';
        const description = (hookData['tool_input'] as string) ?? '';

        // Forward approval request to iOS via event bus
        eventBus.emit('approval.request', {
          type: 'approval.request',
          requestId,
          tool,
          description: typeof description === 'string' ? description : JSON.stringify(description),
          details: hookData,
        });

        // Block until iOS responds
        const decision = await approvalQueue.waitForDecision(requestId, tool);

        sendJson(res, 200, { decision });
        return;
      }

      // Post-tool-use: fire and forget
      if (method === 'POST' && url === '/hooks/post-tool-use') {
        const body = await readBody(req);
        let hookData: Record<string, unknown>;
        try {
          hookData = JSON.parse(body) as Record<string, unknown>;
        } catch {
          sendJson(res, 400, { error: 'Invalid JSON in hook payload' });
          return;
        }
        const sessionId = (hookData['session_id'] as string) ?? '';
        const tool = (hookData['tool_name'] as string) ?? 'unknown';
        const output = (hookData['tool_output'] as string) ?? '';

        eventBus.emit('tool.complete', {
          type: 'tool.complete',
          sessionId,
          tool,
          output: typeof output === 'string' ? output : JSON.stringify(output),
          success: true,
        });

        sendJson(res, 200, { status: 'ok' });
        return;
      }

      // Notification: fire and forget
      if (method === 'POST' && url === '/hooks/notification') {
        const body = await readBody(req);
        let hookData: Record<string, unknown>;
        try {
          hookData = JSON.parse(body) as Record<string, unknown>;
        } catch {
          sendJson(res, 400, { error: 'Invalid JSON in hook payload' });
          return;
        }

        logger.info({ hookData }, 'Notification hook received');
        // TODO: Parse agent lifecycle events from notification data
        // and forward to agentTracker

        sendJson(res, 200, { status: 'ok' });
        return;
      }

      // 404
      sendJson(res, 404, { error: 'Not found' });
    } catch (err) {
      logger.error({ err, url, method }, 'Hook server error');
      sendJson(res, 500, { error: 'Internal server error' });
    }
  });

  server.listen(port, () => {
    logger.info({ port }, 'Hook HTTP server listening');
  });

  return server;
}
