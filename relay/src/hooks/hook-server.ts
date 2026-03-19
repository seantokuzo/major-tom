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
        const toolInput = hookData['tool_input'] as Record<string, unknown> | undefined;

        // Forward approval request to client via event bus
        eventBus.emit('approval.request', {
          type: 'approval.request',
          requestId,
          tool,
          description: toolInput ? JSON.stringify(toolInput) : '',
          details: hookData,
        });

        // Block until iOS responds
        const decision = await approvalQueue.waitForDecision(requestId, tool);

        // Map our decision to Claude Code's expected format
        // Claude Code expects: { hookSpecificOutput: { hookEventName, permissionDecision } }
        // permissionDecision must be: "allow" | "deny" | "ask"
        const permissionDecision =
          decision === 'allow' || decision === 'allow_always' ? 'allow' :
          decision === 'deny' ? 'deny' :
          'ask'; // 'skip' maps to 'ask' (let Claude Code decide)

        sendJson(res, 200, {
          hookSpecificOutput: {
            hookEventName: 'PreToolUse',
            permissionDecision,
          },
        });
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
        const toolResult = hookData['tool_result'] as Record<string, unknown> | undefined;
        const toolUseId = (hookData['tool_use_id'] as string) || undefined;

        eventBus.emit('tool.complete', {
          type: 'tool.complete',
          sessionId,
          tool,
          ...(toolUseId && { toolUseId }),
          output: toolResult ? JSON.stringify(toolResult) : '',
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

        // Notification hooks have: message, title, notification_type
        const message = (hookData['message'] as string) ?? '';
        const title = (hookData['title'] as string) ?? '';
        const notificationType = (hookData['notification_type'] as string) ?? '';

        logger.info({ title, notificationType, message }, 'Notification hook received');

        eventBus.emit('notification', {
          type: 'notification',
          title,
          message,
          notificationType,
        });

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
