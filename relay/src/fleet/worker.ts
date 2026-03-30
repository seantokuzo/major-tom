/**
 * Fleet Worker — Child process entry point for ClaudeCliAdapter sessions.
 *
 * Spawned by FleetManager via `child_process.fork()` with a specific `cwd`.
 * Manages one or more SDK sessions within this working directory.
 * Communicates with the parent relay process exclusively via IPC messages.
 *
 * Does NOT have its own HTTP server, WebSocket server, or Fastify instance.
 */

import { randomUUID } from 'node:crypto';
import {
  unstable_v2_createSession,
  type SDKSession,
  type SDKMessage,
  type PermissionResult,
} from '@anthropic-ai/claude-agent-sdk';
import { ApprovalQueue } from '../hooks/approval-queue.js';
import { PermissionFilter } from '../permissions/permission-filter.js';
import {
  isParentToChildMessage,
  type ParentToChildMessage,
  type ChildToParentMessage,
} from './ipc-messages.js';
import pino from 'pino';

// ── Worker-local logger ─────────────────────────────────────

const workerId = process.env['FLEET_WORKER_ID'] ?? randomUUID();
const workerLog = pino({
  name: `fleet-worker-${workerId.slice(0, 8)}`,
  level: process.env['LOG_LEVEL'] ?? 'info',
});

// ── Agent role classification (mirrors claude-cli.adapter.ts) ──

const ROLE_KEYWORDS: [RegExp, string][] = [
  [/\b(explore|search|find|grep|look|read|glob|discover)\b/i, 'researcher'],
  [/\b(plan|design|architect|strategy|blueprint)\b/i, 'architect'],
  [/\b(test|validate|verify|assert|spec)\b/i, 'qa'],
  [/\b(build|compile|deploy|docker|ci|infrastructure)\b/i, 'devops'],
  [/\b(style|css|ui|ux|layout|component|svelte|react|frontend)\b/i, 'frontend'],
  [/\b(api|server|database|backend|relay|endpoint|route)\b/i, 'backend'],
  [/\b(review|refactor|fix|lint|cleanup)\b/i, 'lead'],
  [/\b(write|implement|create|add|update|edit)\b/i, 'engineer'],
];

function classifyAgentRole(description: string): string {
  for (const [pattern, role] of ROLE_KEYWORDS) {
    if (pattern.test(description)) return role;
  }
  return 'engineer';
}

// ── Session tracking ────────────────────────────────────────

interface WorkerSession {
  sessionId: string;
  sdkSession: SDKSession;
  streamAbort: AbortController;
  hasStreamedText: boolean;
  streamAlive: boolean;
  /** Context files: path → content */
  contextFiles: Map<string, string>;
}

const sessions = new Map<string, WorkerSession>();
const approvalQueue = new ApprovalQueue();
const permissionFilter = new PermissionFilter();

// ── IPC send helper ─────────────────────────────────────────

function sendToParent(msg: ChildToParentMessage): void {
  if (process.send) {
    process.send(msg);
  } else {
    workerLog.error('process.send not available — not running as child process');
  }
}

// ── Session management ──────────────────────────────────────

async function startSession(sessionId: string, _workingDir: string): Promise<void> {
  try {
    const sdkSession = unstable_v2_createSession({
      model: 'claude-sonnet-4-20250514',
      permissionMode: 'default',
      canUseTool: (toolName, input, options) =>
        handlePermission(sessionId, toolName, input, options.toolUseID),
      env: {
        ...process.env,
        NO_COLOR: '1',
      },
    });

    const streamAbort = new AbortController();
    const entry: WorkerSession = {
      sessionId,
      sdkSession,
      streamAbort,
      hasStreamedText: false,
      streamAlive: false,
      contextFiles: new Map(),
    };
    sessions.set(sessionId, entry);

    // Start consuming the stream in the background
    consumeStream(sessionId, sdkSession, streamAbort.signal);

    sendToParent({
      type: 'ipc:session.started',
      sessionId,
      workingDir: process.cwd(),
    });

    workerLog.info({ sessionId, cwd: process.cwd() }, 'SDK session created in worker');
  } catch (err) {
    const errorMsg = err instanceof Error ? err.message : String(err);
    sendToParent({
      type: 'ipc:session.error',
      sessionId,
      error: errorMsg,
    });
    workerLog.error({ sessionId, err }, 'Failed to create SDK session');
  }
}

function destroySession(sessionId: string): void {
  const entry = sessions.get(sessionId);
  if (!entry) return;

  entry.streamAbort.abort();
  entry.sdkSession.close();
  sessions.delete(sessionId);
  workerLog.info({ sessionId }, 'Session destroyed in worker');
}

