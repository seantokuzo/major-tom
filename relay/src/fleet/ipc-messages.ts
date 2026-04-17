/**
 * IPC Message Types — Typed protocol between parent relay process and child workers.
 *
 * All messages are discriminated unions keyed by the `type` field.
 * Parent → Child messages start with `ipc:` prefix.
 * Child → Parent messages also use `ipc:` prefix.
 */

import type { ApprovalDecision } from '../hooks/approval-queue.js';
import type { PermissionMode, GodSubMode, AutoAllowReason } from '../permissions/permission-filter.js';

// ── Parent → Child Messages ────────────────────────────────

export interface IpcSessionStart {
  type: 'ipc:session.start';
  sessionId: string;
  workingDir: string;
}

export interface IpcSessionDestroy {
  type: 'ipc:session.destroy';
  sessionId: string;
}

export interface IpcPrompt {
  type: 'ipc:prompt';
  sessionId: string;
  text: string;
  context?: string[];
}

export interface IpcApproval {
  type: 'ipc:approval';
  sessionId: string;
  requestId: string;
  decision: ApprovalDecision;
}

export interface IpcCancel {
  type: 'ipc:cancel';
  sessionId: string;
}

export interface IpcAgentMessage {
  type: 'ipc:agent.message';
  sessionId: string;
  agentId: string;
  text: string;
}

export interface IpcContextAdd {
  type: 'ipc:context.add';
  sessionId: string;
  path: string;
  content: string;
}

export interface IpcContextRemove {
  type: 'ipc:context.remove';
  sessionId: string;
  path: string;
}

export interface IpcPermissionMode {
  type: 'ipc:permission.mode';
  mode: PermissionMode;
  delaySeconds?: number;
  godSubMode?: GodSubMode;
}

export interface IpcSpriteMessage {
  type: 'ipc:sprite.message';
  sessionId: string;
  spriteHandle: string;
  subagentId: string;
  text: string;
  messageId: string;
}

/**
 * Parent → Child: enqueue a /btw message for turn-boundary injection.
 * Worker owns the queue; parent routes here after looking up the session's
 * worker. The `role` + `task` come from the sprite mapping so the worker
 * can build the constraint framing without loading mapping state itself.
 */
export interface IpcSpriteEnqueue {
  type: 'ipc:sprite.enqueue';
  sessionId: string;
  subagentId: string;
  spriteHandle: string;
  messageId: string;
  userText: string;
  role: string;
  task: string;
}

/**
 * Parent → Child: drop queued /btw entries for a subagent (fires when the
 * sprite layer unlinks before delivery — scenario #4).
 */
export interface IpcSpriteDrop {
  type: 'ipc:sprite.drop';
  sessionId: string;
  subagentId: string;
  reason: string;
}

export type ParentToChildMessage =
  | IpcSessionStart
  | IpcSessionDestroy
  | IpcPrompt
  | IpcApproval
  | IpcCancel
  | IpcAgentMessage
  | IpcContextAdd
  | IpcContextRemove
  | IpcPermissionMode
  | IpcSpriteMessage
  | IpcSpriteEnqueue
  | IpcSpriteDrop;

// ── Child → Parent Messages ────────────────────────────────

export interface IpcSessionStarted {
  type: 'ipc:session.started';
  sessionId: string;
  workingDir: string;
}

export interface IpcSessionError {
  type: 'ipc:session.error';
  sessionId: string;
  error: string;
}

export interface IpcOutput {
  type: 'ipc:output';
  sessionId: string;
  chunk: string;
}

export interface IpcApprovalRequest {
  type: 'ipc:approval.request';
  sessionId: string;
  requestId: string;
  tool: string;
  description: string;
  details: Record<string, unknown>;
}

export interface IpcApprovalAuto {
  type: 'ipc:approval.auto';
  tool: string;
  description: string;
  reason: AutoAllowReason;
  toolUseId: string;
}

export interface IpcToolStart {
  type: 'ipc:tool.start';
  sessionId: string;
  tool: string;
  input: Record<string, unknown>;
  /** Wave 5 — subagent that owns this tool call (from parent_tool_use_id). */
  subagentId?: string;
  /** Wave 5 — SDK tool_use_id for correlation. */
  toolUseId?: string;
}

export interface IpcToolComplete {
  type: 'ipc:tool.complete';
  sessionId: string;
  tool: string;
  output: string;
  success: boolean;
  /** Wave 5 — subagent that owned this tool call. */
  subagentId?: string;
  /** Wave 5 — SDK tool_use_id for correlation. */
  toolUseId?: string;
}

export interface IpcAgentLifecycle {
  type: 'ipc:agent.lifecycle';
  sessionId: string;
  agentId: string;
  event: 'spawn' | 'working' | 'idle' | 'complete' | 'dismissed';
  task?: string;
  role?: string;
  parentId?: string;
  result?: string;
  /** Wave 5 — cumulative tool calls attributed to this subagent. */
  toolCount?: number;
  /** Wave 5 — cumulative tokens attributed to this subagent. */
  tokenCount?: number;
}

export interface IpcSessionResult {
  type: 'ipc:session.result';
  sessionId: string;
  costUsd: number;
  numTurns: number;
  durationMs: number;
  inputTokens?: number;
  outputTokens?: number;
}

export interface IpcWorkerReady {
  type: 'ipc:worker.ready';
  workerId: string;
  workingDir: string;
}

export interface IpcWorkerError {
  type: 'ipc:worker.error';
  workerId: string;
  error: string;
}

/**
 * Child → Parent: a /btw message reached terminal state (delivered to
 * the client or dropped because the subagent went away first). The parent
 * fans this out to iOS/PWA clients as `sprite.response`.
 */
export interface IpcSpriteResponse {
  type: 'ipc:sprite.response';
  sessionId: string;
  spriteHandle: string;
  subagentId: string;
  messageId: string;
  text: string;
  status: 'delivered' | 'dropped';
  dropReason?: string;
}

export type ChildToParentMessage =
  | IpcSessionStarted
  | IpcSessionError
  | IpcOutput
  | IpcApprovalRequest
  | IpcApprovalAuto
  | IpcToolStart
  | IpcToolComplete
  | IpcAgentLifecycle
  | IpcSessionResult
  | IpcWorkerReady
  | IpcWorkerError
  | IpcSpriteResponse;

// ── Union of all IPC messages ──────────────────────────────

export type IpcMessage = ParentToChildMessage | ChildToParentMessage;

// ── Type guards ────────────────────────────────────────────

export function isChildToParentMessage(msg: unknown): msg is ChildToParentMessage {
  if (typeof msg !== 'object' || msg === null) return false;
  const typed = msg as { type?: string };
  if (typeof typed.type !== 'string') return false;
  return typed.type.startsWith('ipc:') && [
    'ipc:session.started',
    'ipc:session.error',
    'ipc:output',
    'ipc:approval.request',
    'ipc:approval.auto',
    'ipc:tool.start',
    'ipc:tool.complete',
    'ipc:agent.lifecycle',
    'ipc:session.result',
    'ipc:worker.ready',
    'ipc:worker.error',
    'ipc:sprite.response',
  ].includes(typed.type);
}

export function isParentToChildMessage(msg: unknown): msg is ParentToChildMessage {
  if (typeof msg !== 'object' || msg === null) return false;
  const typed = msg as { type?: string };
  if (typeof typed.type !== 'string') return false;
  return typed.type.startsWith('ipc:') && [
    'ipc:session.start',
    'ipc:session.destroy',
    'ipc:prompt',
    'ipc:approval',
    'ipc:cancel',
    'ipc:agent.message',
    'ipc:context.add',
    'ipc:context.remove',
    'ipc:permission.mode',
    'ipc:sprite.message',
    'ipc:sprite.enqueue',
    'ipc:sprite.drop',
  ].includes(typed.type);
}