async function sendPrompt(sessionId: string, text: string): Promise<void> {
  const entry = sessions.get(sessionId);
  if (!entry) {
    workerLog.warn({ sessionId }, 'sendPrompt: session not found');
    return;
  }
  if (!entry.streamAlive) {
    workerLog.warn({ sessionId }, 'sendPrompt: stream is dead');
    sendToParent({
      type: 'ipc:session.error',
      sessionId,
      error: 'SDK session stream is dead — cannot send prompt',
    });
    return;
  }

  // Prepend context files if any
  const contextText = getContextText(entry);
  const finalText = contextText ? `${contextText}${text}` : text;

  await entry.sdkSession.send(finalText);
  workerLog.info({ sessionId, textLength: finalText.length, hasContext: !!contextText }, 'Prompt sent via SDK');
}

async function sendAgentMessage(sessionId: string, agentId: string, text: string): Promise<void> {
  const entry = sessions.get(sessionId);
  if (!entry) {
    workerLog.warn({ sessionId }, 'sendAgentMessage: session not found');
    return;
  }

  const wrappedText = `[Regarding agent ${agentId}]: ${text}`;
  await entry.sdkSession.send(wrappedText);
  workerLog.info({ sessionId, agentId, textLength: text.length }, 'Agent message sent via SDK');
}

async function cancelSession(sessionId: string): Promise<void> {
  const entry = sessions.get(sessionId);
  if (!entry) return;

  entry.streamAbort.abort();
  entry.sdkSession.close();
  sessions.delete(sessionId);
  workerLog.info({ sessionId }, 'Session cancelled in worker');
}

// ── Context file management ─────────────────────────────────

function addContextFile(sessionId: string, path: string, content: string): void {
  const entry = sessions.get(sessionId);
  if (!entry) return;
  entry.contextFiles.set(path, content);
}

function removeContextFile(sessionId: string, path: string): void {
  const entry = sessions.get(sessionId);
  if (!entry) return;
  entry.contextFiles.delete(path);
}

function getContextText(entry: WorkerSession): string {
  if (entry.contextFiles.size === 0) return '';

  const parts: string[] = ['<attached-files>'];
  for (const [filePath, content] of entry.contextFiles) {
    const escapedPath = filePath.replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
    parts.push(`<file path="${escapedPath}">`);
    parts.push(content);
    parts.push('</file>');
  }
  parts.push('</attached-files>\n\n');
  return parts.join('\n');
}

// ── Permission handling ─────────────────────────────────────

async function handlePermission(
  sessionId: string,
  toolName: string,
  input: Record<string, unknown>,
  toolUseId: string,
): Promise<PermissionResult> {
  // Check permission filter first (smart/god auto-allow)
  const filterResult = permissionFilter.check(toolName, input);
  if (filterResult.allowed) {
    workerLog.info(
      { sessionId, toolName, reason: filterResult.reason, toolUseId },
      'Auto-allowed by permission filter',
    );
    sendToParent({
      type: 'ipc:approval.auto',
      tool: toolName,
      description: JSON.stringify(input),
      reason: filterResult.reason,
      toolUseId,
    });
    return { behavior: 'allow', toolUseID: toolUseId };
  }

  // Not auto-allowed — queue for manual/delay approval
  const requestId = randomUUID();
  const description = JSON.stringify(input);
  const details: Record<string, unknown> = {
    tool_name: toolName,
    tool_input: input,
    tool_use_id: toolUseId,
  };

  // Send approval request to parent
  sendToParent({
    type: 'ipc:approval.request',
    sessionId,
    requestId,
    tool: toolName,
    description,
    details,
  });

  workerLog.info({ sessionId, requestId, toolName, toolUseId }, 'Permission requested');

  const decision = await approvalQueue.waitForDecision(requestId, toolName, description, details);

  workerLog.info({ sessionId, requestId, toolName, decision }, 'Permission decision received');

  if (decision === 'allow_always') {
    permissionFilter.addSessionAllow(toolName);
    return { behavior: 'allow', toolUseID: toolUseId };
  }

  if (decision === 'allow') {
    return { behavior: 'allow', toolUseID: toolUseId };
  }

  return {
    behavior: 'deny',
    message: `User denied ${toolName}`,
    toolUseID: toolUseId,
  };
}

// ── Stream consumption ──────────────────────────────────────

async function consumeStream(
  sessionId: string,
  sdkSession: SDKSession,
  signal: AbortSignal,
): Promise<void> {
  const entry = sessions.get(sessionId);
  if (entry) entry.streamAlive = true;

  try {
    while (!signal.aborted) {
      let messagesInTurn = 0;
      for await (const message of sdkSession.stream()) {
        if (signal.aborted) break;
        handleSdkMessage(sessionId, message);
        messagesInTurn++;
      }

      if (messagesInTurn === 0) {
        workerLog.warn({ sessionId }, 'Stream returned 0 messages — stopping consumer');
        break;
      }

      workerLog.debug({ sessionId, messagesInTurn }, 'Turn stream ended, waiting for next turn');
    }
  } catch (err) {
    if (!signal.aborted) {
      workerLog.error({ sessionId, err }, 'Stream error');
      sendToParent({
        type: 'ipc:output',
        sessionId,
        chunk: `\n[Stream error: ${err instanceof Error ? err.message : 'unknown'}]\n`,
      });
    }
  } finally {
    if (entry) entry.streamAlive = false;
    workerLog.info({ sessionId }, 'Stream consumer exited');
  }
}

function handleSdkMessage(sessionId: string, message: SDKMessage): void {
  const type = message.type;

  switch (type) {
    case 'system':
      handleSystemMessage(sessionId, message);
      break;
    case 'assistant':
      handleAssistantMessage(sessionId, message);
      break;
    case 'stream_event':
      handleStreamEvent(sessionId, message);
      break;
    case 'result':
      handleResultMessage(sessionId, message);
      break;
    default:
      workerLog.debug({ sessionId, type }, 'Unhandled SDK message type');
  }
}

// ── System messages ─────────────────────────────────────────

function handleSystemMessage(sessionId: string, message: SDKMessage): void {
  if (message.type !== 'system') return;
  const msg = message as Record<string, unknown>;
  const subtype = msg['subtype'] as string;

  switch (subtype) {
    case 'init':
      workerLog.info(
        { sessionId, model: msg['model'], version: msg['claude_code_version'] },
        'Claude session initialized',
      );
      break;

    case 'task_started': {
      const taskId = msg['task_id'] as string;
      const description = (msg['description'] as string) ?? '';
      const role = classifyAgentRole(description);
      sendToParent({
        type: 'ipc:agent.lifecycle',
        agentId: taskId,
        event: 'spawn',
        task: description,
        role,
      });
      break;
    }

    case 'task_progress': {
      const taskId = msg['task_id'] as string;
      sendToParent({
        type: 'ipc:agent.lifecycle',
        agentId: taskId,
        event: 'working',
        task: (msg['description'] as string) ?? (msg['summary'] as string) ?? '',
      });
      break;
    }

    case 'task_notification': {
      const taskId = msg['task_id'] as string;
      const status = msg['status'] as string;
      sendToParent({
        type: 'ipc:agent.lifecycle',
        agentId: taskId,
        event: status === 'completed' ? 'complete' : 'dismissed',
        result: (msg['summary'] as string) ?? status,
      });
      break;
    }

    case 'status': {
      const status = msg['status'] as string | null;
      if (status === 'compacting') {
        sendToParent({
          type: 'ipc:output',
          sessionId,
          chunk: '\n[Compacting context...]\n',
        });
      }
      break;
    }

    case 'api_retry':
      workerLog.warn({ sessionId, attempt: msg['attempt'], error: msg['error'] }, 'API retry');
      break;

    default:
      workerLog.debug({ sessionId, subtype }, 'Unhandled system event');
  }
}

// ── Assistant messages ──────────────────────────────────────

function handleAssistantMessage(sessionId: string, message: SDKMessage): void {
  if (message.type !== 'assistant') return;
  const msg = message as Record<string, unknown>;
  const betaMessage = msg['message'] as Record<string, unknown> | undefined;
  if (!betaMessage) return;

  const content = betaMessage['content'] as Array<Record<string, unknown>> | undefined;
  if (!content) return;

  const entry = sessions.get(sessionId);

  for (const block of content) {
    if (block['type'] === 'text') {
      // Only emit full text if we didn't already stream it via deltas
      if (!entry?.hasStreamedText) {
        const text = block['text'] as string;
        if (text) {
          sendToParent({ type: 'ipc:output', sessionId, chunk: text });
        }
      }
    }

    if (block['type'] === 'tool_use') {
      sendToParent({
        type: 'ipc:tool.start',
        sessionId,
        tool: block['name'] as string,
        input: block['input'] as Record<string, unknown>,
      });
    }
  }
}

// ── Stream events (real-time deltas) ────────────────────────

function handleStreamEvent(sessionId: string, message: SDKMessage): void {
  if (message.type !== 'stream_event') return;
  const msg = message as Record<string, unknown>;
  const innerEvent = msg['event'] as Record<string, unknown> | undefined;
  if (!innerEvent) return;

  const eventType = innerEvent['type'] as string;

  switch (eventType) {
    case 'content_block_delta': {
      const delta = innerEvent['delta'] as Record<string, unknown> | undefined;
      if (delta?.['type'] === 'text_delta') {
        const text = delta['text'] as string;
        if (text) {
          const entry = sessions.get(sessionId);
          if (entry) entry.hasStreamedText = true;
          sendToParent({ type: 'ipc:output', sessionId, chunk: text });
        }
      }
      break;
    }

    case 'content_block_start': {
      const block = innerEvent['content_block'] as Record<string, unknown> | undefined;
      if (block?.['type'] === 'tool_use') {
        sendToParent({
          type: 'ipc:output',
          sessionId,
          chunk: `\n[Using ${block['name']}...]\n`,
        });
      }
      break;
    }
  }
}

// ── Result messages ─────────────────────────────────────────

function handleResultMessage(sessionId: string, message: SDKMessage): void {
  if (message.type !== 'result') return;

  // Reset streaming flag for next turn
  const entry = sessions.get(sessionId);
  if (entry) entry.hasStreamedText = false;

  const msg = message as Record<string, unknown>;
  const subtype = msg['subtype'] as string;
  const isError = msg['is_error'] as boolean;

  if (isError || subtype !== 'success') {
    const errors = msg['errors'] as string[] | undefined;
    const errorText = errors?.join(', ') ?? subtype;
    sendToParent({
      type: 'ipc:output',
      sessionId,
      chunk: `\n[Error: ${errorText}]\n`,
    });
  }

  const rawDuration = Number(msg['durationMs']);
  const rawCost = Number(msg['total_costUsd']);
  const rawTurns = Number(msg['numTurns']);
  const rawInputTokens = Number(msg['input_tokens']);
  const rawOutputTokens = Number(msg['output_tokens']);
  const durationMs = Number.isFinite(rawDuration) ? rawDuration : 0;
  const costUsd = Number.isFinite(rawCost) ? rawCost : 0;
  const numTurns = Number.isFinite(rawTurns) ? rawTurns : 0;
  const inputTokens = Number.isFinite(rawInputTokens) ? rawInputTokens : undefined;
  const outputTokens = Number.isFinite(rawOutputTokens) ? rawOutputTokens : undefined;

  workerLog.info(
    { sessionId, subtype, durationMs, cost: costUsd, turns: numTurns, inputTokens, outputTokens },
    'Prompt result',
  );

  sendToParent({
    type: 'ipc:session.result',
    sessionId,
    costUsd,
    numTurns,
    durationMs,
    inputTokens,
    outputTokens,
  });
}

// ── IPC message handler ─────────────────────────────────────

function handleParentMessage(msg: ParentToChildMessage): void {
  switch (msg.type) {
    case 'ipc:session.start':
      void startSession(msg.sessionId, msg.workingDir);
      break;

    case 'ipc:session.destroy':
      destroySession(msg.sessionId);
      break;

    case 'ipc:prompt':
      void sendPrompt(msg.sessionId, msg.text);
      break;

    case 'ipc:approval':
      approvalQueue.resolve(msg.requestId, msg.decision);
      break;

    case 'ipc:cancel':
      void cancelSession(msg.sessionId);
      break;

    case 'ipc:agent.message':
      void sendAgentMessage(msg.sessionId, msg.agentId, msg.text);
      break;

    case 'ipc:context.add':
      addContextFile(msg.sessionId, msg.path, msg.content);
      break;

    case 'ipc:context.remove':
      removeContextFile(msg.sessionId, msg.path);
      break;

    case 'ipc:permission.mode':
      permissionFilter.setMode(msg.mode, msg.delaySeconds, msg.godSubMode);
      if (msg.mode === 'god') {
        approvalQueue.flushPending();
      } else if (msg.mode === 'smart') {
        approvalQueue.flushMatching((tool, details) => {
          const input = (details?.['tool_input'] as Record<string, unknown>) ?? {};
          return permissionFilter.check(tool, input).allowed;
        });
      }
      {
        const queueMode = msg.mode === 'delay' ? 'delay' as const : 'manual' as const;
        approvalQueue.setMode(queueMode, msg.delaySeconds);
      }
      break;
  }
}

// ── Process event wiring ────────────────────────────────────

process.on('message', (raw: unknown) => {
  if (!isParentToChildMessage(raw)) {
    workerLog.warn({ raw }, 'Received unknown IPC message');
    return;
  }
  handleParentMessage(raw);
});

// ── Graceful shutdown ───────────────────────────────────────

function shutdown(): void {
  workerLog.info({ sessionCount: sessions.size }, 'Worker shutting down');

  for (const [sessionId, entry] of sessions) {
    workerLog.info({ sessionId }, 'Closing SDK session');
    entry.streamAbort.abort();
    entry.sdkSession.close();
  }
  sessions.clear();

  // Give IPC messages time to flush, then exit
  setTimeout(() => {
    process.exit(0);
  }, 500);
}

process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);

// ── Worker ready signal ─────────────────────────────────────

sendToParent({
  type: 'ipc:worker.ready',
  workerId,
  workingDir: process.cwd(),
});

workerLog.info({ workerId, cwd: process.cwd() }, 'Fleet worker started');
